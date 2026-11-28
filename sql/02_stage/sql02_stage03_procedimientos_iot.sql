USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

-- =====================================================================
-- RAW -> STAGE
-- =====================================================================
CREATE OR REPLACE PROCEDURE DWH_OLIST.CONTROL.SP_RAW_A_STAGE_IOT()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_hay BOOLEAN;
  v_run TIMESTAMP_NTZ;
BEGIN
  -- 1) Bitacora de archivos cargados a RAW (una fila por lote + archivo)
  MERGE INTO DWH_OLIST.CONTROL.BITACORA_CARGA b
  USING (
    SELECT REGEXP_SUBSTR(file_name, 'L[0-9]{3}') AS lote,
           table_name                            AS tabla_destino,
           file_name                             AS archivo,
           row_parsed                            AS filas_leidas,
           row_count                             AS filas_cargadas,
           row_parsed - row_count                AS filas_rechazadas,
           status                                AS estado,
           last_load_time::TIMESTAMP_NTZ         AS fecha_carga
    FROM DWH_OLIST.INFORMATION_SCHEMA.LOAD_HISTORY
    WHERE schema_name = 'RAW' AND table_name = 'TELEMETRIA_IOT'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY file_name ORDER BY last_load_time) = 1
  ) s
  ON b.lote = s.lote AND b.tabla_destino = s.tabla_destino AND b.archivo = s.archivo
  WHEN NOT MATCHED THEN INSERT
    (lote, tabla_destino, archivo, filas_leidas, filas_cargadas, filas_rechazadas, estado, fecha_carga)
  VALUES
    (s.lote, s.tabla_destino, s.archivo, s.filas_leidas, s.filas_cargadas, s.filas_rechazadas, s.estado, s.fecha_carga);

  -- 2) Si el Stream no tiene datos nuevos, no hay nada que hacer
  SELECT SYSTEM$STREAM_HAS_DATA('DWH_OLIST.RAW.STM_TELEMETRIA_IOT') INTO :v_hay;
  IF (NOT v_hay) THEN
    RETURN 'Sin filas nuevas en RAW: nada que procesar';
  END IF;

  v_run := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

  START TRANSACTION;

  -- 3) Lecturas: parseo, deduplicacion, distancia a la ruta y clasificacion
  MERGE INTO DWH_OLIST.STAGE.STG_TELEMETRIA t
  USING (
    WITH prm AS (
      SELECT
        MAX(IFF(dimension = 'MOVIMIENTO' AND clase = 'DETENIDO',  vel_max, NULL))       AS det_vel_max,
        MAX(IFF(dimension = 'MOVIMIENTO' AND clase = 'DESVIO',    desvio_min_km, NULL))  AS desvio_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    temp_min, NULL))       AS rech_t_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    temp_max, NULL))       AS rech_t_max,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    lat_min, NULL))        AS rech_lat_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    lat_max, NULL))        AS rech_lat_max,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    lon_min, NULL))        AS rech_lon_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'RECHAZADA',    lon_max, NULL))        AS rech_lon_max,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'SOSPECHOSA',   temp_min, NULL))       AS sosp_t_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'SOSPECHOSA',   temp_max, NULL))       AS sosp_t_max,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'SOSPECHOSA',   vel_min, NULL))        AS sosp_v_min,
        MAX(IFF(dimension = 'CALIDAD' AND clase = 'SOSPECHOSA',   vel_max, NULL))        AS sosp_v_max
      FROM DWH_OLIST.CORE.DIM_CLASIFICACION_IOT
    ),
    term AS (
      SELECT perfil,
             MAX(IFF(clase = 'NORMAL', temp_min, NULL)) AS n_min,
             MAX(IFF(clase = 'NORMAL', temp_max, NULL)) AS n_max,
             MAX(IFF(clase = 'ALERTA', temp_min, NULL)) AS a_min,
             MAX(IFF(clase = 'ALERTA', temp_max, NULL)) AS a_max
      FROM DWH_OLIST.CORE.DIM_CLASIFICACION_IOT
      WHERE dimension = 'TERMICO'
      GROUP BY perfil
    ),
    crudo AS (
      SELECT payload:device_id::STRING AS device_id,
             TRY_TO_TIMESTAMP_NTZ(REPLACE(payload:ts::STRING, 'Z', ''), 'YYYY-MM-DD"T"HH24:MI:SS') AS lectura_ts,
             TRY_TO_DOUBLE(payload:gps.lat::STRING)   AS latitud,
             TRY_TO_DOUBLE(payload:gps.lon::STRING)   AS longitud,
             TRY_TO_DOUBLE(payload:temp_c::STRING)    AS temperatura_c,
             TRY_TO_DOUBLE(payload:speed_kmh::STRING) AS velocidad_kmh,
             UPPER(TRIM(payload:perfil_termico::STRING)) AS perfil_termico,
             payload:order_ids[0]::STRING             AS pedido_principal_id,
             ARRAY_SIZE(payload:order_ids)            AS n_pedidos,
             _archivo, _fila, _lote
      FROM DWH_OLIST.RAW.STM_TELEMETRIA_IOT
    ),
    unico AS (
      SELECT * FROM crudo
      WHERE device_id IS NOT NULL AND lectura_ts IS NOT NULL
      QUALIFY ROW_NUMBER() OVER (PARTITION BY device_id, lectura_ts ORDER BY _archivo, _fila) = 1
    ),
    ruta AS (
      SELECT u.*,
             CASE WHEN r.order_id IS NOT NULL
                   AND u.latitud  BETWEEN -90 AND 90
                   AND u.longitud BETWEEN -180 AND 180
                  THEN ST_DISTANCE(
                         ST_MAKEPOINT(u.longitud, u.latitud),
                         ST_MAKELINE(ST_MAKEPOINT(r.origen_lon, r.origen_lat),
                                     ST_MAKEPOINT(r.destino_lon, r.destino_lat))) / 1000
             END AS desvio_km
      FROM unico u
      LEFT JOIN DWH_OLIST.STAGE.STG_RUTA_PEDIDO r ON r.order_id = u.pedido_principal_id
    ),
    evalua AS (
      SELECT x.device_id, x.lectura_ts, x.latitud, x.longitud, x.temperatura_c, x.velocidad_kmh,
             x.perfil_termico, x.pedido_principal_id, x.n_pedidos, x.desvio_km,
             x._archivo, x._lote,
             CASE
               WHEN x.latitud IS NULL OR x.longitud IS NULL OR x.temperatura_c IS NULL
                    OR x.velocidad_kmh IS NULL THEN 'CAMPO_NULO'
               WHEN x.latitud  NOT BETWEEN p.rech_lat_min AND p.rech_lat_max
                    OR x.longitud NOT BETWEEN p.rech_lon_min AND p.rech_lon_max THEN 'COORDENADAS_FUERA_DE_BRASIL'
               WHEN x.temperatura_c NOT BETWEEN p.rech_t_min AND p.rech_t_max THEN 'TEMPERATURA_IMPOSIBLE'
               WHEN tm.perfil IS NULL THEN 'PERFIL_DESCONOCIDO'
               WHEN x.temperatura_c NOT BETWEEN p.sosp_t_min AND p.sosp_t_max THEN 'TEMPERATURA_ATIPICA'
               WHEN x.velocidad_kmh NOT BETWEEN p.sosp_v_min AND p.sosp_v_max THEN 'VELOCIDAD_ATIPICA'
             END AS motivo,
             tm.n_min, tm.n_max, tm.a_min, tm.a_max, p.det_vel_max, p.desvio_min
      FROM ruta x
      CROSS JOIN prm p
      LEFT JOIN term tm ON tm.perfil = x.perfil_termico
    )
    SELECT device_id, lectura_ts, latitud, longitud, temperatura_c, velocidad_kmh,
           perfil_termico, pedido_principal_id, n_pedidos, desvio_km,
           CASE WHEN motivo IN ('CAMPO_NULO','COORDENADAS_FUERA_DE_BRASIL','TEMPERATURA_IMPOSIBLE') THEN NULL
                WHEN n_min IS NULL THEN NULL
                WHEN temperatura_c >= n_min AND temperatura_c < n_max THEN 'NORMAL'
                WHEN temperatura_c >= a_min AND temperatura_c < a_max THEN 'ALERTA'
                ELSE 'CRITICO' END AS clase_termica,
           CASE WHEN motivo IN ('CAMPO_NULO','COORDENADAS_FUERA_DE_BRASIL','TEMPERATURA_IMPOSIBLE') THEN NULL
                WHEN desvio_km >= desvio_min THEN 'DESVIO'
                WHEN velocidad_kmh < det_vel_max THEN 'DETENIDO'
                ELSE 'EN_RUTA' END AS clase_movimiento,
           CASE WHEN motivo IN ('CAMPO_NULO','COORDENADAS_FUERA_DE_BRASIL','TEMPERATURA_IMPOSIBLE') THEN 'RECHAZADA'
                WHEN motivo IS NOT NULL THEN 'SOSPECHOSA'
                ELSE 'VALIDA' END AS clase_calidad,
           motivo AS motivo_calidad,
           _archivo, _lote
    FROM evalua
  ) s
  ON t.device_id = s.device_id AND t.lectura_ts = s.lectura_ts
  WHEN NOT MATCHED THEN INSERT
    (device_id, lectura_ts, latitud, longitud, temperatura_c, velocidad_kmh, perfil_termico,
     pedido_principal_id, n_pedidos, desvio_km, clase_termica, clase_movimiento, clase_calidad,
     motivo_calidad, _archivo, _lote, _fecha_stage)
  VALUES
    (s.device_id, s.lectura_ts, s.latitud, s.longitud, s.temperatura_c, s.velocidad_kmh, s.perfil_termico,
     s.pedido_principal_id, s.n_pedidos, s.desvio_km, s.clase_termica, s.clase_movimiento, s.clase_calidad,
     s.motivo_calidad, s._archivo, s._lote, :v_run);

  -- 4) Aplanado con LATERAL FLATTEN: una fila por lectura y pedido
  MERGE INTO DWH_OLIST.STAGE.STG_TELEMETRIA_PEDIDO t
  USING (
    SELECT device_id, lectura_ts, order_id, MIN(_lote) AS _lote
    FROM (
      SELECT r.payload:device_id::STRING AS device_id,
             TRY_TO_TIMESTAMP_NTZ(REPLACE(r.payload:ts::STRING, 'Z', ''), 'YYYY-MM-DD"T"HH24:MI:SS') AS lectura_ts,
             f.value::STRING AS order_id,
             r._lote AS _lote
      FROM DWH_OLIST.RAW.STM_TELEMETRIA_IOT r,
           LATERAL FLATTEN(INPUT => r.payload:order_ids) f
    )
    WHERE device_id IS NOT NULL AND lectura_ts IS NOT NULL AND order_id IS NOT NULL
    GROUP BY device_id, lectura_ts, order_id
  ) s
  ON t.device_id = s.device_id AND t.lectura_ts = s.lectura_ts AND t.order_id = s.order_id
  WHEN NOT MATCHED THEN INSERT (device_id, lectura_ts, order_id, _lote, _fecha_stage)
  VALUES (s.device_id, s.lectura_ts, s.order_id, s._lote, :v_run);

  -- 5) Bitacora del proceso, por lote
  INSERT INTO DWH_OLIST.CONTROL.BITACORA_PROCESO
    (proceso, lote, filas_entrada, filas_nuevas_stage, filas_no_insertadas,
     filas_rechazadas, filas_sospechosas, fecha_proceso)
  SELECT 'RAW_A_STAGE_IOT', r.lote, r.n, COALESCE(s.nuevas, 0), r.n - COALESCE(s.nuevas, 0),
         COALESCE(s.rech, 0), COALESCE(s.sosp, 0), :v_run
  FROM (SELECT _lote AS lote, COUNT(*) AS n
        FROM DWH_OLIST.RAW.STM_TELEMETRIA_IOT GROUP BY _lote) r
  LEFT JOIN (SELECT _lote AS lote, COUNT(*) AS nuevas,
                    COUNT_IF(clase_calidad = 'RECHAZADA') AS rech,
                    COUNT_IF(clase_calidad = 'SOSPECHOSA') AS sosp
             FROM DWH_OLIST.STAGE.STG_TELEMETRIA
             WHERE _fecha_stage = :v_run
             GROUP BY _lote) s
    ON r.lote = s.lote;

  COMMIT;
  RETURN 'RAW -> STAGE completado';
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;

