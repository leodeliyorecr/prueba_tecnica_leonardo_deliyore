
/*
  bloque2_star_schema.sql
  Autor: Leonardo Deliyore Téllez
  Dataset: leo-deliyore-analytics-2026.retail_data (mismo dataset — tablas raw + Star Schema)


--    GENERALES --
--    Clave surrogate: INTEGER en formato YYYYMMDD (ej. 20240115)
--    VND_031 excluido 
--    Hash utilizado SHA-256 - recomendado por RGPD
--    is_contaminated = TRUE para TIENDA_008 y TIENDA_037
--    Se crea tabla puente -- bridge_promotion se requiere porque una tienda puede
      tener varias promociones en el tiempo


-- Fact Table 

--    Granularidad: UN REGISTRO POR ÍTEM POR TRANSACCIÓN
--    (nivel transaction_item_id).
--    Particion en transaction_date
--    Clustered en store_id, category 
--    unit_cost se desnormaliza desde dim_product.cost
*/


-- //////////////////////////////////
/*
Justificacion de que el 60% de transacciones no tienen customer_id

El Bloque 0 confirmó que 104,632 transacciones (59.8%) no tienen customer_id 
porque loyalty_card = FALSE. 
Tiene el desafio de como manejar la ausencia de una dimension
Una respuesta rapida es crear un registro dummy, pero al ser un numero importante
de customer_id = null, esto inflaria las estadisticas hacia ese registro, no se 
puede tener un registro claro de ranking de clientes, por lo que se toma la decision
de solo tomar como clientes a quienes se pueden identificar
y a su vez por temas de privacidad el customer_id se has

*/
-- //////////////////////////////////

-- ///////////////////////////////////
-- 1. dim_date
--    Una fila por día del calendario.
--    Se genera con GENERATE_DATE_ARRAY
-- //////////////////////////////////


CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_date`
(
  date_key          INT64   NOT NULL OPTIONS(description="PK surrogate YYYYMMDD"),
  full_date         DATE    NOT NULL OPTIONS(description="Fecha completa"),
  year              INT64   NOT NULL,
  quarter           INT64   NOT NULL,
  month             INT64   NOT NULL,
  month_name        STRING  NOT NULL,
  week_of_year      INT64   NOT NULL,
  day_of_week       INT64   NOT NULL,
  day_name          STRING  NOT NULL,
  is_weekend        BOOL    NOT NULL,
  is_holiday_CR     BOOL    NOT NULL,
  is_holiday_GT     BOOL    NOT NULL,
  is_holiday_HN     BOOL    NOT NULL,
  is_holiday_SV     BOOL    NOT NULL,
  is_holiday_NI     BOOL    NOT NULL,
  fiscal_period     STRING  NOT NULL
);


-- INSERTs dim_date
-- Existen dias feriados diferentes por pais

INSERT INTO `leo-deliyore-analytics-2026.retail_data.dim_date`
SELECT
  CAST(FORMAT_DATE('%Y%m%d', d) AS INT64)          AS date_key,
  d                                                  AS full_date,
  EXTRACT(YEAR    FROM d)                            AS year,
  EXTRACT(QUARTER FROM d)                            AS quarter,
  EXTRACT(MONTH   FROM d)                            AS month,
  FORMAT_DATE('%B', d)                               AS month_name,
  EXTRACT(ISOWEEK FROM d)                            AS week_of_year,
  EXTRACT(DAYOFWEEK FROM d)                          AS day_of_week,
  FORMAT_DATE('%A', d)                               AS day_name,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7)                AS is_weekend,
  FALSE AS is_holiday_CR,
  FALSE AS is_holiday_GT,
  FALSE AS is_holiday_HN,
  FALSE AS is_holiday_SV,
  FALSE AS is_holiday_NI,
  CONCAT('FY', CAST(EXTRACT(YEAR FROM d) AS STRING),
         '-Q', CAST(EXTRACT(QUARTER FROM d) AS STRING)) AS fiscal_period
FROM UNNEST(GENERATE_DATE_ARRAY(
  '2024-01-01',
  (SELECT MAX(transaction_date) FROM `leo-deliyore-analytics-2026.retail_data.transactions`)
)) AS d;




-- 2. dim_vendor
-- VND_031 excluido 
CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_vendor`
(
  vendor_key        INT64   NOT NULL OPTIONS(description="PK surrogate"),
  vendor_id         STRING  NOT NULL,
  vendor_name       STRING  NOT NULL,
  country           STRING  NOT NULL,
  tier              STRING  NOT NULL,
  is_shared_catalog BOOL    NOT NULL,
  is_valid          BOOL    NOT NULL
);




