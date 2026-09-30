Construye una aplicación web completa y funcional: **Sistema Contable y Financiero MeUp** — plataforma interna de gestión contable para MeUp, empresa colombiana de piedra natural con 5 sedes. Toda la interfaz en español. Moneda COP con formato colombiano ($1.500.000), USD para el módulo de importaciones. Fechas dd/mm/aaaa, zona horaria America/Bogota.

STACK: React + TypeScript + Vite + Tailwind CSS, Supabase (Postgres + Auth + RLS) como backend. Iconos lucide-react, gráficos con recharts.

MARCO CONTABLE: normativa colombiana, Plan Único de Cuentas (PUC), partida doble estricta. IMPORTANTE: SIIGO sigue siendo el sistema contable legal de la empresa — esta aplicación es el sistema de gestión financiera operativa y genera asientos y archivos EXPORTABLES a SIIGO; no lo reemplaza. Incluir siempre la vía de exportación.

════════════════════════════════════
ARQUITECTURA — MÓDULOS
════════════════════════════════════
1. Dashboard ejecutivo
2. Bancos y movimientos (multi-cuenta, multi-moneda)
3. Conciliación bancaria
4. Transacciones / Asientos contables
5. Facturación y compras (clientes, proveedores locales, órdenes de compra)
6. Transportes (pagos a transportistas persona natural)
7. Importaciones (proveedores internacionales, USD, TRM)
8. Reportes y estados financieros
9. Terceros
10. Usuarios, roles y auditoría
11. Configuración (parámetros fiscales, PUC, cuentas bancarias, periodos)
12. Integraciones (webhooks n8n, import extractos/Symphony, export SIIGO)

Relaciones clave: comprobante → conciliación → movimiento bancario → asiento contable → estados financieros. Compra Symphony → detalle de items → cuentas por pagar a proveedor → pago → movimiento bancario. Solicitud de transporte → pago(s) con retefuente → movimiento bancario → comprobante de egreso.

