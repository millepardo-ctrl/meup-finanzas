-- 0012 — El estado de pago (PENDIENTE/ABONADO/PAGADO) se calcula en un trigger BEFORE UPDATE sobre
-- proveedores_locales_pagos. Así se recalcula tanto cuando cambia valor_pagado (nuevo pago) como cuando
-- llega la OC con su total a pagar (oc_total_pagar), sin llamar funciones desde dentro de otra sentencia.
-- Un estado puesto a mano (p.ej. desde Lovable) NO se pisa si no cambió valor_pagado ni oc_total_pagar.

create or replace function plp_calc_estado_pago() returns trigger
language plpgsql set search_path = public as $$
begin
  if (new.valor_pagado is distinct from old.valor_pagado)
     or (new.oc_total_pagar is distinct from old.oc_total_pagar and new.valor_pagado > 0) then
    new.estado_pago := case
      when new.valor_pagado <= 0 then 'PENDIENTE'
      when new.valor_pagado >= coalesce(new.oc_total_pagar, new.valor_costo) - 1 then 'PAGADO'
      else 'ABONADO' end;
  end if;
  return new;
end $$;

drop trigger if exists trg_plp_estado_pago on proveedores_locales_pagos;
create trigger trg_plp_estado_pago before update on proveedores_locales_pagos
  for each row execute function plp_calc_estado_pago();

-- recalcular_pago_oc ahora solo suma los pagos; el estado lo pone el trigger de arriba
create or replace function recalcular_pago_oc(p_control text) returns void
language plpgsql set search_path = public as $$
begin
  update proveedores_locales_pagos p set
    valor_pagado = (select coalesce(sum(valor), 0) from pagos_oc where id_control = p_control),
    fecha_pago   = coalesce((select max(fecha_pago) from pagos_oc where id_control = p_control), p.fecha_pago)
  where p.id_control = p_control;
end $$;
