# Leonardo Antonio Deliyore Tellez

## 1. Completitud `IGNORAR`
                ¿Qué porcentaje de transacciones no tiene customer_id?
                ¿Es consistente con loyalty_card = FALSE?

- **Respuesta:**
                59.8% de transacciones no tienen 'customer_id'.
                El cual es consistente con 'loyalty_card = FALSE', los clientes que no tienen
                'customer_id' son anonimos. 
                El plan de lealtad tiene un 40.2% de penetracion.

- **Hallazgo:** 
                104,632 / 174,880 transacciones no tienen 'customer_id'.

- **Consistencia:**
                Los 104,632 registros sin 'customer_id' son los que 'loyalty_card = FALSE'.

- **Decisión:**
                Existe una oportunidad de negocio para ese 59.8% de "clientes" no identificados, de momento se ignoran para analisis de "clientes identificados".


## 2. Consistencia `ALERTA`
                ¿El total_amount en transactions coincide con la suma de unit_price × quantity en transaction_items?

- **Respuesta:**
                No coinciden al 100%.
                Existen 1,745 transacciones inconsistentes, es el 1.0%.

- **Hallazgo:**   1,745 transacciones (1.0%) muestran diferencia entre 
                'total_amount' reportado y el calculado desde los ítems. 
                Todas las diferencias van en una sola dirección 'total_amount' es siempre MENOR que 'SUM(unit_price × quantity)' y ademas la columna de was_on_promo
                y payment_method, no demuestra una corelacion con las diferencias, por lo que esto se marca como una `ALERTA`. 
                

- **Decisión:**   Para todas las consultas siguientes se usará 'SUM(unit_price × quantity)'
                como un facto, el campo 'total_amount' representa informacion con sesgo.



- ## 3. Unicidad 
                ¿Existen 'transaction_id' duplicados?

- **Hallazgo:**   
                En la tabla 'transactions' existen 174.880 registros y no hay ids duplicados.



## 4. Validez.  `ALERTA`
                ¿Hay 'total_amount' negativos o cero? 
                ¿Hay 'unit_price = 0' con 'was_on_promo = FALSE'?

- **Hallazgo 4-1:** 
                Existen 3 transacciones en cero
                3 transacciones.
                TX_00065737 - TX_00108161 - TX_00036043 

- **Decisión 4-1:** 
                Se deben de marcar como ALERTA y reportar a los compañeros de TI para
                que revisen el POS ya que son transacciones en `STATUS = COMPLETED`,
                ademas son clientes anonimos lo cual no permite hacer el tracking de los movimientos.
                Excluir las 3 transacciones de todos los análisis 'WHERE total_amount > 0'.
                
- **Hallazgo 4-2:** 
                Existen 231 ítems con precio cero sin estar en promoción. 
                
- **Decisión 4-2:** 
                Excluir los 231 ítems de futuros calculos, pero se debe de alertar porque 
                en los 231 casos el factor comun es el `ITEM_089` puede ser algun error 
                de inventario y ademas en otros registros el `ITEM_089` si tiene un valor 
                positivo, por lo que refuerza algun error.



## 5. Integridad referencial `ALERTA`
                ¿Hay 'store_id' en transactions que no existan en stores? 
                ¿'vendor_id' en products que no existan en vendors?

- **Hallazgo 5-1:** 
                No existen registros de la tabla transactions SIN informacion de la tabla maestra STORES

- **Hallazgo 5-2:** 
                En la tabla productos si existen 5 registros con el vendor_id = 'VND_031' que no existe
                en la tabla maestra 'vendors'  
                
- **Decisión 5-2:** 
                Se genera una alerta para la jefatura de datos, para corregir.




## 6. Frescura `IGNORAR - de momento`
                ¿Hay tiendas con gaps de días consecutivos sin transacciones?
                ¿Son esperables o sospechosos?

- **Hallazgo:** 
                La TIENDA_012 es la unica tienda con un gap considerable estuvo 8 días sin registrar transacciones en septiembre 2024, es el unico sospechozo.


**Decisión:** 
                Antes de marcar el período 2024-09-09 a 2024-09-17 de TIENDA_012 como alerta, consultaria con operaciones o canales para saber si existio alguna situacion especial en la cuidad de Escuintla - Guatemala, que no le permitio reportar transacciones.
                Pero en el caso que se detecten mas movimientos a futuro, entonces si lo marcaria como Alerta.


          
## 7. Integridad Temporal `ALERTA`
                ¿Existe alguna tienda con transacciones anteriores a su `opening_date`?

- **Hallazgo:** 
                Existen 50 transacciones en TIENDA_037 tienen fecha anterior a su `opening_date`. 
                Las transacciones son consecutivas (TX_00168273 → TX_00168322) y ocurren exactamente en las 2 semanas previas a la apertura de la tienda.

                Asumiendo que TIENDA_037 opera en Guatemala, el monto de $13,422.65 en moneda local(quetzal) equivale a aproximadamente **$1,700 USD** — un monto no despreciable que podría distorsionar calculos.

- **Decisión:** 
                Excluir estas 50 transacciones de todos los análisis aplicando `WHERE t.transaction_date >= s.opening_date`. 


## 8. A/B Test — Contaminación de Grupos `EXCLUIR`

                ¿Hay tiendas asignadas simultáneamente a CONTROL y TREATMENT?

- **Hallazgo:** 
                Si, hay dos tiendas (TIENDA_008 y TIENDA_037) aparecen simultáneamente en ambos grupos del experimento, durante exactamente el mismo período. 
                Esto contamina el A/B test.

- **Decisión:** 
                Excluir TIENDA_008 y TIENDA_037 del análisis A/B.