════════════════════════════════════
BASE DE DATOS (tablas y campos)
════════════════════════════════════
usuarios(id, email, nombre, rol_id, activo, ultimo_acceso)
roles(id, nombre, permisos jsonb)
terceros(id, nit, dv, razon_social, tipo ENUM[CLIENTE, PROVEEDOR_LOCAL, PROVEEDOR_INTL, TRANSPORTISTA, BANCO, EMPLEADO, ESTADO], ciudad, telefono, email, activo)
cuentas_bancarias(id, codigo, banco, tipo_cuenta, numero, moneda, codigo_puc, activa) — SEMILLA con las cuentas reales: BC-CTE-3762 (Bancolombia corriente, COP), BC-AHO-8985 (Bancolombia ahorros), DV-AHO-4335 (Davivienda ahorros), DV-CTE-6614 (Davivienda corriente), BA-9030 (Banco Agrario), BC-PAN-USD (Bancolombia Panamá 3826, USD)
plan_cuentas(codigo_puc, nombre, clase, naturaleza ENUM[DEBITO, CREDITO], nivel, activa)
movimientos_bancarios(id, fecha, cuenta_id, descripcion, referencia, moneda, valor NUMERIC signed, tipo ENUM[INGRESO, EGRESO, TRASLADO, IMPUESTO, GASTO_BANCARIO], categoria TEXT [VENTA, TRANSPORTE, NOMINA, ARRIENDO, VIATICOS, IMPUESTOS, SERVICIOS, PUBLICIDAD, COMPRA_PROVEEDOR, GIRO_INTERNACIONAL, GASTO_GENERAL, INTERES_CREDITO, 4X1000, POR_CLASIFICAR], tercero_id, factura_oc, conciliacion_id, asiento_id, estado_contable ENUM[PENDIENTE, CONTABILIZADO], origen ENUM[EXTRACTO, APP, WEBHOOK], human_review BOOL)
comprobantes(id, fecha_recibido, canal ENUM[TELEGRAM, WHATSAPP, MANUAL], remitente, grupo_origen ENUM[PAGOS, LOGISTICA, CONTABILIDAD], tipo ENUM[COMPROBANTE_PAGO, COMPROBANTE_EGRESO, FACTURA, ORDEN_COMPRA], url_archivo, valor, fecha_pago, referencia_bancaria, tercero_texto, id_compra_informado, categoria_gasto, estado ENUM[PROCESADO, CONCILIADO, SIN_MATCH, AMBIGUO, COPIA_SOPORTE, SOPORTE_VINCULADO, ARCHIVO], movimiento_id)
asientos(id, fecha, tipo_comprobante ENUM[RC, CE, CC, NC], numero_consecutivo, tercero_id, descripcion, estado ENUM[BORRADOR, CONTABILIZADO, ANULADO], total_debito, total_credito, periodo_id, exportado_siigo BOOL, creado_por, timestamps)
asientos_detalle(id, asiento_id, codigo_puc, tercero_id, descripcion, debito NUMERIC, credito NUMERIC, centro_costo)
facturas_venta(id, numero, fecha, cliente_id, subtotal, iva, retenciones, total, abonos, saldo, estado ENUM[PENDIENTE, PARCIAL, PAGADA, ANULADA])
compras(id, id_symphony UNIQUE, fecha, cliente, vendedor, centro_costo, estado_symphony, valor_venta, valor_domicilio_cobrado, costo_transporte_symphony, costo_transporte_real, margen_transporte GENERATED, tipo_origen ENUM[IMPORTADO, LOCAL, MIXTO], total_compra, abonos_cliente, saldo_cliente, transportista_symphony, origen, destino)
compras_detalle(id, compra_id, cod_producto TEXT NOT NULL — SIEMPRE texto para conservar ceros iniciales tipo 0162501 —, producto, info, cantidad, costo_total, venta_total, nit_proveedor TEXT, tipo_proveedor ENUM[IMPORTADO, LOCAL, SIN_NIT])
proveedores_pagos(id, compra_id, tercero_id, valor_costo, estado ENUM[PENDIENTE, ABONADO, PAGADO], fecha_pago, cuenta_id, movimiento_id, comprobante_siigo)
transportes_solicitudes(id, fecha, compra_id, cuenta_cobro, remision, transportista_id, cedula, telefono_o_cuenta, medio_pago ENUM[NEQUI, DAVIPLATA, BANCOLOMBIA, OTRO], valor_solicitado, retefuente_calculada, pago_neto, valor_pagado_acum, saldo_pendiente, estado ENUM[PENDIENTE, PARCIAL, PAGADO, DUPLICADO, REVISAR])
transportes_pagos(id, solicitud_id, compra_id, tipo ENUM[TOTAL, ABONO, SALDO], valor, retencion, pago_neto, fecha_pago, cuenta_id, medio_pago, url_comprobante, movimiento_id, estado)
importaciones(id, proveedor_id, invoice_num, moneda, valor_invoice, dim_num, trm_dim, bl_num, fecha_bl, naviera, agente_aduanas, iva_dim_cop, fecha_llegada, estado ENUM[EN_TRANSITO, NACIONALIZADA, PAGADA], saldo_pendiente_usd)
importaciones_pagos(id, importacion_id, tipo ENUM[INVOICE, AGENTE, NAVIERA, IVA_DIM, OTRO], fecha, moneda, valor, trm_pago, valor_cop, cuenta_id)
conciliaciones(id, comprobante_id, movimiento_id, valor_comprobante, valor_banco, diferencia, metodo ENUM[AUTO, MANUAL], estado, revisado_por)
periodos(id, anio, mes, estado ENUM[ABIERTO, CERRADO], cerrado_por, fecha_cierre)
config(clave PK, valor, descripcion) — SEMILLAS: UVT_2026=52374, UMBRAL_RETEFUENTE_TRANSPORTE=209496 (4 UVT), TARIFA_RETEFUENTE_TRANSPORTE=0.01, IVA=0.19, GMF=0.004
auditoria(id, usuario_id, accion, tabla, registro_id, datos_antes jsonb, datos_despues jsonb, timestamp)

