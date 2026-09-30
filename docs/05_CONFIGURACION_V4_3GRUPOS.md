# Configuración v4 · 3 Grupos + Egresos + Fórmulas
Sistema Financiero MeUp · Julio 2026

---

## 1. Qué cambia con la versión de 3 grupos

El grupo de Telegram donde llega el mensaje ahora ES la clasificación:

| Grupo | Qué llega | Qué hace el sistema |
|---|---|---|
| **Pagos** | Abonos de ventas (asesores) | COMPROBANTE_PAGO → concilia WF-02 contra ingresos del banco, escribe ID/cliente/VENTA en BANCOS_MOV |
| **Pagos Logística** | Solicitudes de pago a transportistas + sus comprobantes | Texto → WF-07 (solicitud); comprobante → WF-08 (match, abonos, BANCOS_MOV categoría TRANSPORTE) |
| **Contabilidad** | Todos los egresos: arriendos, nómina, viáticos, impuestos, gastos, facturas, giros, **OC + comprobante de proveedores locales** | COMPROBANTE_EGRESO con **CATEGORIA_GASTO** → WF-10 (nuevo) concilia contra egresos del banco, categoriza BANCOS_MOV, y si trae OC marca el pago en PROVEEDORES_LOCALES_PAGOS. Las OC (documento pedido, sin transferencia) quedan como ORDEN_COMPRA / estado ARCHIVO, guardadas en Drive con su número extraído |

Ya no hay adivinanza: un pantallazo de cliente que diga "Enviaste" en el grupo Pagos es venta, punto. El mismo caso que te falló queda resuelto de raíz.

**Respuesta a tu duda de dónde viven los egresos:** todos los soportes quedan en COMPROBANTES_WA (con GRUPO_ORIGEN=CONTABILIDAD y su CATEGORIA_GASTO), y su efecto contable queda en BANCOS_MOV cuando WF-10 los cruza: el movimiento del extracto recibe la categoría (ARRIENDO, NOMINA, VIATICOS, IMPUESTOS, GIRO_INTERNACIONAL...), el tercero y la OC. O sea: COMPROBANTES_WA = archivo documental; BANCOS_MOV = libro de movimientos categorizado. Los pagos a proveedores locales además actualizan PROVEEDORES_LOCALES_PAGOS (PAGADO o ABONADO).

**Respuesta a tu duda del desfase de un día:** el diseño es asíncrono a propósito. El comprobante llega hoy → queda PROCESADO → los motores intentan cada 30 min → no encuentran nada (el extracto no existe) → queda SIN_MATCH con UNA alerta → mañana subes el extracto → el siguiente ciclo lo cruza solo. Corregí el bug que impedía esto: antes SIN_MATCH era estado final; ahora se reintenta silenciosamente (sin repetir alertas) hasta que aparece el movimiento. La ventana de cruce es ±3 días, de sobra para la carga del día siguiente.

**Carpetas por mes:** implementado. Todo archivo se guarda en `/COMPROBANTES_WA/AAAA-MM/` y la carpeta del mes se crea sola la primera vez. No recomiendo subcarpetas por proveedor: el buscador real es el Sheet (filtras por OC_NUM o por nombre y ahí está el link directo al archivo).

## 2. Pasos de configuración (en orden)

**2.1 Telegram (10 min)**
1. Crea los grupos "MeUp Pagos" y "MeUp Contabilidad" (el actual -5154074469 queda como "MeUp Pagos Logística", o renómbralo según prefieras).
2. Agrega el MISMO bot a los 3 grupos.
3. Confirma en @BotFather → /setprivacy → **Disable** (una sola vez, aplica a todos los grupos).
4. Obtén los chat_id de los 2 grupos nuevos (mensaje en el grupo → `https://api.telegram.org/bot<TOKEN>/getUpdates`).
5. Pásame los 2 chat_id y te regenero WF-01 v4 y WF-10 con todo incrustado, **o** reemplaza tú los marcadores `REEMPLAZAR_CHAT_ID_PAGOS`, `REEMPLAZAR_CHAT_ID_LOGISTICA`, `REEMPLAZAR_CHAT_ID_CONTABILIDAD` (aparecen en el nodo "Clasificar mensaje" de WF-01 v4, en los 2 nodos de confirmación, y en los 2 nodos Telegram de WF-10).

**2.2 Google Sheet — encabezados nuevos (1 min)**
En COMPROBANTES_WA agrega: **V1** = `GRUPO_ORIGEN` · **W1** = `CATEGORIA_GASTO` · **X1** = `OC_NUM` (U1 = ID_COMPRA_INFORMADO ya lo tienes).

**2.3 Google Sheet — fórmulas autoextensibles (5 min, una sola vez)**
Detectaste bien el problema: las fórmulas estaban solo en las filas de ejemplo, y las filas que agrega n8n no las heredan. La solución es convertirlas a fórmulas de columna completa (BYROW/ARRAYFORMULA), que se calculan solas para cada fila nueva. **Borra primero la fórmula vieja de la fila 2** en cada caso y pega:

- **TRANSPORTES_SOLICITUDES · L2** (pagado acumulado):
`=BYROW(A2:A;LAMBDA(id;SI(id="";;SUMAR.SI.CONJUNTO(TRANSPORTES_PAGOS!G:G;TRANSPORTES_PAGOS!B:B;id;TRANSPORTES_PAGOS!L:L;"PAGADO"))))`
- **TRANSPORTES_SOLICITUDES · M2** (saldo):
`=ARRAYFORMULA(SI(A2:A="";;K2:K-L2:L))`
- **COMPRAS_SYMPHONY · L2** (costo transporte real):
`=BYROW(A2:A;LAMBDA(id;SI(id="";;SUMAR.SI.CONJUNTO(TRANSPORTES_PAGOS!G:G;TRANSPORTES_PAGOS!C:C;id;TRANSPORTES_PAGOS!L:L;"PAGADO"))))`
- **COMPRAS_SYMPHONY · M2** (margen transporte):
`=ARRAYFORMULA(SI(A2:A="";;J2:J-SI(L2:L>0;L2:L;K2:K)))`
- **CREDITOS · N2** (intereses acumulados por crédito):
`=BYROW(C2:C;LAMBDA(nc;SI(nc="";;SUMAR.SI.CONJUNTO(INTERESES!I:I;INTERESES!G:G;nc))))`
- **PROVEEDORES_LOCALES_PAGOS · D2** (nombre desde catálogo):
`=ARRAYFORMULA(SI(C2:C="";;SI.ERROR(BUSCARV(C2:C;CAT_TERCEROS!A:B;2;FALSO);"")))`
- **IMPORTACIONES · S2** (saldo pendiente invoice):
`=BYROW(A2:A;LAMBDA(id;SI(id="";;E2-SUMAR.SI.CONJUNTO(IMPORTACIONES_PAGOS!F:F;IMPORTACIONES_PAGOS!B:B;id;IMPORTACIONES_PAGOS!C:C;"INVOICE"))))` — *nota: si tu Sheet está en inglés, usa SUMIFS/IF/IFERROR/VLOOKUP y comas en vez de punto y coma.*

Importante: al pegar cada una, borra también cualquier resto de fórmula vieja en las filas de abajo de esa columna (si hay un valor escrito debajo, la fórmula de columna muestra #REF hasta que lo borres). Las columnas RETENCION/PAGO_NETO de TRANSPORTES_PAGOS **no** se convierten: esas las escribe n8n con el valor calculado.

**2.4 n8n — importar/reemplazar (10 min)**
1. **Elimina** WF-01 v3 (queda reemplazado).
2. Importa **WF-01 v4** → credenciales → 3 chat_id → ID de WF-07 → activar.
3. Importa **WF-10** (nuevo) → credenciales → chat_id contabilidad → activar.
4. Reimporta **WF-02**, **WF-04** y **WF-08** (traen el fix de fechas y el reintento de SIN_MATCH) → credenciales → activar.

## 3. El ciclo diario completo (cómo queda operando)

```
DURANTE EL DÍA (en caliente)
· Asesores → grupo Pagos: comprobante + "ID 15889" → OCR + registro + vínculo de ID
· Logística → grupo Logística: solicitud → alerta a tesorería con NETO a pagar
· Tesorería paga → comprobante al grupo → WF-08 marca PAGADO (queda SIN_MATCH bancario, normal)
· Contabilidad → grupo Contabilidad: soportes de gastos, OC + transferencia a proveedor
  → todo OCR-eado, categorizado y archivado por mes (SIN_MATCH bancario, normal)

MAÑANA SIGUIENTE (10 min de la auxiliar)
· Subir extractos del día a /EXTRACTOS_ENTRADA (nombre con código de cuenta)
· Subir compras Symphony del día a /COMPRAS_SYMPHONY_ENTRADA
→ En los siguientes 30 min los motores cruzan TODO lo del día anterior:
  ingresos ↔ comprobantes de clientes (con ID y cliente escritos en el banco),
  egresos ↔ transportistas / gastos / proveedores locales
→ Resumen 7:00 am: lo que quedó sin cruzar es la lista de trabajo del día

REVISIÓN DIARIA (contadora/auxiliar)
· Filtrar HUMAN_REVIEW = PENDIENTE, validar, cambiar a REVISADO
· Resolver AMBIGUO / SIN_MATCH persistentes
· BANCOS_MOV queda categorizado y listo para contabilizar en SIIGO
```

## 4. Prueba de aceptación de la v4 (guion de 15 minutos)

1. Grupo Pagos: foto de comprobante de cliente + texto "ID 15889" → fila COMPROBANTE_PAGO con GRUPO_ORIGEN=PAGOS, archivo en carpeta 2026-07, ID vinculada con confirmación del bot.
2. Grupo Logística: texto de solicitud → alerta con neto; luego foto del pago → PAGADO en TRANSPORTES_PAGOS.
3. Grupo Contabilidad: PDF de una OC → fila ORDEN_COMPRA estado ARCHIVO con OC_NUM extraído; luego el comprobante de la transferencia al proveedor → COMPROBANTE_EGRESO con CATEGORIA_GASTO=COMPRA_PROVEEDOR.
4. Al día siguiente: subir extracto → verificar que el pago del cliente quedó VENTA con ID en BANCOS_MOV, el egreso del proveedor quedó categorizado, y PROVEEDORES_LOCALES_PAGOS marcó PAGADO.
5. Verificar que las fórmulas de columna calculan solas en las filas nuevas.
