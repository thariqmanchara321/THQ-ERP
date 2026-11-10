create index if not exists transport_logistics_evidence_trip_fk_idx
  on public.transport_logistics_evidence(trip_id);
create index if not exists transport_logistics_evidence_transfer_fk_idx
  on public.transport_logistics_evidence(stock_transfer_id)
  where stock_transfer_id is not null;
create index if not exists transport_logistics_evidence_receipt_fk_idx
  on public.transport_logistics_evidence(receipt_id)
  where receipt_id is not null;

create index if not exists transport_logistics_exceptions_trip_fk_idx
  on public.transport_logistics_exceptions(trip_id);
create index if not exists transport_logistics_exceptions_receipt_fk_idx
  on public.transport_logistics_exceptions(receipt_id);
create index if not exists transport_logistics_exceptions_transfer_fk_idx
  on public.transport_logistics_exceptions(stock_transfer_id);
create index if not exists transport_logistics_exceptions_variant_fk_idx
  on public.transport_logistics_exceptions(variant_id);;
