USE ROLE SYSADMIN;
USE WAREHOUSE WH_CARGA;
USE DATABASE DWH_OLIST;

CREATE TABLE IF NOT EXISTS CONTROL.BITACORA_CARGA (
  lote              STRING,
  tabla_destino     STRING,
  archivo           STRING,
  filas_leidas      NUMBER,
  filas_cargadas    NUMBER,
  filas_rechazadas  NUMBER,
  estado            STRING,
  fecha_carga       TIMESTAMP_NTZ
);

-- MERGE para que ejecutarlo varias veces no duplique registros
MERGE INTO CONTROL.BITACORA_CARGA b
USING (
  SELECT 'L001'                         AS lote,
         table_name                     AS tabla_destino,
         file_name                      AS archivo,
         row_parsed                     AS filas_leidas,
         row_count                      AS filas_cargadas,
         row_parsed - row_count         AS filas_rechazadas,
         status                         AS estado,
         last_load_time::TIMESTAMP_NTZ  AS fecha_carga
  FROM DWH_OLIST.INFORMATION_SCHEMA.LOAD_HISTORY
  WHERE schema_name = 'RAW'
    AND table_name IN ('CUSTOMERS','GEOLOCATION','ORDER_ITEMS','ORDER_PAYMENTS',
                       'ORDER_REVIEWS','ORDERS','PRODUCTS','SELLERS','CATEGORY_TRANSLATION')
) s
ON  b.lote = s.lote AND b.tabla_destino = s.tabla_destino AND b.archivo = s.archivo
WHEN NOT MATCHED THEN INSERT
  (lote, tabla_destino, archivo, filas_leidas, filas_cargadas, filas_rechazadas, estado, fecha_carga)
VALUES
  (s.lote, s.tabla_destino, s.archivo, s.filas_leidas, s.filas_cargadas, s.filas_rechazadas, s.estado, s.fecha_carga);

SELECT * FROM CONTROL.BITACORA_CARGA ORDER BY tabla_destino;