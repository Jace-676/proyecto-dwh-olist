USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

CREATE OR REPLACE TABLE OPTIM.TEL_CK_FECHA_DISP CLUSTER BY (fecha_key, dispositivo_key) AS
SELECT * FROM OPTIM.TEL_BASE ORDER BY fecha_key, dispositivo_key;

CREATE OR REPLACE TABLE OPTIM.TEL_CK_DISP_FECHA CLUSTER BY (dispositivo_key, fecha_key) AS
SELECT * FROM OPTIM.TEL_BASE ORDER BY dispositivo_key, fecha_key;

CREATE OR REPLACE TABLE OPTIM.ITEM_CK_FECHA CLUSTER BY (fecha_compra_key) AS
SELECT * FROM OPTIM.ITEM_BASE ORDER BY fecha_compra_key;

ALTER TABLE OPTIM.TEL_CK_FECHA_DISP SUSPEND RECLUSTER;
ALTER TABLE OPTIM.TEL_CK_DISP_FECHA SUSPEND RECLUSTER;
ALTER TABLE OPTIM.ITEM_CK_FECHA     SUSPEND RECLUSTER;

SELECT tabla, clave,
       j:total_partition_count::INT           AS particiones,
       j:total_constant_partition_count::INT  AS particiones_constantes,
       ROUND(j:average_overlaps::FLOAT, 2)    AS solapamiento_prom,
       ROUND(j:average_depth::FLOAT, 2)       AS profundidad_prom
FROM (
  SELECT 'TEL_BASE (sin clave)' AS tabla, '(fecha_key, dispositivo_key)' AS clave,
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.TEL_BASE','(fecha_key, dispositivo_key)')) AS j
  UNION ALL
  SELECT 'TEL_BASE (sin clave)', '(dispositivo_key, fecha_key)',
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.TEL_BASE','(dispositivo_key, fecha_key)'))
  UNION ALL
  SELECT 'TEL_CK_FECHA_DISP', '(fecha_key, dispositivo_key)',
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.TEL_CK_FECHA_DISP','(fecha_key, dispositivo_key)'))
  UNION ALL
  SELECT 'TEL_CK_DISP_FECHA', '(dispositivo_key, fecha_key)',
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.TEL_CK_DISP_FECHA','(dispositivo_key, fecha_key)'))
  UNION ALL
  SELECT 'ITEM_BASE (sin clave)', '(fecha_compra_key)',
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.ITEM_BASE','(fecha_compra_key)'))
  UNION ALL
  SELECT 'ITEM_CK_FECHA', '(fecha_compra_key)',
         PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('DWH_OLIST.OPTIM.ITEM_CK_FECHA','(fecha_compra_key)'))
)
ORDER BY tabla, clave;