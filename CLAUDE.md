# meup-finanzas

Sistema financiero automatizado de **MeUp** (marca de París Ingenieros SAS, distribuidor
colombiano de piedra natural y cerámica). Este repo es la fuente de verdad versionada
del sistema — léelo completo antes de tocar cualquier workflow, tabla o dashboard.

**No es un rewrite.** n8n sigue siendo el motor de ejecución (self-hosted en Hetzner,
`n8n.meup.co`). Este repo existe para: versionar lo que antes solo vivía en n8n Cloud/Sheets,
documentar las reglas de negocio con precisión, y dar una base ordenada para que Opus planee
y Codex construya sin redescubrir bugs ya resueltos.

## Arquitectura actual

```
Telegram (3 grupos) ──┐
Drive/Dropbox ─────────┼──► n8n (WF-01..WF-11) ──► Supabase/Postgres (meup-finanzas)
Symphony (export) ─────┘         │                        │
                                  ▼                        ▼
                          Claude API (OCR/NLP)      Lovable (dashboard + editor)
                                  │
                                  ▼
                          SIIGO (Fase 4, no activa aún)
```

- **Antes:** Google Sheets `MEUP_FINANZAS_MASTER` era la fuente de verdad operativa.
- **Ahora (migración en curso):** Postgres en Supabase (`docs/03_diccionario_datos` +
  `migrations/0001_schema_inicial.sql`) reemplaza a Sheets, tabla por tabla, empezando
  por las de mayor volumen (`COMPRAS_DETALLE`, `BANCOS_MOV`, `COMPROBANTES_WA`).
- Google Sheets queda de respaldo/lectura hasta que cada tabla termine su migración —
  **nunca duplicar sin que un lado sea de solo lectura.**
- Almacenamiento de documentos: migrando de Google Drive a **Dropbox** (ya tiene plan
  propio la empresa), carpetas por `AAAA-MM`, mismo patrón que ya usaba Drive.

## 3 grupos de Telegram (señal de clasificación primaria)

1. **Pagos** — asesores + tesorería, abonos/pagos de clientes.
2. **Pagos Logística** — logística + tesorería, solicitudes y comprobantes de pago a transportistas.
3. **Contabilidad** — auxiliares/contadora/tesorería, todo lo demás: gastos, facturas de
   compra, OC, nómina, viáticos, importaciones, giros internacionales.

El `chat_id` del grupo es la señal principal de clasificación en el router (WF-01);
se refina con la dirección de flujo de dinero detectada por OCR.

## Reglas de negocio críticas (no violar sin confirmarlas primero)

- `ID_COMPRA` es **siempre** el número de Symphony tal cual (ej. `15889`, nunca `15889-C`) —
  todos los cruces dependen de esto.
- Symphony invierte la nomenclatura intuitiva: `VALOR_DOMICILIO` = cobrado al cliente;
  `COSTO_TRANSPORTE` = pagado al transportista.
- NIT `900570024` = producto propio importado. Cualquier otro NIT = proveedor local.
  Mezcla en una compra = `MIXTO`.
- **Retefuente transporte:** 1% si el bruto ≥ 4 UVT (`$209.496` en 2026, ver tabla `config`,
  parámetro `UMBRAL_RETEFUENTE_TRANSPORTE`). `PAGO_NETO = VALOR − RETENCION`. El comprobante
  que llega por Telegram muestra el NETO — el matching contra banco debe intentar neto Y bruto.
  **Pendiente confirmar con la contadora si hay excepciones por régimen del transportista.**
- Pagos a transportistas = comprobante de **egreso** en SIIGO, nunca `RECIBOS_CAJA`.
- `BANCOS_MOV.ORIGEN`: `EXTRACTO` (real, cargado por WF-04) vs `TRANSPORTE_APP` (proyección
  de WF-08 mientras el egreso real no llega al extracto). Siempre buscar primero el real
  antes de crear la proyección.
- `HUMAN_REVIEW` (`PENDIENTE`/`REVISADO`) existe en las tablas que reciben datos automáticos —
  todo lo automático nace `PENDIENTE`.
