# Brief Técnico · Sistema Financiero Automatizado MeUp
**Para: desarrollador/técnico que se incorpora al proyecto**
Versión 1.0 · Agosto 2026

> Este documento asume cero contexto previo. Si algo aquí contradice lo que
> encuentres corriendo en producción, lo que está corriendo manda — pero
> avisa para actualizar este documento.

---

## 1. Qué es esto y por qué existe

MeUp es una empresa colombiana de piedra natural y cerámica (13 años, 5-6 sedes, ~25 empleados). El dueño/operador (Milena Pardo) tenía toda la operación financiera en WhatsApp/Excel manual: comprobantes de pago sueltos, sin trazabilidad, conciliación bancaria manual, sin visibilidad de quién debe qué a quién.

Este sistema automatiza: recepción de comprobantes por Telegram (interino, migración a WhatsApp Cloud API pendiente), OCR con Claude, conciliación automática contra extractos bancarios, gestión de pagos a transportistas con retefuente, carga de compras desde un CRM externo (Symphony), y generación de reportes financieros.

**Filosofía de diseño no negociable: una sola fuente de verdad operativa (Google Sheets), SIIGO sigue siendo la contabilidad legal.** Nunca se debe crear un segundo sistema que escriba a los mismos datos sin que uno de los dos quede como espejo de solo lectura.

---

## 2. Arquitectura general

```
┌─────────────┐     ┌──────────────────────────────────────┐     ┌─────────┐
│  Telegram    │────▶│              n8n (11 flujos)          │────▶│ Google  │
│  3 grupos    │     │  WF-01 router → WF-02..WF-10 motores  │◀───▶│ Sheets  │
└─────────────┘     └──────────────────────────────────────┘     │ MASTER  │
       ▲                          │              │                └────┬────┘
       │ confirmaciones           ▼              ▼                     │
       │                    Google Drive     Anthropic API             │
       │                  (archivos por mes)  (OCR + NLP)               │
       │                                                                │
       └────────────────────── alertas ────────────────────────────────┘
                                                                         │
                                                          ┌──────────────┴──────┐
                                                          │  WF-11 (proxy REST) │
                                                          └──────────┬───────────┘
                                                                     ▼
                                                          Lovable (dashboard, lectura)
                                                          Bolt (prototipo evaluación,
                                                                base de datos propia,
                                                                NO conectado aún)

SIIGO ← (Fase 4, no activa) — contabilidad legal, alimentada manualmente hoy
```

---

## 3. Stack técnico

| Capa | Tecnología | Notas |
|---|---|---|
| Orquestación | n8n | Actualmente en n8n Cloud; **migración en curso** a self-hosted (Hetzner CX23, Docker Compose + Caddy, dominio `n8n.meup.co`) por límite de ejecuciones/mes |
| Base de datos operativa | Google Sheets | 1 spreadsheet, 18 pestañas. ID: `1LgOCIMRXpyCQP9m9BYlHYjgykZ-otTXz-psuY0mRUdc` |
| Almacenamiento de archivos | Google Drive | Carpetas por mes (`AAAA-MM`), autocreadas |
| Mensajería entrante | Telegram Bot API (interino) | 1 bot, 3 grupos (chat_id abajo). Migración futura a WhatsApp Cloud API ya tiene JSON preparado (WF-01 v2) |
| OCR / NLP | Anthropic API, `claude-sonnet-4-6` | Usado para: leer comprobantes de pago, parsear solicitudes de transporte en lenguaje natural |
| Contabilidad legal | SIIGO | Fase 4, **no conectada aún** — pendiente credenciales API y decisión de la contadora sobre modelo de recibo de caja |
| Visualización | Lovable | Suscripción paga activa; dashboard en construcción, consume WF-11 |
| Prototipo evaluación | Bolt.new | Sistema contable completo con Supabase/Postgres propio — **en pausa, no conectado**, es evaluación de si algún día se reemplaza Sheets |
| CRM de compras (fuente externa) | Symphony | Sistema externo del que se exporta un XLSX de compras periódicamente; no hay API, es carga manual de archivo |

