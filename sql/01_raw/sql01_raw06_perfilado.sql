USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

SELECT n, hallazgo, filas
FROM (
  SELECT 1 AS n, 'Pedidos sin fecha de entrega al cliente (cualquier estado)' AS hallazgo, COUNT(*) AS filas
  FROM RAW.ORDERS WHERE order_delivered_customer_date IS NULL
  UNION ALL
  SELECT 2, 'Pedidos "delivered" sin fecha de entrega al cliente', COUNT(*)
  FROM RAW.ORDERS WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
  UNION ALL
  SELECT 3, 'Productos sin categoria', COUNT(*)
  FROM RAW.PRODUCTS WHERE product_category_name IS NULL
  UNION ALL
  SELECT 4, 'Productos con categoria sin traduccion', COUNT(*)
  FROM RAW.PRODUCTS p
  WHERE p.product_category_name IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM RAW.CATEGORY_TRANSLATION t
                    WHERE t.product_category_name = p.product_category_name)
  UNION ALL
  SELECT 5, 'Categorias distintas sin traduccion', COUNT(DISTINCT p.product_category_name)
  FROM RAW.PRODUCTS p
  WHERE p.product_category_name IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM RAW.CATEGORY_TRANSLATION t
                    WHERE t.product_category_name = p.product_category_name)
  UNION ALL
  SELECT 6, 'Resenas: filas con review_id repetido (sobrantes)', COUNT(*) - COUNT(DISTINCT review_id)
  FROM RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 7, 'Pedidos con mas de una resena', COUNT(*)
  FROM (SELECT order_id FROM RAW.ORDER_REVIEWS GROUP BY order_id HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 8, 'Pedidos sin resena', COUNT(*)
  FROM RAW.ORDERS o
  WHERE NOT EXISTS (SELECT 1 FROM RAW.ORDER_REVIEWS r WHERE r.order_id = o.order_id)
  UNION ALL
  SELECT 9, 'Pedidos sin items', COUNT(*)
  FROM RAW.ORDERS o
  WHERE NOT EXISTS (SELECT 1 FROM RAW.ORDER_ITEMS i WHERE i.order_id = o.order_id)
  UNION ALL
  SELECT 10, 'Items cuyo pedido no existe', COUNT(*)
  FROM RAW.ORDER_ITEMS i
  WHERE NOT EXISTS (SELECT 1 FROM RAW.ORDERS o WHERE o.order_id = i.order_id)
  UNION ALL
  SELECT 11, 'Items cuyo producto no existe', COUNT(*)
  FROM RAW.ORDER_ITEMS i
  WHERE NOT EXISTS (SELECT 1 FROM RAW.PRODUCTS p WHERE p.product_id = i.product_id)
  UNION ALL
  SELECT 12, 'Items cuyo vendedor no existe', COUNT(*)
  FROM RAW.ORDER_ITEMS i
  WHERE NOT EXISTS (SELECT 1 FROM RAW.SELLERS s WHERE s.seller_id = i.seller_id)
  UNION ALL
  SELECT 13, 'Pedidos con entrega anterior a la compra', COUNT(*)
  FROM RAW.ORDERS
  WHERE TRY_TO_TIMESTAMP_NTZ(order_delivered_customer_date) < TRY_TO_TIMESTAMP_NTZ(order_purchase_timestamp)
  UNION ALL
  SELECT 14, 'Pagos con tipo not_defined', COUNT(*)
  FROM RAW.ORDER_PAYMENTS WHERE payment_type = 'not_defined'
  UNION ALL
  SELECT 15, 'Geolocalizacion: filas totales', COUNT(*) FROM RAW.GEOLOCATION
  UNION ALL
  SELECT 16, 'Geolocalizacion: prefijos postales distintos', COUNT(DISTINCT geolocation_zip_code_prefix)
  FROM RAW.GEOLOCATION
  UNION ALL
  SELECT 17, 'Geolocalizacion: coordenadas fuera de Brasil', COUNT(*)
  FROM RAW.GEOLOCATION
  WHERE NOT (TRY_TO_DOUBLE(geolocation_lat) BETWEEN -34 AND 6
         AND TRY_TO_DOUBLE(geolocation_lng) BETWEEN -74 AND -34)
)
ORDER BY n;