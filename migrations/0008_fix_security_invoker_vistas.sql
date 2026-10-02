-- Supabase linter (security advisor) marcó v_rentabilidad_compra como SECURITY DEFINER:
-- al crearla el rol dueño del proyecto, Postgres la ejecuta con los privilegios de ese
-- dueño en vez de los del usuario que consulta, lo que ignora cualquier RLS futura por
-- rol (hoy no importa porque la política es "authenticated = acceso total", pero rompería
-- la Fase 4 pendiente de RLS por rol si no se corrige ahora). Mismo chequeo aplicado a
-- v_compras_symphony_calc por si quedó con el mismo problema.
-- Encontrado vía Supabase advisors (2 oct 2026).
alter view v_rentabilidad_compra set (security_invoker = on);
alter view v_compras_symphony_calc set (security_invoker = on);
