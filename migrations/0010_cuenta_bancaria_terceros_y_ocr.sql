-- Permite identificar AL TERCERO (proveedor o colaborador de nómina) por el número de cuenta
-- de destino que trae el comprobante de pago, en vez de depender de que el comprobante
-- mencione el número de OC/compra (que normalmente no trae — feedback real de Milena,
-- 3 oct 2026: "el comprobante de pago no va a traer el ID de la compra").
alter table cat_terceros add column if not exists cuenta_bancaria text;
comment on column cat_terceros.cuenta_bancaria is
  'Número de cuenta/Nequi/Daviplata de este tercero (solo dígitos, normalizado). Permite que WF-10 identifique quién recibió un pago por la cuenta destino del comprobante, sin depender de que el comprobante mencione el ID de compra. tipo=COLABORADOR usa esto para nómina.';

alter table comprobantes_wa add column if not exists ocr_cuenta_destino text;
comment on column comprobantes_wa.ocr_cuenta_destino is
  'Número de cuenta/Nequi/Daviplata de destino extraído del comprobante por OCR (solo dígitos). Usado por WF-10 para cruzar contra cat_terceros.cuenta_bancaria.';

create index if not exists idx_cat_terceros_cuenta on cat_terceros(cuenta_bancaria) where cuenta_bancaria is not null;