════════════════════════════════════
LÓGICA DE NEGOCIO CONTABLE
════════════════════════════════════
- Partida doble estricta: un asiento solo puede guardarse como CONTABILIZADO si SUM(debito) = SUM(credito) en sus líneas; validación en vivo en el editor con indicador de descuadre.
- Naturaleza por clase PUC: clases 1, 5, 6, 7 aumentan al débito; clases 2, 3, 4 aumentan al crédito.
- Generación automática de asientos desde eventos (con plantillas editables):
  · Ingreso de cliente conciliado → Recibo de Caja (RC): débito banco (11xx según cuenta) / crédito 130505 cartera o 280505 anticipos.
  · Pago a transportista → Comprobante de Egreso (CE): débito 613550 o 513550 fletes / crédito banco por el neto / crédito 236525 retefuente. Retefuente automática: 1% del bruto si bruto ≥ config UMBRAL_RETEFUENTE_TRANSPORTE; pago_neto = bruto − retención.
  · Compra a proveedor local → CC: débito inventario 1435 o gasto / crédito 220505 CxP / crédito retenciones si aplican.
  · 4x1000 detectado en extracto → débito 511595 GMF / crédito banco.
  · Pago de importación → manejo multimoneda: valor USD × TRM del pago; diferencia en cambio a 421020 (ingreso) o 530525 (gasto).
- Periodos contables: al cerrar un periodo, sus asientos y movimientos quedan inmutables (solo ADMIN + CONTADORA pueden reabrir con nota de auditoría).
- Anulación de asiento: nunca borrar; genera contrapartida inversa con referencia cruzada.
- Conciliación bancaria: motor de sugerencias por valor exacto (±$1), ventana de fecha ±3 días y referencia; score de confianza; aprobación manual con un clic; los movimientos y comprobantes conciliados quedan enlazados.
- Estados financieros calculados en tiempo real desde asientos CONTABILIZADOS: Balance de Prueba (saldos por cuenta con débitos/créditos del periodo), Estado de Resultados (mensual y acumulado, por centro de costo), Balance General clasificado, Flujo de Caja método directo (desde movimientos bancarios por categoría), Libro Diario, Auxiliar por cuenta y por tercero.

════════════════════════════════════
PANTALLAS
════════════════════════════════════
1. Login (Supabase Auth email+contraseña) y recuperación.
2. DASHBOARD: 8 tarjetas KPI (saldo consolidado y por cuenta bancaria, ingresos del mes, egresos del mes, flujo neto, cartera clientes, CxP proveedores, transportes pendientes de pago $, retenciones por declarar); gráfico de barras ingresos vs egresos últimos 12 meses; dona de egresos por categoría; línea de saldo diario consolidado; tabla de últimos 10 movimientos; panel de alertas (movimientos sin conciliar >3 días, registros en human_review, compras con margen de transporte negativo resaltadas en rojo).
3. BANCOS: selector de cuenta con saldo; tabla de movimientos con filtros combinables (rango de fechas, tipo, categoría, tercero, estado contable, origen); edición de categoría y tercero en línea; importador de extractos CSV/XLSX con vista previa, mapeo de columnas, formato colombiano de números (1.500.000,50) y detección de duplicados por fecha+valor+referencia.
4. CONCILIACIÓN: dos paneles lado a lado (comprobantes sin conciliar / movimientos sin conciliar), sugerencias automáticas con score y diferencia, botón Conciliar, historial.
5. ASIENTOS: lista con filtros; editor con líneas débito/crédito, buscador de cuentas PUC, autocompletado de terceros, validación de cuadre en vivo, botones contabilizar / duplicar / anular.
6. FACTURACIÓN Y COMPRAS: subtabs — Facturas de venta (crear, listar, PDF imprimible, aplicar abonos); Compras Symphony (lista con margen de transporte y semáforo verde/rojo, importador del XLSX maestro-detalle de Symphony que aplana cabecera + items y clasifica proveedores por NIT: 900570024 = producto propio importado, otro NIT = proveedor local); Detalle por compra con sus items; Cuentas por pagar a proveedores con aging (0-30, 31-60, >60 días).
7. TRANSPORTES: solicitudes con estado y saldo pendiente; registrar pago con retefuente y neto calculados automáticamente; filtros por compra, transportista, medio de pago; total de retefuente del periodo.
8. IMPORTACIONES: lista con barra de progreso de pago del invoice; registrar pago con TRM; resumen de costos de nacionalización por importación.
9. REPORTES: generador con filtros (periodo, centro de costo, tercero, cuenta); Balance de Prueba, PyG, Balance General, Flujo de Caja, Libro Diario, Auxiliares, Reporte de retenciones practicadas (retefuente por periodo, listo para declarar); todos exportables a Excel y PDF; botón "Exportar a SIIGO" que genera CSV de asientos del periodo con el layout de importación de SIIGO.
10. TERCEROS: CRUD con validación de NIT/dígito de verificación; ficha con saldo, movimientos y documentos asociados.
11. USUARIOS Y ROLES: gestión, asignación de rol, log de auditoría filtrable.
12. CONFIGURACIÓN: parámetros fiscales editables (UVT, umbrales, tarifas), plan de cuentas CRUD, cuentas bancarias, apertura/cierre de periodos.
13. INTEGRACIONES: página que muestra los endpoints webhook con su token (regenerable) para conectar n8n; importadores manuales; historial de sincronizaciones.