---

## 4. Modelo de datos — Google Sheets (18 pestañas)

Fuente de verdad canónica: `REFERENCIA_SISTEMA_FINANCIERO_MEUP.md` en los archivos del proyecto — **debe consultarse ese documento para el diccionario de columnas exacto**, aquí solo el resumen funcional.

| Pestaña | Rol | Escrita por |
|---|---|---|
| CONFIG | Parámetros fiscales (UVT, umbral retefuente 1%/4UVT=$209.496 en 2026) | Manual |
| CAT_BANCOS | Catálogo de 6 cuentas bancarias reales (Bancolombia CTE/AHO, Davivienda AHO/CTE, Agrario, Bancolombia Panamá USD) | Manual |
| CAT_TERCEROS | Catálogo de NITs/nombres (clientes, proveedores, transportistas) | Manual + WF-09 (agrega proveedores locales) |
| IMPORTACIONES / IMPORTACIONES_PAGOS | Compras a proveedores internacionales en USD | WF-06 |
| CREDITOS / INTERESES | Créditos bancarios vigentes | Manual |
| BANCOS_MOV | **Libro de movimientos bancarios categorizado** — el corazón contable | WF-04 (extractos) + enriquecido por WF-02/08/10 |
| COMPROBANTES_WA | Todo lo que llega por Telegram, con resultado de OCR | WF-01 v4 |
| COMPRAS_SYMPHONY / COMPRAS_DETALLE | Compras del CRM externo, cabecera + items | WF-09 |
| PROVEEDORES_LOCALES_PAGOS | Cuentas por pagar a proveedores colombianos | WF-09 (genera) + WF-10 (marca pagado) |
| TRANSPORTES_SOLICITUDES / TRANSPORTES_PAGOS | Solicitudes y pagos a transportistas, con retefuente calculada | WF-07 / WF-08 |
| CONCILIACION | Log de conciliaciones cliente↔banco | WF-02 |
| RECIBOS_CAJA | Fase 4 (SIIGO), no activa | WF-03 (inactivo) |
| DASH_KPI | Indicadores agregados para el dashboard | Fórmulas + WF-05 |

**Columnas con fórmula de columna (BYROW/ARRAYFORMULA en fila 2, se autoextiende):** TRANSPORTES_SOLICITUDES L,M · COMPRAS_SYMPHONY L,M · CREDITOS N · PROVEEDORES_LOCALES_PAGOS D · IMPORTACIONES S. **Regla de oro:** nunca escribir un valor manual debajo de esas celdas en su columna — rompe la fórmula con #REF.

**Regla de negocio crítica:** `ID_COMPRA` es siempre el número de Symphony (ej. `15889`), nunca con prefijos. La **remisión** que aparece en las solicitudes de transporte ES el mismo número que el ID de compra — se usa para cruzar automáticamente cuando no viene un ID explícito.

**NIT propio:** `900570024` = producto importado directo de MeUp. Cualquier otro NIT en una línea de compra = proveedor local. Mezcla de ambos en una misma compra = `MIXTO`.

---

## 5. Los 11 flujos de n8n — detalle

### WF-01 v4 · Router de Telegram (3 grupos)
**Trigger:** Telegram Trigger (polling/webhook único por bot — **solo puede haber un Telegram Trigger activo por bot en toda la instancia**, esto es una limitación dura de la API de Telegram, no de n8n).

**Lógica:** el `chat_id` del mensaje determina el grupo de origen, que es la señal de clasificación primaria:
- `-5363971034` **Pagos** — abonos de clientes. Todo comprobante aquí es venta salvo evidencia fuerte de lo contrario.
- `-5154074469` **Pagos Logística** — solicitudes de pago a transportistas + sus comprobantes de egreso.
- `-5559621779` **Contabilidad** — todos los demás egresos: arriendos, nómina, viáticos, impuestos, facturas de compra, OCs de proveedores locales.

