create table if not exists public.transport_logistics_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  receipt_id uuid not null references public.transport_logistics_receipts(id) on delete cascade,
  transfer_item_id uuid not null references public.stock_transfer_items(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  tracking_mode text not null,
  dispatched_quantity numeric not null check (dispatched_quantity > 0),
  good_quantity numeric not null default 0 check (good_quantity >= 0),
  damaged_quantity numeric not null default 0 check (damaged_quantity >= 0),
  missing_quantity numeric not null default 0 check (missing_quantity >= 0),
  returned_quantity numeric not null default 0 check (returned_quantity >= 0),
  created_at timestamptz not null default now(),
  unique (receipt_id, transfer_item_id),
  check (abs((good_quantity + damaged_quantity + missing_quantity + returned_quantity) - dispatched_quantity) <= 0.000001)
);;
