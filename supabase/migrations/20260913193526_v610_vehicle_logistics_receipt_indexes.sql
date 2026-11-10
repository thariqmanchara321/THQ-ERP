create index if not exists idx_transport_logistics_receipts_trip on public.transport_logistics_receipts(tenant_id, trip_id, received_at desc);
create index if not exists idx_transport_logistics_receipts_transfer on public.transport_logistics_receipts(tenant_id, stock_transfer_id);
create index if not exists idx_transport_logistics_receipt_lines_receipt on public.transport_logistics_receipt_lines(tenant_id, receipt_id);;
