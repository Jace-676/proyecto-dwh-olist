USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALISIS;
USE DATABASE DWH_OLIST;

SELECT payload, _archivo, _lote FROM RAW.TELEMETRIA_IOT LIMIT 5;
SELECT _lote, COUNT(*) AS filas FROM RAW.TELEMETRIA_IOT GROUP BY _lote ORDER BY _lote;

SELECT r.payload:device_id::STRING AS device_id,
       r.payload:ts::STRING        AS ts,
       f.index                     AS posicion,
       f.value::STRING             AS order_id
FROM RAW.TELEMETRIA_IOT r,
     LATERAL FLATTEN(INPUT => r.payload:order_ids) f
LIMIT 10;

SELECT 'CALIDAD' AS dimension, clase_calidad AS clase, COUNT(*) AS lecturas
FROM STAGE.STG_TELEMETRIA GROUP BY 2
UNION ALL
SELECT 'TERMICO', clase_termica, COUNT(*) FROM STAGE.STG_TELEMETRIA
WHERE clase_calidad <> 'RECHAZADA' GROUP BY 2
UNION ALL
SELECT 'MOVIMIENTO', clase_movimiento, COUNT(*) FROM STAGE.STG_TELEMETRIA
WHERE clase_calidad <> 'RECHAZADA' GROUP BY 2
ORDER BY 1, 3 DESC;

SELECT motivo_calidad, COUNT(*) AS lecturas
FROM STAGE.STG_TELEMETRIA
WHERE motivo_calidad IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;

-- 1) RAW vs STAGE: la diferencia son duplicados y filas sin clave
SELECT (SELECT COUNT(*) FROM RAW.TELEMETRIA_IOT)   AS filas_raw,
       (SELECT COUNT(*) FROM STAGE.STG_TELEMETRIA) AS filas_stage,
       (SELECT COUNT(*) FROM RAW.TELEMETRIA_IOT) - (SELECT COUNT(*) FROM STAGE.STG_TELEMETRIA) AS duplicadas_descartadas;

-- 2) El desvio calculado debe ser pequeno en EN_RUTA/DETENIDO y >= 30 en DESVIO
SELECT clase_movimiento, COUNT(*) AS lecturas,
       ROUND(MIN(desvio_km),1) AS min_km, ROUND(AVG(desvio_km),1) AS prom_km, ROUND(MAX(desvio_km),1) AS max_km
FROM STAGE.STG_TELEMETRIA
WHERE clase_calidad <> 'RECHAZADA'
GROUP BY 1;

-- 3) Ninguna lectura valida debe quedar sin ruta (esperado: 0)
SELECT COUNT_IF(desvio_km IS NULL) AS sin_ruta
FROM STAGE.STG_TELEMETRIA WHERE clase_calidad <> 'RECHAZADA';

-- 4) STAGE (no rechazadas) debe igualar CORE
SELECT (SELECT COUNT(*) FROM STAGE.STG_TELEMETRIA WHERE clase_calidad <> 'RECHAZADA') AS stage_validas,
       (SELECT COUNT(*) FROM CORE.FACT_TELEMETRIA_IOT) AS core_fact,
       (SELECT COUNT(*) FROM CORE.DIM_DISPOSITIVO_IOT) AS dispositivos,
       (SELECT COUNT(*) FROM CORE.PUENTE_ENTREGA_DISPOSITIVO) AS puente;

SHOW STREAMS IN SCHEMA DWH_OLIST.RAW;
SHOW TASKS IN SCHEMA DWH_OLIST.CONTROL;
SELECT SYSTEM$STREAM_HAS_DATA('DWH_OLIST.RAW.STM_TELEMETRIA_IOT');

SELECT * FROM CONTROL.BITACORA_CARGA WHERE tabla_destino = 'TELEMETRIA_IOT' ORDER BY archivo;
SELECT * FROM CONTROL.BITACORA_PROCESO ORDER BY fecha_proceso, lote;