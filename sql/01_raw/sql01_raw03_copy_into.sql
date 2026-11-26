USE ROLE SYSADMIN;
USE WAREHOUSE WH_CARGA;
USE DATABASE DWH_OLIST;

COPY INTO RAW.CUSTOMERS
  (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
   _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_customers_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.GEOLOCATION
  (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city,
   geolocation_state, _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_geolocation_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.ORDER_ITEMS
  (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value,
   _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_order_items_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.ORDER_PAYMENTS
  (order_id, payment_sequential, payment_type, payment_installments, payment_value,
   _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_order_payments_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.ORDER_REVIEWS
  (review_id, order_id, review_score, review_comment_title, review_comment_message,
   review_creation_date, review_answer_timestamp, _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_order_reviews_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.ORDERS
  (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
   order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date,
   _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_orders_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.PRODUCTS
  (product_id, product_category_name, product_name_lenght, product_description_lenght,
   product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm,
   _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_products_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.SELLERS
  (seller_id, seller_zip_code_prefix, seller_city, seller_state, _archivo, _fila, _lote)
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*olist_sellers_dataset\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.CATEGORY_TRANSLATION
  (product_category_name, product_category_name_english, _archivo, _fila, _lote)
FROM (SELECT $1, $2, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, 'L001'
      FROM @RAW.STG_OLIST)
PATTERN = '.*product_category_name_translation\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV_OLIST')
ON_ERROR = 'ABORT_STATEMENT';