- `CAT_TERCEROS` = catálogo (quién es el tercero). `PROVEEDORES_LOCALES_PAGOS` = transaccional
  (qué se debe por una compra puntual). El nombre en la transaccional es lookup al catálogo,
  nunca se duplica a mano.

Diccionario de columnas exacto (heredado de Sheets, ahora también en Postgres):
`docs/REFERENCIA_SISTEMA_FINANCIERO_MEUP.md`.

## 8 patrones anti-bug de n8n (aprendidos en producción — no repetir)

1. **Nunca dejar lecturas paralelas antes de un Code node.** `$('Node').all()` explota con
   "hasn't been executed" si dos nodos previos corren en paralelo. Serializar siempre.
2. **`alwaysOutputData: true`** en cualquier nodo de búsqueda/lookup que pueda devolver cero
   filas — si no, n8n mata toda la rama.
3. **`.first()`, nunca `.item`** en referencias cross-branch una vez que el flujo se paraleliza.
4. **Datos binarios no sobreviven pasar por nodos JSON-only** (ej. gestión de carpetas de
   Drive/Dropbox). Si hay lógica de carpetas entre la descarga y la subida, puentear
   binario+JSON explícitamente en un Code node dedicado.
5. **Rate limit de Sheets (~60 escrituras/min)** — con Postgres esto deja de aplicar, pero si
   algún nodo sigue escribiendo a Sheets durante la transición, usar `Wait` entre escrituras
   simultáneas.
6. **`cellFormat: 'RAW'`** en nodos de Sheets que tocan códigos de producto con ceros a la
   izquierda (si aún queda algún nodo de Sheets vivo).
7. **Fechas tolerantes.** Excel serial, DD/MM/YYYY e ISO deben pasar por un parser tolerante
   (`parseF()`) — una fecha no parseable NUNCA debe bloquear un match, debe pasar a
   desempate por valor.
8. **Telegram permite un solo Trigger activo por bot en toda la instancia n8n.** Cualquier
   feature conversacional nuevo es una ruta más dentro del router existente, nunca un
   trigger nuevo.
9. **Un nodo Postgres de escritura (INSERT/UPDATE con `executeQuery`) NO hace echo del
   input como output**, a diferencia de los nodos de Sheets (append/update), que sí
   devuelven la fila de entrada como salida. Cualquier nodo aguas abajo que dependa de
   `$json.CAMPO` "a secas" para un dato que se originó antes del nodo Postgres recibe
   `undefined` en silencio (no hay error — el mensaje sale, la fila se escribe, pero con
   campos vacíos). Encontrado en producción en WF-02/07/08 durante la migración (2 oct
   2026): una alerta de Telegram salió con todos los placeholders vacíos porque el nodo
   de alerta leía `$json` después de un `UPDATE` de Postgres que no traía esos campos.
   **Regla:** después de cualquier nodo Postgres de escritura, todo nodo siguiente debe
   referenciar los campos con `$('NodoOrigen').item.json.CAMPO` (el nodo Code/lectura
   donde nació el dato), nunca `$json.CAMPO` a secas. Los nodos IF/Switch sí preservan
   el pass-through correctamente — el problema es exclusivo de los nodos Postgres de
   escritura.

## Estructura del repo

```
CLAUDE.md                      # este archivo
docs/                          # brief técnico, diccionario de datos, plan de fases
migrations/                    # SQL versionado, aplicado a Supabase project meup-finanzas
workflows/                     # export JSON de cada WF activo (WF-01 v4 .. WF-11)
workflows/obsoletos/           # versiones reemplazadas, NO usar, se conservan por referencia
scripts/                       # (pendiente) deploy-n8n.js — push de workflows/ al n8n vía API REST
```

## Infraestructura (IDs fijos, sin credenciales)

- n8n self-hosted: Hetzner CX23, Docker + Caddy, `n8n.meup.co`.
- Supabase project `meup-finanzas`: `wzlmaylzwdewqppkmdnn` (`https://wzlmaylzwdewqppkmdnn.supabase.co`).
- Google Sheet legado `MEUP_FINANZAS_MASTER`: `1LgOCIMRXpyCQP9m9BYlHYjgykZ-otTXz-psuY0mRUdc`
  (en migración, no eliminar hasta cerrar Fase 3).
