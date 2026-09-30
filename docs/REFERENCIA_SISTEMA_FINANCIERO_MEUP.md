# REFERENCIA TÉCNICA · Sistema Financiero Automatizado MeUp
**Documento de contexto para Claude — subir a los archivos del proyecto MeUp**
Versión 1.1 · Julio 2026 · Fuente de verdad de la implementación

> Propósito: cualquier conversación futura sobre el sistema financiero debe
> partir de este documento. Contiene el diccionario de datos EXACTO
> (extraído del archivo real), el inventario de flujos n8n y las
> convenciones de diseño. Si algo aquí contradice la memoria de una
> conversación anterior, ESTE documento manda.

## 1. Arquitectura en una línea
WhatsApp/Drive/Symphony → n8n (WF-01..WF-09) → Google Sheets MEUP_FINANZAS_MASTER (fuente de verdad operativa) → SIIGO (fuente de verdad contable) + Lovable (visualización vía proxy n8n).

## 2. Inventario de flujos n8n (versiones vigentes)
| Flujo | Archivo | Función | Trigger |
|---|---|---|---|
| WF-01 v2 | WF01_v2_whatsapp_router.json | Router WhatsApp: adjunto→OCR / texto→WF-07. OCR con Claude extrae dirección ENVIADO/RECIBIDO, teléfono destino. Egresos = COMPROBANTE_EGRESO | Webhook Meta |
| WF-02 | WF02_conciliacion.json | Conciliación comprobantes de CLIENTES ↔ ingresos bancarios (excluye COMPROBANTE_EGRESO) | Cada 30 min |
| WF-03 | WF03_siigo_recibo_caja.json | Conciliado → Recibo de Caja vía API SIIGO | Cada hora |
| WF-04 | WF04_carga_extractos.json | Extracto bancario (nombre de archivo con código de cuenta) → normaliza → BANCOS_MOV | Drive /EXTRACTOS_ENTRADA |
| WF-05 | WF05_alertas_y_reporte.json | Resumen diario 7:00 am por Telegram | Cron |
| WF-06 | WF06_importaciones.json | Registro de pagos de importación + saldo invoice | Webhook |
| WF-07 v2 | WF07_v2_solicitud_transporte.json | Texto → solicitudes de pago a transportistas (multi-despacho), valida vs Symphony, dedup, calcula retefuente, crea pago PENDIENTE | Execute Workflow desde WF-01 |
| WF-08 | WF08_pago_transportista.json | COMPROBANTE_EGRESO ↔ TRANSPORTES_PAGOS: match por NETO o bruto, abonos con fila SALDO, antiduplicado doble (pago y banco), registra egreso en BANCOS_MOV | Cada 30 min |
| WF-09 | WF09_carga_compras_symphony.json | Compras Symphony: upsert completo (IDs nuevos se agregan; existentes actualizan ESTADO/GESTION/COSTO_TRANSPORTE_SYMPHONY/ABONOS/SALDO/TRANSPORTISTA). Apto carga diaria | Drive /COMPRAS_SYMPHONY_ENTRADA |
Obsoletos (NO usar): WF01_whatsapp_comprobantes.json, WF07_solicitud_transporte.json.

## 3. Diccionario de datos (columnas exactas por pestaña)
### CONFIG
A=PARAMETRO | B=VALOR | C=NOTAS

### CAT_BANCOS
A=CODIGO | B=BANCO | C=TIPO_CUENTA | D=NUMERO | E=MONEDA | F=CODIGO_PUC | G=ACTIVA | H=NOTAS

### CAT_TERCEROS
A=NIT | B=NOMBRE | C=TIPO | D=CIUDAD | E=NOTAS

### IMPORTACIONES
A=ID_IMPORT | B=PROVEEDOR | C=INVOICE_NUM | D=MONEDA | E=VALOR_INVOICE | F=FACTURA_INVOICE | G=DIM_NUM | H=TRM_DIM | I=BL_NUM | J=FECHA_BL | K=AGENTE_ADUANAS | L=FACT_AGENTE_NUM | M=FACT_AGENTE_COP | N=NAVIERA_FACT_NUM | O=NAVIERA_FACT_COP | P=IVA_DIM_COP | Q=FECHA_LLEGADA | R=ESTADO | S=SALDO_PEND_USD | T=NOTAS

### IMPORTACIONES_PAGOS
A=ID_PAGO | B=ID_IMPORT | C=TIPO_PAGO | D=FECHA | E=MONEDA | F=VALOR | G=TRM_PAGO | H=VALOR_COP | I=CUENTA_ORIGEN | J=COMPROBANTE_SIIGO | K=NOTAS