-- 3. Dim product
CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_product`
(
  product_key       INT64   NOT NULL OPTIONS(description="PK surrogate"),
  item_id           STRING  NOT NULL,
  item_name         STRING  NOT NULL,
  brand             STRING,
  vendor_key        INT64   NOT NULL,
  vendor_id         STRING  NOT NULL,
  category          STRING  NOT NULL,
  department        STRING,
  cost              FLOAT64 NOT NULL,
  is_orphan_vendor  BOOL    NOT NULL
);



-- 4. dim_store

CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_store`
(
  store_key         INT64   NOT NULL OPTIONS(description="PK surrogate"),
  store_id          STRING  NOT NULL,
  store_name        STRING  NOT NULL,
  country           STRING  NOT NULL,
  city              STRING  NOT NULL,
  format            STRING  NOT NULL,
  size_sqm          INT64   NOT NULL, 
  opening_date      DATE    NOT NULL,
  region            STRING  NOT NULL, 
  is_comparable     BOOL    NOT NULL, 
  valid_from        DATE    NOT NULL, 
  valid_to          DATE,            
  is_current        BOOL    NOT NULL 

);



-- ============================================================
-- 5. dim_customer
--    Solo "clientes" con loyalty_card = TRUE
--    en fact_sales es NULL.

CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_customer`
(
  customer_key            INT64   NOT NULL OPTIONS(description="PK surrogate"),
  customer_id_hashed      STRING  NOT NULL,
  cohort_month            DATE    NOT NULL,
  first_transaction_date  DATE    NOT NULL ,
  acquisition_store_key   INT64,           
  acquisition_country     STRING 
);



-- 6. dim_promotion

CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.dim_promotion`
(
  promotion_key     INT64   NOT NULL OPTIONS(description="PK surrogate"),
  store_id          STRING  NOT NULL,
  promo_name        STRING  NOT NULL,
  variant           STRING  NOT NULL,
  start_date        DATE    NOT NULL,
  end_date          DATE    NOT NULL,
  promo_type        STRING  NOT NULL,
  is_contaminated   BOOL    NOT NULL
);


-- 7. bridge_promotion

CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.bridge_promotion`
(
  transaction_id    STRING  NOT NULL,
  promotion_key     INT64   NOT NULL
);



-- 8. fact_sales 
-- Fact Table


CREATE OR REPLACE TABLE `leo-deliyore-analytics-2026.retail_data.fact_sales`
(
  -- Claves
  transaction_item_id     STRING  NOT NULL, 
  transaction_id          STRING  NOT NULL, 
  transaction_date        DATE    NOT NULL, 
  transaction_date_key    INT64   NOT NULL, 
  store_key               INT64   NOT NULL, 
  product_key             INT64   NOT NULL, 
  customer_key            INT64,          
  payment_method          STRING  NOT NULL, 
  loyalty_card            BOOL    NOT NULL,
  status                  STRING  NOT NULL,
  quantity                INT64   NOT NULL, 
  unit_price              FLOAT64 NOT NULL,
  gmv                     FLOAT64 NOT NULL, 
  unit_cost               FLOAT64 NOT NULL,
  gross_margin            FLOAT64 NOT NULL,
  was_on_promo            BOOL    NOT NULL,
  total_amount_reported   FLOAT64,         
  data_quality_flag       STRING,
)
PARTITION BY transaction_date
CLUSTER BY store_key, product_key
OPTIONS(
  partition_expiration_days=NULL,
  require_partition_filter=FALSE
);


-- 9. view_clean_sales
-- Se crea una vista limpia con filtros detectados previamente

CREATE OR REPLACE VIEW `leo-deliyore-analytics-2026.retail_data.view_clean_sales` AS
SELECT fs.*, ds.store_name, ds.country, ds.format, ds.size_sqm, ds.region, ds.is_comparable,
  dp.item_name, dp.category, dp.department, dp.brand, dv.vendor_id, dv.vendor_name, dv.tier AS vendor_tier,
  dv.is_valid AS vendor_is_valid, dd.year, dd.quarter, dd.month, dd.week_of_year, dd.is_weekend, dd.fiscal_period
FROM `leo-deliyore-analytics-2026.retail_data.fact_sales` fs
JOIN `leo-deliyore-analytics-2026.retail_data.dim_store`   ds ON fs.store_key   = ds.store_key   AND ds.is_current = TRUE
JOIN `leo-deliyore-analytics-2026.retail_data.dim_product` dp ON fs.product_key = dp.product_key
JOIN `leo-deliyore-analytics-2026.retail_data.dim_vendor`  dv ON dp.vendor_key  = dv.vendor_key
JOIN `leo-deliyore-analytics-2026.retail_data.dim_date`    dd ON fs.transaction_date_key = dd.date_key
WHERE
  fs.data_quality_flag IS NULL
  AND fs.status = 'COMPLETED'
  AND dv.is_valid = TRUE;

----------- FIN -------------
