USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

-- Conteos: origen (STAGE) vs destino (CORE)
SELECT tabla, filas_stage, filas_core, IFF(filas_stage = filas_core, 'OK', 'REVISAR') AS resultado
FROM (
  SELECT 'GEOGRAFIA' AS tabla, (SELECT COUNT(*) FROM STAGE.STG_GEOGRAFIA) AS filas_stage, (SELECT COUNT(*) FROM CORE.DIM_GEOGRAFIA) AS filas_core
  UNION ALL SELECT 'CLIENTE',   (SELECT COUNT(*) FROM STAGE.STG_CLIENTES),   (SELECT COUNT(*) FROM CORE.DIM_CLIENTE)
  UNION ALL SELECT 'VENDEDOR',  (SELECT COUNT(*) FROM STAGE.STG_VENDEDORES), (SELECT COUNT(*) FROM CORE.DIM_VENDEDOR)
  UNION ALL SELECT 'CATEGORIA', (SELECT COUNT(*) FROM STAGE.STG_CATEGORIAS), (SELECT COUNT(*) FROM CORE.DIM_CATEGORIA)
  UNION ALL SELECT 'PRODUCTO',  (SELECT COUNT(*) FROM STAGE.STG_PRODUCTOS),  (SELECT COUNT(*) FROM CORE.DIM_PRODUCTO)
  UNION ALL SELECT 'ITEM_PEDIDO', (SELECT COUNT(*) FROM STAGE.STG_ITEMS),    (SELECT COUNT(*) FROM CORE.FACT_ITEM_PEDIDO)
  UNION ALL SELECT 'PAGO',      (SELECT COUNT(*) FROM STAGE.STG_PAGOS),      (SELECT COUNT(*) FROM CORE.FACT_PAGO)
  UNION ALL SELECT 'RESENA',    (SELECT COUNT(*) FROM STAGE.STG_RESENAS),    (SELECT COUNT(*) FROM CORE.FACT_RESENA)
)
ORDER BY tabla;

-- Claves sin resolver en el hecho principal (esperado: todo 0)
SELECT COUNT_IF(producto_key IS NULL)     AS sin_producto,
       COUNT_IF(vendedor_key IS NULL)     AS sin_vendedor,
       COUNT_IF(cliente_key IS NULL)      AS sin_cliente,
       COUNT_IF(fecha_compra_key IS NULL) AS sin_fecha_compra
FROM CORE.FACT_ITEM_PEDIDO;

-- Fechas del hecho que no existen en DIM_FECHA (esperado: 0)
SELECT COUNT(*) AS fechas_fuera_de_dim
FROM CORE.FACT_ITEM_PEDIDO f
WHERE NOT EXISTS (SELECT 1 FROM CORE.DIM_FECHA d WHERE d.fecha_key = f.fecha_compra_key);

-- Muestra del hecho (para la captura)
SELECT pedido_id, item_numero, estado_pedido, precio, flete, dias_despacho, dias_retraso, entregado_a_tiempo
FROM CORE.FACT_ITEM_PEDIDO
LIMIT 10;