Router interno (nodo Switch) separa en 3 rutas: `COMPROBANTE` (adjunto → OCR), `SOLICITUD_TRANSPORTE` (texto en grupo Logística con 2+ marcadores estructurales: cuenta de cobro, remisión, cédula, costo, banco/medio — no depende de verbos específicos porque el lenguaje real es muy variado, ej. "hacer anticipo" en vez de "pagar"), `REFERENCIA_ID` (texto con un número de 4-6 dígitos que vincula un comprobante recién enviado con su ID de compra).

**Detalles de implementación importantes para quien toque este flujo:**
- `if (msg.from?.is_bot) return [];` al inicio — **crítico**, sin esto el bot procesa sus propias confirmaciones y entra en bucle.
- El binario del archivo (foto/PDF) se descarga UNA vez y se bifurca en paralelo hacia OCR y hacia Drive — nunca encadenar OCR después de Drive, porque Drive solo devuelve metadata, no el binario.
- Carpetas de Drive por mes (`AAAA-MM`) se buscan y crean con `alwaysOutputData: true` en el nodo de búsqueda (si no, una carpeta inexistente mata la rama entera en n8n).
- Nodo Wait de 25s en la ruta REFERENCIA_ID: evita condición de carrera cuando el asesor manda el texto de la ID muy rápido después de la foto (el OCR toma ~10s).
- Antiduplicado de "copia de soporte": si el mismo comprobante llega a dos grupos (caso real: pago a transportista se manda a Logística Y Contabilidad), se detecta por referencia bancaria o valor+fecha+beneficiario, y la segunda copia se archiva como `COPIA_SOPORTE` sin ser procesada por ningún motor.
- OCR usa un prompt con los identificadores de MeUp (NIT, nombre, las 6 cuentas) para determinar `destino_es_meup`/`origen_es_meup` — la clasificación NO se basa en si el comprobante dice "Enviaste" (eso es perspectiva del que paga, no indica si es ingreso o egreso para MeUp).
- Vinculación factura+OC↔pago cuando llegan por separado: se implementó en WF-10, no aquí.

### WF-02 · Conciliación de clientes
**Trigger:** Schedule cada 30 min.
Cruza `COMPROBANTES_WA` (CLASIFICACION=COMPROBANTE_PAGO) contra `BANCOS_MOV` (TIPO=INGRESO): valor ±$1, fecha ±3 días, desempate por `ID_COMPRA_INFORMADO` si hay ambigüedad. Al conciliar, enriquece la fila del banco con CATEGORIA=VENTA, TERCERO, FACTURA_OC, DETALLE.

**Bug corregido a fondo (relevante si aparecen nuevos):** las fechas de movimientos cargados con versiones viejas de WF-04 quedaron como serial de Excel (`"46208"`), y el comparador de fechas los descartaba silenciosamente. Ahora hay un `parseF()` compartido en varios motores que entiende serial/dd-mm-aaaa/ISO, y si la fecha es ilegible, **no descarta el candidato** — deja que decidan el valor y otros desempates.

### WF-03 · Recibo de caja SIIGO
**Estado: NO activo (Fase 4).** Requiere credenciales API de SIIGO + IDs de document-type/payment-type + decisión pendiente de la contadora (¿el RC va como anticipo o cruzado contra factura?).

### WF-04 · Carga de extractos bancarios
**Trigger:** archivo nuevo en carpeta Drive `EXTRACTOS_ENTRADA`.
El nombre del archivo debe incluir el código de cuenta (ej. `BC-CTE-3762_2026-07.xlsx`). Normalizador tolerante a: valores con letras/símbolos (`"COP -$ 15.476.400,00"`), fechas en serial de Excel o dd/mm/aaaa, referencias en 2 columnas separadas. Clasificador de categoría por patrones de texto en la descripción (4x1000, comisiones, nómina, PSE, Nequi, etc.) — heurístico, requiere revisión humana de `POR_CLASIFICAR`.

