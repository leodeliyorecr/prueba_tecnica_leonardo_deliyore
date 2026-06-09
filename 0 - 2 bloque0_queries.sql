/*
Fecha: 8 Junio 2026
Prueba Tecnica: Data Analyst -  Leonardo Antonio Deliyore Tellez
bloque0_auditoria.sql
*/


SELECT 'vendors' as Table_Test, COUNT(*) as Total FROM `leo-deliyore-analytics-2026.retail_data.vendors`
UNION ALL
SELECT 'products', COUNT(*) FROM `leo-deliyore-analytics-2026.retail_data.products`
UNION ALL
SELECT 'stores', COUNT(*) FROM `leo-deliyore-analytics-2026.retail_data.stores`
UNION ALL
SELECT 'store_promotions', COUNT(*) FROM `leo-deliyore-analytics-2026.retail_data.store_promotions`
UNION ALL
SELECT 'transactions', COUNT(*) FROM `leo-deliyore-analytics-2026.retail_data.transactions`
UNION ALL
SELECT 'transaction_items', COUNT(*) FROM `leo-deliyore-analytics-2026.retail_data.transaction_items`


/*

------------- Query 1 ----------------
Completitud ¿Qué porcentaje de transacciones no tiene customer_id ? ¿Es consistente con loyalty_card = FALSE ?
 
*/

-- Inicio
SELECT
  COUNTIF(loyalty_card = FALSE) AS loyalty_false,
  COUNTIF(loyalty_card = TRUE) AS loyalty_true,
  ROUND(COUNTIF(loyalty_card = FALSE) / COUNT(*) * 100, 1) AS POR_loyalty_false,
  ROUND(COUNTIF(loyalty_card = TRUE) / COUNT(*) * 100, 1) AS POR_loyalty_true,
  -- Consistencia: loyalty_card=FALSE sin customer_id deben ser iguales
  COUNTIF(loyalty_card = FALSE AND customer_id IS NULL) AS loyalty_false_sin_id,
  COUNTIF(loyalty_card = TRUE AND customer_id IS NULL) AS inconsistencia_critica
FROM `leo-deliyore-analytics-2026.retail_data.transactions`;

------------- Fin --------------------




/*
------------- Query 2 ----------------
Consistencia ¿El total_amount en transactions coincide con la suma de unit_price × quantity
en transaction_items?
 
*/

/*
SELECT transaction_id, quantity, unit_price, (quantity * unit_price) items_total_amount 
FROM `leo-deliyore-analytics-2026.retail_data.transaction_items`  
where transaction_id = 'TX_00000008'

SELECT transaction_id, total_amount from `leo-deliyore-analytics-2026.retail_data.transactions` where transaction_id = 'TX_00000008'
*/


WITH calculated AS (
  SELECT
    transaction_id,
    SUM(unit_price * quantity) AS items_total_amount
  FROM `leo-deliyore-analytics-2026.retail_data.transaction_items`
  GROUP BY transaction_id
)
SELECT
  COUNT(*) AS total_transacciones,
  COUNTIF(ABS(t.total_amount - c.items_total_amount) > 0.01) AS inconsistentes,
  ROUND(COUNTIF(ABS(t.total_amount - c.items_total_amount) > 0.01) / COUNT(*) * 100, 1) AS pct_inconsistentes,
  ROUND(AVG(CASE WHEN ABS(t.total_amount - c.items_total_amount) > 0.01
    THEN ABS(t.total_amount - c.items_total_amount) END), 2) AS diferencia_promedio,
  ROUND(MAX(ABS(t.total_amount - c.items_total_amount)), 2) AS diferencia_maxima
FROM `leo-deliyore-analytics-2026.retail_data.transactions` t
JOIN calculated c ON t.transaction_id = c.transaction_id;

------------- Fin --------------------



/*
------------- Query 3 ----------------
Unicidad ¿Existen 'transaction_id' duplicados?
 
*/

/*
SELECT count(*)
FROM `leo-deliyore-analytics-2026.retail_data.transactions`

SELECT distinct transaction_id 
FROM `leo-deliyore-analytics-2026.retail_data.transactions`
*/