- 3 chat_id de Telegram: Pagos `-5363971034`, Pagos Logística `-5154074469`,
  Contabilidad `-5559621779`.
- Branding: navy `#1B2B4B`, dorado `#C9A55A`.

Credenciales reales viven **solo** en el gestor de credenciales de n8n y en Supabase —
nunca en este repo. Cualquier JSON con marcador `REEMPLAZAR_...` es intencional.

## Fases

Ver `docs/04_PLAN_IMPLEMENTACION_PASO_A_PASO.md` para el detalle histórico y
`docs/03_diccionario_datos.md`/este archivo para el estado vigente:

0. Infra (repo, Supabase, credenciales Dropbox) — hecho.
1. Repo scaffold + docs + workflows versionados — hecho.
2. Schema Postgres en Supabase — hecho (`migrations/0001_schema_inicial.sql`).
3. Migrar workflows de nodos Sheets → Postgres — **hecho, cerrado (2 oct 2026).**
   - `COMPRAS_DETALLE` (WF-09), `BANCOS_MOV` (WF-04), `COMPROBANTES_WA` (WF-01),
     `CONCILIACION` (WF-02), `TRANSPORTES_SOLICITUDES`/`TRANSPORTES_PAGOS`
     (WF-07, WF-08) — los 6 migrados, importados, activados y probados en
     producción. Las versiones Sheets equivalentes quedaron desactivadas en
     n8n y movidas a `workflows/obsoletos/`.
   - Bugs de esquema encontrados y corregidos en el camino: `ocr_confianza`
     (era `numeric`, es texto categórico ALTA/MEDIA/BAJA — migración 0003),
     `retefuente_aplica` (era `boolean`, es tri-estado POR_CONFIRMAR/SI/NO —
     migración 0004, y migración 0007 que además le quitó el NOT NULL porque
     la fila "revisar a mano" de WF-07 la manda en null explícito), y
     `transportes_solicitudes.valor_solicitado` relajado a nullable (migración
     0005, mismo caso).
   - Patrón confirmado en WF-07/08/02: varias tablas tienen FK estrictas
     (`id_compra`, `id_mov_banco`, `id_doc_wa`, `cuenta`→`cat_bancos`). El código
     de cada workflow debe dejar esos campos en null cuando la referencia no
     existe todavía, en vez de bloquear el insert — coherente con el patrón
     anti-bug #7 (nunca bloquear por un dato no resuelto).
   - Bug de producción encontrado y corregido tras activar: el patrón anti-bug
     #9 (nodos Postgres de escritura no hacen echo del input) rompía las
     alertas de Telegram de los 3 flujos — corregido en los JSON vigentes.
   - **WF-08 tomaba por error comprobantes del grupo CONTABILIDAD** (facturas,
     OC, arriendo, nómina, anticipos) porque su query de lectura filtraba solo
     por `clasificacion = 'COMPROBANTE_EGRESO'`, sin filtrar `grupo_origen`.
     Los marcaba `SIN_MATCH`/`AMBIGUO` al no encontrar nada en
     `TRANSPORTES_PAGOS` (no pagan transporte). No llegó a duplicar pagos
     (WF-08 solo escribe dinero cuando SÍ encuentra match), pero sí
     contaminaba el estado y consumía ciclos de revisión. Corregido
     agregando `and grupo_origen = 'LOGISTICA'` a la query (3 oct 2026).
   - **Gap encontrado y cerrado (3 oct 2026):** `WF-10` (conciliación de
     egresos generales del grupo CONTABILIDAD — vincula factura/OC con su
     comprobante de pago cuando llegan por separado, marca
     `PROVEEDORES_LOCALES_PAGOS` como pagado, categoriza `BANCOS_MOV`) nunca
     se había migrado a Postgres; seguía leyendo el Google Sheet, que ya no
     recibía escrituras desde que WF-01 migró — estuvo efectivamente
     desconectado desde que cerró esta fase. Migrado a `WF10_conciliacion_egresos_pg.json`,
     misma lógica de 3 niveles de confianza de la versión Sheets (misma OC
     hasta 7 días, mismo valor+remitente hasta 24h, mismo valor hasta 1h),
     probada contra el caso real de producción (OC 16101 ↔ comprobante de
     pago a Grupo Puma) antes de desplegar.
     - **Bug de clasificación encontrado de paso, también corregido:** WF-01
       nunca clasificaba un documento como `FACTURA` — una factura sin
       transferencia (tipo_documento=FACTURA del OCR) caía en la rama
       genérica de Contabilidad y quedaba como `COMPROBANTE_EGRESO` con
       `ESTADO=REVISAR`, indistinguible de un comprobante de pago real y
       nunca recogida como "soporte" por el motor de vinculación. Corregido
       en `Parsear resultado OCR`: ahora `CLASIFICACION='FACTURA'`,
       `ESTADO='ARCHIVO'` (igual que `ORDEN_COMPRA`), y el prompt de OCR
       pide extraer proveedor + número de OC/pedido referenciado también
       para facturas.
     - **Limitación conocida de WF10_pg:** el nivel de confianza más fuerte
       (misma OC, 7 días) solo vincula si el comprobante de pago trae el
       número de OC/ID de compra — ya sea porque el OCR lo lee directo del
       comprobante, o porque quien lo envía a Telegram lo escribe en el
       caption (ej. "OC 16101"), igual que ya se hace en el grupo Pagos. Un
       comprobante de transferencia bancaria normal casi nunca menciona la
       OC por sí solo — **para que la vinculación automática funcione de
       forma confiable, quien envía el comprobante a Contabilidad debe
       escribir el número de OC/ID en el mensaje.** Sin eso, el egreso
       igual se concilia contra el banco (no se pierde), pero no se vincula
       automáticamente con su factura/OC ni marca el proveedor como pagado
       — queda para revisión manual.
