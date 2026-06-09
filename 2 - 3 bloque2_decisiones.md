# Bloque 2 — Modelado de Datos + Diseño de Pipeline
**Prueba Técnica · Data Analyst · Cadena de Retail Multiformato**
**Autor:** Leonardo Deliyore Téllez
**Dataset:** leo-deliyore-analytics-2026.retail_data (mismo dataset — tablas raw + Star Schema) 

--


## Parte B — Diseño del Pipeline ETL/ELT

### ¿Cómo manejar que las tiendas reportan ventas con hasta 2 horas de retraso?

El pipeline se ejecuta a las 02:00 AM, lo que da 2+ horas de margen para que todas las tiendas de los 5 países hayan enviado sus datos del día anterior.

Si a las 02:00 AM una tienda aún no reportó:
1. El pipeline corre igual con las tiendas disponibles.
2. Se genera una **alerta automática** (ver siguiente sección).
3. Al día siguiente, si llegan los datos retrasados, se procesan con una ventana de 48 horas el pipeline siempre consulta 
`WHERE transaction_date >= CURRENT_DATE - 2` para capturar datos tardios.
4. Los registros de llegada tardía se marcan con `late_arrival = TRUE`.

---

### ¿Cómo detectar automáticamente que una tienda dejó de enviar datos?


- Si `dias_sin_datos >= 2`: se dispara notificación automática al equipo de ingeniería de datos por el medio de comunicacion de la empresa.
- El hallazgo del Bloque 0 (TIENDA_012 con 8 días sin datos en septiembre 2024) habría sido capturado en el día 2 con este monitor.
- Este mismo monitor alimenta el widget de "Stock" en el dashboard del Bloque 5 (ítems sin movimiento reciente).

---

### ¿Cómo hacer cargas incrementales sin duplicar transacciones?


Todas las cargas a `fact_sales` usan `MERGE` con `transaction_item_id` como clave de deduplicación:

**Protecciones adicionales:**
1. **Ambiente Staging con dedup previo:** antes del MERGE, el staging aplica `ROW_NUMBER() OVER (PARTITION BY transaction_item_id ORDER BY ingestion_timestamp DESC) = 1` para quedar solo con la versión más reciente de cada ítem en caso de duplicados en la fuente.
2. **Particionamiento por fecha:** `fact_sales` está particionada por `transaction_date`. El MERGE solo toca las particiones de los últimos 2 días, no escanea toda la tabla.
3. **Watermark en pipeline:** el orquestador (Cloud Composer / Airflow) guarda el `MAX(ingestion_timestamp)` procesado. En cada ejecución, solo procesa registros nuevos desde ese watermark.

---

### ¿Con qué frecuencia correría el pipeline si el dashboard necesita refresh diario?

**Frecuencia: 1 vez al día, y batch parciales por ejemplo cada 6 horas**

Por categorias, paises o tiendas

---

## Parte C — Gobernanza

### ¿Cómo proteger `customer_id` para cumplir con políticas de privacidad?

El `customer_id` es información personal identificable 

El `customer_id` original se convierte en `customer_id_hashed = SHA256(customer_id || salt)` durante el proceso ETL. 
El ID original nunca se escribe en BigQuery y se almacena en tablas de negocio con acceso muy restringido.


### ¿Quién debería ser el Data Owner de la tabla de transacciones?

**Data Owner propuesto: Jefatura de datos -**


---

### Si dos reportes muestran GMV diferente para la misma tienda y el mismo día — ¿cuál sería tu proceso para resolverlo?



**Paso 1 — Identificar la fuente de cada reporte**
Cada reporte debe tener documentada su query o vista de origen. La primera pregunta es: ¿uno usa `total_amount` y el otro usa `SUM(unit_price × quantity)`?

> El Bloque 0 ya identificó que estas dos métricas difieren en 1,745 transacciones. Esta es la causa más probable de discrepancias entre reportes.

**Paso 2 — Verificar los filtros aplicados**

Checklist de diferencias comunes:

Incluye plan de lealtad
Incluye RETURNED
Incluye total_amount ≤ 0
Incluye tx antes de apertura
Incluye unit_price = 0
Rango de fechas exacto
Zona horaria aplicada

Si existe un error corregir


**Paso 3 — Documentar y corregir**
- Si la discrepancia es por definición (uno incluye RETURNED, el otro no): documentar ambas definiciones como métricas distintas (`gmv_bruto` vs `gmv_neto`) con nombres explícitos.


---