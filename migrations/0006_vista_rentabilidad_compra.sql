-- Rentabilidad por compra (Symphony), separada en producto y transporte, y sumada.
-- Costo real primero, estimado como fallback (mismo criterio que BANCOS_MOV.ORIGEN):
--   - Producto, proveedor local (nit != 900570024): costo real si ya hay pago
--     registrado en proveedores_locales_pagos (cruzado por id_compra + nit);
--     si no, el estimado de Symphony (compras_detalle.costo_total) como fallback.
--   - Producto, importado (nit = 900570024): siempre estimado de Symphony — no
--     existe un "pago a proveedor" que cruzar para producto propio importado.
--   - Transporte: real pagado (transportes_pagos.valor, estado PAGADO) si existe;
--     si no, el estimado de Symphony (costo_transporte_symphony) como fallback.
--     Reutiliza la misma suma que ya expone v_compras_symphony_calc.costo_transporte_pagado.

create or replace view v_rentabilidad_compra as
with costo_producto_por_nit as (
  -- Costo por grupo (id_compra, nit_proveedor) dentro de cada compra: suma de Symphony
  -- vs el pago real local cuando existe.
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

  coalesce(cs.valor_domicilio_cobrado, 0) as ingreso_transporte,
  case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
       else coalesce(cs.costo_transporte_symphony, 0) end as costo_transporte,
  coalesce(cs.valor_domicilio_cobrado, 0)
    - (case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
            else coalesce(cs.costo_transporte_symphony, 0) end) as rentabilidad_transporte,
  (calc.costo_transporte_pagado > 0) as transporte_costo_es_real,

  (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0))
    + (coalesce(cs.valor_domicilio_cobrado, 0)
       - (case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
               else coalesce(cs.costo_transporte_symphony, 0) end)) as rentabilidad_total,

  case when coalesce(cs.total_compra, 0) = 0 then null
       else round(
         100 * (
           (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0))
           + (coalesce(cs.valor_domicilio_cobrado, 0)
              - (case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
                      else coalesce(cs.costo_transporte_symphony, 0) end))
         ) / cs.total_compra, 2)
  end as rentabilidad_pct

from compras_symphony cs
left join v_compras_symphony_calc calc on calc.id_compra = cs.id_compra
left join producto_agg pa on pa.id_compra = cs.id_compra;
