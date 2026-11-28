USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALISIS;
USE DATABASE DWH_OLIST;

SELECT g.estado                              AS estado_cliente,
       ca.categoria_en                       AS categoria,
       ROUND(SUM(f.precio), 2)               AS ingreso,
       RANK() OVER (PARTITION BY g.estado ORDER BY SUM(f.precio) DESC) AS posicion
FROM CORE.FACT_ITEM_PEDIDO f
JOIN CORE.DIM_CLIENTE   c  ON c.cliente_key    = f.cliente_key
JOIN CORE.DIM_GEOGRAFIA g  ON g.geografia_key  = c.geografia_key
JOIN CORE.DIM_PRODUCTO  p  ON p.producto_key   = f.producto_key
JOIN CORE.DIM_CATEGORIA ca ON ca.categoria_key = p.categoria_key
WHERE f.estado_pedido NOT IN ('canceled', 'unavailable')
GROUP BY g.estado, ca.categoria_en
QUALIFY posicion <= 3
ORDER BY estado_cliente, posicion;

WITH mensual AS (
  SELECT d.anio * 100 + d.mes AS periodo,
         SUM(f.precio)        AS ingreso,
         COUNT(DISTINCT f.pedido_id) AS pedidos
  FROM CORE.FACT_ITEM_PEDIDO f
  JOIN CORE.DIM_FECHA d ON d.fecha_key = f.fecha_compra_key
  WHERE f.estado_pedido NOT IN ('canceled', 'unavailable')
    AND d.anio * 100 + d.mes BETWEEN 201701 AND 201808
  GROUP BY d.anio * 100 + d.mes
)
SELECT periodo,
       ROUND(ingreso, 2) AS ingreso,
       pedidos,
       ROUND(LAG(ingreso) OVER (ORDER BY periodo), 2) AS ingreso_mes_anterior,
       ROUND(100 * (ingreso / NULLIF(LAG(ingreso) OVER (ORDER BY periodo), 0) - 1), 1) AS crecimiento_pct,
       ROUND(SUM(ingreso) OVER (ORDER BY periodo ROWS UNBOUNDED PRECEDING), 2) AS ingreso_acumulado,
       ROUND(AVG(ingreso) OVER (ORDER BY periodo ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS media_movil_3m
FROM mensual
ORDER BY periodo;

WITH pedidos AS (
  SELECT DISTINCT f.pedido_id, c.customer_unique_id,
         DATE_TRUNC('month', f.fecha_compra_ts)::DATE AS mes
  FROM CORE.FACT_ITEM_PEDIDO f
  JOIN CORE.DIM_CLIENTE c ON c.cliente_key = f.cliente_key
  WHERE f.estado_pedido NOT IN ('canceled', 'unavailable')
    AND f.fecha_compra_ts IS NOT NULL
),
primero AS (
  SELECT customer_unique_id, MIN(mes) AS mes_cohorte
  FROM pedidos GROUP BY customer_unique_id
),
actividad AS (
  SELECT p.customer_unique_id, r.mes_cohorte,
         DATEDIFF('month', r.mes_cohorte, p.mes) AS meses_desde
  FROM pedidos p
  JOIN primero r ON r.customer_unique_id = p.customer_unique_id
)
SELECT mes_cohorte,
       COUNT(DISTINCT IFF(meses_desde = 0, customer_unique_id, NULL)) AS clientes_cohorte,
       ROUND(100 * COUNT(DISTINCT IFF(meses_desde = 1, customer_unique_id, NULL))
             / NULLIF(COUNT(DISTINCT IFF(meses_desde = 0, customer_unique_id, NULL)), 0), 2) AS retencion_m1_pct,
       ROUND(100 * COUNT(DISTINCT IFF(meses_desde = 2, customer_unique_id, NULL))
             / NULLIF(COUNT(DISTINCT IFF(meses_desde = 0, customer_unique_id, NULL)), 0), 2) AS retencion_m2_pct,
       ROUND(100 * COUNT(DISTINCT IFF(meses_desde = 3, customer_unique_id, NULL))
             / NULLIF(COUNT(DISTINCT IFF(meses_desde = 0, customer_unique_id, NULL)), 0), 2) AS retencion_m3_pct,
       ROUND(100 * COUNT(DISTINCT IFF(meses_desde = 6, customer_unique_id, NULL))
             / NULLIF(COUNT(DISTINCT IFF(meses_desde = 0, customer_unique_id, NULL)), 0), 2) AS retencion_m6_pct
FROM actividad
WHERE mes_cohorte BETWEEN '2017-01-01' AND '2018-01-01'
GROUP BY mes_cohorte
ORDER BY mes_cohorte;

WITH pedidos AS (
  SELECT DISTINCT f.pedido_id, c.customer_unique_id
  FROM CORE.FACT_ITEM_PEDIDO f
  JOIN CORE.DIM_CLIENTE c ON c.cliente_key = f.cliente_key
  WHERE f.estado_pedido NOT IN ('canceled', 'unavailable')
)
SELECT COUNT(*) AS clientes,
       COUNT_IF(n > 1) AS clientes_con_recompra,
       ROUND(100 * COUNT_IF(n > 1) / COUNT(*), 2) AS pct_recompra
FROM (SELECT customer_unique_id, COUNT(*) AS n FROM pedidos GROUP BY customer_unique_id);

WITH ped AS (
  SELECT f.pedido_id, f.dias_retraso, f.entregado_a_tiempo,
         gv.latitud AS v_lat, gv.longitud AS v_lon,
         gc.latitud AS c_lat, gc.longitud AS c_lon
  FROM CORE.FACT_ITEM_PEDIDO f
  JOIN CORE.DIM_VENDEDOR  v  ON v.vendedor_key  = f.vendedor_key
  JOIN CORE.DIM_GEOGRAFIA gv ON gv.geografia_key = v.geografia_key
  JOIN CORE.DIM_CLIENTE   c  ON c.cliente_key   = f.cliente_key
  JOIN CORE.DIM_GEOGRAFIA gc ON gc.geografia_key = c.geografia_key
  WHERE f.item_numero = 1
    AND f.entregado_a_tiempo IS NOT NULL
    AND gv.latitud IS NOT NULL AND gc.latitud IS NOT NULL
),
dist AS (
  SELECT pedido_id, dias_retraso, entregado_a_tiempo,
         ST_DISTANCE(ST_MAKEPOINT(v_lon, v_lat), ST_MAKEPOINT(c_lon, c_lat)) / 1000 AS km
  FROM ped
)
SELECT CASE WHEN km < 100  THEN '1) menos de 100 km'
            WHEN km < 500  THEN '2) 100 a 500 km'
            WHEN km < 1000 THEN '3) 500 a 1000 km'
            WHEN km < 2000 THEN '4) 1000 a 2000 km'
            ELSE                '5) mas de 2000 km' END AS rango_distancia,
       COUNT(*) AS pedidos,
       ROUND(AVG(dias_retraso), 2) AS dias_retraso_prom,
       ROUND(100 * AVG(IFF(entregado_a_tiempo, 1, 0)), 1) AS pct_a_tiempo
FROM dist
GROUP BY 1
ORDER BY 1;

WITH resena_pedido AS (
  SELECT pedido_id, calificacion
  FROM CORE.FACT_RESENA
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pedido_id
                             ORDER BY fecha_respuesta_ts DESC NULLS LAST, review_id) = 1
),
ped AS (
  SELECT pedido_id, MAX(dias_retraso) AS dias_retraso
  FROM CORE.FACT_ITEM_PEDIDO
  WHERE estado_pedido = 'delivered' AND dias_retraso IS NOT NULL
  GROUP BY pedido_id
)
SELECT CASE WHEN p.dias_retraso <= 0 THEN '1) a tiempo o antes'
            WHEN p.dias_retraso <= 3 THEN '2) retraso 1 a 3 dias'
            WHEN p.dias_retraso <= 7 THEN '3) retraso 4 a 7 dias'
            ELSE                          '4) retraso mayor a 7 dias' END AS situacion_entrega,
       COUNT(*) AS pedidos,
       ROUND(AVG(r.calificacion), 2) AS calificacion_prom,
       ROUND(100 * COUNT_IF(r.calificacion <= 2) / COUNT(*), 1) AS pct_calificacion_1_o_2
FROM ped p
JOIN resena_pedido r ON r.pedido_id = p.pedido_id
GROUP BY 1
ORDER BY 1;

WITH resena_pedido AS (
  SELECT pedido_id, calificacion
  FROM CORE.FACT_RESENA
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pedido_id
                             ORDER BY fecha_respuesta_ts DESC NULLS LAST, review_id) = 1
),
tel AS (
  SELECT t.pedido_principal_id AS pedido_id,
         COUNT_IF(ct.clase IN ('ALERTA', 'CRITICO')) AS lecturas_alerta
  FROM CORE.FACT_TELEMETRIA_IOT t
  JOIN CORE.DIM_CLASIFICACION_IOT ct ON ct.clasificacion_key = t.clasif_termica_key
  GROUP BY t.pedido_principal_id
)
SELECT IFF(tel.lecturas_alerta > 0, 'con alerta termica', 'sin alerta termica') AS grupo,
       COUNT(*) AS pedidos,
       ROUND(AVG(r.calificacion), 3) AS calificacion_prom
