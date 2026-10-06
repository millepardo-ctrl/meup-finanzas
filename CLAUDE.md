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
10. **Un nodo sin `executeOnce: true` se ejecuta una vez POR CADA item que reciba del
    nodo anterior**, incluso si su lógica no depende de ese item (una descarga de un
    archivo fijo, un SELECT sin parámetros). Si ese nodo está encadenado después de un
    nodo con muchos items, el resultado se multiplica en cascada: un nodo de descarga
    con 111 items de entrada produce 111 descargas del mismo archivo; el siguiente nodo
    que lea esos binarios corre 111 veces más; un lookup a Postgres más adelante corre
    aún más veces. Encontrado en producción en WF-04 (5 oct 2026): `Descargar archivo
    (plano)` encadenado después de `Leer CSV/XLSX` (111 items) se ejecutó 111 veces,
    `Leer sin encabezado (plano)` terminó con 12.432 items (111×~112), y `Leer
    CAT_BANCOS` con 74.592 (12.432×6) — la explosión de datos duplicados corrompía la
    detección de formato en el Code node siguiente, y de paso machacaba Supabase con
    miles de consultas repetidas. **Regla:** cualquier nodo que descargue/consulte algo
    que NO varía por item (un archivo fijo, una tabla de catálogo sin filtro por fila)
    debe marcarse `executeOnce: true`, sin importar cuántos items traiga el nodo
    anterior en la cadena.

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
     - **Rediseñado (3 oct 2026) tras feedback de Milena:** un comprobante de
       transferencia normal no trae el ID de la compra (eso fue una
       suposición incorrecta de la primera versión) — lo único estable que
       trae es la **cuenta de destino**. Rediseño: `cat_terceros` ganó una
       columna `cuenta_bancaria` (migración 0010), y el prompt de OCR de
       WF-01 ahora extrae `cuenta_destino` del comprobante
       (`comprobantes_wa.ocr_cuenta_destino`). WF10_pg identifica al tercero
       buscando esa cuenta en `cat_terceros` ANTES de intentar nada por OC:
       - `tipo='PROVEEDOR_LOCAL'` → resuelve el NIT y busca, entre las
         deudas pendientes de ESE proveedor en `PROVEEDORES_LOCALES_PAGOS`,
         la que coincide en valor (exacta = `PAGADO`, menor = `ABONADO`
         parcial, única deuda pendiente = se asume aunque el valor no calce
         exacto). El número de OC/ID explícito en el comprobante (si acaso
         llega) sigue teniendo prioridad cuando está presente.
       - `tipo='COLABORADOR'` (nómina) → no hay cuenta por cobrar que
         marcar, solo categoriza el movimiento como `NOMINA` con el nombre
         del colaborador como tercero.
       - Si la cuenta no está en el catálogo (o el comprobante no tiene
         cuenta reconocible) el egreso **igual se concilia contra el banco**
         — nunca se bloquea — solo queda sin proveedor/colaborador
         vinculado, para revisión manual. Este es el caso normal de gastos
         de logística/domicilios que se pagan a diario sin que la factura
         haya llegado todavía: quedan categorizados y conciliados, sin
         necesitar ningún soporte.
       - La vinculación factura/OC ↔ comprobante (3 niveles) ahora también
         usa "mismo proveedor vía cuenta" como segundo nivel de confianza
         (entre "misma OC explícita" y "mismo remitente+valor 24h").
     - **Pendiente de Milena:** cargar `cat_terceros.cuenta_bancaria` para
       los proveedores y colaboradores de nómina que se quiera que el
       sistema reconozca automáticamente (vía Lovable o pidiéndomelo a mí
       con la lista). Sin esos datos cargados, el sistema sigue funcionando
       pero sin la vinculación automática — como hasta ahora.
     - **Bug de datos encontrado y corregido (3 oct 2026):** las 22 filas de
       `PROVEEDORES_LOCALES_PAGOS` tenían `proveedor_nombre` en null —
       el INSERT de WF-09 nunca llenaba esa columna (el nombre real vive en
       `cat_terceros.nombre` vía `nit_proveedor`, pero la columna
       denormalizada quedaba vacía, lo que podía mostrar proveedores sin
       nombre en cualquier vista de Lovable que lea `proveedor_nombre`
       directo sin hacer el join). Corregido en el nodo
       `Upsert PROVEEDORES_LOCALES_PAGOS` de `WF09_carga_compras_symphony_pg.json`:
       ahora el INSERT y el UPDATE del upsert sacan el nombre con un
       subselect a `cat_terceros` por NIT, así que queda sincronizado
       automáticamente incluso si el nombre en el catálogo cambia después.
       Las 22 filas existentes se corrigieron con un backfill directo en
       Supabase. **Pendiente de Milena: reimportar WF-09 en n8n** para que
       las compras nuevas de Symphony traigan el nombre desde ya.
     - **Verificación pendiente (bloqueada por datos, no por código):**
       intenté correr en vivo el caso real OC 16101 / Grupo Puma y encontré
       que `BANCOS_MOV` no tiene movimientos más recientes al 6 jul 2026
       (WF-04 necesita un extracto nuevo) y que la compra 16101 no existe
       todavía en `COMPRAS_DETALLE` (pendiente de sync de Symphony/WF-09).
       Ninguno de los dos es un bug de esta migración — son datos de origen
       que faltan por cargar. La lógica del motor de WF-10 (identificación
       por cuenta, 3 niveles de confianza, nómina, gasto sin soporte) se
       validó de forma aislada con un script de prueba (4 escenarios,
       todos correctos) mientras se consigue data real para probar en vivo.
     - **Ajuste a WF-04 (5 oct 2026):** el extracto de Bancolombia de la cuenta
       762 llega como CSV **sin encabezado** y con cualquier nombre de archivo
       (10 columnas fijas: cuenta_raw, oficina, _, fecha `AAAAMMDD`, _, valor,
       código de operación, descripción, estado, _). El normalizador de
       siempre asume encabezado real + nombre de archivo con el código de
       cuenta, así que con este formato no producía ningún movimiento.
       Se agregó un segundo modo al nodo `Normalizar a esquema BANCOS_MOV`:
       detecta este layout leyendo el CSV crudo directo del binario
       descargado (nunca vía `Leer CSV/XLSX` para este caso — ese nodo trata
       la fila 1 como encabezado y, como varias columnas de este extracto
       vienen vacías, los nombres de columna que generaría colisionan entre
       sí y se pierde información), resuelve la cuenta buscando la columna 1
       en el nuevo `cat_bancos.numero` (nuevo nodo `Leer CAT_BANCOS`, no
       requiere renombrar el archivo), y parsea la fecha `AAAAMMDD`
       explícitamente. Se cargó `cat_bancos.numero = '602-460337-62'` para
       `BC-CTE-3762`. De paso se corrigió que "PAGO A NOMIN <nombre
       truncado>" no se reconocía como `NOMINA` (el truncamiento del
       extracto le come la última A a "NOMINA").
       **Falló en el primer intento en producción (5 oct 2026), corregido:**
       la primera versión intentaba leer el binario descargado a mano
       (base64) desde el Code node para detectar y parsear el formato sin
       encabezado. En esta instancia n8n guarda los binarios en filesystem
       (no en memoria), así que esa lectura directa venía vacía y el flujo
       caía siempre a la rama vieja (busca el código de cuenta en el
       nombre del archivo) — de ahí el error real
       ("El nombre del archivo debe incluir...") que reportó Milena al
       reimportar. Corregido reemplazando esa lectura manual por un
       segundo nodo dedicado (`Descargar archivo (plano)` +
       `Leer CSV sin encabezado (plano)`, extractFromFile con
       `headerRow: false` sobre una segunda descarga del mismo archivo):
       n8n ya sabe leer el binario sin importar dónde lo tenga guardado, y
       con `headerRow: false` entrega cada fila con claves posicionales
       "0".."9" sin inventar nombres de columna — evita también la
       colisión de columnas vacías que tendría reconstruir la fila
       "escondida" de `Leer CSV/XLSX`. Vuelto a probar contra el archivo
       real: 402/402 filas coinciden.
       **Falló por segunda vez en producción (5 oct 2026), corregido:** el
       nuevo nodo `Descargar archivo (plano)` dio 404 ("The resource you
       are requesting could not be found"). Copié `fileId.value = {{
       $json.id }}` del nodo `Descargar archivo` original sin ajustarlo —
       en su nueva posición (después de `Leer CSV/XLSX`) `$json` ya no es
       el archivo de Drive sino una fila de datos ya extraída, así que el
       ID de descarga quedaba vacío/incorrecto. Corregido apuntando
       explícitamente al nodo del trigger:
       `{{ $('Nuevo extracto en Drive (carpeta EXTRACTOS_ENTRADA)').first().json.id }}`.
       **Lección general (no estaba en la lista de patrones anti-bug):**
       una vez que un flujo pasa por otros nodos, `$json` "a secas" ya no
       es confiable para volver a referenciar el ítem original — hay que
       nombrar el nodo explícitamente con `$('NodoOrigen')`, igual que ya
       aplica el patrón anti-bug #9 para datos que pasan por un nodo
       Postgres de escritura.
       **Falló por tercera vez en producción (5 oct 2026), corregido:**
       con el fileId ya corregido, el nodo `Leer CSV sin encabezado
       (plano)` rechazó el archivo: "The file selected in 'Input Binary
       Field' is not in csv format". La captura de pantalla que envió
       Milena confirmó la causa real: el archivo que llega a Drive es un
       **.xlsx binario genuino** (`File Extension: xlsx`, mime
       `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`),
       no un CSV de texto — el ejemplo que Milena había pegado en el chat
       al principio era una vista/exportación en texto de ese contenido,
       no representativa del tipo de archivo real guardado en Drive. Yo
       había forzado `operation: "csv"` en ese nodo, lo cual hace que el
       parser CSV de n8n rechace cualquier binario que no sea texto CSV
       real. Corregido quitando esa operación explícita (queda solo
       `headerRow: false`), para que el nodo use el mismo autodetect que
       ya usa con éxito `Leer CSV/XLSX` sobre este mismo archivo real —
       la única diferencia es que ya no consume la primera fila como
       encabezado. Nodo renombrado de `Leer CSV sin encabezado (plano)` a
       `Leer sin encabezado (plano)` (deja de ser CSV-específico) en los
       tres lugares donde aparecía (nombre del nodo, `connections`, y la
       referencia `$('...')` dentro del Code node). Vuelto a probar en
       local: 402/402 filas, `NOMINA` (3) y `REINTEGRO_PROVEEDOR` (13)
       correctos.
       **Falló por cuarta vez en producción (5 oct 2026), corregido:**
       sin el error de "not in csv format", pero reapareció el mismo
       error de las primeras dos fallas ("El nombre del archivo debe
       incluir..."). Causa: al quitar la operación explícita, el nodo
       quedó en modo autodetect, que para este archivo sigue tomando la
       fila 1 como encabezado real (con los valores de esa fila como
       nombres de columna) sin respetar `headerRow:false` — confirmado
       en una captura de Milena del panel de salida del nodo, donde las
       "claves" eran valores de datos en vez de `"0".."9"`. n8n expone
       una operación `xlsx` específica (distinta de `xls` y de `csv`),
       con su propio soporte de `headerRow`. Como el archivo real sí es
       xlsx, fijar `operation: "xlsx"` no lo rechaza (a diferencia de
       forzar `"csv"`) y sí aplica `headerRow:false` correctamente.
       **Falló por quinta vez en producción (5 oct 2026), corregido:**
       mismo error de siempre, pero la captura del canvas reveló la
       causa real (ver patrón anti-bug #10): sin `executeOnce`,
       `Descargar archivo (plano)` corría una vez por cada uno de los
       111 items que entregaba `Leer CSV/XLSX`, y `Leer CAT_BANCOS`
       heredaba la misma multiplicación — la cadena terminaba con
       12.432 items en `Leer sin encabezado (plano)` y 74.592 en `Leer
       CAT_BANCOS`, en vez de ~112 y 6. Esa explosión de datos
       duplicados corrompía la detección de formato en el Code node.
       Corregido marcando `executeOnce: true` en ambos nodos (ninguno
       depende del item que recibe: uno descarga siempre el mismo
       archivo, el otro hace un SELECT sin filtro por fila).
       **Falló por sexta vez en producción (5 oct 2026), corregido:** con
       `executeOnce` aplicado, la captura de Milena confirmó que los
       conteos de items ya quedaron correctos (`Leer sin encabezado
       (plano)`: 112, `Leer CAT_BANCOS`: 6 — la explosión quedó resuelta),
       pero el mismo error de "nombre de archivo" persistió. Eso descarta
       la explosión de items como causa restante: el esquema de claves
       que entrega n8n para este nodo (`operation: "xlsx"`,
       `headerRow:false`) simplemente no es `"0".."9"` como asumí
       (probablemente usa otro esquema interno, p.ej. letras de columna).
       En vez de seguir adivinando el nombre exacto de clave contra
       producción, `col()` ahora cae a lectura posicional real vía
       `Object.values(row)[idx]` cuando no encuentra la clave numérica
       esperada — el orden de propiedades de un objeto en JS sigue el
       orden de inserción (el orden real de columnas del archivo), así
       que funciona sin importar qué nombre de clave use n8n
       internamente. Probado localmente simulando tanto claves `"0".."9"`
       como claves tipo letra (A, B, C...): 402/402 filas en ambos casos.
       **Falló por séptima vez en producción (5 oct 2026), MISMO mensaje
       exacto de error, incluso con los conteos de items ya correctos
       (112/6, confirmado por Milena).** Un error idéntico letra por
       letra después de dos fixes de código distintos (executeOnce +
       col() posicional) ya no es informativo por sí solo — no hay forma
       de saber desde aquí si el código se reimportó de verdad con cada
       fix o si el problema real es otro. En vez de seguir iterando a
       ciegas sobre captura tras captura, se cambió el enfoque: si `Leer
       sin encabezado (plano)` SÍ trae filas pero ninguna calza con el
       patrón esperado (fecha AAAAMMDD en posición 3, valor numérico en
       posición 5), ahora se lanza un error de **diagnóstico explícito**
       que muestra las claves y valores reales de la primera fila, en
       vez de caer en silencio a la rama de Formato A (que da el mensaje
       engañoso de "nombre de archivo" sin importar la causa real).
       **Pendiente de Milena: reimportar WF-04 una vez más (séptimo fix)
       y volver a probar.** Si el error sigue siendo sobre "nombre de
       archivo" después de esto, es señal de que el reimport no está
       tomando el cambio (revisar que WF-04 se reemplace por completo,
       no se fusione con la versión anterior); si cambia al mensaje de
       "DIAGNOSTICO formato plano: ...", esa salida da la respuesta
       definitiva de una sola vez.
       **Causa real confirmada (5 oct 2026):** el mensaje de diagnóstico
       dio la respuesta exacta en el primer intento. Forma real de cada
       fila que entrega `extractFromFile` con `operation: "xlsx"` +
       `headerRow:false` en esta versión de n8n (2.31.5):
       `{ row: ["602-460337-62", 787, " ", 20261005, " ", 13992700, 301,
       " CONSIGNACION EN EFECTIVO", 0] }` — un único campo llamado
       **`row`** cuyo valor es un array con las celdas en orden. No es
       `"0".."9"` ni letras de columna (las dos hipótesis de los
       intentos anteriores). Por eso el fallback `Object.values(row)[idx]`
       tampoco servía: `Object.values({row: [...]})` da `[[...]]` — un
       array de un solo elemento que ES el array completo — así que
       cualquier `idx > 0` daba `undefined`. **Corregido (octavo intento):**
       `col()` ahora revisa primero `row.row[idx]` (el caso real
       confirmado), con los fallbacks anteriores detrás por compatibilidad
       si el esquema cambia en otra versión de n8n. Probado localmente
       con la fila exacta del error de diagnóstico, con el archivo
       completo (402/402, `REINTEGRO_PROVEEDOR` 13, `NOMINA` 3) y con los
       esquemas simulados de los intentos previos — todos siguen pasando.
       **Pendiente de Milena: reimportar WF-04 una vez más (octavo fix,
       con causa ya confirmada) y probar con el archivo real.**
       Los formatos con
       encabezado real (otros bancos) siguen funcionando igual que antes, sin
       ningún cambio. Si BC-AHO-8985 o BC-PAN-USD (también Bancolombia)
       llegan en este mismo formato plano, falta registrar su respectivo
       `cat_bancos.numero` — en cuanto llegue el primer archivo de cada una
       lo reviso y lo cargo igual que con la 762.
       **Confirmado por Milena (5 oct 2026):** las filas "PAGO DE PROV
       `<nombre>`" con valor **positivo** son reintegros/ajustes de un
       proveedor (envío fallido, cancelación de pedido, etc.), no un pago
       saliente. Agregada la regla en `clasificar()`:
       `PAGO DE PROV` + valor > 0 → `INGRESO / REINTEGRO_PROVEEDOR`.
       **WF-04 idempotente (6 oct 2026):** el extracto se sube con un día de
       retraso y puede traer días ya cargados. El Code node asigna a cada
       fila una `ocurrencia` (1ª, 2ª… vez que aparece la misma combinación
       cuenta|fecha|valor|referencia|descripcion dentro del archivo) y el
       INSERT solo inserta si en `bancos_mov` (origen EXTRACTO) hay menos
       filas con esa clave natural que `ocurrencia`. Así re-subir días
       solapados no duplica, y dos movimientos legítimamente idénticos el
       mismo día sí se conservan. Los `id_mov` heredados no cambian (otras
       tablas tienen FK a ellos). El INSERT usa `returning id_mov` y
       `Finalizar carga` informa "N nuevos (M ya estaban cargados)".
       Los 2 pares de movimientos aparentemente duplicados: vienen del
       mismo archivo, probablemente reales (Milena confirmando) — no borrar.
       **WF-10 espera en silencio (6 oct 2026):** el comprobante llega por
       Telegram al instante, el extracto un día después. Un comprobante sin
       movimiento candidato permanece `PROCESADO` y NO alerta hasta que
       (a) el último extracto cargado (max fecha de `origen='EXTRACTO'`,
       todas las cuentas) cubra su fecha + `GRACIA_DIAS=1`, o (b) pasen
       `ESPERA_MAX_H=72` h desde que se recibió (red de seguridad: ¿falta
       subir el extracto?). Sin fecha legible alerta de una vez. Ya en
       `SIN_MATCH` no repite alerta; `AMBIGUO` alerta de inmediato. Filas
       `TRANSPORTE_APP` no cuentan para la cobertura.
       WF-04 y WF-10 ya reimportados por Milena (6 oct 2026). Confirmó que los
       2 pares de movimientos "duplicados" del extracto SON reales (mismo día,
       mismo valor, dos veces) — la carga idempotente los conserva.
       **Cuentas de terceros cargadas (6 oct 2026)** desde
       `Plantilla_Cuentas_Terceros_MeUp.xlsx` a `cat_terceros.cuenta_bancaria`
       (solo dígitos, tal cual venían): 24 proveedores existentes (21 con
       cuenta), 11 terceros nuevos con `tipo='PROVEEDOR_SERVICIOS'`
       (logística, navieras, seguros, domicilios; 6 con cuenta, el resto paga
       por PSE/sin cuenta) y 23 colaboradores con `tipo='COLABORADOR'`
       (nit = cédula; 20 con cuenta). WF-10 ahora compara cuentas ignorando
       ceros a la izquierda (`normCta`), porque Excel los pierde en cuentas
       Bancolombia de 10 dígitos (p.ej. Seal Line, Transmovilizar, HJ).
       **Pendiente de Milena:** (1) reimportar WF-10 por el cambio `normCta`;
       (2) `31864726235` aparece para dos colaboradores (Yair Zuleta y Sami
       Pardo) — se dejó SIN cuenta en ambos hasta que confirme cuál es;
       (3) la cuenta Nequi `3022684188` de Ingrid Pardo es idéntica al
       teléfono de Compañía Nacional de Minerales — no se cargó (solo su
       BBVA), confirmar si es correcta; (4) Inducargo/Marmobi/Piedras y Arte
       sin cuenta (pagos esporádicos por Nequi).
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
