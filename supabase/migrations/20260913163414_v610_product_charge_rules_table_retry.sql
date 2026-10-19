create table if not exists public.product_charge_rules_v610 (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 product_variant_id uuid not null,
 charge_catalog_id uuid not null,
 order_type text not null default 'delivery',
 quantity_mode text not null default 'per_unit',
 quantity_value numeric not null default 1,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);;