════════════════════════════════════
API (Supabase Edge Functions / REST)
════════════════════════════════════
POST /api/webhooks/movimientos — recibe lote de movimientos bancarios desde n8n (auth por header X-Api-Key)
POST /api/webhooks/comprobantes — recibe comprobantes procesados por OCR desde n8n
GET /api/kpis?periodo=YYYY-MM
GET|POST /api/asientos · POST /api/asientos/:id/contabilizar · POST /api/asientos/:id/anular
GET /api/reportes/(balance-prueba|pyg|balance-general|flujo-caja|libro-diario|retenciones)?desde&hasta&centro_costo
POST /api/conciliaciones · GET /api/conciliaciones/sugerencias
POST /api/import/extracto · POST /api/import/compras-symphony
GET /api/export/siigo?periodo=YYYY-MM
CRUD /api/terceros · /api/cuentas-bancarias · /api/config

════════════════════════════════════
ROLES Y SEGURIDAD
════════════════════════════════════
- ADMIN: acceso total, única que gestiona usuarios y reabre periodos.
- CONTADORA: contabilidad completa, cierres de periodo, reportes, export SIIGO; sin gestión de usuarios.
- AUXILIAR_CONTABLE: captura, conciliación, importación de extractos; no contabiliza cierres ni anula.
- TESORERIA: bancos, transportes, pagos a proveedores e importaciones; lectura en contabilidad.
- CONSULTA: dashboard y reportes en solo lectura.
Implementar con Supabase RLS en todas las tablas según rol; toda escritura registra fila en auditoria (antes/después); periodos CERRADOS inmutables; anulaciones con doble confirmación y motivo obligatorio; nunca exponer claves en el cliente; sesión con expiración.

════════════════════════════════════
ESTILO VISUAL
════════════════════════════════════
Identidad MeUp: azul marino #1B2B4B (sidebar, encabezados, botones primarios) y dorado #C9A55A (acentos, iconos activos, borde superior de tarjetas KPI). Fondo general #F8F8F6, tarjetas blancas con sombra suave y bordes redondeados. Tipografía Inter. Sidebar colapsable con iconos lucide y etiqueta de rol del usuario. Badges de estado: verde (contabilizado/pagado), azul (conciliado), amarillo (pendiente), naranja (parcial/ambiguo), rojo (error/vencido/margen negativo). Tablas densas con orden por columna, búsqueda y paginación. Números en formato es-CO. Diseño responsive. Sobrio y profesional, sin gradientes llamativos.

════════════════════════════════════
DATOS SEMILLA (para que la app abra funcional)
════════════════════════════════════
Un usuario demo por cada rol; plan de cuentas PUC resumido con las cuentas mencionadas en la lógica; las 6 cuentas bancarias reales listadas arriba; 10 terceros variados (clientes, proveedor local, transportista, DIAN, banco); 15 movimientos bancarios de ejemplo en 2 cuentas (incluyendo un 4x1000, una comisión y un ingreso de cliente); 3 compras Symphony con sus items (una IMPORTADA, una LOCAL, una MIXTA, y una con margen de transporte negativo); 2 solicitudes de transporte (una con retefuente aplicada: bruto 2.450.000 → retención 24.500 → neto 2.425.500); 1 importación en USD con un pago con TRM; 4 asientos de ejemplo cuadrados y contabilizados.

Prioriza que TODO compile y navegue sin errores. Si algún módulo no cabe en la primera generación, déjalo visible en el menú con estado "En construcción" en lugar de romper la aplicación.
