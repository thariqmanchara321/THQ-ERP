create table if not exists public.transport_logistics_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  stock_transfer_id uuid not null references public.stock_transfers(id) on delete restrict,
  receipt_number text not null,
  status text not null default 'finalized' check (status in ('finalized')),
  good_quantity numeric not null default 0 check (good_quantity >= 0),
  damaged_quantity numeric not null default 0 check (damaged_quantity >= 0),
  missing_quantity numeric not null default 0 check (missing_quantity >= 0),
  returned_quantity numeric not null default 0 check (returned_quantity >= 0),
  note text,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (tenant_id, receipt_number),
  unique (tenant_id, stock_transfer_id)
);;