4. Editor de datos para contabilidad en Lovable (Supabase conectado manualmente
   vía `@supabase/supabase-js` con URL + anon key — el conector nativo OAuth de
   Lovable está roto). Conectados a datos reales: Comprobantes, Compras,
   Proveedores, Bancos, Catálogos, Transportes, Conciliación, Rentabilidad
   (`v_rentabilidad_compra`, % y $ COP separados por producto/transporte) y
   la mayoría de KPIs del dashboard. Pendiente: gráficos adicionales del
   dashboard y RLS por rol (hoy es "authenticated = acceso total").
5. Storage Drive → Dropbox.
6. Diferido: SIIGO Fase 4, WhatsApp Cloud API, agente conversacional Telegram.

## Otros sistemas MeUp (fuera del alcance de este repo, no tocar desde acá)

- Generador de Oferta Larga (`WF-OFERTA-LARGA`, `WF-GUARDAR-OFERTA`) — Sheet propio distinto
  a este.
- `WF-BOT-COTIZACIONES` — bot de precios de proveedores.
- Agente Frida (OpenClaw) — prospección de proveedores.
- Motor de precios / ficha técnica — skills propias de Claude, no viven aquí.
- **`inventario-meup`** — sistema de inventario, Supabase project propio
  (`mqgzsskdvdgvqjswxovm`, misma organización de Supabase que `meup-finanzas`
  pero proyecto distinto) + su propio Lovable. No fusionar en un monorepo con
  este repo ni conectar en vivo vía Supabase Wrappers/FDW para el día a día:
  acopla la disponibilidad de finanzas a la de inventario. Cuando se construya
  costeo (inventario ↔ financiero), el patrón a seguir es el mismo que
  `BANCOS_MOV.ORIGEN` (`EXTRACTO` vs `TRANSPORTE_APP`): un workflow n8n nuevo
  (candidato `WF-12`) que copia de solo lectura los campos necesarios
  (SKU, cantidad, costo promedio, bodega) hacia una tabla caché en
  `meup-finanzas` (ej. `inv_existencias_cache`), nunca escritura en sentido
  contrario. La vista/tabla de costeo hace el `JOIN` localmente contra esa
  caché, no contra el otro proyecto en tiempo real.