### CREDITOS
A=ID_CREDITO | B=BANCO | C=NUMERO_CREDITO | D=FECHA_DESEMBOLSO | E=MONEDA | F=VALOR_USD | G=VALOR_COP | H=TASA | I=PROVEEDOR_DESTINO | J=FECHA_LLEGADA_MCIA | K=ESTADO | L=FECHA_CANCELACION | M=NOTAS | N=INTERESES_ACUM

### INTERESES
A=FECHA | B=COMPROBANTE | C=CODIGO_CONTABLE | D=CUENTA_CONTABLE | E=NIT_TERCERO | F=TERCERO | G=NUMERO_CREDITO | H=DESCRIPCION | I=DEBITO | J=CREDITO

### BANCOS_MOV
A=ID_MOV | B=FECHA | C=CUENTA | D=DESCRIPCION | E=REFERENCIA | F=MONEDA | G=VALOR | H=TIPO | I=CATEGORIA | J=DETALLE | K=COMPROBANTE_SIIGO | L=FACTURA_OC | M=TERCERO | N=ID_CONCILIACION | O=ESTADO_CONTABLE | P=ORIGEN | Q=HUMAN_REVIEW

### COMPROBANTES_WA
A=ID_DOC | B=FECHA_RECIBIDO | C=REMITENTE_WA | D=NOMBRE_CONTACTO | E=TIPO_ARCHIVO | F=URL_DRIVE | G=OCR_ESTADO | H=OCR_FECHA_PAGO | I=OCR_VALOR | J=OCR_BANCO_ORIGEN | K=OCR_BANCO_DESTINO | L=OCR_REFERENCIA | M=OCR_CLIENTE | N=OCR_CONFIANZA | O=CLASIFICACION | P=ID_MOV_MATCH | Q=ESTADO | R=RECIBO_SIIGO | S=NOTAS | T=HUMAN_REVIEW

### COMPRAS_SYMPHONY
A=ID_COMPRA | B=FECHA | C=CLIENTE | D=DOCUMENTO | E=CENTRO_COSTO | F=VENDEDOR | G=ESTADO_SYMPHONY | H=GESTION | I=VALOR_VENTA | J=VALOR_DOMICILIO_COBRADO | K=COSTO_TRANSPORTE_SYMPHONY | L=COSTO_TRANSPORTE_REAL | M=MARGEN_TRANSPORTE | N=TIPO_ORIGEN | O=TOTAL_COMPRA | P=ABONOS_CLIENTE | Q=SALDO_CLIENTE | R=TRANSPORTISTA_SYMPHONY | S=ORIGEN | T=DESTINO | U=HUMAN_REVIEW | V=NOTAS

### COMPRAS_DETALLE
A=ID_COMPRA | B=COD_PRODUCTO | C=PRODUCTO | D=INFO | E=CANTIDAD | F=COSTO_TOTAL | G=VENTA_TOTAL | H=NIT_PROVEEDOR | I=TIPO_PROVEEDOR | J=RETENCION_DESC | K=HUMAN_REVIEW

### PROVEEDORES_LOCALES_PAGOS
A=ID_CONTROL | B=ID_COMPRA | C=NIT_PROVEEDOR | D=PROVEEDOR_NOMBRE | E=VALOR_COSTO | F=ESTADO_PAGO | G=FECHA_PAGO | H=CUENTA_ORIGEN | I=COMPROBANTE_SIIGO | J=ID_MOV_BANCO | K=HUMAN_REVIEW | L=NOTAS

### TRANSPORTES_SOLICITUDES
A=ID_SOLICITUD | B=FECHA_SOLICITUD | C=SOLICITADO_POR_WA | D=ID_COMPRA | E=CUENTA_COBRO | F=REMISION | G=TRANSPORTISTA | H=CEDULA | I=TELEFONO | J=MEDIO_PAGO | K=VALOR_SOLICITADO | L=VALOR_PAGADO_ACUM | M=SALDO_PENDIENTE | N=ESTADO | O=RETEFUENTE_APLICA | P=URL_MENSAJE_ORIGEN | Q=NOTAS | R=HUMAN_REVIEW

### TRANSPORTES_PAGOS
A=ID_PAGO | B=ID_SOLICITUD | C=ID_COMPRA | D=TRANSPORTISTA | E=CEDULA | F=TIPO | G=VALOR | H=FECHA_PAGO | I=MEDIO_PAGO | J=CUENTA_ORIGEN | K=URL_COMPROBANTE | L=ESTADO | M=ID_DOC_WA | N=ID_MOV_BANCO | O=COMPROBANTE_SIIGO | P=DUPLICADO_DE | Q=NOTAS | R=HUMAN_REVIEW | S=RETENCION | T=PAGO_NETO