**Cuidado:** "Transferencia cta suc virtual" en Bancolombia es genérico (puede ser CUALQUIER pago, no solo traslados entre cuentas propias) — solo se clasifica TRASLADO_INTERNO si la referencia contiene el número de una cuenta propia.

### WF-05 · Resumen diario
**Trigger:** Cron 7:00 am. Lee COMPROBANTES_WA + BANCOS_MOV + CREDITOS, envía resumen a Telegram (grupo Contabilidad).

### WF-06 · Pagos de importación
**Trigger:** Webhook (pensado para conectarse desde Lovable). Calcula VALOR_COP con TRM del día, actualiza saldo de invoice.

### WF-07 v2 · Solicitud de transporte (sub-workflow)
**Trigger:** Execute Workflow (invocado por WF-01, **no tiene trigger propio activo**).
Parser con Claude que extrae de texto libre en español colombiano N solicitudes en un solo mensaje (multi-solicitud soportado). Extrae: cuenta de cobro, remisión (=ID de compra si no viene explícito), transportista, cédula, teléfono O número de cuenta bancaria, valor, tipo (TOTAL/ABONO — "anticipo" se mapea a ABONO). Valida contra COMPRAS_SYMPHONY (existencia + alerta si supera 120% de lo cobrado al cliente). Calcula retefuente (1% si bruto ≥ $209.496) y PAGO_NETO. Deduplica por cuenta_cobro+remisión o por id_compra+valor+transportista.

### WF-08 · Pago a transportista
**Trigger:** Schedule cada 30 min.
Cruza comprobantes CLASIFICACION=COMPROBANTE_EGRESO del grupo Logística contra TRANSPORTES_PAGOS pendientes — **matching contra NETO o BRUTO** (el comprobante bancario siempre muestra el neto real que salió, después de restar retefuente). Soporta abono parcial (crea fila SALDO). Antiduplicado doble: pago ya marcado PAGADO, o el egreso ya está vinculado en el extracto. Estados de problema (`SIN_MATCH`/`AMBIGUO`) se persisten para no re-alertar en cada ciclo.

### WF-09 · Carga de compras Symphony
**Trigger:** archivo nuevo en Drive `COMPRAS_SYMPHONY_ENTRADA`.
**Importante — estructura real del archivo de Symphony** (descubierta con archivo real, no documentación): una fila con `Id` por cada compra, seguida de N filas con `Id` vacío que son los items de esa compra (no solo 1 fila resumen). Excepción: 1-2 filas por archivo sin `Id` NI `Productos` que son de retenciones/continuación y deben descartarse.

Upsert de 3 niveles con memoria independiente por tabla: cabecera (nueva→agrega, existente→actualiza campos mutables como ESTADO/ABONOS/SALDO), detalle (por ID_COMPRA — carga el detalle aunque la cabecera ya exista, corrección de un bug donde el detalle nunca se cargaba en recargas), proveedores locales (agrupa por NIT dentro de cada compra, genera fila en PROVEEDORES_LOCALES_PAGOS si el NIT no es el propio).

`COD_PRODUCTO` se lee y escribe en modo `RAW` — sin esto Google Sheets/pandas interpreta `"0162501"` como número y pierde el cero inicial.

**Rate limiting de Google Sheets:** los 3 Appends (cabecera/detalle/proveedores) se ejecutaban en paralelo desde el nodo Switch y superaban el límite de escrituras/minuto de la API. Se agregaron nodos `Wait` de 2s antes de los Appends de detalle y proveedores para serializar las escrituras.

**Decisión de producto:** si Symphony reduce cantidades o elimina items de una compra ya cargada, el detalle NO se resincroniza automáticamente (para no pisar anotaciones manuales de pago) — se corrige a mano en el Sheet. Es intencional, ocurre pocas veces según el negocio.

