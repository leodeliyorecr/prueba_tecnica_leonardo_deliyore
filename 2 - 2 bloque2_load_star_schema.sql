/*
  bloque2_load_star_schema.sql
  Autor: Leonardo Deliyore Téllez
  Dataset: leo-deliyore-analytics-2026.retail_data (mismo dataset — tablas raw + Star Schema)

  Parte 2 de Star_Schema

  -- Generales

  PRIVACIDAD: customer_id -- Hash utilizado SHA-256 - recomendado por RGPD


*/


-- ///////////////////////////////////
-- 1. Load dim_vendor
-- Surrogate key: ROW_NUMBER sobre vendor_id ordenado
-- VND_031: vendor huérfano
-- //////////////////////////////////


INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_vendor`
SELECT

  ROW_NUMBER() OVER (ORDER BY vendor_id)  AS vendor_key,
  vendor_id,
  vendor_name,
  country,
  tier,
  is_shared_catalog,
  TRUE AS is_valid 
FROM `leo-deliyore-analytics-2026.retail_data.vendors`

UNION ALL

SELECT
  9999        AS vendor_key,
  'VND_031'   AS vendor_id,
  'UNKNOWN'   AS vendor_name,
  'UNKNOWN'   AS country,
  'UNKNOWN'   AS tier,
  FALSE       AS is_shared_catalog,
  FALSE       AS is_valid 
;



-- ///////////////////////////////////
-- 2. Load dim_product
-- //////////////////////////////////

INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_product`
SELECT  ROW_NUMBER() OVER (ORDER BY p.item_id)  AS product_key,
  p.item_id, p.item_name, p.brand, dv.vendor_key, p.vendor_id,
  p.category, p.department, p.cost, 
  p.vendor_id = 'VND_031'AS is_orphan_vendor
FROM `leo-deliyore-analytics-2026.retail_data.products` p
LEFT JOIN `leo-deliyore-analytics-2026.retail_data.dim_vendor` dv
  ON p.vendor_id = dv.vendor_id
;


-- ///////////////////////////////////
-- 3: Load dim_store
-- is_comparable: TRUE si opening_date <= 13 meses
-- ///////////////////////////////////

INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_store`
WITH max_date AS (
  SELECT MAX(transaction_date) AS max_tx_date
  FROM `leo-deliyore-analytics-2026.retail_data.transactions`
)
SELECT
  ROW_NUMBER() OVER (ORDER BY s.store_id)  AS store_key,
  s.store_id, s.store_name, s.country, s.city, s.format, s.size_sqm,
  s.opening_date, s.region,
  s.opening_date <= DATE_SUB(m.max_tx_date, INTERVAL 13 MONTH) AS is_comparable,
  s.opening_date  AS valid_from,
  CAST(NULL AS DATE)  AS valid_to,
  TRUE            AS is_current
FROM `leo-deliyore-analytics-2026.retail_data.stores` s
CROSS JOIN max_date m
;



-- 4: Load dim_customer

INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_customer`
WITH first_tx AS (
  SELECT
    customer_id,
    MIN(transaction_date)                        AS first_transaction_date,
    DATE_TRUNC(MIN(transaction_date), MONTH)     AS cohort_month,
    ARRAY_AGG(store_id ORDER BY transaction_date LIMIT 1)[OFFSET(0)] AS first_store_id
  FROM `leo-deliyore-analytics-2026.retail_data.transactions`
  WHERE
    loyalty_card  = TRUE
    AND customer_id IS NOT NULL
    AND total_amount > 0          
    AND status    = 'COMPLETED'
  GROUP BY customer_id
)
SELECT
  ROW_NUMBER() OVER (ORDER BY ft.customer_id)  AS customer_key,
  TO_HEX(SHA256(ft.customer_id))               AS customer_id_hashed,
  ft.cohort_month,
  ft.first_transaction_date,
  ds.store_key                                  AS acquisition_store_key,
  ds.country                                    AS acquisition_country
FROM first_tx ft
LEFT JOIN `leo-deliyore-analytics-2026.retail_data.dim_store` ds
  ON ft.first_store_id = ds.store_id AND ds.is_current = TRUE
;


-- 5: Load dim_promotion

INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_promotion`
SELECT
  ROW_NUMBER() OVER (ORDER BY store_id, promo_name, variant)  AS promotion_key,
  store_id,
  promo_name,
  variant,
  start_date,
  end_date,
  promo_type,
  store_id IN ('TIENDA_008', 'TIENDA_037')  AS is_contaminated
FROM `leo-deliyore-analytics-2026.retail_data.store_promotions`
;



-- 6: Load fact_sales  


INSERT INTO `leo-deliyore-analytics-2026.retail_data.fact_sales`
WITH


base AS (
  SELECT ti.transaction_item_id, ti.transaction_id, t.transaction_date,
    CAST(FORMAT_DATE('%Y%m%d', t.transaction_date) AS INT64) AS transaction_date_key,
    ds.store_key, dp.product_key, dc.customer_key, t.payment_method, t.loyalty_card,
    t.status, ti.quantity, ti.unit_price, ti.unit_price * ti.quantity AS gmv,
    dp_raw.cost AS unit_cost, (ti.unit_price - dp_raw.cost) * ti.quantity AS gross_margin,
    ti.was_on_promo, t.total_amount AS total_amount_reported,
    CASE
      WHEN t.total_amount <= 0
        THEN 'MONTO_INVALIDO'
      WHEN t.transaction_date < s.opening_date
        THEN 'TRAN_ANTES_APERTURA'
      WHEN ti.unit_price = 0 AND ti.was_on_promo = FALSE
        THEN 'PRECIO_CERO_SIN_PROMO'
      ELSE NULL 
    END AS data_quality_flag
  FROM `leo-deliyore-analytics-2026.retail_data.transaction_items` ti

  JOIN `leo-deliyore-analytics-2026.retail_data.transactions` t
    ON ti.transaction_id = t.transaction_id

  JOIN `leo-deliyore-analytics-2026.retail_data.stores` s
    ON t.store_id = s.store_id

  JOIN `leo-deliyore-analytics-2026.retail_data.dim_store` ds
    ON t.store_id = ds.store_id AND ds.is_current = TRUE

  JOIN `leo-deliyore-analytics-2026.retail_data.products` dp_raw
    ON ti.item_id = dp_raw.item_id

  JOIN `leo-deliyore-analytics-2026.retail_data.dim_product` dp
    ON ti.item_id = dp.item_id

  LEFT JOIN `leo-deliyore-analytics-2026.retail_data.dim_customer` dc
    ON TO_HEX(SHA256(t.customer_id)) = dc.customer_id_hashed
    AND t.loyalty_card = TRUE
    AND t.customer_id IS NOT NULL
)

SELECT * FROM base
;


-- STEP 7: Cargar bridge_promotion

INSERT INTO `leo-deliyore-analytics-2026.retail_data.bridge_promotion`
SELECT DISTINCT
  t.transaction_id,
  dp.promotion_key
FROM `leo-deliyore-analytics-2026.retail_data.transactions` t
JOIN `leo-deliyore-analytics-2026.retail_data.dim_store` ds
  ON t.store_id = ds.store_id AND ds.is_current = TRUE
JOIN `leo-deliyore-analytics-2026.retail_data.dim_promotion` dp
  ON ds.store_id = dp.store_id
  AND t.transaction_date BETWEEN dp.start_date AND dp.end_date
;







