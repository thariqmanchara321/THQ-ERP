-- THQ ERP V4.8.5 — Warehouse & Transfers foundation.
begin;

-- Existing business_locations remain the single location model. Warehouses are
-- locations whose hierarchy_role/location_type is warehouse, avoiding a second
-- stock/location master that could drift from the rest of THQ ERP.

alter table public.stock_transfers
  add column if not exists expected_arrival_date date,
  add column if not exists transport_reference text,
  add column if not exists dispatch_note text,
  add column if not exists receive_note text,
  add column if not exists in_transit_at timestamptz,
  add column if not exists request_key text,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists ux_stock_transfers_v485_request_key
  on public.stock_transfers(tenant_id,request_key)
  where request_key is not null and trim(request_key)<>'';
create index if not exists idx_stock_transfers_v485_transit
  on public.stock_transfers(tenant_id,status,from_location_id,to_location_id,created_at desc);

-- Add an explicit in_transit state while keeping dispatched for old records.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.stock_transfers'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
      and pg_get_constraintdef(oid) ilike '%requested%'
  loop
    execute format('alter table public.stock_transfers drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.stock_transfers
  add constraint stock_transfers_status_v485_check
  check(status in('draft','requested','approved','dispatched','in_transit','received','rejected','cancelled'));

alter table public.stock_transfer_items
  add column if not exists tracking_mode text not null default 'none',
  add column if not exists tracking_payload jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.stock_transfer_items'::regclass
      and conname='stock_transfer_items_tracking_v485_check'
  ) then
    alter table public.stock_transfer_items
      add constraint stock_transfer_items_tracking_v485_check
      check(tracking_mode in('none','serial','batch'));
  end if;
end $$;

-- Batch stock reservation prevents FEFO/customer sales from consuming stock
-- already committed to an approved/requested transfer.
alter table public.inventory_batch_balances_v483
  add column if not exists reserved_quantity numeric not null default 0;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.inventory_batch_balances_v483'::regclass
      and conname='inventory_batch_balances_reserved_v485_check'
  ) then
    alter table public.inventory_batch_balances_v483
      add constraint inventory_batch_balances_reserved_v485_check
      check(reserved_quantity>=0 and reserved_quantity<=quantity+0.000001);
  end if;
end $$;

-- A serial remains physically in_stock while reserved. Dispatch moves it to
-- in_transit and receive restores it to in_stock at the destination.
alter table public.inventory_serials_v483
  add column if not exists reserved_transfer_id uuid references public.stock_transfers(id) on delete set null;
create index if not exists idx_inventory_serials_v485_reserved
  on public.inventory_serials_v483(tenant_id,reserved_transfer_id,variant_id)
  where reserved_transfer_id is not null;

