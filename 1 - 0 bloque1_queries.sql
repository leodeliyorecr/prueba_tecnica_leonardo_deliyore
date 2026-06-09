/*
bloque1_queries.sql
Fecha: 8 Junio 2026
Prueba Tecnica: Data Analyst -  Leonardo Antonio Deliyore Tellez
Herramienta: BigQuery SQL
DataSet leo-deliyore-analytics-2026.retail_data
Cadena de Retail Multiformato · Centroamérica
*/


-- Filtros encontrados en bloque0_auditoria.md
-- 1. total_amount > 0          → excluye 3 transacciones con monto inválido
-- 2. transaction_date >= opening_date → excluye 50 tx antes de apertura (TIENDA_037)
-- 3. unit_price > 0            → excluye 231 ítems con precio cero sin promo
-- 4. vendor_id != 'VND_031'    → excluye vendor huérfano en análisis GMROI
-- 5. TIENDA_008 y TIENDA_037   → excluidas del análisis A/B (contaminadas)
-- 6. status = 'COMPLETED'      → Se excluyen 3,553 devoluciones = status = RETURNED 


/*

------------- Query 1 - Ventas comparables (Comp Sales)----------------
Calcula el crecimiento YoY solo para tiendas que estuvieron operando en ambos períodos 
(excluye tiendas abiertas hace menos de 13 meses). Por país y formato muestra:


-- En la tabla de transacciones hay operaciones de todo el año 2024, pero en el 2025 solo hay 6 meses
-- por lo que solo se compara entre los meses de enero a junio
 
*/

WITH

gmv_by_store_year AS (
  SELECT t.store_id,
    EXTRACT(YEAR FROM t.transaction_date) AS year,
    SUM(ti.unit_price * ti.quantity) AS gmv
  FROM `leo-deliyore-analytics-2026.retail_data.transactions` t
  JOIN `leo-deliyore-analytics-2026.retail_data.transaction_items` ti
    ON t.transaction_id = ti.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON t.store_id = s.store_id
  WHERE
    t.total_amount > 0
    AND t.transaction_date >= s.opening_date
    AND t.status = 'COMPLETED'
    AND ti.unit_price > 0
    AND EXTRACT(MONTH FROM t.transaction_date) BETWEEN 1 AND 6
  GROUP BY t.store_id, year
),

comparable_stores AS (
  SELECT store_id
  FROM `leo-deliyore-analytics-2026.retail_data.stores`
  WHERE opening_date <= DATE_SUB(
    (SELECT MAX(transaction_date) FROM `leo-deliyore-analytics-2026.retail_data.transactions`),
    INTERVAL 13 MONTH
  )
),

comp_sales AS (
  SELECT g.store_id,
    MAX(CASE WHEN g.year = 2024 THEN g.gmv END) AS gmv_2024,
    MAX(CASE WHEN g.year = 2025 THEN g.gmv END) AS gmv_2025
  FROM gmv_by_store_year g
  INNER JOIN comparable_stores cs ON g.store_id = cs.store_id
  GROUP BY g.store_id
)

SELECT s.country, s.format, s.store_id, s.store_name,
  ROUND(cs.gmv_2024, 2) AS gmv_ene_jun_2024,
  ROUND(cs.gmv_2025, 2) AS gmv_ene_jun_2025,
  ROUND((cs.gmv_2025 - cs.gmv_2024) / cs.gmv_2024 * 100, 2) AS POR_comp_sales_growth,
  RANK() OVER (
    PARTITION BY s.format
    ORDER BY (cs.gmv_2025 - cs.gmv_2024) / cs.gmv_2024 DESC
  ) AS ranking_dentro_formato
FROM comp_sales cs
JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
  ON cs.store_id = s.store_id
WHERE cs.gmv_2024 IS NOT NULL
  AND cs.gmv_2025 IS NOT NULL
ORDER BY s.country, s.format, POR_comp_sales_growth DESC;