-- =====================================================================
-- STAGE -> CORE (incremental por marca de agua; MERGE = idempotente)
-- =====================================================================
CREATE OR REPLACE PROCEDURE DWH_OLIST.CONTROL.SP_STAGE_A_CORE_IOT()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  v_wm TIMESTAMP_NTZ;
BEGIN
  SELECT COALESCE(MAX(_fecha_stage), '1900-01-01'::TIMESTAMP_NTZ) INTO :v_wm
  FROM DWH_OLIST.CORE.FACT_TELEMETRIA_IOT;

  START TRANSACTION;

  -- Dimension de dispositivos
  MERGE INTO DWH_OLIST.CORE.DIM_DISPOSITIVO_IOT t
  USING (
    SELECT device_id, MIN(lectura_ts) AS primera, MAX(lectura_ts) AS ultima
    FROM DWH_OLIST.STAGE.STG_TELEMETRIA
    WHERE clase_calidad <> 'RECHAZADA' AND _fecha_stage > :v_wm
    GROUP BY device_id
  ) s
  ON t.device_id = s.device_id
  WHEN MATCHED THEN UPDATE SET
    primera_lectura_ts = LEAST(t.primera_lectura_ts, s.primera),
    ultima_lectura_ts  = GREATEST(t.ultima_lectura_ts, s.ultima)
  WHEN NOT MATCHED THEN INSERT (device_id, tipo_sensor, primera_lectura_ts, ultima_lectura_ts)
  VALUES (s.device_id, 'GPS_TEMP_VELOCIDAD', s.primera, s.ultima);

  -- Hecho de telemetria (solo lecturas no rechazadas)
  MERGE INTO DWH_OLIST.CORE.FACT_TELEMETRIA_IOT t
  USING (
    SELECT d.dispositivo_key, s.lectura_ts,
           YEAR(s.lectura_ts) * 10000 + MONTH(s.lectura_ts) * 100 + DAY(s.lectura_ts) AS fecha_key,
           s.latitud, s.longitud, s.temperatura_c, s.velocidad_kmh, s.desvio_km,
           s.perfil_termico, s.pedido_principal_id,
           kt.clasificacion_key AS clasif_termica_key,
           km.clasificacion_key AS clasif_movimiento_key,
           kc.clasificacion_key AS clasif_calidad_key,
           s._lote, s._fecha_stage
    FROM DWH_OLIST.STAGE.STG_TELEMETRIA s
    JOIN DWH_OLIST.CORE.DIM_DISPOSITIVO_IOT d ON d.device_id = s.device_id
    LEFT JOIN DWH_OLIST.CORE.DIM_CLASIFICACION_IOT kt
           ON kt.dimension = 'TERMICO' AND kt.perfil = s.perfil_termico AND kt.clase = s.clase_termica
    LEFT JOIN DWH_OLIST.CORE.DIM_CLASIFICACION_IOT km
           ON km.dimension = 'MOVIMIENTO' AND km.perfil = '*' AND km.clase = s.clase_movimiento
    LEFT JOIN DWH_OLIST.CORE.DIM_CLASIFICACION_IOT kc
           ON kc.dimension = 'CALIDAD' AND kc.perfil = '*' AND kc.clase = s.clase_calidad
    WHERE s.clase_calidad <> 'RECHAZADA' AND s._fecha_stage > :v_wm
  ) f
  ON t.dispositivo_key = f.dispositivo_key AND t.lectura_ts = f.lectura_ts
  WHEN NOT MATCHED THEN INSERT
    (dispositivo_key, lectura_ts, fecha_key, latitud, longitud, temperatura_c, velocidad_kmh,
     desvio_km, perfil_termico, pedido_principal_id, clasif_termica_key, clasif_movimiento_key,
     clasif_calidad_key, _lote, _fecha_stage)
  VALUES
    (f.dispositivo_key, f.lectura_ts, f.fecha_key, f.latitud, f.longitud, f.temperatura_c, f.velocidad_kmh,
     f.desvio_km, f.perfil_termico, f.pedido_principal_id, f.clasif_termica_key, f.clasif_movimiento_key,
     f.clasif_calidad_key, f._lote, f._fecha_stage);

  -- Puente pedido <-> dispositivo (se recalcula completo para los pedidos tocados en esta corrida)
  MERGE INTO DWH_OLIST.CORE.PUENTE_ENTREGA_DISPOSITIVO t
  USING (
    SELECT p.order_id AS pedido_id, d.dispositivo_key,
           MIN(p.lectura_ts) AS inicio_ts, MAX(p.lectura_ts) AS fin_ts, COUNT(*) AS n_lecturas
    FROM DWH_OLIST.STAGE.STG_TELEMETRIA_PEDIDO p
    JOIN DWH_OLIST.STAGE.STG_TELEMETRIA s
      ON s.device_id = p.device_id AND s.lectura_ts = p.lectura_ts AND s.clase_calidad <> 'RECHAZADA'
    JOIN DWH_OLIST.CORE.DIM_DISPOSITIVO_IOT d ON d.device_id = p.device_id
    WHERE p.order_id IN (SELECT order_id FROM DWH_OLIST.STAGE.STG_TELEMETRIA_PEDIDO
                         WHERE _fecha_stage > :v_wm)
    GROUP BY p.order_id, d.dispositivo_key
  ) s
  ON t.pedido_id = s.pedido_id AND t.dispositivo_key = s.dispositivo_key
  WHEN MATCHED THEN UPDATE SET
    inicio_ts = s.inicio_ts, fin_ts = s.fin_ts, n_lecturas = s.n_lecturas
  WHEN NOT MATCHED THEN INSERT (pedido_id, dispositivo_key, inicio_ts, fin_ts, n_lecturas)
  VALUES (s.pedido_id, s.dispositivo_key, s.inicio_ts, s.fin_ts, s.n_lecturas);

  COMMIT;
  RETURN 'STAGE -> CORE completado';
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;

