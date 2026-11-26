USE ROLE SYSADMIN;
USE WAREHOUSE WH_CARGA;
USE DATABASE DWH_OLIST;

CREATE OR REPLACE TABLE RAW.CUSTOMERS (
  customer_id STRING, customer_unique_id STRING, customer_zip_code_prefix STRING,
  customer_city STRING, customer_state STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.GEOLOCATION (
  geolocation_zip_code_prefix STRING, geolocation_lat STRING, geolocation_lng STRING,
  geolocation_city STRING, geolocation_state STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDER_ITEMS (
  order_id STRING, order_item_id STRING, product_id STRING, seller_id STRING,
  shipping_limit_date STRING, price STRING, freight_value STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDER_PAYMENTS (
  order_id STRING, payment_sequential STRING, payment_type STRING,
  payment_installments STRING, payment_value STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDER_REVIEWS (
  review_id STRING, order_id STRING, review_score STRING,
  review_comment_title STRING, review_comment_message STRING,
  review_creation_date STRING, review_answer_timestamp STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDERS (
  order_id STRING, customer_id STRING, order_status STRING,
  order_purchase_timestamp STRING, order_approved_at STRING,
  order_delivered_carrier_date STRING, order_delivered_customer_date STRING,
  order_estimated_delivery_date STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.PRODUCTS (
  product_id STRING, product_category_name STRING, product_name_lenght STRING,
  product_description_lenght STRING, product_photos_qty STRING, product_weight_g STRING,
  product_length_cm STRING, product_height_cm STRING, product_width_cm STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.SELLERS (
  seller_id STRING, seller_zip_code_prefix STRING, seller_city STRING, seller_state STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.CATEGORY_TRANSLATION (
  product_category_name STRING, product_category_name_english STRING,
  _archivo STRING, _fila NUMBER, _lote STRING,
  _fecha_ingesta TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

SHOW TABLES IN SCHEMA RAW;