### WF-10 · Conciliación de egresos generales
**Trigger:** Schedule cada 30 min.
Cruza comprobantes CLASIFICACION=COMPROBANTE_EGRESO del grupo Contabilidad (excluyendo los que ya toma WF-08 por ser de transporte) contra egresos bancarios. Si el egreso paga una compra a proveedor local (por OC o por monto), marca PROVEEDORES_LOCALES_PAGOS como PAGADO/ABONADO.

**Asociación de soportes que llegan en momentos distintos** (ej. OC enviada un día, comprobante de pago dos días después): 3 niveles de confianza decrecientes — (1) misma OC, hasta 7 días, cualquier remitente; (2) mismo valor + mismo remitente, hasta 24h; (3) mismo valor, cualquier remitente, hasta 1h. El soporte (factura/OC) vinculado queda como `SOPORTE_VINCULADO` apuntando al ID del pago.

### WF-11 · Proxy de lectura para Lovable
**Trigger:** Webhook GET `/meup-finanzas-data?tabla=X`.
Autenticación por header `x-api-key` contra token fijo. Lista blanca de 15 pestañas permitidas. Existe para que el dashboard no necesite el Sheet público. Respuesta: `{tabla, actualizado, n, datos: [...]}`.

---

## 6. Patrones sistémicos de n8n (aplican a cualquier flujo nuevo)

Estos bugs aparecieron repetidas veces durante la construcción y ya están corregidos en los 11 flujos actuales — cualquier flujo nuevo debe seguir estos patrones desde el diseño:

1. **Lecturas de múltiples pestañas antes de un nodo Code:** deben encadenarse en **serie estricta** (nodo A → nodo B → nodo C → motor), nunca en paralelo desde un mismo disparador. n8n no garantiza que todas las ramas paralelas terminen antes de que el motor se dispare, y `$('Nodo').all()` explota con "hasn't been executed" si esa rama no corrió a tiempo.
2. **`alwaysOutputData: true`** en cualquier nodo de lectura/búsqueda cuyo resultado podría ser cero filas — si no, n8n mata la rama entera en vez de continuar con lista vacía.
3. **Referencias entre ramas paralelas** deben usar `.first()`, nunca `.item` — `.item` intenta emparejar por índice y falla con "Invalid expression" en cuanto las ramas se bifurcan.
4. **Binario de archivos** no sobrevive pasar por nodos que solo devuelven JSON (como los de gestión de carpetas de Drive) — hay que bifurcar desde el nodo de descarga original hacia cada rama que lo necesite, o usar un nodo puente que junte JSON + binario antes de la operación final.
5. **Google Sheets API rate limit:** máximo ~60 escrituras/min. Cualquier flujo con 3+ Appends/Updates en paralelo necesita nodos `Wait` de 2s intercalados.
6. **Alertas de "sin match" o "ambiguo":** el estado debe persistirse en el Sheet en el primer ciclo que se detecta, y los ciclos siguientes deben chequear ese estado para NO re-alertar — si no, un motor cada 30 min genera spam infinito de Telegram sobre el mismo problema no resuelto.
7. **El bot no debe procesar sus propios mensajes** — filtrar `msg.from?.is_bot` al inicio de cualquier flujo que escuche Telegram y también escriba confirmaciones ahí.
8. **Fechas:** nunca asumir un formato único. Usar un parser tolerante (serial Excel / dd-mm-aaaa / ISO) en cualquier comparación de fechas entre fuentes distintas (Sheets vs OCR vs extractos).

---

## 7. Infraestructura y credenciales

**Migración en curso:** n8n Cloud → self-hosted en Hetzner (CX23, 4GB RAM, ~€6.49/mes) por límite de ejecuciones (el volumen real del sistema en operación normal es ~14.000 ejecuciones/mes, muy por encima de los planes económicos de Cloud). Docker Compose con Caddy para HTTPS automático sobre `n8n.meup.co`. Ver `MANUAL_N8N_SELF_HOSTED_MEUP.md` en los archivos del proyecto para el procedimiento paso a paso.