-- =====================================================================
-- Foto de conteos y checksums (prueba de idempotencia)
-- =====================================================================
CREATE OR REPLACE PROCEDURE DWH_OLIST.CONTROL.SP_SNAPSHOT(ETIQUETA STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  INSERT INTO DWH_OLIST.CONTROL.PRUEBA_IDEMPOTENCIA (etiqueta, tabla, filas, checksum)
  SELECT :ETIQUETA, 'RAW.TELEMETRIA_IOT', COUNT(*), HASH_AGG(payload)
  FROM DWH_OLIST.RAW.TELEMETRIA_IOT
  UNION ALL
  SELECT :ETIQUETA, 'STAGE.STG_TELEMETRIA', COUNT(*),
         HASH_AGG(device_id, lectura_ts, latitud, longitud, temperatura_c, velocidad_kmh,
                  clase_termica, clase_movimiento, clase_calidad)
  FROM DWH_OLIST.STAGE.STG_TELEMETRIA
  UNION ALL
  SELECT :ETIQUETA, 'STAGE.STG_TELEMETRIA_PEDIDO', COUNT(*), HASH_AGG(device_id, lectura_ts, order_id)
  FROM DWH_OLIST.STAGE.STG_TELEMETRIA_PEDIDO
  UNION ALL
  SELECT :ETIQUETA, 'CORE.FACT_TELEMETRIA_IOT', COUNT(*),
         HASH_AGG(dispositivo_key, lectura_ts, latitud, longitud, temperatura_c, velocidad_kmh,
                  desvio_km, clasif_termica_key, clasif_movimiento_key, clasif_calidad_key)
  FROM DWH_OLIST.CORE.FACT_TELEMETRIA_IOT
  UNION ALL
  SELECT :ETIQUETA, 'CORE.DIM_DISPOSITIVO_IOT', COUNT(*), HASH_AGG(device_id)
  FROM DWH_OLIST.CORE.DIM_DISPOSITIVO_IOT
  UNION ALL
  SELECT :ETIQUETA, 'CORE.PUENTE_ENTREGA_DISPOSITIVO', COUNT(*),
         HASH_AGG(pedido_id, dispositivo_key, inicio_ts, fin_ts, n_lecturas)
  FROM DWH_OLIST.CORE.PUENTE_ENTREGA_DISPOSITIVO;
  RETURN 'Snapshot ' || :ETIQUETA;
END;
$$;