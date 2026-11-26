USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

-- ---------- DIM_FECHA (2016-01-01 a 2019-12-31 = 1461 dias) ----------
MERGE INTO CORE.DIM_FECHA t
USING (
  SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d) AS fecha_key,
         d                                          AS fecha,
         YEAR(d)                                    AS anio,
         QUARTER(d)                                 AS trimestre,
         MONTH(d)                                   AS mes,
         MONTHNAME(d)                               AS nombre_mes,
         DAY(d)                                     AS dia,
         DAYOFWEEKISO(d)                            AS dia_semana,
         DAYNAME(d)                                 AS nombre_dia,
         (DAYOFWEEKISO(d) >= 6)                     AS es_fin_de_semana
  FROM (
    SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2016-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 1461))
  )
) s
ON t.fecha_key = s.fecha_key
WHEN MATCHED THEN UPDATE SET
  fecha = s.fecha, anio = s.anio, trimestre = s.trimestre, mes = s.mes,
  nombre_mes = s.nombre_mes, dia = s.dia, dia_semana = s.dia_semana,
  nombre_dia = s.nombre_dia, es_fin_de_semana = s.es_fin_de_semana
WHEN NOT MATCHED THEN INSERT
  (fecha_key, fecha, anio, trimestre, mes, nombre_mes, dia, dia_semana, nombre_dia, es_fin_de_semana)
VALUES
  (s.fecha_key, s.fecha, s.anio, s.trimestre, s.mes, s.nombre_mes, s.dia, s.dia_semana, s.nombre_dia, s.es_fin_de_semana);

-- ---------- DIM_GEOGRAFIA ----------
MERGE INTO CORE.DIM_GEOGRAFIA t
USING STAGE.STG_GEOGRAFIA s
ON t.zip_prefix = s.zip_prefix
WHEN MATCHED THEN UPDATE SET
  ciudad = s.ciudad, estado = s.estado, latitud = s.lat, longitud = s.lon, n_puntos = s.n_puntos
WHEN NOT MATCHED THEN INSERT (zip_prefix, ciudad, estado, latitud, longitud, n_puntos)
VALUES (s.zip_prefix, s.ciudad, s.estado, s.lat, s.lon, s.n_puntos);

-- ---------- DIM_CLIENTE ----------
MERGE INTO CORE.DIM_CLIENTE t
USING (
  SELECT c.customer_id, c.customer_unique_id, g.geografia_key
  FROM STAGE.STG_CLIENTES c
  LEFT JOIN CORE.DIM_GEOGRAFIA g ON g.zip_prefix = c.zip_prefix
) s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN UPDATE SET
  customer_unique_id = s.customer_unique_id, geografia_key = s.geografia_key
WHEN NOT MATCHED THEN INSERT (customer_id, customer_unique_id, geografia_key)
VALUES (s.customer_id, s.customer_unique_id, s.geografia_key);

-- ---------- DIM_VENDEDOR ----------
MERGE INTO CORE.DIM_VENDEDOR t
USING (
  SELECT v.seller_id, g.geografia_key
  FROM STAGE.STG_VENDEDORES v
  LEFT JOIN CORE.DIM_GEOGRAFIA g ON g.zip_prefix = v.zip_prefix
) s
ON t.seller_id = s.seller_id
WHEN MATCHED THEN UPDATE SET geografia_key = s.geografia_key
WHEN NOT MATCHED THEN INSERT (seller_id, geografia_key)
VALUES (s.seller_id, s.geografia_key);

-- ---------- DIM_CATEGORIA ----------
MERGE INTO CORE.DIM_CATEGORIA t
USING STAGE.STG_CATEGORIAS s
ON t.categoria_pt = s.categoria_pt
WHEN MATCHED THEN UPDATE SET categoria_en = s.categoria_en, origen_traduccion = s.origen
WHEN NOT MATCHED THEN INSERT (categoria_pt, categoria_en, origen_traduccion)
VALUES (s.categoria_pt, s.categoria_en, s.origen);

