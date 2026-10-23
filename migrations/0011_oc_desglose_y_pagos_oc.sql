-- 0011 — Desglose de la ORDEN DE COMPRA y pagos reales por OC (23 oct 2026)
--
-- Contexto (feedback de Milena): cada OC es independiente (un proveedor, un pedido) y trae su
-- desglose: subtotal + IVA - retenciones = total a pagar. Ese total es lo que realmente sale del
-- banco. Un mismo pedido puede pagarse en varios abonos (p.ej. 50% al iniciar producción).
-- El pago real se registra tanto desde el comprobante de Telegram como desde el extracto
-- (ambos son reales y verificables); si llegan los dos para el mismo pago, es UNA sola fila.
--
-- Rentabilidad: el costo de la compra sigue siendo el SUBTOTAL (valor_costo / oc_subtotal).
-- IVA y retenciones NO son costo: se guardan aparte y nunca entran a v_rentabilidad_compra.

-- 1) Lo que el OCR extrae de la OC
alter table comprobantes_wa
  add column if not exists ocr_subtotal      numeric(18,2),
  add column if not exists ocr_iva           numeric(18,2),
  add column if not exists ocr_rete_fuente   numeric(18,2),
  add column if not exists ocr_rete_ica      numeric(18,2),
  add column if not exists ocr_nit_proveedor text,
  add column if not exists oc_formato        text,   -- SYMPHONY (con desglose) | SIIGO (solo total)
  add column if not exists oc_version        text;

-- 2) La OC aplicada a la deuda con el proveedor (una fila de proveedores_locales_pagos = una OC)
alter table proveedores_locales_pagos
  add column if not exists oc_id_doc        text,
  add column if not exists oc_formato       text,
  add column if not exists oc_version       text,
  add column if not exists oc_subtotal      numeric(18,2),
  add column if not exists oc_iva           numeric(18,2),
  add column if not exists oc_rete_fuente   numeric(18,2),
  add column if not exists oc_rete_ica      numeric(18,2),
  add column if not exists oc_total_pagar   numeric(18,2),
  add column if not exists valor_pagado     numeric(18,2) not null default 0;

alter table proveedores_locales_pagos
  add column if not exists saldo_pagar numeric(18,2)
  generated always as (case when oc_total_pagar is null then null else oc_total_pagar - valor_pagado end) stored;

comment on column proveedores_locales_pagos.valor_costo is
  'Costo ESTIMADO sin IVA (viene de Symphony). Es el costo para rentabilidad.';
comment on column proveedores_locales_pagos.oc_total_pagar is
  'Total a pagar según la OC = subtotal + IVA - retenciones. Es el dinero que realmente sale del banco.';
comment on column proveedores_locales_pagos.valor_pagado is
  'Suma de pagos_oc de esta OC (pagos reales, por comprobante y/o extracto). Mantenido por trigger.';

-- 3) Un pago real a una OC (abono o pago final)
create table if not exists pagos_oc (
  id_pago       text primary key default ('PAGO-' || substr(md5(random()::text || clock_timestamp()::text), 1, 10)),
  id_control    text not null references proveedores_locales_pagos(id_control) on delete cascade,
  id_compra     text,
  nit_proveedor text,
  valor         numeric(18,2) not null,
  fecha_pago    date,
  fuente        text not null check (fuente in ('COMPROBANTE','EXTRACTO','AMBOS')),
  id_doc_wa     text references comprobantes_wa(id_doc),
  id_mov_banco  text references bancos_mov(id_mov),
  human_review  text not null default 'PENDIENTE',
  notas         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
-- un comprobante y un movimiento bancario solo pueden respaldar UN pago (evita contarlo dos veces)
create unique index if not exists uq_pagos_oc_doc on pagos_oc(id_doc_wa)    where id_doc_wa    is not null;
create unique index if not exists uq_pagos_oc_mov on pagos_oc(id_mov_banco) where id_mov_banco is not null;
create index if not exists idx_pagos_oc_control on pagos_oc(id_control);

create trigger trg_pagos_oc_upd before update on pagos_oc
  for each row execute function set_updated_at();

alter table pagos_oc enable row level security;
create policy pagos_oc_authenticated_all on pagos_oc for all to authenticated using (true) with check (true);

-- 4) Recalcular valor_pagado y estado de una OC (PENDIENTE / ABONADO / PAGADO)
create or replace function recalcular_pago_oc(p_control text) returns void
language plpgsql set search_path = public as $$
declare v_pag numeric;
begin
  select coalesce(sum(valor), 0) into v_pag from pagos_oc where id_control = p_control;
  update proveedores_locales_pagos p set
    valor_pagado = v_pag,
    estado_pago = case
      when v_pag <= 0 then 'PENDIENTE'
      when v_pag >= coalesce(p.oc_total_pagar, p.valor_costo) - 1 then 'PAGADO'
      else 'ABONADO' end,
    fecha_pago = coalesce((select max(fecha_pago) from pagos_oc where id_control = p_control), p.fecha_pago)
  where p.id_control = p_control;
end $$;

create or replace function trg_pagos_oc_recalcular() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op in ('UPDATE','DELETE') then perform recalcular_pago_oc(old.id_control); end if;
  if tg_op in ('INSERT','UPDATE') then perform recalcular_pago_oc(new.id_control); end if;
  return null;
end $$;

create trigger trg_pagos_oc_recalc after insert or update or delete on pagos_oc
  for each row execute function trg_pagos_oc_recalcular();