**Credenciales que vive únicamente en n8n (nunca en el Sheet ni en los JSON):**
- Google Sheets OAuth2 + Google Drive OAuth2 (misma cuenta de servicio)
- Telegram Bot API (token del bot único usado en los 3 grupos)
- Anthropic API key (header `x-api-key`)
- SIIGO API (pendiente de obtener — Fase 4)

**IDs fijos de la instancia actual** (confirmar que sigan vigentes tras la migración a Hetzner):
- Sheet maestro: `1LgOCIMRXpyCQP9m9BYlHYjgykZ-otTXz-psuY0mRUdc`
- Carpetas Drive: EXTRACTOS_ENTRADA, EXTRACTOS_PROCESADOS, COMPRAS_SYMPHONY_ENTRADA, COMPROBANTES_WA (con subcarpetas por mes)
- Chat IDs Telegram: Pagos `-5363971034` · Logística `-5154074469` · Contabilidad `-5559621779`

---

## 8. Capa de visualización

**Lovable (activo, suscripción pagada):** dashboard de solo lectura que consume WF-11. En construcción por fases — MVP inicial: Resumen + Comprobantes; siguiente fase: Transportes, Compras, Importaciones/Bancos. Estilo MeUp: navy `#1B2B4B` + dorado `#C9A55A`.

**Bolt.new (prototipo, en pausa):** se generó un sistema contable completo con Postgres propio (Supabase), partida doble, PUC colombiano, generación automática de asientos, roles/RLS. **No está conectado a nada real.** Es una evaluación de si en el futuro conviene migrar de Google Sheets a una base de datos relacional propia. Si se decide avanzar por ese camino, el punto de integración serían webhooks de entrada compatibles con los mismos payloads que hoy reciben las pestañas de Sheets — cambiar destino en los flujos de n8n, no reconstruir la lógica de negocio.

---

## 9. Deuda técnica y pendientes conocidos

- [ ] Migración completa a Hetzner (self-hosted) — en curso.
- [ ] Fase 4 SIIGO: credenciales API + decisión de la contadora sobre modelo de recibo de caja.
- [ ] Migración de canal de Telegram → WhatsApp Cloud API (WF-01 v2 ya existe preparado, requiere cuenta Meta Business verificada y decide si migra el número actual o usa uno nuevo).
- [ ] Confirmar con la contadora: excepciones de retefuente transporte por régimen del transportista.
- [ ] Nombres reales de los NITs locales detectados automáticamente en CAT_TERCEROS (hoy quedan como "PROVEEDOR LOCAL <nit>" hasta que se editen a mano).
- [ ] Agente conversacional de consultas en Telegram (`/estado 15831`, reportes en lenguaje natural) — diseño ya definido (4ª ruta dentro de WF-01, capa determinista + capa Claude encima), pendiente de construir cuando el sistema lleve más tiempo estable.
- [ ] Reconstrucción/traslado de credenciales tras la migración a Hetzner — cada flujo debe reasignar credenciales manualmente al reimportar en la nueva instancia.

---

## 10. Cómo se ha trabajado (para mantener el mismo estándar)

Cada cambio a un flujo de n8n se ha validado con un harness de pruebas en Node.js que simula la lógica del nodo Code fuera de n8n (no hay entorno de test real de n8n disponible) antes de entregar el JSON. Los JSON se entregan con todos los IDs/tokens de infraestructura ya incrustados salvo credenciales (que se asignan manualmente en la UI de n8n por seguridad). Cambios de esquema en el Sheet siempre se prueban primero contra datos/archivos reales subidos por Milena antes de asumir estructura — varios bugs grandes (formato real de Symphony, formato real de extractos Bancolombia/Panamá) solo se descubrieron así.