SELECT 'trans' AS tabla,
       COUNT(*) AS total_registros,
       COUNT(DISTINCT transaction_id) AS ids_unicos,
       COUNT(*) - COUNT(DISTINCT transaction_id) AS cant_duplicados
FROM `leo-deliyore-analytics-2026.retail_data.transactions`
 
------------- Fin --------------------



/*
------------- Query 4 ----------------
Validez     ¿Hay 'total_amount' negativos o cero? 
            ¿Hay 'unit_price = 0' con 'was_on_promo = FALSE'?
*/


-- 4.1 --
SELECT
  transaction_id,
  customer_id,
  total_amount,
  status,
  transaction_date,
  store_id
FROM `leo-deliyore-analytics-2026.retail_data.transactions`
WHERE total_amount <= 0
ORDER BY total_amount;

-- 4.2 --

SELECT
  COUNT(*) AS items_precio_cero_sin_promo,
FROM `leo-deliyore-analytics-2026.retail_data.transaction_items`
WHERE unit_price = 0
  AND was_on_promo = FALSE;

------------- Fin --------------------




/*
------------- Query 5 ----------------
Integridad referencial     ¿Hay 'store_id' en transactions que no existan en stores? 
                           ¿'vendor_id' en products que no existan en vendors?
*/


SELECT
  COUNT(DISTINCT t.store_id) AS registros_huerfanos
FROM `leo-deliyore-analytics-2026.retail_data.transactions` T
LEFT JOIN `leo-deliyore-analytics-2026.retail_data.stores` S
  ON T.store_id = S.store_id
WHERE S.store_id IS NULL
 


SELECT DISTINCT p.vendor_id, COUNT(*) AS productos_afectados
FROM `leo-deliyore-analytics-2026.retail_data.products` P
LEFT JOIN `leo-deliyore-analytics-2026.retail_data.vendors` V
  ON P.vendor_id = V.vendor_id
WHERE V.vendor_id IS NULL
GROUP BY P.vendor_id;

------------- Fin --------------------


/*
------------- Query 6 ----------------
Frescura    ¿Hay tiendas con gaps de días consecutivos sin transacciones?

*/

WITH daily_trans AS (
  SELECT
    store_id,
    transaction_date,
    LAG(transaction_date) OVER (
      PARTITION BY store_id
      ORDER BY transaction_date
    ) AS prev_date
  FROM (
    SELECT DISTINCT store_id, transaction_date
    FROM `leo-deliyore-analytics-2026.retail_data.transactions`
  )
)
SELECT
  store_id,
  prev_date AS fecha_inicio_gap,
  transaction_date AS fecha_fin_gap,
  DATE_DIFF(transaction_date, prev_date, DAY) AS gap_dias
FROM daily_trans
WHERE DATE_DIFF(transaction_date, prev_date, DAY) >= 7
ORDER BY gap_dias DESC;

------------- Fin --------------------


/*
------------- Query 7 ----------------
Integridad Temporal     ¿Existe alguna tienda con transacciones anteriores a su `opening_date`?
*/

SELECT
  T.store_id,
  S.opening_date,
  COUNT(*) AS transacciones_antes_apertura,
  MIN(T.transaction_date) AS primera_tran_invalida,
  MAX(T.transaction_date) AS ultima_tran_invalida,
  ROUND(SUM(T.total_amount), 2) AS total_amount_afectado
FROM `leo-deliyore-analytics-2026.retail_data.transactions` T
JOIN `leo-deliyore-analytics-2026.retail_data.stores` S
  ON T.store_id = S.store_id
WHERE T.transaction_date < S.opening_date
GROUP BY T.store_id, S.opening_date
ORDER BY transacciones_antes_apertura DESC;

------------- Fin --------------------


/*
------------- Query 8 ----------------
Integridad Temporal     ¿Existe alguna tienda con transacciones anteriores a su `opening_date`?
*/


SELECT  
    store_id,
    COUNT(DISTINCT variant) AS num_variantes,
FROM `leo-deliyore-analytics-2026.retail_data.store_promotions` 
group by store_id
HAVING COUNT(DISTINCT variant) > 1;