------------- Fin --------------------


/*

------------- Query 2 - Productividad por metro cuadrado---------------
-- GMV/m², transacciones/m², ticket promedio — ranking dentro de su formato
-- Marca BAJO_RENDIMIENTO: percentil 25 dentro de formato
 
*/


WITH

last_quarter AS (
  SELECT t.store_id,
    SUM(ti.unit_price * ti.quantity) AS gmv_trimestre,
    COUNT(DISTINCT t.transaction_id) AS num_transacciones
  FROM `leo-deliyore-analytics-2026.retail_data.transactions` t
  JOIN `leo-deliyore-analytics-2026.retail_data.transaction_items` ti
    ON t.transaction_id = ti.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON t.store_id = s.store_id
  WHERE
    t.transaction_date >= DATE_SUB(
      (SELECT MAX(transaction_date) FROM `leo-deliyore-analytics-2026.retail_data.transactions`),
      INTERVAL 3 MONTH
    )
    AND t.total_amount > 0
    AND t.transaction_date >= s.opening_date
    AND t.status = 'COMPLETED'
    AND ti.unit_price > 0
  GROUP BY t.store_id
),

store_metrics AS (
  SELECT s.store_id, s.store_name, s.country, s.format, s.size_sqm, lq.gmv_trimestre,
    ROUND(lq.gmv_trimestre / s.size_sqm, 2) AS gmv_por_m2,
    ROUND(lq.num_transacciones / s.size_sqm, 4) AS transacciones_por_m2,
    ROUND(lq.gmv_trimestre / lq.num_transacciones, 2) AS ticket_promedio
  FROM last_quarter lq
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON lq.store_id = s.store_id
),

percentiles AS (
  SELECT DISTINCT
    format,
    PERCENTILE_CONT(gmv_por_m2, 0.25) OVER (PARTITION BY format) AS p25_gmv_m2
  FROM store_metrics
)

SELECT sm.store_id, sm.store_name, sm.country, sm.format, sm.size_sqm,
  ROUND(sm.gmv_trimestre, 2) AS gmv_trimestre,
  sm.gmv_por_m2, sm.transacciones_por_m2, sm.ticket_promedio,
  RANK() OVER (PARTITION BY sm.format ORDER BY sm.gmv_por_m2 DESC) AS ranking_formato,
  CASE
    WHEN sm.gmv_por_m2 <= p.p25_gmv_m2 THEN 'BAJO_RENDIMIENTO'
    ELSE 'NORMAL'
  END AS estado_rendimiento
FROM store_metrics sm
JOIN percentiles p ON sm.format = p.format
ORDER BY sm.format, sm.gmv_por_m2 DESC;

------------- Fin --------------------


------------- Query 3 - Analisis de cohortes de Clientes con Tarjeta de Lealtad---------------
-- Cohorte = mes de primera transacción
-- Tamaño de cada cohorte
-- Retención en meses 1, 2, 3 y 6 
-- Si el ticket crece o decrece con el tiempo
-- Tabla Pivoteada


WITH
-- Primera transacción por cliente
first_transaction AS (
  SELECT customer_id,
    MIN(transaction_date) AS first_date,
    DATE_TRUNC(MIN(transaction_date), MONTH) AS cohort_month
  FROM `leo-deliyore-analytics-2026.retail_data.transactions`
  WHERE
    loyalty_card = TRUE
    AND customer_id IS NOT NULL
    AND total_amount > 0                -- filtros
    AND status = 'COMPLETED'            
  GROUP BY customer_id
),

