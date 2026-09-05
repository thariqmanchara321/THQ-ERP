alter table public.location_document_numbers enable row level security;

drop index if exists public.idx_expenses_tenant_date_v46;
drop index if exists public.idx_restaurant_orders_ops_v489;