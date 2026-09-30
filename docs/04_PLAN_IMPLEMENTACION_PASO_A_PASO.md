# Plan de Implementación · Sistema Financiero MeUp
**Ruta paso a paso, en orden de dependencias, con verificación en cada etapa**
Versión 1.0 · Julio 2026

> Principio del plan: cada fase produce algo que ya funciona solo, y ninguna
> fase depende de una posterior. Si te detienes en la fase 3, lo montado
> hasta ahí sigue siendo útil. El dinero real (SIIGO) entra de último,
> cuando el sistema ya demostró precisión.

---

## FASE 0 · Prerrequisitos (1 tarde) — sin esto nada arranca

**0.1 Google Sheets**
- [ ] Sube `MEUP_FINANZAS_MASTER.xlsx` a Google Drive → clic derecho → "Abrir con Hojas de cálculo de Google" → Archivo → Guardar como hoja de cálculo de Google.
- [ ] Copia el **ID del documento** (la cadena larga de la URL entre `/d/` y `/edit`). Guárdalo: lo vas a pegar en los 9 flujos.
- [ ] Verifica que las 18 pestañas abrieron bien y que DASH_KPI muestra valores (no errores #REF).
- [ ] Comparte el archivo SOLO con: tú, la contadora, y la cuenta Google que usará n8n (como Editor).

**0.2 Carpetas en Google Drive** (crea y anota el ID de cada una, está en la URL)
- [ ] `/MEUP_FINANZAS/COMPROBANTES_WA/`
- [ ] `/MEUP_FINANZAS/EXTRACTOS_ENTRADA/`
- [ ] `/MEUP_FINANZAS/EXTRACTOS_PROCESADOS/`
- [ ] `/MEUP_FINANZAS/COMPRAS_SYMPHONY_ENTRADA/`

**0.3 n8n**
- [ ] Decide: n8n Cloud (más rápido de arrancar, ~USD 24/mes) o self-hosted (VPS ~USD 6-12/mes, requiere quien lo administre). Para empezar recomiendo Cloud; migrar después es exportar/importar los mismos JSON.
- [ ] Crea la cuenta/instancia y verifica que puedes crear un workflow de prueba.

**0.4 Telegram**
- [ ] Habla con @BotFather en Telegram → `/newbot` → guarda el token.
- [ ] Crea un grupo "MeUp Finanzas" (tú + tesorería), agrega el bot.
- [ ] Obtén el chat_id del grupo (mandando un mensaje y consultando `https://api.telegram.org/bot<TOKEN>/getUpdates`).

**Checkpoint fase 0:** tienes 6 datos anotados: ID del Sheet, 4 IDs de carpetas, token+chat_id de Telegram.

---

## FASE 1 · Bancos y Symphony (semana 1) — valor inmediato, riesgo cero

Empieza por aquí porque no depende de WhatsApp ni de APIs externas difíciles: solo Google + Telegram, y automatiza trabajo que hoy haces a mano.

**1.1 Credenciales en n8n** (menú Credentials → Add)
- [ ] Google Sheets OAuth2 y Google Drive OAuth2 (misma cuenta con la que compartiste el Sheet).
- [ ] Telegram API (el token del bot).

**1.2 Importar y configurar WF-04 (extractos) y WF-05 (alertas)**
- [ ] Import from file → `WF04_carga_extractos.json` y `WF05_alertas_y_reporte.json`.
- [ ] En cada nodo con marcador: reemplaza `REEMPLAZAR_ID_SHEET_MASTER`, IDs de carpetas, `REEMPLAZAR_CHAT_ID_TELEGRAM`, y asigna las credenciales creadas.
- [ ] Activa ambos flujos.

**1.3 Prueba de fuego WF-04**
- [ ] Descarga el extracto de junio de Bancolombia Cte, renómbralo `BC-CTE-3762_2026-06.csv` y súbelo a `/EXTRACTOS_ENTRADA`.
- [ ] Verifica: filas nuevas en BANCOS_MOV con TIPO/CATEGORIA clasificados, archivo movido a `/EXTRACTOS_PROCESADOS`, confirmación en Telegram.
- [ ] Revisa los `POR_CLASIFICAR` y corrígelos a mano — así calibras qué reglas de clasificación agregar después.
- [ ] Repite con una cuenta más (ej. DV-AHO-4335). Si ambas pasan, sube el resto.

**1.4 Importar y configurar WF-09 (Symphony)**
- [ ] Importa `WF09_carga_compras_symphony.json`, reemplaza marcadores, activa.
- [ ] Sube el archivo de compras de HOY a `/COMPRAS_SYMPHONY_ENTRADA`.
- [ ] Verifica: las compras nuevas aparecen en COMPRAS_SYMPHONY; las 25 de julio que ya venían precargadas se ACTUALIZAN (abonos/saldo) sin duplicarse.
- [ ] Al día siguiente sube el archivo diario otra vez y confirma que solo cambian los campos mutables.

**Checkpoint fase 1:** todas las mañanas a las 7:00 llega el resumen a Telegram, los extractos entran solos y Symphony se carga a diario. Ya eliminaste 3 tareas manuales.

---

## FASE 2 · WhatsApp: recepción y OCR (semana 2) — el corazón del sistema

**2.1 Canal de WhatsApp — decisión previa**
- Opción A (recomendada): **WhatsApp Business Cloud API** (Meta for Developers). Requiere: cuenta Meta Business verificada, un número dedicado (puede ser el actual si aceptas migrarlo a la API — deja de funcionar en el celular con la app normal). Crear app → producto WhatsApp → token permanente → configurar webhook.
- Opción B: **Evolution API** (open source, usa el número actual sin migrar, vía QR como WhatsApp Web). Menos formal, sin costo Meta, pero depende de una sesión activa. Solo cambia los 2 primeros nodos de WF-01; pídeme la variante si eliges esta.
- [ ] Decisión tomada y canal funcionando (recibes el JSON del webhook en n8n al mandar un mensaje de prueba).

**2.2 API key de Anthropic**
- [ ] Crea cuenta en console.anthropic.com → API Keys → guarda la key. Créale una credencial "Header Auth" en n8n (header `x-api-key`).

**2.3 Importar en ESTE orden (WF-01 referencia a WF-07):**
- [ ] 1º `WF07_v2_solicitud_transporte.json` → reemplaza marcadores → guarda → **copia el ID del workflow** (está en la URL de n8n).
- [ ] 2º `WF01_v2_whatsapp_router.json` → reemplaza marcadores incluyendo `REEMPLAZAR_ID_WORKFLOW_WF07` con el ID que copiaste → conecta el webhook a Meta (verificación GET del hub.challenge) → activa ambos.

**2.4 Pruebas guionadas (modo observación, sin pagar nada aún)**
- [ ] Manda una foto de un comprobante viejo de cliente → debe aparecer en COMPROBANTES_WA con OCR lleno y CLASIFICACION=COMPROBANTE_PAGO.
- [ ] Manda un comprobante viejo de un pago que TÚ hiciste (Nequi enviado) → CLASIFICACION=COMPROBANTE_EGRESO.
- [ ] Manda el texto real de una solicitud de transporte (el formato de logística) → fila en TRANSPORTES_SOLICITUDES + pago PENDIENTE + alerta Telegram con el NETO a pagar.
- [ ] Manda una solicitud con DOS transportistas en el mismo mensaje → dos filas.
- [ ] Manda la misma solicitud dos veces → la segunda queda DUPLICADO con alerta.
- [ ] Manda un "buenos días" → no debe pasar nada (IGNORAR).
- [ ] Durante 3-5 días, deja que el equipo mande lo real y revisa a diario OCR_CONFIANZA y los REVISAR. Meta: >90% de extracciones correctas antes de seguir.

**Checkpoint fase 2:** todo lo que entra por WhatsApp queda archivado en Drive, leído por OCR y registrado — pero todavía nada toca la contabilidad.

---

## FASE 3 · Conciliación y transportes end-to-end (semana 3)

**3.1 Importar WF-02 (conciliación clientes) y WF-08 (pagos transportistas)**
- [ ] Importa ambos, reemplaza marcadores, activa.
- Requisito: la fase 1 debe estar viva (WF-02 y WF-08 cruzan contra BANCOS_MOV; sin extractos cargados todo saldrá SIN_MATCH, que es correcto pero ruidoso).

**3.2 Ciclo real completo de un pago a transportista**
- [ ] Logística manda la solicitud → llega alerta con neto.
- [ ] Tesorería paga el NETO y manda el comprobante al chat.
- [ ] En máximo 30 min: TRANSPORTES_PAGOS pasa a PAGADO con URL del comprobante, la solicitud a PAGADO (o PARCIAL si fue abono), aparece el egreso en BANCOS_MOV con CATEGORIA=TRANSPORTE y ORIGEN=TRANSPORTE_APP, y llega la confirmación a Telegram.
- [ ] Prueba de abono: paga la mitad → verifica que se crea la fila SALDO pendiente.
- [ ] Prueba de duplicado: reenvía el mismo comprobante → alerta roja, nada se registra.
- [ ] Cuando cargues el siguiente extracto (WF-04), verifica que el egreso real se vincula al proyectado en vez de duplicarse.

**3.3 Ciclo de cliente**
- [ ] Un cliente real paga y manda comprobante → CONCILIADO contra el ingreso del extracto, fila en CONCILIACION.
- [ ] Los SIN_MATCH del día se resuelven en la revisión matinal (5-10 min con el resumen de las 7:00).

**Checkpoint fase 3:** el sistema opera completo de punta a punta, con HUMAN_REVIEW como red de seguridad. Solo falta contabilizar automático.

---

## FASE 4 · SIIGO (semana 4-5) — el último eslabón, a propósito

No actives esto hasta que las fases 2-3 lleven al menos 2 semanas con >95% de matching correcto. Un error de OCR en Sheets se corrige en segundos; en SIIGO es un ajuste contable.

- [ ] Solicita a SIIGO las credenciales de API (usuario API + access_key; lo gestiona tu ejecutivo de cuenta o soporte SIIGO Nube).
- [ ] Con Postman o desde n8n: `GET /v1/document-types?type=RC` → anota el `id` del Recibo de Caja; `GET /v1/payment-types?document_type=RC` → id del medio de pago transferencia. Pégalos en el nodo "Construir voucher RC" de WF-03 (está señalado con ⚠️ adentro).
- [ ] Punto pendiente con la contadora ANTES de activar: ¿el recibo va como anticipo (AdvancePayment) o cruzado contra factura de venta? El flujo está en anticipo; si es contra factura, pídeme el ajuste con el ejemplo real.
- [ ] Importa WF-03, prueba con UN comprobante conciliado, verifica el recibo en SIIGO, y solo entonces activa el cron.
- [ ] Los comprobantes de egreso de transportistas se contabilizan por ahora manualmente (la contadora toma TRANSPORTES_PAGOS como fuente y llena COMPROBANTE_SIIGO). Automatizarlo vía `POST /v1/journals` es una fase 6 opcional — primero confirma con ella la parametrización de retefuente.

---

## FASE 5 · Lovable y cierre (semana 5-6)

- [ ] Pídeme el **WF-10 proxy de lectura** (webhook GET protegido con header para que Lovable lea el Sheet sin hacerlo público) — son 3 nodos, te lo entrego cuando llegues aquí.
- [ ] Construye el dashboard en Lovable con el prompt del documento 02 + la sección Transportes del documento 03. Orden de pantallas: 1º Resumen + Comprobantes WA, 2º Transportes, 3º Importaciones/Créditos/Bancos.
- [ ] Importa WF-06 (pagos de importación) y conecta el formulario del dashboard a su webhook (protégelo con header auth).
- [ ] Migra el histórico que quieras conservar: IMPORT → IMPORTACIONES/IMPORTACIONES_PAGOS y CREDITOS al esquema nuevo (los ejemplos CR-001..CR-008 e IMP-031 te marcan el patrón; puedo hacer la migración masiva si me pasas el archivo completo).

---

## Calendario resumido

| Semana | Fase | Resultado visible |
|---|---|---|
| 1 | 0 + 1 | Resumen diario Telegram; extractos y Symphony automáticos |
| 2 | 2 | WhatsApp + OCR en observación |
| 3 | 3 | Conciliación y transportes end-to-end |
| 4-5 | 4 | Recibos de caja automáticos en SIIGO |
| 5-6 | 5 | Dashboard Lovable + importaciones + histórico |

## Reglas de oro durante la implementación
1. Un flujo a la vez, y no avanzas de fase sin pasar el checkpoint.
2. Credenciales SOLO en n8n — nunca en el Sheet, nunca en los JSON, nunca por WhatsApp.
3. Las primeras 2 semanas revisa TODO lo que quede HUMAN_REVIEW=PENDIENTE; después gobiérnalo por el KPI.
4. Si un flujo falla, n8n guarda la ejecución con el error exacto (menú Executions) — mándame el pantallazo del nodo rojo y lo resolvemos.
5. Cambios estructurales (pestañas, columnas, reglas) → actualizamos juntos REFERENCIA_SISTEMA_FINANCIERO_MEUP.md en el proyecto.
