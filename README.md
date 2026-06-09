# Prueba Técnica: Data Analyst — Leonardo Antonio Deliyore Téllez
**Fecha:** 9 Junio 2026
**Herramienta:** BigQuery SQL
**Dataset:** `leo-deliyore-analytics-2026.retail_data`
**Cadena de Retail Multiformato · Centroamérica**

---

## Archivos

### Bloque 0 — Auditoría de Calidad de Datos
| Archivo | Descripción |
|---------|-------------|
| `bloque0_auditoria.md` | Hallazgos de calidad de datos y decisiones tomadas |
| `bloque0_auditoria.sql` | Queries de auditoría |

### Bloque 1 — SQL Avanzado
| Archivo | Descripción |
|---------|-------------|
| `bloque1_queries.sql` | 6 queries comentadas (Comp Sales, GMROI, Cohortes, Quiebres de stock, Promociones) |

### Bloque 2 — Modelado de Datos + Pipeline
| Archivo | Descripción |
|---------|-------------|
| `bloque2_modelo.pdf` | Diagrama del Star Schema |
| `bloque2_star_schema.sql` | DDL — crea las tablas del modelo dimensional en BigQuery |
| `bloque2_load_star_schema.sql` | ETL — pobla las tablas desde los datos raw |
| `bloque2_decisiones.md` | Justificación de decisiones de diseño, pipeline y gobernanza |

**Instrucciones Bloque 2:**
1. Ejecutar `bloque2_star_schema.sql`
2. Ejecutar `bloque2_load_star_schema.sql`

---

## Dataset — Registros por Tabla

| Archivo | Filas | Columnas |
|---------|-------|----------|
| transactions.csv | 174,880 | 8 |
| transaction_items.csv | 542,015 | 6 |
| stores.csv | 40 | 8 |
| products.csv | 200 | 7 |
| vendors.csv | 30 | 5 |
| store_promotions.csv | 42 | 6 |

---

