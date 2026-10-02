-- retefuente_aplica seguía NOT NULL (el default 'POR_CONFIRMAR' nunca aplica cuando el
-- INSERT manda NULL explícito, que es justo lo que hace WF-07 en la fila de "revisar a
-- mano" cuando el parser no logra extraer ninguna solicitud). Mismo caso que
-- valor_solicitado en la migración 0005. Encontrado en producción (2 oct 2026).
alter table transportes_solicitudes alter column retefuente_aplica drop not null;
