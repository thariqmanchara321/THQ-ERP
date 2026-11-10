alter table public.transport_logistics_receipt_lines add column if not exists details jsonb not null default '[]'::jsonb;;