-- GMV transacciones de clientes con pl
loyalty_transactions AS (
  SELECT T.customer_id, T.transaction_date,
    SUM(Ti.unit_price * Ti.quantity) AS GMV
  FROM `leo-deliyore-analytics-2026.retail_data.transactions` T
  JOIN `leo-deliyore-analytics-2026.retail_data.transaction_items` Ti
    ON T.transaction_id = Ti.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` S
    ON T.store_id = S.store_id
  WHERE
    T.loyalty_card = TRUE
    AND T.customer_id IS NOT NULL
    AND T.total_amount > 0              -- filtros
    AND T.transaction_date >= S.opening_date
    AND Ti.unit_price > 0               
    AND T.status = 'COMPLETED'          

  GROUP BY T.customer_id, T.transaction_date
),

-- Mes de adquisicion
cohort_data AS (
  SELECT FT.cohort_month, LT.customer_id,
    DATE_DIFF(DATE_TRUNC(LT.transaction_date, MONTH), FT.cohort_month, MONTH) AS month_number,
    LT.gmv
  FROM loyalty_transactions LT
  JOIN first_transaction ft ON LT.customer_id = FT.customer_id
),

-- Tamaño de Cohorte
cohort_size AS (
  SELECT cohort_month,
    COUNT(DISTINCT customer_id) AS cohort_customers
  FROM first_transaction
  GROUP BY cohort_month
),

-- Actividad por cohorte y mes
cohort_activity AS (
  SELECT cohort_month, month_number,
    COUNT(DISTINCT customer_id) AS active_customers,
    ROUND(SUM(gmv) / COUNT(DISTINCT customer_id), 2) AS avg_ticket
  FROM cohort_data
  WHERE month_number IN (0, 1, 2, 3, 6)
  GROUP BY cohort_month, month_number
)

-- Tabla pivot:
SELECT FORMAT_DATE('%Y-%m', CA.cohort_month) AS cohort_month,
  CS.cohort_customers AS cohort_size,
  -- Mes 1
  ROUND(MAX(CASE WHEN CA.month_number = 1 THEN CA.active_customers END)
    / CS.cohort_customers * 100, 1) AS POR_retention_mes_1,
  MAX(CASE WHEN CA.month_number = 1 THEN CA.avg_ticket END) AS ticket_mes_1,
  -- Mes 2
  ROUND(MAX(CASE WHEN CA.month_number = 2 THEN CA.active_customers END)
    / CS.cohort_customers * 100, 1) AS POR_retention_mes_2,
  MAX(CASE WHEN CA.month_number = 2 THEN CA.avg_ticket END) AS ticket_mes_2,
  -- Mes 3
  ROUND(MAX(CASE WHEN CA.month_number = 3 THEN CA.active_customers END)
    / CS.cohort_customers * 100, 1) AS POR_retention_mes_3,
  MAX(CASE WHEN CA.month_number = 3 THEN CA.avg_ticket END) AS ticket_mes_3,
  -- Mes 6
  ROUND(MAX(CASE WHEN CA.month_number = 6 THEN CA.active_customers END)
    / CS.cohort_customers * 100, 1) AS POR_retention_mes_6,
  MAX(CASE WHEN CA.month_number = 6 THEN CA.avg_ticket END) AS ticket_mes_6
FROM cohort_activity CA
JOIN cohort_size CS ON CA.cohort_month = CS.cohort_month
GROUP BY CA.cohort_month, CS.cohort_customers
ORDER BY CA.cohort_month;

------------- Fin --------------------

------------- Query 4 - GMROI por Proveedor y Categoría---------------
-- GMROI = Margen Bruto / Costo Total
-- Marca GMROI_BAJO cuando < 1
-- Excluye vendor huérfano VND_031


WITH

vendor_category_metrics AS (
  SELECT P.vendor_id, V.vendor_name, P.category,
    SUM(Ti.unit_price * Ti.quantity) AS gmv,
    SUM(P.cost * Ti.quantity) AS costo_total,
    SUM((Ti.unit_price - P.cost) * Ti.quantity) AS margen_bruto,
    COUNT(DISTINCT P.item_id) AS skus_activos,
    ROUND(
      SUM(Ti.quantity) /
      NULLIF(DATE_DIFF(MAX(T.transaction_date), MIN(T.transaction_date), DAY), 0)
    , 2) AS velocidad_venta_unidades_dia
  FROM `leo-deliyore-analytics-2026.retail_data.transaction_items` Ti
  JOIN `leo-deliyore-analytics-2026.retail_data.transactions` T
    ON Ti.transaction_id = T.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` S
    ON T.store_id = S.store_id
  JOIN `leo-deliyore-analytics-2026.retail_data.products` P
    ON Ti.item_id = P.item_id
  JOIN `leo-deliyore-analytics-2026.retail_data.vendors` V
    ON P.vendor_id = V.vendor_id
  WHERE
    T.total_amount > 0                          -- filtros
    AND T.transaction_date >= S.opening_date    
    AND Ti.unit_price > 0                       
    AND P.vendor_id != 'VND_031'                
    AND T.status = 'COMPLETED'                  
  GROUP BY P.vendor_id, V.vendor_name, P.category
)

