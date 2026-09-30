-- retefuente_aplica es un tri-estado de negocio (POR_CONFIRMAR / SI / NO), no un booleano.
-- Descubierto al migrar WF-07 a Postgres: el workflow siempre escribe 'POR_CONFIRMAR'
-- hasta que la contadora confirme si aplica excepción por régimen del transportista.
alter table transportes_solicitudes
  alter column retefuente_aplica type text using (case when retefuente_aplica then 'SI' else 'POR_CONFIRMAR' end),
  alter column retefuente_aplica set default 'POR_CONFIRMAR';
