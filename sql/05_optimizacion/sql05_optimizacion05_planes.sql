USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALISIS;
USE DATABASE DWH_OLIST;

SET v_disp = (SELECT dispositivo_key FROM OPTIM.TEL_BASE GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1);
SET v_mes  = (SELECT FLOOR(fecha_key / 100) FROM OPTIM.TEL_BASE
              WHERE dispositivo_key = $v_disp GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1);

-- ANTES: tabla sin clave
EXPLAIN
SELECT COUNT(*), AVG(temperatura_c) FROM OPTIM.TEL_BASE
WHERE dispositivo_key = $v_disp AND fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 31;

-- DESPUES: tabla con clave (dispositivo_key, fecha_key)
EXPLAIN
SELECT COUNT(*), AVG(temperatura_c) FROM OPTIM.TEL_CK_DISP_FECHA
WHERE dispositivo_key = $v_disp AND fecha_key BETWEEN $v_mes * 100 + 1 AND $v_mes * 100 + 31;