SELECT vendor_id, vendor_name, category,
  ROUND(gmv, 2) AS gmv,
  ROUND(costo_total, 2) AS costo_total,
  ROUND(margen_bruto, 2) AS margen_bruto,
  ROUND(margen_bruto / NULLIF(costo_total, 0), 4) AS gmroi,
  skus_activos, velocidad_venta_unidades_dia,
  CASE
    WHEN margen_bruto / NULLIF(costo_total, 0) < 1 THEN 'GMROI_BAJO'
    ELSE 'OK'
  END AS estado_gmroi
FROM vendor_category_metrics
ORDER BY gmroi ASC;

------------- Fin --------------------



------------- Query 5 - Detección de Posibles Quiebres de Stock---------------
-- Gap de 3+ días consecutivos sin ventas en tienda donde históricamente sí se vendía el ítem
-- Ordenado por GMV estimado perdido DESC


WITH

-- Ventas diarias por tienda e ítem
sales_by_store_item AS (
  SELECT t.store_id, ti.item_id, t.transaction_date,
    SUM(ti.quantity) AS units_sold,
    SUM(ti.unit_price * ti.quantity) AS gmv
  FROM `leo-deliyore-analytics-2026.retail_data.transactions` t
  JOIN `leo-deliyore-analytics-2026.retail_data.transaction_items` ti
    ON t.transaction_id = ti.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON t.store_id = s.store_id
  WHERE
    t.total_amount > 0                          -- filtros
    AND t.transaction_date >= s.opening_date                   
    AND ti.unit_price > 0
    AND t.status = 'COMPLETED'                          
  GROUP BY t.store_id, ti.item_id, t.transaction_date
),

-- Ventas promedio diarias historicas
avg_daily_sales AS (
  SELECT store_id, item_id,
    AVG(units_sold) AS avg_units_per_day,
    AVG(gmv) AS avg_gmv_per_day
  FROM sales_by_store_item
  GROUP BY store_id, item_id
  HAVING COUNT(DISTINCT transaction_date) >= 7
),

-- Detectar gaps entre ventas consecutivas
gaps AS (
  SELECT store_id, item_id, transaction_date AS sale_after_gap,
    LAG(transaction_date) OVER (
      PARTITION BY store_id, item_id
      ORDER BY transaction_date
    ) AS last_sale_date,
    DATE_DIFF(
      transaction_date,
      LAG(transaction_date) OVER (
        PARTITION BY store_id, item_id
        ORDER BY transaction_date
      ),
      DAY
    ) AS gap_days
  FROM sales_by_store_item
)

SELECT g.store_id, g.item_id, p.item_name, p.category, g.last_sale_date AS fecha_inicio_gap, g.sale_after_gap AS fecha_fin_gap,
  g.gap_days AS duracion_dias,
  ROUND(ads.avg_units_per_day, 2) AS ventas_promedio_diarias,
  ROUND(ads.avg_gmv_per_day * (g.gap_days - 1), 2) AS gmv_estimado_perdido
