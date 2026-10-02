# meup-finanzas

Sistema financiero automatizado de MeUp — repo de trabajo para la migración de
Google Sheets a Supabase/Postgres, la reorganización del storage de documentos
hacia Dropbox, y el dashboard/editor en Lovable.

Empieza por **`CLAUDE.md`** — contiene el contexto de negocio, las reglas críticas
y los 9 patrones anti-bug aprendidos en producción. Cualquier trabajo con Claude
Code, Opus u Codex sobre este repo debe partir de ahí.

## Contenido

- `CLAUDE.md` — contexto y reglas (leer primero)
- `docs/` — brief técnico, diccionario de datos, plan de fases, manual de n8n self-hosted
- `migrations/` — SQL versionado, aplicado al proyecto Supabase `meup-finanzas`
- `workflows/` — export JSON de los 11 workflows n8n vigentes (obsoletos aparte)

## Estado (2 oct 2026)

- ✅ Fase 0 — infraestructura (Supabase project, credenciales Dropbox, repo)
- ✅ Fase 1 — repo scaffold, docs y workflows versionados
- ✅ Fase 2 — schema Postgres aplicado en Supabase (`migrations/0001_schema_inicial.sql`)
- ✅ Fase 3 — WF-09 (compras Symphony), WF-04 (extractos bancarios), WF-01
  (comprobantes WhatsApp/Telegram), WF-02 (conciliación), WF-07 (solicitud
  transporte) y WF-08 (pago transportista) migrados a Postgres y en producción.
  Las versiones Sheets equivalentes quedaron desactivadas en n8n y archivadas
  en `workflows/obsoletos/`
- ⏳ Fase 4 — editor Lovable para contabilidad + dashboard: Comprobantes,
  Compras, Proveedores, Bancos, Catálogos, Transportes, Conciliación y
  Rentabilidad (`v_rentabilidad_compra`) ya conectados a datos reales; faltan
  gráficos avanzados y refinar RLS por rol
- ⏳ Fase 5 — storage Drive → Dropbox
- ⏸️ Fase 6 (diferido) — SIIGO Fase 4, WhatsApp Cloud API, agente conversacional
