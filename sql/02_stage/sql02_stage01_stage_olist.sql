USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

CREATE OR REPLACE TABLE STAGE.STG_CLIENTES AS
SELECT TRIM(customer_id)                           AS customer_id,
       TRIM(customer_unique_id)                    AS customer_unique_id,
       LPAD(TRIM(customer_zip_code_prefix), 5, '0') AS zip_prefix,
       LOWER(TRIM(customer_city))                  AS ciudad,
       UPPER(TRIM(customer_state))                 AS estado
FROM RAW.CUSTOMERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(customer_id) ORDER BY _fila) = 1;

CREATE OR REPLACE TABLE STAGE.STG_VENDEDORES AS
SELECT TRIM(seller_id)                             AS seller_id,
       LPAD(TRIM(seller_zip_code_prefix), 5, '0')  AS zip_prefix,
       LOWER(TRIM(seller_city))                    AS ciudad,
       UPPER(TRIM(seller_state))                   AS estado
FROM RAW.SELLERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(seller_id) ORDER BY _fila) = 1;

-- Categorias: traduccion de Olist + categorias sin traduccion + categoria "sin_categoria"
CREATE OR REPLACE TABLE STAGE.STG_CATEGORIAS AS
SELECT TRIM(product_category_name)         AS categoria_pt,
       TRIM(product_category_name_english) AS categoria_en,
       'OLIST'                             AS origen
FROM RAW.CATEGORY_TRANSLATION
UNION ALL
SELECT DISTINCT TRIM(p.product_category_name), TRIM(p.product_category_name), 'SIN_TRADUCCION'
FROM RAW.PRODUCTS p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM RAW.CATEGORY_TRANSLATION t
                  WHERE TRIM(t.product_category_name) = TRIM(p.product_category_name))
UNION ALL
SELECT 'sin_categoria', 'sin_categoria', 'SIN_CATEGORIA';

CREATE OR REPLACE TABLE STAGE.STG_PRODUCTOS AS
SELECT TRIM(product_id) AS product_id,
       COALESCE(NULLIF(TRIM(product_category_name), ''), 'sin_categoria') AS categoria_pt,
       TRY_TO_NUMBER(product_name_lenght, 12, 2)::INT        AS longitud_nombre,
       TRY_TO_NUMBER(product_description_lenght, 12, 2)::INT AS longitud_descripcion,
       TRY_TO_NUMBER(product_photos_qty, 12, 2)::INT         AS num_fotos,
       TRY_TO_NUMBER(product_weight_g, 12, 2)::INT           AS peso_g,
       TRY_TO_NUMBER(product_length_cm, 12, 2)::INT          AS largo_cm,
       TRY_TO_NUMBER(product_height_cm, 12, 2)::INT          AS alto_cm,
       TRY_TO_NUMBER(product_width_cm, 12, 2)::INT           AS ancho_cm
FROM RAW.PRODUCTS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(product_id) ORDER BY _fila) = 1;

CREATE OR REPLACE TABLE STAGE.STG_PEDIDOS AS
SELECT TRIM(order_id)                                       AS order_id,
       TRIM(customer_id)                                    AS customer_id,
       LOWER(TRIM(order_status))                            AS estado_pedido,
       TRY_TO_TIMESTAMP_NTZ(order_purchase_timestamp)       AS fecha_compra,
       TRY_TO_TIMESTAMP_NTZ(order_approved_at)              AS fecha_aprobacion,
       TRY_TO_TIMESTAMP_NTZ(order_delivered_carrier_date)   AS fecha_envio_transportista,
       TRY_TO_TIMESTAMP_NTZ(order_delivered_customer_date)  AS fecha_entrega_cliente,
       TRY_TO_TIMESTAMP_NTZ(order_estimated_delivery_date)  AS fecha_entrega_estimada
FROM RAW.ORDERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(order_id) ORDER BY _fila) = 1;

