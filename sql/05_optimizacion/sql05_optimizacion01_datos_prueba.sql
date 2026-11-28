USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

CREATE TRANSIENT SCHEMA IF NOT EXISTS OPTIM
  COMMENT = 'Copias escaladas para pruebas de rendimiento (no son datos de negocio)';

-- ---------- Diagnostico: tamano y particiones de las tablas REALES ----------
SELECT 'CORE.FACT_TELEMETRIA_IOT' AS tabla,
       (SELECT COUNT(*) FROM CORE.FACT_TELEMETRIA_IOT) AS filas,
       PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.CORE.FACT_TELEMETRIA_IOT', '(fecha_key)')):total_partition_count::INT AS micro_particiones
UNION ALL
SELECT 'CORE.FACT_ITEM_PEDIDO',
       (SELECT COUNT(*) FROM CORE.FACT_ITEM_PEDIDO),
       PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.CORE.FACT_ITEM_PEDIDO', '(fecha_compra_key)')):total_partition_count::INT;

-- ---------- Telemetria escalada: x10 dispositivos, orden natural por tiempo ----------
-- dispositivo_key + n*100000 crea "flotas" nuevas sin chocar con las claves reales.
CREATE OR REPLACE TABLE OPTIM.TEL_BASE AS
SELECT f.dispositivo_key + g.n * 100000 AS dispositivo_key,
       f.lectura_ts, f.fecha_key, f.latitud, f.longitud, f.temperatura_c,
       f.velocidad_kmh, f.desvio_km,
       f.clasif_termica_key, f.clasif_movimiento_key, f.clasif_calidad_key
FROM CORE.FACT_TELEMETRIA_IOT f
CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
            FROM TABLE(GENERATOR(ROWCOUNT => 10))) g       -- <-- AJUSTA este numero
ORDER BY f.lectura_ts;

-- ---------- Items escalados: x200, orden arbitrario (no por fecha) ----------
-- Se ordena por el id del pedido (hexadecimal): equivale a una carga sin orden de fecha.
CREATE OR REPLACE TABLE OPTIM.ITEM_BASE AS
SELECT f.pedido_id || '-' || g.n::STRING AS pedido_id,
       f.item_numero, f.producto_key, f.vendedor_key, f.cliente_key,
       f.fecha_compra_key, f.estado_pedido, f.precio, f.flete,
       f.dias_retraso, f.entregado_a_tiempo
FROM CORE.FACT_ITEM_PEDIDO f
CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
            FROM TABLE(GENERATOR(ROWCOUNT => 200))) g
ORDER BY 1;

SELECT 'OPTIM.TEL_BASE'  AS tabla, COUNT(*) AS filas FROM OPTIM.TEL_BASE
UNION ALL
SELECT 'OPTIM.ITEM_BASE', COUNT(*) FROM OPTIM.ITEM_BASE;