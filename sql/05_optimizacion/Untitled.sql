USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALISIS;
USE DATABASE DWH_OLIST;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Dispositivo mas activo y su mes mas activo (se calcula una vez, sobre la tabla base)
SET v_disp = (SELECT dispositivo_key FROM OPTIM.TEL_BASE GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1);
SET v_mes  = (SELECT FLOOR(fecha_key / 100) FROM OPTIM.TEL_BASE
              WHERE dispositivo_key = $v_disp GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1);

-- ===== Q1: un dispositivo en un mes =====
ALTER SESSION SET QUERY_TAG = 'F4CL_Q1_BASE';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom, MAX(velocidad_kmh) AS vel_max
FROM OPTIM.TEL_BASE
WHERE dispositivo_key = $v_disp AND fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 31;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q1_FECHA_DISP';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom, MAX(velocidad_kmh) AS vel_max
FROM OPTIM.TEL_CK_FECHA_DISP
WHERE dispositivo_key = $v_disp AND fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 31;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q1_DISP_FECHA';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom, MAX(velocidad_kmh) AS vel_max
FROM OPTIM.TEL_CK_DISP_FECHA
WHERE dispositivo_key = $v_disp AND fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 31;

-- ===== Q2: un dispositivo, todo el periodo =====
ALTER SESSION SET QUERY_TAG = 'F4CL_Q2_BASE';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_BASE WHERE dispositivo_key = $v_disp;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q2_FECHA_DISP';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_CK_FECHA_DISP WHERE dispositivo_key = $v_disp;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q2_DISP_FECHA';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_CK_DISP_FECHA WHERE dispositivo_key = $v_disp;

-- ===== Q3: una semana, todos los dispositivos =====
ALTER SESSION SET QUERY_TAG = 'F4CL_Q3_BASE';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_BASE WHERE fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 7;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q3_FECHA_DISP';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_CK_FECHA_DISP WHERE fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 7;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q3_DISP_FECHA';
SELECT COUNT(*) AS lecturas, ROUND(AVG(temperatura_c),2) AS temp_prom
FROM OPTIM.TEL_CK_DISP_FECHA WHERE fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 7;

-- ===== Q4 y Q5: items (marzo de 2018 y una semana) =====
ALTER SESSION SET QUERY_TAG = 'F4CL_Q4_ITEM_BASE';
SELECT COUNT(*) AS items, SUM(precio) AS ingreso, SUM(flete) AS flete
FROM OPTIM.ITEM_BASE WHERE fecha_compra_key BETWEEN 20180301 AND 20180331;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q4_ITEM_FECHA';
SELECT COUNT(*) AS items, SUM(precio) AS ingreso, SUM(flete) AS flete
FROM OPTIM.ITEM_CK_FECHA WHERE fecha_compra_key BETWEEN 20180301 AND 20180331;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q5_ITEM_BASE';
SELECT COUNT(*) AS items, SUM(precio) AS ingreso
FROM OPTIM.ITEM_BASE WHERE fecha_compra_key BETWEEN 20180301 AND 20180307;

ALTER SESSION SET QUERY_TAG = 'F4CL_Q5_ITEM_FECHA';
SELECT COUNT(*) AS items, SUM(precio) AS ingreso
FROM OPTIM.ITEM_CK_FECHA WHERE fecha_compra_key BETWEEN 20180301 AND 20180307;

ALTER SESSION UNSET QUERY_TAG;

SELECT query_tag                                        AS consulta,
       partitions_scanned                               AS particiones_escaneadas,
       partitions_total                                 AS particiones_totales,
       ROUND(100 * partitions_scanned / NULLIF(partitions_total, 0), 1) AS pct_escaneado,
       ROUND(bytes_scanned / 1024 / 1024)               AS mb_escaneados,
       ROUND(total_elapsed_time / 1000, 2)              AS segundos
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_tag LIKE 'F4CL%'
  AND query_type = 'SELECT'
  AND start_time > DATEADD('hour', -3, CURRENT_TIMESTAMP())
QUALIFY ROW_NUMBER() OVER (PARTITION BY query_tag ORDER BY start_time DESC) = 1
ORDER BY SUBSTR(query_tag, 1, 7), query_tag;

