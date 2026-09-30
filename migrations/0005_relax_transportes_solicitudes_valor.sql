-- valor_solicitado puede venir vacío cuando el parser de Claude no logra extraer datos
-- y la fila se crea solo para marcarla ESTADO='REVISAR' (revisión manual).
-- Descubierto al migrar WF-07 a Postgres (30 sep 2026).
alter table transportes_solicitudes alter column valor_solicitado drop not null;