-- ---------- DIM_PRODUCTO ----------
MERGE INTO CORE.DIM_PRODUCTO t
USING (
  SELECT p.product_id, c.categoria_key, p.longitud_nombre, p.longitud_descripcion,
         p.num_fotos, p.peso_g, p.largo_cm, p.alto_cm, p.ancho_cm
  FROM STAGE.STG_PRODUCTOS p
  LEFT JOIN CORE.DIM_CATEGORIA c ON c.categoria_pt = p.categoria_pt
) s
ON t.product_id = s.product_id
WHEN MATCHED THEN UPDATE SET
  categoria_key = s.categoria_key, longitud_nombre = s.longitud_nombre,
  longitud_descripcion = s.longitud_descripcion, num_fotos = s.num_fotos,
  peso_g = s.peso_g, largo_cm = s.largo_cm, alto_cm = s.alto_cm, ancho_cm = s.ancho_cm
WHEN NOT MATCHED THEN INSERT
  (product_id, categoria_key, longitud_nombre, longitud_descripcion, num_fotos, peso_g, largo_cm, alto_cm, ancho_cm)
VALUES
  (s.product_id, s.categoria_key, s.longitud_nombre, s.longitud_descripcion, s.num_fotos, s.peso_g, s.largo_cm, s.alto_cm, s.ancho_cm);

-- ---------- FACT_ITEM_PEDIDO ----------
MERGE INTO CORE.FACT_ITEM_PEDIDO t
USING (
  SELECT i.order_id AS pedido_id,
         i.order_item_id AS item_numero,
         dp.producto_key,
         dv.vendedor_key,
         dc.cliente_key,
         YEAR(o.fecha_compra) * 10000 + MONTH(o.fecha_compra) * 100 + DAY(o.fecha_compra) AS fecha_compra_key,
         YEAR(o.fecha_entrega_estimada) * 10000 + MONTH(o.fecha_entrega_estimada) * 100 + DAY(o.fecha_entrega_estimada) AS fecha_entrega_estimada_key,
         YEAR(o.fecha_entrega_cliente) * 10000 + MONTH(o.fecha_entrega_cliente) * 100 + DAY(o.fecha_entrega_cliente) AS fecha_entrega_real_key,
         o.estado_pedido,
         o.fecha_compra               AS fecha_compra_ts,
         o.fecha_envio_transportista  AS fecha_envio_transportista_ts,
         o.fecha_entrega_cliente      AS fecha_entrega_real_ts,
         o.fecha_entrega_estimada     AS fecha_entrega_estimada_ts,
         i.fecha_limite_envio         AS fecha_limite_envio_ts,
         i.precio,
         i.flete,
         DATEDIFF('day', o.fecha_compra, o.fecha_envio_transportista)        AS dias_despacho,
         DATEDIFF('day', o.fecha_entrega_estimada, o.fecha_entrega_cliente)  AS dias_retraso,
         IFF(o.fecha_entrega_cliente IS NULL OR o.fecha_entrega_estimada IS NULL,
             NULL,
             DATEDIFF('day', o.fecha_entrega_estimada, o.fecha_entrega_cliente) <= 0) AS entregado_a_tiempo
  FROM STAGE.STG_ITEMS i
  JOIN STAGE.STG_PEDIDOS o      ON o.order_id = i.order_id
  LEFT JOIN CORE.DIM_PRODUCTO dp ON dp.product_id = i.product_id
  LEFT JOIN CORE.DIM_VENDEDOR dv ON dv.seller_id = i.seller_id
  LEFT JOIN CORE.DIM_CLIENTE dc  ON dc.customer_id = o.customer_id
) s
ON t.pedido_id = s.pedido_id AND t.item_numero = s.item_numero
WHEN MATCHED THEN UPDATE SET
  producto_key = s.producto_key, vendedor_key = s.vendedor_key, cliente_key = s.cliente_key,
  fecha_compra_key = s.fecha_compra_key,
  fecha_entrega_estimada_key = s.fecha_entrega_estimada_key,
  fecha_entrega_real_key = s.fecha_entrega_real_key,
  estado_pedido = s.estado_pedido,
  fecha_compra_ts = s.fecha_compra_ts,
  fecha_envio_transportista_ts = s.fecha_envio_transportista_ts,
  fecha_entrega_real_ts = s.fecha_entrega_real_ts,
  fecha_entrega_estimada_ts = s.fecha_entrega_estimada_ts,
  fecha_limite_envio_ts = s.fecha_limite_envio_ts,
  precio = s.precio, flete = s.flete,
  dias_despacho = s.dias_despacho, dias_retraso = s.dias_retraso,
  entregado_a_tiempo = s.entregado_a_tiempo