FROM tel
JOIN resena_pedido r ON r.pedido_id = tel.pedido_id
GROUP BY 1
ORDER BY 1;

WITH ruta AS (
  SELECT f.pedido_id, gv.estado AS estado_origen, gc.estado AS estado_destino
  FROM CORE.FACT_ITEM_PEDIDO f
  JOIN CORE.DIM_VENDEDOR  v  ON v.vendedor_key  = f.vendedor_key
  JOIN CORE.DIM_GEOGRAFIA gv ON gv.geografia_key = v.geografia_key
  JOIN CORE.DIM_CLIENTE   c  ON c.cliente_key   = f.cliente_key
  JOIN CORE.DIM_GEOGRAFIA gc ON gc.geografia_key = c.geografia_key
  WHERE f.item_numero = 1
),
lect AS (
  SELECT t.pedido_principal_id AS pedido_id,
         COUNT(*) AS lecturas,
         COUNT_IF(ct.clase IN ('ALERTA', 'CRITICO')) AS alertas_termicas,
         COUNT_IF(cm.clase = 'DESVIO') AS desvios
  FROM CORE.FACT_TELEMETRIA_IOT t
  JOIN CORE.DIM_CLASIFICACION_IOT ct ON ct.clasificacion_key = t.clasif_termica_key
  JOIN CORE.DIM_CLASIFICACION_IOT cm ON cm.clasificacion_key = t.clasif_movimiento_key
  GROUP BY t.pedido_principal_id
)
SELECT r.estado_origen || ' -> ' || r.estado_destino AS ruta,
       COUNT(DISTINCT l.pedido_id) AS pedidos,
       SUM(l.lecturas)             AS lecturas,
       SUM(l.alertas_termicas)     AS alertas_termicas,
       SUM(l.desvios)              AS desvios,
       ROUND(100 * SUM(l.alertas_termicas) / SUM(l.lecturas), 2) AS pct_lecturas_en_alerta
FROM ruta r
JOIN lect l ON l.pedido_id = r.pedido_id
GROUP BY r.estado_origen, r.estado_destino
HAVING SUM(l.lecturas) >= 5000
QUALIFY RANK() OVER (ORDER BY SUM(l.alertas_termicas) / SUM(l.lecturas) DESC) <= 10
ORDER BY pct_lecturas_en_alerta DESC;