### CONCILIACION
A=ID_CONC | B=FECHA | C=ID_DOC_WA | D=ID_MOV_BANCO | E=VALOR_COMPROBANTE | F=VALOR_BANCO | G=DIFERENCIA | H=METODO_MATCH | I=ESTADO | J=REVISADO_POR | K=NOTAS | L=HUMAN_REVIEW

### RECIBOS_CAJA
A=FECHA | B=ID_DOC_VENTA | C=VALOR | D=CLIENTE | E=NIT | F=CUENTA_DESTINO | G=RECIBO_SIIGO | H=ID_DOC_WA | I=ASESOR

### DASH_KPI
A=INDICADOR | B=VALOR | C=DETALLE

## 4. Convenciones y reglas de negocio críticas
- **Una celda = un dato.** Fechas como fecha, valores sin símbolos, IDs secuenciales, filas nuevas al final.
- **ID_COMPRA es SIEMPRE el número de Symphony** (15889, no "ID 15889-C") — los SUMIFS de cruce dependen de esto.
- **Symphony invertido vs intuición:** Valor domicilio = cobrado al cliente; Costo domicilio = pagado al transportista.
- **NIT 900570024 = producto propio importado.** Otro NIT = proveedor local. Mezcla = MIXTO.
- **Retefuente transporte:** 1% si bruto ≥ CONFIG!B3 (4 UVT; $209.496 en 2026 — actualizar CONFIG cada enero Y la constante 209496 en los code nodes de WF-07). PAGO_NETO = bruto − retención. El comprobante muestra el NETO; WF-08 cruza contra neto o bruto. Pendiente confirmar excepciones con la contadora.
- **Pagos a transportistas = comprobante de egreso en SIIGO**, nunca RECIBOS_CAJA.
- **BANCOS_MOV.ORIGEN:** EXTRACTO (real, WF-04) vs TRANSPORTE_APP (proyección WF-08 cuando el egreso aún no llega al extracto). WF-08 primero busca el egreso real y lo vincula antes de crear proyección.
- **HUMAN_REVIEW (PENDIENTE/REVISADO)** en: BANCOS_MOV, COMPROBANTES_WA, TRANSPORTES_SOLICITUDES, TRANSPORTES_PAGOS, CONCILIACION, COMPRAS_SYMPHONY, COMPRAS_DETALLE, PROVEEDORES_LOCALES_PAGOS. Todo lo automático nace PENDIENTE.
- **CAT_TERCEROS = catálogo (quién); PROVEEDORES_LOCALES_PAGOS = transaccional (qué se debe por compra).** El nombre en la transaccional es VLOOKUP al catálogo.
- Estados COMPROBANTES_WA: RECIBIDO→PROCESADO→CONCILIADO→CONTABILIZADO; ramas: REVISAR/SIN_MATCH/AMBIGUO/ERROR/DUPLICADO/CONCILIADO_TRANSPORTE.
- Estados TRANSPORTES: solicitud PENDIENTE/PARCIAL/PAGADO/DUPLICADO/REVISAR; pago PENDIENTE/PAGADO/DUPLICADO; TIPO TOTAL/ABONO/SALDO.
- Fórmulas clave: CREDITOS!N=SUMIFS(INTERESES por NUMERO_CREDITO); COMPRAS_SYMPHONY!L=SUMIFS(TRANSPORTES_PAGOS G por C=ID_COMPRA y L=PAGADO); M=J−SI(L>0;L;K); TRANSPORTES_SOLICITUDES!L/M=pagado acumulado/saldo.
- Branding MeUp: navy #1B2B4B, dorado #C9A55A.

## 5. Pendientes conocidos (a julio 2026)
1. Reemplazar marcadores REEMPLAZAR_* en los 9 JSON (credenciales solo en n8n).
2. Confirmar con contadora: excepciones de retefuente transporte; modelo de importación SIIGO (vía B).
3. Nombres reales de los 5 NIT locales en CAT_TERCEROS.
4. Número de cuenta Bancolombia Panamá; NITs de clientes frecuentes.
5. Decidir WhatsApp Cloud API oficial vs Evolution API.
6. Proxy n8n para Lovable (WF-08 de lectura propuesto en doc 02) — no hacer público el Sheet.
7. Cuadro del acuerdo DIAN si se quiere pestaña de cuotas.
