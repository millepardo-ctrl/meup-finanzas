Crea un dashboard financiero web para MeUp, empresa colombiana de piedra natural. Todo en español, números en formato colombiano ($1.500.000), fechas dd/mm/aaaa. Solo lectura + un formulario (registrar pago de importación). React + Tailwind.

IDENTIDAD VISUAL: azul marino #1B2B4B (sidebar, encabezados, tarjetas principales) y dorado #C9A55A (acentos, iconos activos, borde superior de tarjetas KPI). Fondo claro #F8F8F6, tarjetas blancas con sombra suave. Títulos en Lora (serif), datos y tablas en Inter. Estilo sobrio y elegante, sin gradientes llamativos. Badges de estado: verde (CONTABILIZADO/PAGADO), azul (CONCILIADO/CONCILIADO_EGRESO/CONCILIADO_TRANSPORTE), amarillo (PROCESADO/PENDIENTE), naranja (PARCIAL/AMBIGUO/ABONADO), rojo (ERROR/SIN_MATCH/DUPLICADO), gris (COPIA_SOPORTE/ARCHIVO/SOPORTE_VINCULADO).

DATOS: la app consume JSON desde un proxy n8n. Configuración en dos constantes al inicio del código: BASE_URL y API_KEY (header `x-api-key` en cada petición).
Endpoint: GET {BASE_URL}/webhook/meup-finanzas-data?tabla={NOMBRE}
Respuesta: { tabla, actualizado, n, datos: [...] } donde datos es un array de objetos cuyas claves son los encabezados de cada tabla.
Tablas disponibles: DASH_KPI, BANCOS_MOV, COMPROBANTES_WA, TRANSPORTES_SOLICITUDES, TRANSPORTES_PAGOS, COMPRAS_SYMPHONY, COMPRAS_DETALLE, PROVEEDORES_LOCALES_PAGOS, IMPORTACIONES, IMPORTACIONES_PAGOS, CREDITOS, INTERESES, CONCILIACION, CAT_BANCOS, CAT_TERCEROS.
Refrescar cada 5 minutos con indicador visible de "Última actualización". Manejo de error de red: banner "Sin conexión con n8n" sin romper la app. Los valores numéricos pueden llegar como texto: parsear con tolerancia.

ESTRUCTURA: sidebar colapsable con 6 secciones.

1) RESUMEN (home)
- 8 tarjetas KPI leyendo DASH_KPI (la tabla trae pares INDICADOR/VALOR: mostrar los más relevantes): Ingresos mes, Egresos mes, Intereses acumulados, Créditos vigentes, Comprobantes por revisar, Transportes pendientes $, Retefuente del mes, Registros sin revisión humana.
- Barras: ingresos vs egresos por mes (agregar BANCOS_MOV por mes usando FECHA y TIPO; VALOR es positivo para ingresos, negativo para egresos).
- Dona: egresos por CATEGORIA.
- Tabla: últimos 10 movimientos de BANCOS_MOV.

2) COMPROBANTES (COMPROBANTES_WA)
- 4 tarjetas: Recibidos (todos), Procesados, Por revisar (ERROR+REVISAR+AMBIGUO+SIN_MATCH), Conciliados (CONCILIADO+CONCILIADO_EGRESO+CONCILIADO_TRANSPORTE+CONTABILIZADO).
- Tabla con filtros combinables: ESTADO, GRUPO_ORIGEN (PAGOS/LOGISTICA/CONTABILIDAD), CLASIFICACION, rango de fechas, búsqueda por texto (cliente/referencia). Columnas clave: FECHA_RECIBIDO, GRUPO_ORIGEN, CLASIFICACION, OCR_VALOR, OCR_CLIENTE, ID_COMPRA_INFORMADO, CATEGORIA_GASTO, ESTADO (badge), HUMAN_REVIEW (badge gris/verde), link "Ver" a URL_DRIVE.
- Panel "Ingresos sin comprobante": filas de BANCOS_MOV con TIPO=INGRESO e ID_CONCILIACION vacío, agrupadas por TERCERO — son pagos que entraron al banco sin soporte enviado.

