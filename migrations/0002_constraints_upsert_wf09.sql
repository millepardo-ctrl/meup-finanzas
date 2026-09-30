-- =========================================================
-- Constraints necesarias para los UPSERT nativos de WF-09
-- (antes esto se simulaba a mano en el Code node con sets
-- "existentes/detExistentes/provExistentes" leídos de Sheets;
-- con una unique key real, Postgres lo garantiza solo)
-- =========================================================

-- Una fila de detalle por producto dentro de una compra.
-- Más fino que el control anterior (que bloqueaba TODO el detalle
-- de una compra si ya existía cualquier línea) — ahora una compra
-- recargada con una línea nueva sí la agrega, sin duplicar las que
-- ya estaban.
alter table compras_detalle
  add constraint uq_compras_detalle_compra_producto unique (id_compra, cod_producto);

-- Un proveedor local por compra (igual que la agregación que ya
-- hacía el Code node de WF-09, ahora garantizada por Postgres).
alter table proveedores_locales_pagos
  add constraint uq_plp_compra_nit unique (id_compra, nit_proveedor);
