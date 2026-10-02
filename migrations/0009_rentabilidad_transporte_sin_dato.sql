-- Hallazgo en revisión de Fase 3 (2 oct 2026): cuando Symphony no trae el costo real de
-- transporte (costo_transporte_symphony llega en 0, no en null, aunque sí hay transportista
-- y domicilio cobrado) y todavía no existe un pago real (transportes_pagos PAGADO), la vista
-- asumía costo $0 y mostraba el domicilio cobrado completo como ganancia — inflando la
-- rentabilidad de transporte mientras el pago real sigue pendiente.
--
-- Ahora: si hay domicilio cobrado (valor_domicilio_cobrado > 0) pero ni el pago real ni el
-- estimado de Symphony traen un costo > 0, el costo y la rentabilidad de transporte quedan
-- en NULL ("sin dato") en vez de asumir $0, y lo mismo se propaga a rentabilidad_total /
-- rentabilidad_pct para no mostrar un total falso mientras falta ese dato. Si no hay
-- domicilio cobrado (pedido sin transporte), costo $0 sigue siendo válido y no se marca
-- como sin dato. La columna nueva transporte_sin_dato queda al final (CREATE OR REPLACE
-- VIEW no permite reordenar columnas existentes).

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
    cs.id_compra,
    coalesce(cs.valor_domicilio_cobrado, 0) as ingreso_transporte,
    (calc.costo_transporte_pagado > 0) as transporte_costo_es_real,
    (coalesce(cs.valor_domicilio_cobrado, 0) > 0
      and not (calc.costo_transporte_pagado > 0)
      and not (coalesce(cs.costo_transporte_symphony, 0) > 0)) as transporte_sin_dato,
    case when calc.costo_transporte_pagado > 0 then calc.costo_transporte_pagado
         else coalesce(cs.costo_transporte_symphony, 0) end as costo_transporte_calc
  from compras_symphony cs
  left join v_compras_symphony_calc calc on calc.id_compra = cs.id_compra
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
       else (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0))
            + (ta.ingreso_transporte - ta.costo_transporte_calc)
  end as rentabilidad_total,

  case when ta.transporte_sin_dato then null
       when coalesce(cs.total_compra, 0) = 0 then null
       else round(
         100 * (
           (coalesce(pa.ingreso_producto, cs.valor_venta, 0) - coalesce(pa.costo_producto, 0))
           + (ta.ingreso_transporte - ta.costo_transporte_calc)
         ) / cs.total_compra, 2)
  end as rentabilidad_pct,

  ta.transporte_sin_dato

from compras_symphony cs
left join producto_agg pa on pa.id_compra = cs.id_compra
left join transporte_agg ta on ta.id_compra = cs.id_compra;

alter view v_rentabilidad_compra set (security_invoker = on);
