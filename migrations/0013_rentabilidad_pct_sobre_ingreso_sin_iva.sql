-- 0013 — Rentabilidad en % sobre el ingreso ANTES de IVA, por separado (producto / transporte) y total.
-- Antes: rentabilidad_pct = rentabilidad_total / total_compra, y total_compra incluye IVA (19 % del producto),
-- así que el % salía más bajo que el real. Symphony calcula "% Producto" sobre ValorVenta (sin IVA); esto
-- iguala ese criterio y agrega el % de transporte y el total.
--   rentabilidad_producto_pct    = rentabilidad_producto   / ingreso_producto
--   rentabilidad_transporte_pct  = rentabilidad_transporte / ingreso_transporte  (null si no se cobró domicilio)
--   rentabilidad_pct (total)     = rentabilidad_total      / (ingreso_producto + ingreso_transporte)
-- Costo = subtotal sin IVA; IVA descontable, retefuente y ICA no son costo (confirmado por Milena, 25 oct 2026).
-- Las columnas existentes conservan nombre y posición (Lovable las lee); las nuevas van al final.

create or replace view v_rentabilidad_compra as
with costo_producto_por_nit as (
  select
    cd.id_compra,
    cd.nit_proveedor,
    bool_or(cd.nit_proveedor = '900570024') as es_importado,
    sum(cd.venta_total) as venta_grupo,
    sum(cd.costo_total) as costo_symphony_grupo,
    (select sum(plp.valor_costo) from proveedores_locales_pagos plp
      where plp.id_compra = cd.id_compra and plp.nit_proveedor = cd.nit_proveedor) as costo_real_grupo
  from compras_detalle cd
  where cd.nit_proveedor is not null
  group by cd.id_compra, cd.nit_proveedor
),
producto_agg as (
  select
    id_compra,
    sum(venta_grupo) as ingreso_producto,
    sum(coalesce(costo_real_grupo, costo_symphony_grupo)) as costo_producto,
    bool_or(costo_real_grupo is not null) as producto_tiene_costo_real
  from costo_producto_por_nit
  group by id_compra
),
transporte_agg as (
  select
    cs_1.id_compra,
    coalesce(cs_1.valor_domicilio_cobrado, 0) as ingreso_transporte,
    calc.costo_transporte_pagado > 0 as transporte_costo_es_real,
    coalesce(cs_1.valor_domicilio_cobrado, 0) > 0
      and not calc.costo_transporte_pagado > 0
      and not coalesce(cs_1.costo_transporte_symphony, 0) > 0 as transporte_sin_dato,
    case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
         else coalesce(cs_1.costo_transporte_symphony, 0) end as costo_transporte_calc
  from compras_symphony cs_1
  left join v_compras_symphony_calc calc on calc.id_compra = cs_1.id_compra
)
select
  cs.id_compra,
  cs.fecha,
  cs.cliente,
  cs.vendedor,
  cs.estado_symphony,
  cs.total_compra,
  coalesce(pa.ingreso_producto, cs.valor_venta, 0) as ingreso_producto,
  coalesce(pa.costo_producto, 0) as costo_producto,
  coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0) as rentabilidad_producto,
  coalesce(pa.producto_tiene_costo_real, false) as producto_costo_es_real,
  ta.ingreso_transporte,
  case when ta.transporte_sin_dato then null else ta.costo_transporte_calc end as costo_transporte,
  case when ta.transporte_sin_dato then null else ta.ingreso_transporte - ta.costo_transporte_calc end as rentabilidad_transporte,
  ta.transporte_costo_es_real,
  case when ta.transporte_sin_dato then null
       else coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0)
            + (ta.ingreso_transporte - ta.costo_transporte_calc) end as rentabilidad_total,
  -- % total sobre ingreso sin IVA (producto + transporte)
  case when ta.transporte_sin_dato then null
       when coalesce(pa.ingreso_producto, cs.valor_venta, 0) + ta.ingreso_transporte = 0 then null
       else round(100 * (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0)
                         + (ta.ingreso_transporte - ta.costo_transporte_calc))
                  / (coalesce(pa.ingreso_producto, cs.valor_venta, 0) + ta.ingreso_transporte), 2)
  end as rentabilidad_pct,
  ta.transporte_sin_dato,
  -- columnas nuevas
  case when coalesce(pa.ingreso_producto, cs.valor_venta, 0) = 0 then null
       else round(100 * (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0))
                  / coalesce(pa.ingreso_producto, cs.valor_venta, 0), 2)
  end as rentabilidad_producto_pct,
  case when ta.transporte_sin_dato or ta.ingreso_transporte = 0 then null
       else round(100 * (ta.ingreso_transporte - ta.costo_transporte_calc) / ta.ingreso_transporte, 2)
  end as rentabilidad_transporte_pct,
  coalesce(pa.ingreso_producto, cs.valor_venta, 0) + ta.ingreso_transporte as ingreso_total
from compras_symphony cs
left join producto_agg pa on pa.id_compra = cs.id_compra
left join transporte_agg ta on ta.id_compra = cs.id_compra;

alter view v_rentabilidad_compra set (security_invoker = true);