3) TRANSPORTES
- 4 tarjetas: Pendientes de pago (# y suma de SALDO_PENDIENTE de TRANSPORTES_SOLICITUDES con ESTADO PENDIENTE/PARCIAL), Pagado este mes (TRANSPORTES_PAGOS PAGADO del mes), Abonos vs Totales (conteo por TIPO), Retefuente del mes (suma RETENCION de pagos PAGADO).
- Tabla TRANSPORTES_PAGOS con filtros por ID_COMPRA, transportista (texto), MEDIO_PAGO, ESTADO; columnas VALOR, RETENCION, PAGO_NETO, FECHA_PAGO, link a URL_COMPROBANTE.
- Vista "Margen de transporte": COMPRAS_SYMPHONY con VALOR_DOMICILIO_COBRADO, COSTO_TRANSPORTE_REAL (o SYMPHONY si real=0), MARGEN_TRANSPORTE y %; filas con margen negativo en rojo. Gráfico de barras horizontales: top 10 por margen (dorado positivo, rojo negativo).

4) COMPRAS Y PROVEEDORES
- Tabla COMPRAS_SYMPHONY: ID_COMPRA, FECHA, CLIENTE, VENDEDOR, TIPO_ORIGEN (chip IMPORTADO/LOCAL/MIXTO), TOTAL_COMPRA, ABONOS_CLIENTE, SALDO_CLIENTE (rojo si >0), ESTADO_SYMPHONY. Clic en fila → detalle con sus items de COMPRAS_DETALLE (COD_PRODUCTO como texto, PRODUCTO, CANTIDAD, COSTO_TOTAL, VENTA_TOTAL, TIPO_PROVEEDOR).
- Subtab "Proveedores locales" (PROVEEDORES_LOCALES_PAGOS): tabla con NIT, PROVEEDOR_NOMBRE, ID_COMPRA, VALOR_COSTO, ESTADO_PAGO (badge), FECHA_PAGO; tarjeta con total PENDIENTE.

5) IMPORTACIONES Y CRÉDITOS
- IMPORTACIONES: tabla con barra de progreso de pago (1 − SALDO_PEND_USD/VALOR_INVOICE), estado; detalle con IMPORTACIONES_PAGOS.
- Formulario "Registrar pago de importación" → POST {BASE_URL}/webhook/meup-pago-importacion con header x-api-key y body JSON {id_import, tipo_pago (INVOICE|NEGINTCOMEX|NAVIERA|IVA_DIM|OTRO), fecha, moneda, valor, trm, cuenta_origen, comprobante, notas}; dropdown de importación desde IMPORTACIONES y de cuenta desde CAT_BANCOS.
- CRÉDITOS: tabla con BANCO, NUMERO_CREDITO, MONEDA, VALOR, ESTADO, INTERESES_ACUM; barras horizontales de intereses acumulados por crédito; tarjeta costo relativo (intereses/capital) para comparar líneas.

6) BANCOS
- Selector de cuenta (CAT_BANCOS) + tabla BANCOS_MOV filtrada por CUENTA, con filtros de fecha, TIPO, CATEGORIA, ESTADO_CONTABLE, HUMAN_REVIEW y búsqueda por DESCRIPCION/TERCERO/FACTURA_OC.
- Dona de egresos por CATEGORIA de la cuenta seleccionada; tarjetas de total 4X1000 y GASTO_BANCARIO del mes.
- Indicador de calidad: % de movimientos con ESTADO_CONTABLE=CONTABILIZADO y % con HUMAN_REVIEW=REVISADO.

REGLAS GENERALES: tablas con orden por columna, búsqueda y export CSV; responsive (móvil: KPIs en 2 columnas, tablas con scroll horizontal); tolerar campos vacíos o tablas sin filas sin romper; nunca exponer el API_KEY en la interfaz.