CREATE OR REPLACE TABLE STAGE.STG_ITEMS AS
SELECT TRIM(order_id)                           AS order_id,
       TRY_TO_NUMBER(order_item_id)             AS order_item_id,
       TRIM(product_id)                         AS product_id,
       TRIM(seller_id)                          AS seller_id,
       TRY_TO_TIMESTAMP_NTZ(shipping_limit_date) AS fecha_limite_envio,
       TRY_TO_NUMBER(price, 12, 2)              AS precio,
       TRY_TO_NUMBER(freight_value, 12, 2)      AS flete
FROM RAW.ORDER_ITEMS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(order_id), TRY_TO_NUMBER(order_item_id) ORDER BY _fila) = 1;

CREATE OR REPLACE TABLE STAGE.STG_PAGOS AS
SELECT TRIM(order_id)                        AS order_id,
       TRY_TO_NUMBER(payment_sequential)     AS pago_secuencia,
       LOWER(TRIM(payment_type))             AS tipo_pago,
       TRY_TO_NUMBER(payment_installments)   AS cuotas,
       TRY_TO_NUMBER(payment_value, 12, 2)   AS monto
FROM RAW.ORDER_PAYMENTS
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(order_id), TRY_TO_NUMBER(payment_sequential) ORDER BY _fila) = 1;

-- Resenas: un registro por (review_id, order_id). No se guarda el texto del comentario.
CREATE OR REPLACE TABLE STAGE.STG_RESENAS AS
SELECT TRIM(review_id)                              AS review_id,
       TRIM(order_id)                               AS order_id,
       TRY_TO_NUMBER(review_score)                  AS calificacion,
       (review_comment_message IS NOT NULL)         AS tiene_comentario,
       TRY_TO_TIMESTAMP_NTZ(review_creation_date)   AS fecha_creacion,
       TRY_TO_TIMESTAMP_NTZ(review_answer_timestamp) AS fecha_respuesta
FROM RAW.ORDER_REVIEWS
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY TRIM(review_id), TRIM(order_id)
          ORDER BY TRY_TO_TIMESTAMP_NTZ(review_answer_timestamp) DESC NULLS LAST, _fila) = 1;

-- Geografia: 1 fila por prefijo postal (geolocalizacion + prefijos de clientes/vendedores que faltan)
CREATE OR REPLACE TABLE STAGE.STG_GEOGRAFIA AS
WITH geo AS (
  SELECT LPAD(TRIM(geolocation_zip_code_prefix), 5, '0')       AS zip_prefix,
         AVG(TRY_TO_DOUBLE(geolocation_lat))                    AS lat,
         AVG(TRY_TO_DOUBLE(geolocation_lng))                    AS lon,
         MODE(LOWER(TRIM(geolocation_city)))                    AS ciudad,
         MODE(UPPER(TRIM(geolocation_state)))                   AS estado,
         COUNT(*)                                               AS n_puntos
  FROM RAW.GEOLOCATION
  WHERE geolocation_zip_code_prefix IS NOT NULL
    AND TRY_TO_DOUBLE(geolocation_lat) BETWEEN -34 AND 6
    AND TRY_TO_DOUBLE(geolocation_lng) BETWEEN -74 AND -34
  GROUP BY 1
),
usados AS (
  SELECT zip_prefix, ciudad, estado FROM STAGE.STG_CLIENTES
  UNION ALL
  SELECT zip_prefix, ciudad, estado FROM STAGE.STG_VENDEDORES
),
faltantes AS (
  SELECT u.zip_prefix, MODE(u.ciudad) AS ciudad, MODE(u.estado) AS estado
  FROM usados u
  WHERE u.zip_prefix IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM geo g WHERE g.zip_prefix = u.zip_prefix)
  GROUP BY u.zip_prefix
)
SELECT zip_prefix, lat, lon, ciudad, estado, n_puntos, 'GEOLOCATION' AS origen FROM geo
UNION ALL
SELECT zip_prefix, NULL, NULL, ciudad, estado, 0, 'CLIENTE_VENDEDOR' FROM faltantes;