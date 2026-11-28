USE ROLE SYSADMIN;
USE DATABASE DWH_OLIST;
USE WAREHOUSE WH_CARGA;
ALTER SESSION SET QUERY_TAG = 'F4AIS_B_PESADA';

CREATE OR REPLACE TABLE OPTIM.TMP_CARGA_PESADA AS
SELECT dispositivo_key, lectura_ts, fecha_key,
       AVG(temperatura_c)   OVER (PARTITION BY dispositivo_key ORDER BY lectura_ts
                                  ROWS BETWEEN 200 PRECEDING AND CURRENT ROW) AS temp_mm,
       MAX(velocidad_kmh)   OVER (PARTITION BY dispositivo_key ORDER BY lectura_ts
                                  ROWS BETWEEN 200 PRECEDING AND CURRENT ROW) AS vel_max_mm,
       ROW_NUMBER()         OVER (PARTITION BY dispositivo_key, fecha_key ORDER BY lectura_ts) AS n
FROM OPTIM.TEL_BASE;

ALTER SESSION UNSET QUERY_TAG;

USE ROLE SYSADMIN;
USE DATABASE DWH_OLIST;
USE WAREHOUSE WH_ANALISIS;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'F4AIS_C_ANALISIS';

SELECT fecha_key, COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_BASE GROUP BY fecha_key ORDER BY fecha_key;

SELECT dispositivo_key, MAX(velocidad_kmh) AS vel_max, ROUND(AVG(desvio_km),2) AS desvio_prom
FROM OPTIM.TEL_BASE GROUP BY dispositivo_key ORDER BY vel_max DESC LIMIT 20;

SELECT clasif_termica_key, clasif_movimiento_key, COUNT(*) AS lecturas
FROM OPTIM.TEL_BASE GROUP BY 1, 2 ORDER BY lecturas DESC;

ALTER SESSION UNSET QUERY_TAG;

USE ROLE SYSADMIN;
USE DATABASE DWH_OLIST;

-- Detalle: verifica que las consultas se solaparon con la carga pesada
SELECT query_tag, warehouse_name, query_type,
       TO_CHAR(start_time, 'HH24:MI:SS') AS inicio,
       TO_CHAR(end_time,   'HH24:MI:SS') AS fin,
       ROUND(total_elapsed_time / 1000, 1)       AS seg_total,
       ROUND(queued_overload_time / 1000, 1)     AS seg_en_cola,
       ROUND(execution_time / 1000, 1)           AS seg_ejecucion
FROM TABLE(DWH_OLIST.INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 1000))
WHERE query_tag LIKE 'F4AIS%' AND query_type IN ('SELECT', 'CREATE_TABLE_AS_SELECT')
ORDER BY query_tag, start_time;

-- Resumen: suma de las 3 consultas analiticas por escenario
SELECT query_tag AS escenario,
       COUNT(*) AS consultas,
       ROUND(SUM(total_elapsed_time) / 1000, 1)   AS seg_total_analisis,
       ROUND(SUM(queued_overload_time) / 1000, 1) AS seg_en_cola
FROM TABLE(DWH_OLIST.INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 1000))
WHERE query_tag IN ('F4AIS_C_ANALISIS', 'F4AIS_B_ANALISIS', 'F4AIS_A_ANALISIS')
  AND query_type = 'SELECT'
GROUP BY query_tag
ORDER BY query_tag;

USE ROLE SYSADMIN;
DROP TABLE IF EXISTS OPTIM.TMP_CARGA_PESADA;
DROP TABLE IF EXISTS OPTIM.TMP_CARGA_PESADA_2;
DROP WAREHOUSE IF EXISTS WH_PRUEBA_UNICO;