do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.inventory_serials_v483'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
      and pg_get_constraintdef(oid) ilike '%in_stock%'
  loop
    execute format('alter table public.inventory_serials_v483 drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.inventory_serials_v483
  add constraint inventory_serials_status_v485_check
  check(status in('in_stock','in_transit','sold','returned','quarantine','missing','recalled','void'));

create table if not exists public.stock_transfer_allocations_v485(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  transfer_item_id uuid not null references public.stock_transfer_items(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  serial_id uuid references public.inventory_serials_v483(id) on delete restrict,
  batch_id uuid references public.inventory_batches_v483(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  status text not null default 'reserved' check(status in('reserved','in_transit','received','released')),
  from_location_id uuid not null references public.business_locations(id) on delete restrict,
  to_location_id uuid not null references public.business_locations(id) on delete restrict,
  reserved_at timestamptz not null default now(),
  dispatched_at timestamptz,
  received_at timestamptz,
  released_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((serial_id is not null)::int + (batch_id is not null)::int = 1)
);
create unique index if not exists ux_stock_transfer_alloc_v485_serial_active
  on public.stock_transfer_allocations_v485(tenant_id,serial_id)
  where serial_id is not null and status in('reserved','in_transit');
create index if not exists idx_stock_transfer_alloc_v485_batch
  on public.stock_transfer_allocations_v485(tenant_id,batch_id,from_location_id,status)
  where batch_id is not null;
create index if not exists idx_stock_transfer_alloc_v485_transfer
  on public.stock_transfer_allocations_v485(tenant_id,transfer_id,transfer_item_id,status);
alter table public.stock_transfer_allocations_v485 enable row level security;
revoke all on public.stock_transfer_allocations_v485 from anon,authenticated;

create table if not exists public.stock_transfer_history_v485(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  event_type text not null check(event_type in('requested','approved','rejected','cancelled','dispatched','in_transit','received','note')),
  from_status text,
  to_status text,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_stock_transfer_history_v485
  on public.stock_transfer_history_v485(tenant_id,transfer_id,created_at,id);
alter table public.stock_transfer_history_v485 enable row level security;
revoke all on public.stock_transfer_history_v485 from anon,authenticated;

-- Link the v4.8.3 trace ledger directly to warehouse transfers.
alter table public.inventory_trace_events_v483
  add column if not exists transfer_id uuid references public.stock_transfers(id) on delete set null,
  add column if not exists transfer_item_id uuid references public.stock_transfer_items(id) on delete set null;
create index if not exists idx_inventory_trace_events_v485_transfer
  on public.inventory_trace_events_v483(tenant_id,transfer_id,transfer_item_id,created_at desc)
  where transfer_id is not null;

-- Enrich the existing stock-count tables instead of replacing their audit trail.
alter table public.stock_counts
  add column if not exists request_key text,
  add column if not exists reconciliation_status text not null default 'pending',
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists ux_stock_counts_v485_request_key
  on public.stock_counts(tenant_id,request_key)
  where request_key is not null and trim(request_key)<>'';

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.stock_counts'::regclass
      and conname='stock_counts_reconciliation_v485_check'
  ) then
    alter table public.stock_counts
      add constraint stock_counts_reconciliation_v485_check
      check(reconciliation_status in('pending','reconciled','variance'));
  end if;
end $$;

alter table public.stock_count_items
  add column if not exists tracking_mode text not null default 'none',
  add column if not exists tracking_payload jsonb not null default '{}'::jsonb,
  add column if not exists system_reserved_quantity numeric not null default 0,
  add column if not exists system_damaged_quantity numeric not null default 0,
  add column if not exists system_quarantine_quantity numeric not null default 0,
  add column if not exists reconciliation_note text;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.stock_count_items'::regclass
      and conname='stock_count_items_tracking_v485_check'
  ) then
    alter table public.stock_count_items
      add constraint stock_count_items_tracking_v485_check
      check(tracking_mode in('none','serial','batch'));
  end if;
end $$;

create or replace function private.warehouse_v485_permission(p_tenant_id uuid,p_approval boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if private.erp_user_is_owner(p_tenant_id) then return;end if;
  if p_approval then
    if not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_has_permission(p_tenant_id,'approvals.approve') then
      raise exception 'Warehouse transfer approval permission required';
    end if;
  elsif not private.erp_has_permission(p_tenant_id,'inventory.transfer')
     and not private.erp_has_permission(p_tenant_id,'inventory.manage')
     and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') then
    raise exception 'Warehouse inventory permission required';
  end if;
end$$;
revoke all on function private.warehouse_v485_permission(uuid,boolean) from public;

create or replace function public.warehouse_locations_v485(p_tenant_id uuid)
returns table(
  location_id uuid,location_code text,location_name text,location_type text,hierarchy_role text,
  product_count bigint,on_hand numeric,reserved numeric,available numeric,damaged numeric,quarantine numeric,
  in_transit_in numeric,in_transit_out numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.warehouse_v485_permission(p_tenant_id,false);
  return query
  select l.id,l.location_code,l.name,l.location_type,l.hierarchy_role,
    count(distinct case when coalesce(b.quantity,0)<>0 then b.variant_id end),
    coalesce(sum(b.quantity),0),coalesce(sum(b.reserved_quantity),0),
    coalesce(sum(greatest(b.quantity-b.reserved_quantity-b.damaged_quantity-b.quarantine_quantity,0)),0),
    coalesce(sum(b.damaged_quantity),0),coalesce(sum(b.quarantine_quantity),0),
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0))
      from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id
      where t.tenant_id=p_tenant_id and t.to_location_id=l.id and t.status in('dispatched','in_transit')),0),
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0))
      from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id
      where t.tenant_id=p_tenant_id and t.from_location_id=l.id and t.status in('dispatched','in_transit')),0)
  from public.business_locations l
  left join public.location_stock_balances b on b.tenant_id=l.tenant_id and b.location_id=l.id
  where l.tenant_id=p_tenant_id and l.active
    and (l.hierarchy_role='warehouse' or l.location_type='warehouse')
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
  group by l.id,l.location_code,l.name,l.location_type,l.hierarchy_role
  order by l.name,l.location_code;
end$$;
grant execute on function public.warehouse_locations_v485(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(147,'4.8.5','Warehouse & Transfers','Warehouse/location foundation, tracked transfer allocations, explicit in-transit state, transfer history and enriched stock-count audit fields.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 147 warehouse/transfer foundation applied' as status;
