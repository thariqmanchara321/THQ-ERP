create table if not exists public.transport_logistics_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  stock_transfer_id uuid references public.stock_transfers(id),
  receipt_id uuid references public.transport_logistics_receipts(id),
  evidence_type text not null,
  file_name text not null,
  storage_path text not null,
  mime_type text not null,
  file_size bigint not null,
  note text,
  captured_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint transport_logistics_evidence_type_chk check (evidence_type in ('dispatch_photo','arrival_photo','delivery_photo','damage_photo','receiver_signature','other')),
  constraint transport_logistics_evidence_mime_chk check (mime_type in ('image/jpeg','image/png')),
  constraint transport_logistics_evidence_size_chk check (file_size > 0 and file_size <= 5242880),
  constraint transport_logistics_evidence_storage_uq unique (storage_path)
);
create index if not exists transport_logistics_evidence_trip_idx on public.transport_logistics_evidence(tenant_id,trip_id,created_at desc);
create index if not exists transport_logistics_evidence_receipt_idx on public.transport_logistics_evidence(tenant_id,receipt_id,created_at desc) where receipt_id is not null;
alter table public.transport_logistics_evidence enable row level security;
revoke all on table public.transport_logistics_evidence from public, anon, authenticated;
grant all on table public.transport_logistics_evidence to service_role;

create table if not exists public.transport_logistics_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  receipt_id uuid not null references public.transport_logistics_receipts(id) on delete cascade,
  receipt_line_id uuid not null references public.transport_logistics_receipt_lines(id) on delete cascade,
  stock_transfer_id uuid not null references public.stock_transfers(id),
  variant_id uuid not null references public.product_variants(id),
  exception_type text not null,
  quantity numeric not null,
  status text not null default 'open',
  resolution_code text,
  resolution_note text,
  external_reference text,
  opened_at timestamptz not null default now(),
  opened_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  resolved_at timestamptz,
  resolved_by uuid,
  constraint transport_logistics_exception_type_chk check (exception_type in ('damaged','missing')),
  constraint transport_logistics_exception_qty_chk check (quantity > 0),
  constraint transport_logistics_exception_status_chk check (status in ('open','investigating','resolved','waived')),
  constraint transport_logistics_exception_line_type_uq unique (receipt_line_id,exception_type)
);
create index if not exists transport_logistics_exceptions_tenant_status_idx on public.transport_logistics_exceptions(tenant_id,status,opened_at desc);
create index if not exists transport_logistics_exceptions_trip_idx on public.transport_logistics_exceptions(tenant_id,trip_id,status,opened_at desc);
alter table public.transport_logistics_exceptions enable row level security;
revoke all on table public.transport_logistics_exceptions from public, anon, authenticated;
grant all on table public.transport_logistics_exceptions to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('thq-logistics-evidence','thq-logistics-evidence',false,5242880,array['image/jpeg','image/png']::text[])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;;
