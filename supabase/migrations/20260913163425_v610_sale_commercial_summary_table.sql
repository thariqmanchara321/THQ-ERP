create table if not exists public.sale_commercial_summary_v610 (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 sale_id uuid not null,
 source_type text not null default 'sale',
 source_id uuid,
 order_type text not null default 'sale',
 discount_type text not null default 'none',
 discount_value numeric not null default 0,
 document_discount_total numeric not null default 0,
 classified_charge_total numeric not null default 0,
 charge_breakdown jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now()
);;
