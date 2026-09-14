-- THQ ERP v6.1 Restaurant KOT item snapshot prerequisite
-- Ensures fresh/replayed databases have the KOT item snapshot table before delta/void KOT migrations.

create table if not exists public.restaurant_kot_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  kot_id uuid not null references public.restaurant_kots(id) on delete cascade,
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  order_item_id uuid null references public.restaurant_order_items(id) on delete set null,
  variant_id uuid not null references public.product_variants(id),
  quantity numeric not null,
  item_note text null,
  modifiers jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.restaurant_kot_items enable row level security;
revoke all on table public.restaurant_kot_items from public, anon, authenticated;
grant select, insert, update, delete on table public.restaurant_kot_items to service_role;

create index if not exists idx_restaurant_kot_items_kot
  on public.restaurant_kot_items(tenant_id, kot_id, created_at);

create index if not exists idx_restaurant_kot_items_order
  on public.restaurant_kot_items(tenant_id, order_id, created_at);
