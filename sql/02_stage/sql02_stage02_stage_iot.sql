USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

-- Ruta esperada por pedido: primer item -> vendedor; cliente del pedido.
-- Solo pedidos con coordenadas distintas (ST_MAKELINE no admite dos puntos iguales).
CREATE OR REPLACE TABLE STAGE.STG_RUTA_PEDIDO AS
WITH primer_item AS (
  SELECT order_id, seller_id
  FROM STAGE.STG_ITEMS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_item_id) = 1
)
SELECT o.order_id,
       gv.lat AS origen_lat, gv.lon AS origen_lon,
       gc.lat AS destino_lat, gc.lon AS destino_lon
FROM STAGE.STG_PEDIDOS o
JOIN primer_item i          ON i.order_id = o.order_id
JOIN STAGE.STG_VENDEDORES v ON v.seller_id = i.seller_id
JOIN STAGE.STG_CLIENTES c   ON c.customer_id = o.customer_id
JOIN STAGE.STG_GEOGRAFIA gv ON gv.zip_prefix = v.zip_prefix
JOIN STAGE.STG_GEOGRAFIA gc ON gc.zip_prefix = c.zip_prefix
WHERE gv.lat IS NOT NULL AND gv.lon IS NOT NULL
  AND gc.lat IS NOT NULL AND gc.lon IS NOT NULL
  AND (gv.lat <> gc.lat OR gv.lon <> gc.lon);

-- Lecturas depuradas y clasificadas (incluye las RECHAZADAS, marcadas: es la cuarentena)
CREATE TABLE IF NOT EXISTS STAGE.STG_TELEMETRIA (
  device_id            VARCHAR(20),
  lectura_ts           TIMESTAMP_NTZ,
  latitud              FLOAT,
  longitud             FLOAT,
  temperatura_c        FLOAT,
  velocidad_kmh        FLOAT,
  perfil_termico       VARCHAR(20),
  pedido_principal_id  VARCHAR,
  n_pedidos            NUMBER,
  desvio_km            FLOAT,
  clase_termica        VARCHAR(20),
  clase_movimiento     VARCHAR(20),
  clase_calidad        VARCHAR(20),
  motivo_calidad       VARCHAR(40),
  _archivo             VARCHAR,
  _lote                VARCHAR(10),
  _fecha_stage         TIMESTAMP_NTZ
);

-- Resultado de LATERAL FLATTEN sobre order_ids
CREATE TABLE IF NOT EXISTS STAGE.STG_TELEMETRIA_PEDIDO (
  device_id     VARCHAR(20),
  lectura_ts    TIMESTAMP_NTZ,
  order_id      VARCHAR,
  _lote         VARCHAR(10),
  _fecha_stage  TIMESTAMP_NTZ
);

CREATE OR REPLACE VIEW STAGE.V_TELEMETRIA_CUARENTENA AS
SELECT * FROM STAGE.STG_TELEMETRIA WHERE clase_calidad = 'RECHAZADA';

-- Bitacora por proceso y lote
CREATE TABLE IF NOT EXISTS CONTROL.BITACORA_PROCESO (
  proceso              VARCHAR,
  lote                 VARCHAR,
  filas_entrada        NUMBER,
  filas_nuevas_stage   NUMBER,
  filas_no_insertadas  NUMBER,   -- duplicadas (ya existian) o sin clave
  filas_rechazadas     NUMBER,
  filas_sospechosas    NUMBER,
  fecha_proceso        TIMESTAMP_NTZ
);

-- Evidencia de idempotencia
CREATE TABLE IF NOT EXISTS CONTROL.PRUEBA_IDEMPOTENCIA (
  etiqueta  VARCHAR,
  tabla     VARCHAR,
  filas     NUMBER,
  checksum  NUMBER(38,0),
  momento   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

SELECT COUNT(*) AS rutas_disponibles FROM STAGE.STG_RUTA_PEDIDO;   -- decenas de miles