FROM gaps g
JOIN avg_daily_sales ads
  ON g.store_id = ads.store_id AND g.item_id = ads.item_id
JOIN `leo-deliyore-analytics-2026.retail_data.products` p
  ON g.item_id = p.item_id
WHERE
  g.gap_days >= 3
  AND g.last_sale_date IS NOT NULL
ORDER BY gmv_estimado_perdido DESC;

------------- Fin --------------------



------------- Query 6 - Impacto de Promociones en Ticket y Volumen---------------
-- Compara transacciones CON y SIN ítems en promoción
-- ¿Basket uplift real o solo descuento en lo mismo?


WITH

-- Clasificar cada transacción
transaction_promo_flag AS (
  SELECT transaction_id,
    MAX(
      CASE WHEN was_on_promo = TRUE 
      THEN 1 
      ELSE 0 END
      ) AS has_promo_item
  FROM `leo-deliyore-analytics-2026.retail_data.transaction_items`
  WHERE unit_price > 0                          
  GROUP BY transaction_id
),

-- Metricas por transacción y categoría
transaction_metrics AS (
  SELECT p.category, tpf.has_promo_item, t.transaction_id,
    SUM(ti.unit_price * ti.quantity) AS ticket,
    SUM(ti.quantity) AS total_units
  FROM `leo-deliyore-analytics-2026.retail_data.transaction_items` ti
  JOIN `leo-deliyore-analytics-2026.retail_data.transactions` t
    ON ti.transaction_id = t.transaction_id
  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON t.store_id = s.store_id
  JOIN `leo-deliyore-analytics-2026.retail_data.products` p
    ON ti.item_id = p.item_id
  JOIN transaction_promo_flag tpf
    ON ti.transaction_id = tpf.transaction_id
  WHERE
    t.total_amount > 0                          -- filtros
    AND t.transaction_date >= s.opening_date                     
    AND ti.unit_price > 0                       
    AND t.status = 'COMPLETED' 
  GROUP BY p.category, tpf.has_promo_item, t.transaction_id
)

SELECT category,
  -- Sin promo
  ROUND(AVG(CASE WHEN has_promo_item = 0 THEN ticket END), 2)       AS ticket_sin_promo,
  ROUND(AVG(CASE WHEN has_promo_item = 0 THEN total_units END), 2)  AS unidades_sin_promo,
  COUNT(CASE WHEN has_promo_item = 0 THEN 1 END)                    AS num_tx_sin_promo,
  -- Con promo
  ROUND(AVG(CASE WHEN has_promo_item = 1 THEN ticket END), 2)       AS ticket_con_promo,
  ROUND(AVG(CASE WHEN has_promo_item = 1 THEN total_units END), 2)  AS unidades_con_promo,
  COUNT(CASE WHEN has_promo_item = 1 THEN 1 END)                    AS num_tx_con_promo,
  -- Lift
  ROUND(
    AVG(CASE WHEN has_promo_item = 1 THEN ticket END) -
    AVG(CASE WHEN has_promo_item = 0 THEN ticket END)
  , 2) AS diferencia_ticket,
  ROUND(
    (AVG(CASE WHEN has_promo_item = 1 THEN ticket END) -
     AVG(CASE WHEN has_promo_item = 0 THEN ticket END)) /
    NULLIF(AVG(CASE WHEN has_promo_item = 0 THEN ticket END), 0) * 100
  , 2) AS POR_lift_ticket,
  ROUND(
    (AVG(CASE WHEN has_promo_item = 1 THEN total_units END) -
     AVG(CASE WHEN has_promo_item = 0 THEN total_units END)) /
    NULLIF(AVG(CASE WHEN has_promo_item = 0 THEN total_units END), 0) * 100
  , 2) AS POR_lift_unidades
FROM transaction_metrics
GROUP BY category
ORDER BY POR_lift_ticket DESC;

------------- Fin --------------------
