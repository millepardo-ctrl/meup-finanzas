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
1. Repo scaffold + docs + workflows versionados — en curso (este commit).
2. Schema Postgres en Supabase — hecho (`migrations/0001_schema_inicial.sql`).
3. Migrar workflows de nodos Sheets → Postgres, empezando por `COMPRAS_DETALLE`,
   `BANCOS_MOV`, `COMPROBANTES_WA` — siguiente paso.
4. Editor de datos para contabilidad en Lovable (grilla tipo Excel sobre Supabase) + dashboard.
5. Storage Drive → Dropbox.
6. Diferido: SIIGO Fase 4, WhatsApp Cloud API, agente conversacional Telegram.

## Otros sistemas MeUp (fuera del alcance de este repo, no tocar desde acá)

- Generador de Oferta Larga (`WF-OFERTA-LARGA`, `WF-GUARDAR-OFERTA`) — Sheet propio distinto
  a este.
- `WF-BOT-COTIZACIONES` — bot de precios de proveedores.
- Agente Frida (OpenClaw) — prospección de proveedores.
- Motor de precios / ficha técnica — skills propias de Claude, no viven aquí.
