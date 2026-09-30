-- =========================================================
-- MEUP FINANZAS · Schema inicial (migrado desde Google Sheets)
-- Aplicado a Supabase project: wzlmaylzwdewqppkmdnn
-- Fuente: docs/REFERENCIA_SISTEMA_FINANCIERO_MEUP.md v1.1
-- =========================================================

create extension if not exists pgcrypto;

create or replace function set_updated_at() returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- CATÁLOGOS ----------

create table config (
  parametro   text primary key,
  valor       text not null,
  notas       text,
  updated_at  timestamptz not null default now()
);

create table cat_bancos (
  codigo       text primary key,
  banco        text not null,
  tipo_cuenta  text,
  numero       text,
  moneda       text not null default 'COP',
  codigo_puc   text,
  activa       boolean not null default true,
  notas        text,
  created_at   timestamptz not null default now()
);

create table cat_terceros (
  nit          text primary key,
  nombre       text not null,
  tipo         text,
  ciudad       text,
  notas        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_cat_terceros_upd before update on cat_terceros
  for each row execute function set_updated_at();

-- ---------- IMPORTACIONES ----------

create table importaciones (
  id_import        text primary key,
  proveedor        text,
  invoice_num      text,
  moneda           text default 'USD',
  valor_invoice    numeric(18,2),
  factura_invoice  text,
  dim_num          text,
  trm_dim          numeric(12,4),
  bl_num           text,
  fecha_bl         date,
  agente_aduanas   text,
  fact_agente_num  text,
  fact_agente_cop  numeric(18,2),
  naviera_fact_num text,
  naviera_fact_cop numeric(18,2),
  iva_dim_cop      numeric(18,2),
  fecha_llegada    date,
  estado           text not null default 'ABIERTA',
  notas            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger trg_importaciones_upd before update on importaciones
  for each row execute function set_updated_at();

create table importaciones_pagos (
  id_pago          text primary key,
  id_import        text not null references importaciones(id_import) on delete cascade,
  tipo_pago        text not null,
  fecha            date not null,
  moneda           text not null default 'USD',
  valor            numeric(18,2) not null,
  trm_pago         numeric(12,4),
  valor_cop        numeric(18,2),
  cuenta_origen    text,
  comprobante_siigo text,
  notas            text,
  created_at       timestamptz not null default now()
);
create index idx_import_pagos_id_import on importaciones_pagos(id_import);

create view v_importaciones_saldo with (security_invoker = true) as
select i.*,
       i.valor_invoice - coalesce((
         select sum(p.valor) from importaciones_pagos p
         where p.id_import = i.id_import and p.tipo_pago = 'INVOICE'
       ), 0) as saldo_pend_usd
from importaciones i;

-- ---------- CRÉDITOS E INTERESES ----------

create table creditos (
  id_credito           text primary key,
  banco                text not null,
  numero_credito       text not null,
  fecha_desembolso     date,
  moneda               text default 'COP',
  valor_usd            numeric(18,2),
  valor_cop            numeric(18,2),
  tasa                 numeric(8,4),
  proveedor_destino    text,
  fecha_llegada_mcia   date,
  estado               text not null default 'VIGENTE',
  fecha_cancelacion    date,
  notas                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create unique index idx_creditos_numero on creditos(numero_credito);
create trigger trg_creditos_upd before update on creditos
  for each row execute function set_updated_at();

create table intereses (
  id               bigint generated always as identity primary key,
  fecha            date not null,
  comprobante      text,
  codigo_contable  text,
  cuenta_contable  text,
  nit_tercero      text,
  tercero          text,
  numero_credito   text references creditos(numero_credito),
  descripcion      text,
  debito           numeric(18,2) default 0,
  credito          numeric(18,2) default 0,
  created_at       timestamptz not null default now()
);
create index idx_intereses_numero_credito on intereses(numero_credito);

create view v_creditos_con_intereses with (security_invoker = true) as
select c.*,
       coalesce((select sum(i.debito) from intereses i where i.numero_credito = c.numero_credito), 0) as intereses_acum
from creditos c;

-- ---------- BANCOS ----------

create table bancos_mov (
  id_mov            text primary key,
  fecha             date not null,
  cuenta            text references cat_bancos(codigo),
  descripcion       text,
  referencia        text,
  moneda            text default 'COP',
  valor             numeric(18,2) not null,
  tipo              text not null,
  categoria         text,
  detalle           text,
  comprobante_siigo text,
  factura_oc        text,
  tercero           text,
  id_conciliacion   text,
  estado_contable   text default 'PENDIENTE',
  origen            text not null default 'EXTRACTO',
  human_review      text not null default 'PENDIENTE',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index idx_bancos_mov_fecha on bancos_mov(fecha);
create index idx_bancos_mov_cuenta on bancos_mov(cuenta);
create index idx_bancos_mov_estado on bancos_mov(estado_contable);
create trigger trg_bancos_mov_upd before update on bancos_mov
  for each row execute function set_updated_at();

-- ---------- COMPROBANTES WHATSAPP/TELEGRAM ----------

create table comprobantes_wa (
  id_doc            text primary key,
  fecha_recibido    timestamptz not null default now(),
  remitente_wa      text,
  nombre_contacto   text,
  tipo_archivo      text,
  url_drive         text,
  ocr_estado        text,
  ocr_fecha_pago    date,
  ocr_valor         numeric(18,2),
  ocr_banco_origen  text,
  ocr_banco_destino text,
  ocr_referencia    text,
  ocr_cliente       text,
  ocr_confianza     numeric(5,2),
  clasificacion     text,
  id_mov_match      text references bancos_mov(id_mov),
  estado            text not null default 'RECIBIDO',
  recibo_siigo      text,
  notas             text,
  human_review      text not null default 'PENDIENTE',
  id_compra_informado text,
  grupo_origen      text,
  categoria_gasto   text,
  oc_num            text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index idx_comprobantes_estado on comprobantes_wa(estado);
create index idx_comprobantes_fecha on comprobantes_wa(fecha_recibido);
create trigger trg_comprobantes_upd before update on comprobantes_wa
  for each row execute function set_updated_at();

-- ---------- SYMPHONY: COMPRAS ----------

create table compras_symphony (
  id_compra               text primary key,
  fecha                   date,
  cliente                 text,
  documento               text,
  centro_costo            text,
  vendedor                text,
  estado_symphony         text,
  gestion                 text,
  valor_venta             numeric(18,2),
  valor_domicilio_cobrado numeric(18,2),
  costo_transporte_symphony numeric(18,2),
  costo_transporte_real   numeric(18,2),
  tipo_origen             text,
  total_compra            numeric(18,2),
  transportista_symphony  text,
  origen                  text,
  destino                 text,
  human_review            text not null default 'PENDIENTE',
  notas                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create trigger trg_compras_symphony_upd before update on compras_symphony
  for each row execute function set_updated_at();

create table compras_detalle (
  id               bigint generated always as identity primary key,
  id_compra        text not null references compras_symphony(id_compra) on delete cascade,
  cod_producto     text,
  producto         text,
  info             text,
  cantidad         numeric(14,2),
  costo_total      numeric(18,2),
  venta_total      numeric(18,2),
  nit_proveedor    text,
  tipo_proveedor   text,
  retencion_desc   text,
  human_review     text not null default 'PENDIENTE',
  created_at       timestamptz not null default now()
);
create index idx_compras_detalle_id_compra on compras_detalle(id_compra);

create table proveedores_locales_pagos (
  id_control        text primary key,
  id_compra         text not null references compras_symphony(id_compra),
  nit_proveedor     text references cat_terceros(nit),
  proveedor_nombre  text,
  valor_costo       numeric(18,2),
  estado_pago       text not null default 'PENDIENTE',
  fecha_pago        date,
  cuenta_origen     text,
  comprobante_siigo text,
  id_mov_banco      text references bancos_mov(id_mov),
  human_review      text not null default 'PENDIENTE',
  notas             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index idx_plp_id_compra on proveedores_locales_pagos(id_compra);
create trigger trg_plp_upd before update on proveedores_locales_pagos
  for each row execute function set_updated_at();

-- ---------- TRANSPORTES ----------

create table transportes_solicitudes (
  id_solicitud       text primary key,
  fecha_solicitud    timestamptz not null default now(),
  solicitado_por_wa  text,
  id_compra          text references compras_symphony(id_compra),
  cuenta_cobro       text,
  remision           text,
  transportista      text,
  cedula             text,
  telefono           text,
  medio_pago         text,
  valor_solicitado   numeric(18,2) not null,
  estado             text not null default 'PENDIENTE',
  retefuente_aplica  boolean not null default false,
  url_mensaje_origen text,
  notas              text,
  human_review       text not null default 'PENDIENTE',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_ts_id_compra on transportes_solicitudes(id_compra);
create index idx_ts_estado on transportes_solicitudes(estado);
create trigger trg_ts_upd before update on transportes_solicitudes
  for each row execute function set_updated_at();

create table transportes_pagos (
  id_pago            text primary key,
  id_solicitud       text references transportes_solicitudes(id_solicitud),
  id_compra          text references compras_symphony(id_compra),
  transportista      text,
  cedula             text,
  tipo               text not null default 'TOTAL',
  valor              numeric(18,2) not null,
  fecha_pago         date,
  medio_pago         text,
  cuenta_origen      text,
  url_comprobante    text,
  estado             text not null default 'PENDIENTE',
  id_doc_wa          text references comprobantes_wa(id_doc),
  id_mov_banco       text references bancos_mov(id_mov),
  comprobante_siigo  text,
  duplicado_de       text references transportes_pagos(id_pago),
  notas              text,
  human_review       text not null default 'PENDIENTE',
  retencion          numeric(18,2) not null default 0,
  pago_neto          numeric(18,2),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_tp_id_solicitud on transportes_pagos(id_solicitud);
create index idx_tp_id_compra on transportes_pagos(id_compra);
create trigger trg_tp_upd before update on transportes_pagos
  for each row execute function set_updated_at();

create view v_compras_symphony_calc with (security_invoker = true) as
select cs.*,
       coalesce((
         select sum(tp.valor) from transportes_pagos tp
         where tp.id_compra = cs.id_compra and tp.estado = 'PAGADO'
       ), 0) as costo_transporte_pagado
from compras_symphony cs;

-- ---------- CONCILIACIÓN Y RECIBOS ----------

create table conciliacion (
  id_conc            text primary key,
  fecha              date not null default current_date,
  id_doc_wa          text references comprobantes_wa(id_doc),
  id_mov_banco       text references bancos_mov(id_mov),
  valor_comprobante  numeric(18,2),
  valor_banco        numeric(18,2),
  diferencia         numeric(18,2),
  metodo_match       text,
  estado             text not null default 'CONCILIADO',
  revisado_por       text,
  notas              text,
  human_review       text not null default 'PENDIENTE',
  created_at         timestamptz not null default now()
);
create index idx_conciliacion_doc on conciliacion(id_doc_wa);
create index idx_conciliacion_mov on conciliacion(id_mov_banco);

create table recibos_caja (
  id               bigint generated always as identity primary key,
  fecha            date not null default current_date,
  id_doc_venta     text,
  valor            numeric(18,2),
  cliente          text,
  nit              text,
  cuenta_destino   text,
  recibo_siigo     text,
  id_doc_wa        text references comprobantes_wa(id_doc),
  asesor           text,
  created_at       timestamptz not null default now()
);

-- ---------- RLS ----------
-- Política temporal: cualquier usuario autenticado tiene acceso total.
-- Se refina por rol (contabilidad / logística / lectura) en la Fase 4.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t || '_authenticated_all', t
    );
  end loop;
end $$;