WHEN NOT MATCHED THEN INSERT
  (pedido_id, item_numero, producto_key, vendedor_key, cliente_key,
   fecha_compra_key, fecha_entrega_estimada_key, fecha_entrega_real_key, estado_pedido,
   fecha_compra_ts, fecha_envio_transportista_ts, fecha_entrega_real_ts,
   fecha_entrega_estimada_ts, fecha_limite_envio_ts, precio, flete,
   dias_despacho, dias_retraso, entregado_a_tiempo)
VALUES
  (s.pedido_id, s.item_numero, s.producto_key, s.vendedor_key, s.cliente_key,
   s.fecha_compra_key, s.fecha_entrega_estimada_key, s.fecha_entrega_real_key, s.estado_pedido,
   s.fecha_compra_ts, s.fecha_envio_transportista_ts, s.fecha_entrega_real_ts,
   s.fecha_entrega_estimada_ts, s.fecha_limite_envio_ts, s.precio, s.flete,
   s.dias_despacho, s.dias_retraso, s.entregado_a_tiempo);

-- ---------- FACT_PAGO ----------
MERGE INTO CORE.FACT_PAGO t
USING (
  SELECT p.order_id AS pedido_id, p.pago_secuencia, dc.cliente_key,
         YEAR(o.fecha_compra) * 10000 + MONTH(o.fecha_compra) * 100 + DAY(o.fecha_compra) AS fecha_compra_key,
         p.tipo_pago, p.cuotas, p.monto
  FROM STAGE.STG_PAGOS p
  JOIN STAGE.STG_PEDIDOS o      ON o.order_id = p.order_id
  LEFT JOIN CORE.DIM_CLIENTE dc ON dc.customer_id = o.customer_id
) s
ON t.pedido_id = s.pedido_id AND t.pago_secuencia = s.pago_secuencia
WHEN MATCHED THEN UPDATE SET
  cliente_key = s.cliente_key, fecha_compra_key = s.fecha_compra_key,
  tipo_pago = s.tipo_pago, cuotas = s.cuotas, monto = s.monto
WHEN NOT MATCHED THEN INSERT
  (pedido_id, pago_secuencia, cliente_key, fecha_compra_key, tipo_pago, cuotas, monto)
VALUES
  (s.pedido_id, s.pago_secuencia, s.cliente_key, s.fecha_compra_key, s.tipo_pago, s.cuotas, s.monto);

-- ---------- FACT_RESENA ----------
MERGE INTO CORE.FACT_RESENA t
USING (
  SELECT r.review_id, r.order_id AS pedido_id, dc.cliente_key,
         YEAR(r.fecha_creacion) * 10000 + MONTH(r.fecha_creacion) * 100 + DAY(r.fecha_creacion) AS fecha_creacion_key,
         r.calificacion, r.tiene_comentario, r.fecha_respuesta AS fecha_respuesta_ts
  FROM STAGE.STG_RESENAS r
  JOIN STAGE.STG_PEDIDOS o      ON o.order_id = r.order_id
  LEFT JOIN CORE.DIM_CLIENTE dc ON dc.customer_id = o.customer_id
) s
ON t.review_id = s.review_id AND t.pedido_id = s.pedido_id
WHEN MATCHED THEN UPDATE SET
  cliente_key = s.cliente_key, fecha_creacion_key = s.fecha_creacion_key,
  calificacion = s.calificacion, tiene_comentario = s.tiene_comentario,
  fecha_respuesta_ts = s.fecha_respuesta_ts
WHEN NOT MATCHED THEN INSERT
  (review_id, pedido_id, cliente_key, fecha_creacion_key, calificacion, tiene_comentario, fecha_respuesta_ts)
VALUES
  (s.review_id, s.pedido_id, s.cliente_key, s.fecha_creacion_key, s.calificacion, s.tiene_comentario, s.fecha_respuesta_ts);