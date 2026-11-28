#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generador reproducible de telemetria IoT simulada, anclada a pedidos reales de Olist.

Supuestos de simulacion (documentar en el reporte):
  * Las fechas de Olist se tratan como UTC.
  * Se simula el tramo de conduccion del pedido; el vehiculo se detiene 5 % al inicio
    (carga) y ~10 % al final (entrega).
  * El perfil termico se deriva de la categoria del producto:
    alimentos/bebidas -> REFRIGERADO; perfumeria/belleza/higiene -> CONTROLADO; resto -> AMBIENTE.
  * Los umbrales de clasificacion NO viven aqui: estan en CORE.DIM_CLASIFICACION_IOT.
"""
import argparse
import glob
import gzip
import hashlib
import json
import math
import os
import platform
import sys

import numpy as np
import pandas as pd

LAT_MIN, LAT_MAX = -34.0, 6.0
LON_MIN, LON_MAX = -74.0, -34.0

CAT_REFRIGERADO = {"alimentos", "alimentos_bebidas", "bebidas"}
CAT_CONTROLADO = {"perfumaria", "beleza_saude", "fraldas_higiene"}
PERFILES = ["AMBIENTE", "CONTROLADO", "REFRIGERADO"]  # el indice es el nivel de restriccion

TEMP_BASE = {"AMBIENTE": 24.0, "CONTROLADO": 20.0, "REFRIGERADO": 5.0}
TEMP_OFFSET_SIGMA = {"AMBIENTE": 1.0, "CONTROLADO": 0.5, "REFRIGERADO": 0.4}
TEMP_RUIDO_SIGMA = {"AMBIENTE": 1.5, "CONTROLADO": 0.8, "REFRIGERADO": 0.6}
TEMP_INCIDENTE = {"AMBIENTE": (10.0, 18.0), "CONTROLADO": (7.0, 15.0), "REFRIGERADO": (4.0, 10.0)}
TIPOS_INCIDENTE = ["TEMP", "DESVIO", "PARADA"]
PESOS_INCIDENTE = [0.50, 0.25, 0.25]


# ---------------------------------------------------------------- geometria
def haversine_km(lat1, lon1, lat2, lon2):
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dphi = p2 - p1
    dl = np.radians(np.asarray(lon2) - np.asarray(lon1))
    a = np.sin(dphi / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * 6371.0088 * np.arcsin(np.sqrt(a))


def interp_gc(lat1, lon1, lat2, lon2, f):
    """Puntos sobre el circulo maximo entre (lat1,lon1) y (lat2,lon2); f en [0,1]."""
    la1, lo1, la2, lo2 = map(math.radians, (lat1, lon1, lat2, lon2))
    a = np.array([math.cos(la1) * math.cos(lo1), math.cos(la1) * math.sin(lo1), math.sin(la1)])
    b = np.array([math.cos(la2) * math.cos(lo2), math.cos(la2) * math.sin(lo2), math.sin(la2)])
    omega = math.acos(max(-1.0, min(1.0, float(a @ b))))
    if omega < 1e-9:
        return np.full(len(f), lat1), np.full(len(f), lon1)
    s = math.sin(omega)
    c1 = np.sin((1.0 - f) * omega) / s
    c2 = np.sin(f * omega) / s
    p = c1[:, None] * a[None, :] + c2[:, None] * b[None, :]
    lat = np.degrees(np.arctan2(p[:, 2], np.hypot(p[:, 0], p[:, 1])))
    lon = np.degrees(np.arctan2(p[:, 1], p[:, 0]))
    return lat, lon


def perpendicular(lat1, lon1, lat2, lon2):
    """Vector unitario (este, norte) perpendicular a la ruta."""
    latm = math.radians((lat1 + lat2) / 2)
    vx = (lon2 - lon1) * 111.32 * math.cos(latm)
    vy = (lat2 - lat1) * 110.57
    nrm = math.hypot(vx, vy)
    return -vy / nrm, vx / nrm


# ---------------------------------------------------------------- datos Olist
def leer(dir_, nombre, **kw):
    ruta = os.path.join(dir_, nombre)
    if not os.path.exists(ruta):
        sys.exit(f"ERROR: no se encuentra {ruta}")
    return pd.read_csv(ruta, **kw)


def cargar_pedidos(dir_):
    ped = leer(dir_, "olist_orders_dataset.csv", dtype=str,
               usecols=["order_id", "customer_id", "order_status",
                        "order_delivered_carrier_date", "order_delivered_customer_date"])
    ped = ped[ped["order_status"] == "delivered"].copy()
    ped["t_envio"] = pd.to_datetime(ped["order_delivered_carrier_date"], errors="coerce")
    ped["t_entrega"] = pd.to_datetime(ped["order_delivered_customer_date"], errors="coerce")
    ped = ped.dropna(subset=["t_envio", "t_entrega"])
    epoch = pd.Timestamp("1970-01-01")
    ped["t_envio_s"] = ((ped["t_envio"] - epoch) // pd.Timedelta(seconds=1)).astype("int64")
    ped["t_entrega_s"] = ((ped["t_entrega"] - epoch) // pd.Timedelta(seconds=1)).astype("int64")

    cli = leer(dir_, "olist_customers_dataset.csv", dtype=str,
               usecols=["customer_id", "customer_zip_code_prefix"])
    cli["zip_cli"] = cli["customer_zip_code_prefix"].str.strip().str.zfill(5)

    ven = leer(dir_, "olist_sellers_dataset.csv", dtype=str,
               usecols=["seller_id", "seller_zip_code_prefix"])
    ven["zip_ven"] = ven["seller_zip_code_prefix"].str.strip().str.zfill(5)

    it = leer(dir_, "olist_order_items_dataset.csv", dtype=str,
              usecols=["order_id", "order_item_id", "product_id", "seller_id"])
    it["item_n"] = it["order_item_id"].astype(int)
    pro = leer(dir_, "olist_products_dataset.csv", dtype=str,
               usecols=["product_id", "product_category_name"])
    it = it.merge(pro, on="product_id", how="left")
    it["nivel"] = it["product_category_name"].map(
        lambda c: 2 if c in CAT_REFRIGERADO else (1 if c in CAT_CONTROLADO else 0))
    nivel = it.groupby("order_id")["nivel"].max().rename("nivel").reset_index()
    primero = (it.sort_values(["order_id", "item_n"]).drop_duplicates("order_id")
               [["order_id", "seller_id"]])

    geo = leer(dir_, "olist_geolocation_dataset.csv",
               dtype={"geolocation_zip_code_prefix": str},
               usecols=["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng"])
    geo["zip"] = geo["geolocation_zip_code_prefix"].str.strip().str.zfill(5)
    geo = geo.rename(columns={"geolocation_lat": "lat", "geolocation_lng": "lng"})
    geo = geo[geo["lat"].between(LAT_MIN, LAT_MAX) & geo["lng"].between(LON_MIN, LON_MAX)]
    cent = geo.groupby("zip")[["lat", "lng"]].mean()

    ped = (ped.merge(cli[["customer_id", "zip_cli"]], on="customer_id")
              .merge(primero, on="order_id")
              .merge(nivel, on="order_id")
              .merge(ven[["seller_id", "zip_ven"]], on="seller_id"))
    ped["o_lat"] = ped["zip_ven"].map(cent["lat"])
    ped["o_lon"] = ped["zip_ven"].map(cent["lng"])
    ped["d_lat"] = ped["zip_cli"].map(cent["lat"])
    ped["d_lon"] = ped["zip_cli"].map(cent["lng"])
    ped = ped.dropna(subset=["o_lat", "o_lon", "d_lat", "d_lon"])
    ped = ped.sort_values("order_id").reset_index(drop=True)
    ped["dist_km"] = haversine_km(ped["o_lat"].values, ped["o_lon"].values,
                                  ped["d_lat"].values, ped["d_lon"].values)
    ped = ped[ped["dist_km"] >= 3.0].reset_index(drop=True)
    return ped


# ---------------------------------------------------------------- simulacion
def simular_pedido(rng, w_s, step_s, o_lat, o_lon, d_lat, d_lon, dist_km,
                   perfil, es_inc, tipo, prop_sucios):
    n = int(w_s // step_s) + 1
    k = np.arange(n)
    mov = (k >= int(0.05 * n)) & (k < int(0.90 * n))
    idx_mov = np.flatnonzero(mov)
    if len(idx_mov) < 4:
        return None

    seg = None
    tipo_ef = None
    if es_inc:
        largo = max(2, int(rng.uniform(0.10, 0.25) * len(idx_mov)))
        if tipo == "DESVIO" and (dist_km < 50 or largo < 3):
            tipo = "TEMP"
        ini = int(rng.integers(0, len(idx_mov) - largo + 1))
        seg = idx_mov[ini:ini + largo]
        tipo_ef = tipo
        if tipo == "PARADA":
            mov[seg] = False

    m = int(mov.sum())
    if m < 2:
        return None
    v = dist_km / (m * step_s / 3600.0)
    if v > 110.0:
        return None

    f = np.cumsum(mov) / m
    lat, lon = interp_gc(o_lat, o_lon, d_lat, d_lon, f)
    lat = lat + rng.normal(0.0, 0.008, n)
    lon = lon + rng.normal(0.0, 0.008, n)

    if tipo_ef == "DESVIO":
        amp = rng.uniform(40.0, 90.0) * rng.choice([-1.0, 1.0])
        off = amp * np.sin(np.pi * (np.arange(len(seg)) + 1) / (len(seg) + 1))
        px, py = perpendicular(o_lat, o_lon, d_lat, d_lon)
        lat[seg] += off * py / 110.57
        lon[seg] += off * px / (111.32 * np.cos(np.radians(lat[seg])))

    spd = np.where(mov, np.maximum(v * rng.uniform(0.85, 1.15, n), 5.0), 0.0)

    temp = (TEMP_BASE[perfil] + rng.normal(0.0, TEMP_OFFSET_SIGMA[perfil])
            + rng.normal(0.0, TEMP_RUIDO_SIGMA[perfil], n))
    if tipo_ef == "TEMP":
        lo, hi = TEMP_INCIDENTE[perfil]
        temp[seg] += rng.uniform(lo, hi)

    sucio = rng.random(n) < prop_sucios
    dup = np.zeros(n, dtype=bool)
    cont = {"fuera_brasil": 0, "temp_imposible": 0, "vel_atipica": 0, "duplicada": 0}
    for j in np.flatnonzero(sucio):
        t = int(rng.integers(0, 4))
        if t == 0:
            lat[j] = rng.uniform(35.0, 60.0)
            lon[j] = rng.uniform(-10.0, 30.0)
            cont["fuera_brasil"] += 1
        elif t == 1:
            temp[j] = float(rng.choice([999.9, -99.0]))
            cont["temp_imposible"] += 1
        elif t == 2:
            spd[j] = rng.uniform(150.0, 250.0)
            cont["vel_atipica"] += 1
        else:
            dup[j] = True
            cont["duplicada"] += 1

    return {"n": n, "lat": lat, "lon": lon, "temp": temp, "spd": spd,
            "dup": dup, "tipo": tipo_ef, "sucios": cont}


# ---------------------------------------------------------------- principal
def main():
    ap = argparse.ArgumentParser(description="Generador de telemetria IoT simulada (Olist)")
    ap.add_argument("--olist-dir", default="data/olist")
    ap.add_argument("--salida", default="data/iot")
    ap.add_argument("--semilla", type=int, default=42)
    ap.add_argument("--pedidos", type=int, default=6000, help="pedidos reales a simular")
    ap.add_argument("--intervalo-min", type=float, default=5.0, help="minutos entre lecturas")
    ap.add_argument("--ventana-max-h", type=float, default=96.0)
    ap.add_argument("--prop-incidentes", type=float, default=0.15)
    ap.add_argument("--prop-sucios", type=float, default=0.002)
    ap.add_argument("--dispositivos", type=int, default=60, help="tamano inicial de la flota")
    ap.add_argument("--lecturas-por-archivo", type=int, default=250000)
    ap.add_argument("--num-lotes", type=int, default=2)
    ap.add_argument("--lote-inicial", type=int, default=2, help="L001 fue Olist")
    ap.add_argument("--prefijo", default="telemetria")
    args = ap.parse_args()

    if args.intervalo_min <= 0 or args.num_lotes < 1 or args.pedidos < 1:
        sys.exit("ERROR: parametros invalidos")

    rng = np.random.default_rng(args.semilla)
    step_s = int(round(args.intervalo_min * 60))
    step_h = step_s / 3600.0

    print("Cargando datos de Olist ...")
    ped = cargar_pedidos(args.olist_dir)
    print(f"  pedidos entregados con ruta calculable: {len(ped):,}")

    # --- ventana de conduccion por pedido (vectorizado; el orden es determinista)
    n = len(ped)
    v_nom = rng.uniform(40.0, 65.0, n)
    margen = rng.uniform(1.15, 1.40, n)
    w_real = (ped["t_entrega_s"].values - ped["t_envio_s"].values) / 3600.0
    w_h = np.maximum(ped["dist_km"].values / v_nom * margen, 6 * step_h)
    w_h = np.minimum(w_h, np.minimum(w_real, args.ventana_max_h))
    factible = (w_h >= 6 * step_h - 1e-9) & (ped["dist_km"].values / (0.85 * w_h) <= 110.0)
    ped = ped[factible].copy()
    w_h = w_h[factible]
    ped["w_s"] = (w_h * 3600).astype("int64")
    ped["t0_s"] = ped["t_entrega_s"] - ped["w_s"]
    print(f"  pedidos factibles para simular: {len(ped):,}")

    k_ped = min(args.pedidos, len(ped))
    sel = np.sort(rng.choice(len(ped), size=k_ped, replace=False))
    ped = ped.iloc[sel].sort_values(["t0_s", "order_id"]).reset_index(drop=True)

    nombres = [f"VH-{i:03d}" for i in range(1, args.dispositivos + 1)]
    libre = [0] * len(nombres)

    L_ts, L_dev, L_lat, L_lon, L_tmp, L_spd, L_per, L_ord, L_dup = ([] for _ in range(9))
    ord_ids = []
    stats_inc = {"TEMP": 0, "DESVIO": 0, "PARADA": 0}
    stats_suc = {"fuera_brasil": 0, "temp_imposible": 0, "vel_atipica": 0, "duplicada": 0}
    omitidos = 0

    print(f"Simulando {len(ped):,} pedidos ...")
    for row in ped.itertuples(index=False):
        es_inc = bool(rng.random() < args.prop_incidentes)
        tipo = TIPOS_INCIDENTE[int(rng.choice(3, p=PESOS_INCIDENTE))]
        perfil = PERFILES[int(row.nivel)]
        r = simular_pedido(rng, int(row.w_s), step_s, row.o_lat, row.o_lon, row.d_lat,
                           row.d_lon, row.dist_km, perfil, es_inc, tipo, args.prop_sucios)
        if r is None:
            omitidos += 1
            continue
        t0 = int(row.t0_s)
        libres = [i for i, l in enumerate(libre) if l < t0]
        if not libres:
            nombres.append(f"VH-{len(nombres) + 1:03d}")
            libre.append(0)
            d = len(nombres) - 1
        else:
            d = libres[int(rng.integers(0, len(libres)))]
        ts = t0 + np.arange(r["n"], dtype=np.int64) * step_s
        libre[d] = int(ts[-1]) + step_s

        L_ts.append(ts)
        L_dev.append(np.full(r["n"], d, dtype=np.int32))
        L_lat.append(r["lat"]); L_lon.append(r["lon"])
        L_tmp.append(r["temp"]); L_spd.append(r["spd"])
        L_per.append(np.full(r["n"], int(row.nivel), dtype=np.int8))
        L_ord.append(np.full(r["n"], len(ord_ids), dtype=np.int32))
        L_dup.append(r["dup"])
        ord_ids.append(row.order_id)
        if r["tipo"]:
            stats_inc[r["tipo"]] += 1
        for kk, vv in r["sucios"].items():
            stats_suc[kk] += vv

    if not L_ts:
        sys.exit("ERROR: no se genero ninguna lectura")

    ts_a = np.concatenate(L_ts); dev_a = np.concatenate(L_dev)
    lat_a = np.concatenate(L_lat); lon_a = np.concatenate(L_lon)
    tmp_a = np.concatenate(L_tmp); spd_a = np.concatenate(L_spd)
    per_a = np.concatenate(L_per); ord_a = np.concatenate(L_ord)
    dup_a = np.concatenate(L_dup)

    # lecturas duplicadas (mismo device_id y ts) agregadas al final y luego ordenadas por tiempo
    idx_d = np.flatnonzero(dup_a)
    ts_a = np.concatenate([ts_a, ts_a[idx_d]]); dev_a = np.concatenate([dev_a, dev_a[idx_d]])
    lat_a = np.concatenate([lat_a, lat_a[idx_d]]); lon_a = np.concatenate([lon_a, lon_a[idx_d]])
    tmp_a = np.concatenate([tmp_a, tmp_a[idx_d]]); spd_a = np.concatenate([spd_a, spd_a[idx_d]])
    per_a = np.concatenate([per_a, per_a[idx_d]]); ord_a = np.concatenate([ord_a, ord_a[idx_d]])

    orden = np.argsort(ts_a, kind="stable")
    total = len(orden)

    os.makedirs(args.salida, exist_ok=True)
    for viejo in glob.glob(os.path.join(args.salida, f"{args.prefijo}_L*.json.gz")):
        os.remove(viejo)

    por_archivo = args.lecturas_por_archivo
    n_arch = math.ceil(total / por_archivo)
    manifiesto_archivos = []
    hashes = []
    ejemplo = None

    print(f"Escribiendo {total:,} lecturas en {n_arch} archivos ...")
    for i in range(n_arch):
        idx = orden[i * por_archivo:(i + 1) * por_archivo]
        lote_n = args.lote_inicial + (i * args.num_lotes) // n_arch
        ts_str = ts_a[idx].astype("datetime64[s]").astype(str).tolist()
        dv = dev_a[idx].tolist(); la = lat_a[idx].tolist(); lo = lon_a[idx].tolist()
        tm = tmp_a[idx].tolist(); sp = spd_a[idx].tolist()
        pf = per_a[idx].tolist(); od = ord_a[idx].tolist()
        lineas = [
            f'{{"device_id":"{nombres[dv[j]]}","ts":"{ts_str[j]}Z",'
            f'"gps":{{"lat":{la[j]:.5f},"lon":{lo[j]:.5f}}},'
            f'"temp_c":{tm[j]:.1f},"speed_kmh":{sp[j]:.1f},'
            f'"perfil_termico":"{PERFILES[pf[j]]}","order_ids":["{ord_ids[od[j]]}"]}}'
            for j in range(len(idx))
        ]
        contenido = ("\n".join(lineas) + "\n").encode("utf-8")
        sha = hashlib.sha256(contenido).hexdigest()
        nombre = f"{args.prefijo}_L{lote_n:03d}_{i + 1:04d}.json.gz"
        with open(os.path.join(args.salida, nombre), "wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=6) as gz:
                gz.write(contenido)
        manifiesto_archivos.append({"archivo": nombre, "lote": f"L{lote_n:03d}",
                                    "lecturas": len(lineas), "sha256_contenido": sha})
        hashes.append(sha)
        if ejemplo is None:
            ejemplo = [json.loads(x) for x in lineas[:5]]
        print(f"  {nombre}: {len(lineas):,} lecturas")

    with open(os.path.join(args.salida, "ejemplo_telemetria.json"), "w", encoding="utf-8") as fh:
        json.dump(ejemplo, fh, indent=2)

    manifiesto = {
        "parametros": vars(args),
        "versiones": {"python": platform.python_version(), "numpy": np.__version__,
                      "pandas": pd.__version__},
        "pedidos_simulados": len(ord_ids),
        "pedidos_omitidos": omitidos,
        "dispositivos_usados": len(nombres),
        "lecturas_totales": total,
        "incidentes_por_tipo": stats_inc,
        "registros_sucios_inyectados": stats_suc,
        "archivos": manifiesto_archivos,
        "sha256_global": hashlib.sha256("".join(hashes).encode()).hexdigest(),
    }
    with open(os.path.join(args.salida, "manifiesto.json"), "w", encoding="utf-8") as fh:
        json.dump(manifiesto, fh, indent=2, ensure_ascii=False)

    print("\n=== RESUMEN ===")
    print(f"semilla={args.semilla}  pedidos={len(ord_ids):,}  omitidos={omitidos:,}")
    print(f"dispositivos={len(nombres)}  lecturas={total:,}  archivos={n_arch}")
    print(f"incidentes={stats_inc}")
    print(f"sucios={stats_suc}")
    print(f"sha256_global={manifiesto['sha256_global']}")


if __name__ == "__main__":
    main()
