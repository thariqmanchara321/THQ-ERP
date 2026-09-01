-- THQ ERP V4.8.5 — combined database upgrade from migration 146 to 153.
-- Apply only to a database already at THQ ERP v4.8.4 / migration 146.

-- ============================================================================
-- 147_v485_warehouse_transfer_foundation.sql
-- ============================================================================
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

-- ============================================================================
-- 148_v485_transfer_request_approval.sql
-- ============================================================================
-- THQ ERP V4.8.5 — transfer request, reservation and approval.
begin;

create or replace function private.v485_transfer_history_add(
  p_tenant_id uuid,p_transfer_id uuid,p_event_type text,p_from_status text,p_to_status text,p_note text default null,p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.stock_transfer_history_v485(tenant_id,transfer_id,event_type,from_status,to_status,note,metadata,changed_by)
  values(p_tenant_id,p_transfer_id,p_event_type,nullif(p_from_status,''),nullif(p_to_status,''),nullif(trim(coalesce(p_note,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid());
end$$;
revoke all on function private.v485_transfer_history_add(uuid,uuid,text,text,text,text,jsonb) from public;

create or replace function private.v485_transfer_release_reservation(p_transfer_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r record;a record;
begin
  select * into v from public.stock_transfers where id=p_transfer_id for update;
  if not found or not coalesce(v.reservation_applied,false) then return;end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    update public.location_stock_balances
      set reserved_quantity=greatest(0,reserved_quantity-r.quantity),updated_at=now()
    where tenant_id=v.tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
  end loop;

  for a in select * from public.stock_transfer_allocations_v485 where transfer_id=v.id and status='reserved' order by id loop
    if a.serial_id is not null then
      update public.inventory_serials_v483
        set reserved_transfer_id=null,updated_at=now()
      where id=a.serial_id and tenant_id=v.tenant_id and reserved_transfer_id=v.id;
    elsif a.batch_id is not null then
      update public.inventory_batch_balances_v483
        set reserved_quantity=greatest(0,reserved_quantity-a.quantity),updated_at=now()
      where tenant_id=v.tenant_id and batch_id=a.batch_id and location_id=v.from_location_id;
    end if;
    update public.stock_transfer_allocations_v485
      set status='released',released_at=now(),updated_at=now()
    where id=a.id;
  end loop;

  update public.stock_transfers set reservation_applied=false,updated_at=now() where id=v.id;
end$$;
revoke all on function private.v485_transfer_release_reservation(uuid,text) from public;

create or replace function public.inventory_transfer_request_v485(
  p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text default null,
  p_expected_arrival_date date default null,p_transport_reference text default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_existing jsonb;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_variant uuid;v_qty numeric;v_available numeric;v_mode text;
  v_item_id uuid;v_serials jsonb;s jsonb;v_serial text;v_serial_id uuid;v_serial_count numeric;v_seen_serial text[]:='{}'::text[];
  v_batches jsonb;b jsonb;v_batch_id uuid;v_batch_number text;v_batch_qty numeric;v_batch_available numeric;v_batch_sum numeric;v_seen_batch uuid[]:='{}'::uuid[];
  v_result jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'warehouse.transfer.request');
    if v_existing is not null then return v_existing;end if;
  end if;
  perform private.v4_location_access(p_tenant_id,p_from_location_id,'operate');
  perform private.v4_location_access(p_tenant_id,p_to_location_id,'view');
  perform private.warehouse_v485_permission(p_tenant_id,false);
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Stock transfer permission required';
  end if;
  if p_from_location_id=p_to_location_id then raise exception 'Source and destination must be different';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one transfer item';end if;

  v_no:='TRF-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.stock_transfer_number_seq')::text,6,'0');
  insert into public.stock_transfers(
    id,tenant_id,transfer_number,from_location_id,to_location_id,status,notes,created_by,requested_by,requested_at,
    reservation_applied,expected_arrival_date,transport_reference,request_key,updated_at
  ) values(
    v_id,p_tenant_id,v_no,p_from_location_id,p_to_location_id,'requested',nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid(),now(),
    true,p_expected_arrival_date,nullif(trim(coalesce(p_transport_reference,'')),''),nullif(trim(coalesce(p_request_id,'')),''),now()
  );

  for x in select value from jsonb_array_elements(p_items) loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_variant is null or not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id=v_variant) then raise exception 'Product does not belong to this business';end if;
    if v_qty<=0 then raise exception 'Transfer quantity must be positive';end if;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    if v_mode='serial' and v_qty<>trunc(v_qty) then raise exception 'Serial-tracked transfer quantity must be whole base units';end if;
    perform private.v483_assert_reconciled(p_tenant_id,v_variant,p_from_location_id);

    insert into public.location_stock_balances(tenant_id,location_id,variant_id)
      values(p_tenant_id,p_from_location_id,v_variant) on conflict do nothing;
    select quantity-reserved_quantity-damaged_quantity-quarantine_quantity into v_available
      from public.location_stock_balances
      where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=v_variant
      for update;
    if coalesce(v_available,0)+0.000001<v_qty then raise exception 'Insufficient available stock. Available: %, requested: %',coalesce(v_available,0),v_qty;end if;

    update public.location_stock_balances
      set reserved_quantity=reserved_quantity+v_qty,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=v_variant;

    insert into public.stock_transfer_items(transfer_id,variant_id,quantity,note,tracking_mode,tracking_payload,updated_at)
      values(v_id,v_variant,v_qty,nullif(trim(coalesce(x->>'note','')),''),v_mode,coalesce(x->'tracking','{}'::jsonb),now())
      returning id into v_item_id;

    if v_mode='serial' then
      v_serials:=coalesce(x->'serial_numbers',x->'tracking'->'serial_numbers','[]'::jsonb);
      if jsonb_typeof(v_serials)<>'array' then raise exception 'serial_numbers must be an array';end if;
      select count(*)::numeric into v_serial_count from jsonb_array_elements(v_serials);
      if v_serial_count<>v_qty then raise exception 'Provide exactly % serial numbers for the transfer line',v_qty;end if;
      v_seen_serial:='{}'::text[];
      for s in select value from jsonb_array_elements(v_serials) loop
        v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
        if v_serial='' then raise exception 'Serial number cannot be blank';end if;
        if lower(v_serial)=any(v_seen_serial) then raise exception 'Serial % is duplicated on the transfer',v_serial;end if;
        v_seen_serial:=array_append(v_seen_serial,lower(v_serial));
        select id into v_serial_id from public.inventory_serials_v483
          where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_from_location_id
            and status='in_stock' and reserved_transfer_id is null and lower(trim(serial_number))=lower(v_serial)
          for update;
        if v_serial_id is null then raise exception 'Serial % is not available at the source location',v_serial;end if;
        update public.inventory_serials_v483 set reserved_transfer_id=v_id,updated_at=now() where id=v_serial_id;
        insert into public.stock_transfer_allocations_v485(tenant_id,transfer_id,transfer_item_id,variant_id,serial_id,quantity,status,from_location_id,to_location_id,created_by)
          values(p_tenant_id,v_id,v_item_id,v_variant,v_serial_id,1,'reserved',p_from_location_id,p_to_location_id,auth.uid());
      end loop;
    elsif v_mode='batch' then
      v_batches:=coalesce(x->'batches',x->'tracking'->'batches','[]'::jsonb);
      if jsonb_typeof(v_batches)<>'array' or jsonb_array_length(v_batches)=0 then raise exception 'Batch-tracked transfers require batch allocations';end if;
      v_batch_sum:=0;v_seen_batch:='{}'::uuid[];
      for b in select value from jsonb_array_elements(v_batches) loop
        v_batch_qty:=coalesce(nullif(b->>'quantity','')::numeric,0);
        if v_batch_qty<=0 then raise exception 'Batch transfer quantity must be positive';end if;
        if nullif(b->>'batch_id','') is not null then
          v_batch_id:=(b->>'batch_id')::uuid;
        else
          v_batch_number:=trim(coalesce(b->>'batch_number',''));
          select id into v_batch_id from public.inventory_batches_v483
            where tenant_id=p_tenant_id and variant_id=v_variant and lower(trim(batch_number))=lower(v_batch_number);
        end if;
        if v_batch_id is null then raise exception 'Batch % was not found',coalesce(v_batch_number,'');end if;
        if not exists(
          select 1 from public.inventory_batches_v483 ib
          where ib.id=v_batch_id and ib.tenant_id=p_tenant_id and ib.variant_id=v_variant
        ) then raise exception 'Batch does not belong to the selected product/business';end if;
        if v_batch_id=any(v_seen_batch) then raise exception 'The same batch cannot appear twice on one transfer line';end if;
        v_seen_batch:=array_append(v_seen_batch,v_batch_id);
        select quantity-coalesce(reserved_quantity,0) into v_batch_available
          from public.inventory_batch_balances_v483
          where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_from_location_id
          for update;
        if coalesce(v_batch_available,0)+0.000001<v_batch_qty then raise exception 'Insufficient available quantity in batch %',coalesce(v_batch_number,v_batch_id::text);end if;
        update public.inventory_batch_balances_v483 set reserved_quantity=reserved_quantity+v_batch_qty,updated_at=now()
          where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_from_location_id;
        insert into public.stock_transfer_allocations_v485(tenant_id,transfer_id,transfer_item_id,variant_id,batch_id,quantity,status,from_location_id,to_location_id,created_by)
          values(p_tenant_id,v_id,v_item_id,v_variant,v_batch_id,v_batch_qty,'reserved',p_from_location_id,p_to_location_id,auth.uid());
        v_batch_sum:=v_batch_sum+v_batch_qty;
      end loop;
      if abs(v_batch_sum-v_qty)>0.000001 then raise exception 'Batch allocations % must equal transfer quantity %',v_batch_sum,v_qty;end if;
    end if;
  end loop;

  perform private.v485_transfer_history_add(p_tenant_id,v_id,'requested',null,'requested',p_notes,jsonb_build_object('expected_arrival_date',p_expected_arrival_date,'transport_reference',nullif(trim(coalesce(p_transport_reference,'')),'')));
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v_id::text,'requested');
  v_result:=jsonb_build_object('success',true,'transfer_id',v_id,'transfer_number',v_no,'status','requested','reservation_applied',true);
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_result:=private.v47_request_complete(p_tenant_id,p_request_id,'warehouse.transfer.request',v_result);
  end if;
  return v_result;
end$$;
grant execute on function public.inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text) to authenticated;

create or replace function public.inventory_transfer_decide_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_approve boolean,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;v_to text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'manage');
  perform private.warehouse_v485_permission(p_tenant_id,true);
  if v.status<>'requested' then raise exception 'Only requested transfers can be approved or rejected';end if;
  if coalesce(p_approve,false) then
    update public.stock_transfers set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=v.id;
    v_to:='approved';
    perform private.v485_transfer_history_add(p_tenant_id,v.id,'approved','requested','approved',p_note);
  else
    if trim(coalesce(p_note,''))='' then raise exception 'Rejection reason is required';end if;
    perform private.v485_transfer_release_reservation(v.id,p_note);
    update public.stock_transfers set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=trim(p_note),updated_at=now() where id=v.id;
    v_to:='rejected';
    perform private.v485_transfer_history_add(p_tenant_id,v.id,'rejected','requested','rejected',p_note);
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,v_to);
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status',v_to);
end$$;
grant execute on function public.inventory_transfer_decide_v485(uuid,uuid,boolean,text) to authenticated;

create or replace function public.inventory_transfer_cancel_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'view');
  if v.status not in('draft','requested','approved') then raise exception 'In-transit/received transfers cannot be cancelled';end if;
  if auth.uid()<>v.created_by and not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Transfer cancel permission required';end if;
  perform private.v485_transfer_release_reservation(v.id,p_reason);
  update public.stock_transfers set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'cancelled',v.status,'cancelled',p_reason);
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'cancelled');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','cancelled');
end$$;
grant execute on function public.inventory_transfer_cancel_v485(uuid,uuid,text) to authenticated;

-- Compatibility wrappers: clients still calling the older v4.8.3/v4.2 names get
-- the v4.8.5 tracked-safe reservation/approval behavior.
create or replace function public.inventory_transfer_create_v483(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language sql security definer set search_path=public,private,pg_temp as $$
  select public.inventory_transfer_request_v485($1,$2,$3,$4,$5,null,null,$6)
$$;
grant execute on function public.inventory_transfer_create_v483(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.inventory_transfer_approve_v42(p_tenant_id uuid,p_transfer_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_decide_v485(p_tenant_id,p_transfer_id,true,null);
end$$;
grant execute on function public.inventory_transfer_approve_v42(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_reject_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_decide_v485(p_tenant_id,p_transfer_id,false,p_reason);
end$$;
grant execute on function public.inventory_transfer_reject_v42(uuid,uuid,text) to authenticated;

create or replace function public.inventory_transfer_cancel_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_cancel_v485(p_tenant_id,p_transfer_id,p_reason);
end$$;
grant execute on function public.inventory_transfer_cancel_v42(uuid,uuid,text) to authenticated;

-- Make customer sales reservation-aware. This preserves the v4.8.3 FEFO engine
-- but removes quantities/serials committed to warehouse transfers from saleable stock.
create or replace function private.v483_apply_batch_sale(
 p_tenant_id uuid,p_variant_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_quantity numeric,p_requested jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_remaining numeric:=p_quantity;v_out jsonb:='[]'::jsonb;v_allow_expired boolean:=false;r record;x jsonb;v_batch_id uuid;v_take numeric;v_requested_qty numeric;v_batch_number text;v_seen uuid[]:='{}'::uuid[];v_ref text;v_available numeric;
begin
 select allow_expired_sale into v_allow_expired from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 if jsonb_array_length(coalesce(p_requested,'[]'::jsonb))>0 then
  for x in select value from jsonb_array_elements(p_requested) loop
   v_requested_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);if v_requested_qty<=0 then raise exception 'Requested batch quantity must be positive';end if;
   v_batch_id:=null;
   if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid;else
    v_batch_number:=trim(coalesce(x->>'batch_number',''));select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(v_batch_number);end if;
   if v_batch_id is null then raise exception 'Batch not found for tracked product';end if;
   if v_batch_id=any(v_seen) then raise exception 'The same batch cannot appear twice on one sale line';end if;v_seen:=array_append(v_seen,v_batch_id);
   select b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0) available_quantity into r
     from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
     where b.tenant_id=p_tenant_id and b.id=v_batch_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and b.status='active' for update of bb;
   v_available:=coalesce(r.available_quantity,0);
   if not found or v_available+0.000001<v_requested_qty then raise exception 'Insufficient unreserved quantity in selected batch %',coalesce(r.batch_number,v_batch_number);end if;
   if not coalesce(v_allow_expired,false) and r.expiry_on is not null and r.expiry_on<p_sale_date then raise exception 'Batch % expired on %',r.batch_number,r.expiry_on;end if;
   update public.inventory_batch_balances_v483 set quantity=quantity-v_requested_qty,updated_at=now() where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by)
     values(p_tenant_id,p_variant_id,v_batch_id,'sale',v_requested_qty,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,v_batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_requested_qty,p_sale_date);
   v_remaining:=v_remaining-v_requested_qty;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',v_batch_id,'batch_number',r.batch_number,'quantity',v_requested_qty,'expiry_on',r.expiry_on));
  end loop;
  if abs(v_remaining)>0.000001 then raise exception 'Selected batch quantities must equal required base quantity %',p_quantity;end if;
 else
  for r in
    select b.id batch_id,b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0) available_quantity
    from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
    where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id
      and bb.quantity-coalesce(bb.reserved_quantity,0)>0 and b.status='active'
      and (coalesce(v_allow_expired,false) or b.expiry_on is null or b.expiry_on>=p_sale_date)
    order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number for update of bb
  loop
   exit when v_remaining<=0.000001;v_take:=least(v_remaining,r.available_quantity);
   update public.inventory_batch_balances_v483 set quantity=quantity-v_take,updated_at=now() where tenant_id=p_tenant_id and batch_id=r.batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
     values(p_tenant_id,p_variant_id,r.batch_id,'sale',v_take,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||r.batch_id::text,jsonb_build_object('allocation','FEFO'),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,r.batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_take,p_sale_date);
   v_remaining:=v_remaining-v_take;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',r.batch_id,'batch_number',r.batch_number,'quantity',v_take,'expiry_on',r.expiry_on));
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient eligible unreserved batch stock. Required %, unavailable %',p_quantity,v_remaining;end if;
 end if;
 update public.inventory_batches_v483 b set status='exhausted',updated_at=now()
 where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active'
   and not exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=b.tenant_id and bb.batch_id=b.id and bb.quantity>0);
 return v_out;
end$$;
revoke all on function private.v483_apply_batch_sale(uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,jsonb) from public;

create or replace function private.v483_apply_sale_trace(
 p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_count numeric;s jsonb;v_serial text;v_serial_id uuid;v_ref text;v_batches jsonb;
begin
 if exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and sale_id=p_sale_id) then return;end if;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);select id into v_item_id from public.sale_items where sale_id=p_sale_id and variant_id=v_variant limit 1;if v_item_id is null then raise exception 'Sale line not found for tracked product';end if;
  if v_mode='serial' then
   if v_qty<>trunc(v_qty) then raise exception 'Serial-tracked product % requires whole base units',v_variant;end if;
   v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for tracked sale line',v_qty;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
    v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
    select id into v_serial_id from public.inventory_serials_v483
      where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='in_stock'
        and reserved_transfer_id is null and lower(trim(serial_number))=lower(v_serial) for update;
    if v_serial_id is null then raise exception 'Serial % is not available at the selected store (it may be reserved for transfer)',v_serial;end if;
    update public.inventory_serials_v483 set status='sold',current_location_id=null,customer_id=p_customer_id,sale_id=p_sale_id,sale_item_id=v_item_id,sold_at=now(),updated_at=now() where id=v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by)
      values(p_tenant_id,v_variant,v_serial_id,'sale',1,p_location_id,p_customer_id,p_sale_id,v_item_id,v_ref,'sale:'||p_sale_id::text||':serial:'||v_serial_id::text,auth.uid());
    perform private.v483_create_warranty(p_tenant_id,v_variant,v_serial_id,null,p_customer_id,p_sale_id,v_item_id,1,p_sale_date);
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);perform private.v483_apply_batch_sale(p_tenant_id,v_variant,p_sale_id,v_item_id,p_customer_id,p_location_id,p_sale_date,v_qty,v_batches);
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_sale_trace(uuid,uuid,uuid,uuid,date,jsonb) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(148,'4.8.5','Warehouse & Transfers','Tracked-safe transfer requests reserve aggregate, serial and batch stock; PO-style approval/rejection/cancellation releases reservations safely; sales exclude transfer-reserved stock.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 148 transfer request/approval applied' as status;

-- ============================================================================
-- 149_v485_dispatch_in_transit_receive.sql
-- ============================================================================
-- THQ ERP V4.8.5 — dispatch, in-transit and receive.
begin;

create or replace function public.inventory_transfer_dispatch_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null,p_dispatch_note text default null,p_transport_reference text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r public.stock_transfer_items%rowtype;a record;v_reserved numeric;v_serial text;v_batch text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status in('in_transit','dispatched') then
    return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','in_transit','idempotent',true);
  end if;
  if v.status<>'approved' then raise exception 'Only approved transfers can be dispatched';end if;
  if not coalesce(v.reservation_applied,false) then raise exception 'Transfer reservation is missing; cancel and recreate this transfer';end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    select reserved_quantity into v_reserved from public.location_stock_balances
      where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id for update;
    if coalesce(v_reserved,0)+0.000001<r.quantity then raise exception 'Reserved stock is inconsistent for transfer line %',r.id;end if;

    if r.tracking_mode='serial' then
      if (select count(*) from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' and serial_id is not null)<>r.quantity::bigint then
        raise exception 'Serial allocation is incomplete for transfer line %',r.id;
      end if;
    elsif r.tracking_mode='batch' then
      if abs(coalesce((select sum(quantity) from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' and batch_id is not null),0)-r.quantity)>0.000001 then
        raise exception 'Batch allocation is incomplete for transfer line %',r.id;
      end if;
    end if;

    -- Release the aggregate reservation immediately before removing the source stock.
    update public.location_stock_balances set reserved_quantity=greatest(0,reserved_quantity-r.quantity),updated_at=now()
      where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
    perform private.v4_location_stock_apply(p_tenant_id,v.from_location_id,r.variant_id,-r.quantity,'transfer_out','stock_transfer',v.id,v.transfer_number,'Dispatched / in transit',p_device_id,false);
    update public.stock_transfer_items set dispatched_quantity=r.quantity,updated_at=now() where id=r.id;

    for a in select * from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' order by id loop
      if a.serial_id is not null then
        select serial_number into v_serial from public.inventory_serials_v483
          where id=a.serial_id and tenant_id=p_tenant_id and status='in_stock' and current_location_id=v.from_location_id and reserved_transfer_id=v.id for update;
        if v_serial is null then raise exception 'Reserved serial allocation changed before dispatch';end if;
        update public.inventory_serials_v483
          set status='in_transit',current_location_id=null,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.serial_id,'transfer_out',1,v.from_location_id,v.transfer_number,
          'transfer:'||v.id::text||':out:serial:'||a.serial_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'serial_number',v_serial),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      elsif a.batch_id is not null then
        select b.batch_number into v_batch from public.inventory_batches_v483 b where b.id=a.batch_id and b.tenant_id=p_tenant_id;
        update public.inventory_batch_balances_v483
          set reserved_quantity=greatest(0,reserved_quantity-a.quantity),quantity=quantity-a.quantity,updated_at=now()
          where tenant_id=p_tenant_id and batch_id=a.batch_id and location_id=v.from_location_id
            and reserved_quantity+0.000001>=a.quantity and quantity+0.000001>=a.quantity;
        if not found then raise exception 'Reserved batch allocation changed before dispatch: %',coalesce(v_batch,a.batch_id::text);end if;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.batch_id,'transfer_out',a.quantity,v.from_location_id,v.transfer_number,
          'transfer:'||v.id::text||':out:batch:'||a.batch_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'batch_number',v_batch),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      end if;
      update public.stock_transfer_allocations_v485 set status='in_transit',dispatched_at=now(),updated_at=now() where id=a.id;
    end loop;
  end loop;

  update public.stock_transfers
    set status='in_transit',reservation_applied=false,dispatched_by=auth.uid(),dispatched_at=now(),in_transit_at=now(),
        dispatch_note=nullif(trim(coalesce(p_dispatch_note,'')),''),
        transport_reference=coalesce(nullif(trim(coalesce(p_transport_reference,'')),''),transport_reference),updated_at=now()
    where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'dispatched','approved','in_transit',p_dispatch_note,jsonb_build_object('transport_reference',coalesce(nullif(trim(coalesce(p_transport_reference,'')),''),v.transport_reference)));
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'in_transit');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','in_transit');
end$$;
grant execute on function public.inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text) to authenticated;

create or replace function public.inventory_transfer_receive_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null,p_receive_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r public.stock_transfer_items%rowtype;a record;v_serial text;v_batch text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.to_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status='received' then
    return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','received','idempotent',true);
  end if;
  if v.status not in('in_transit','dispatched') then raise exception 'Only in-transit transfers can be received';end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    if r.dispatched_quantity<=0 then raise exception 'Transfer line % was not dispatched',r.id;end if;
    perform public.inventory_location_assign_v4(p_tenant_id,v.to_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(p_tenant_id,v.to_location_id,r.variant_id,r.dispatched_quantity,'transfer_in','stock_transfer',v.id,v.transfer_number,'Received from transfer',p_device_id,false);

    for a in select * from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='in_transit' order by id loop
      if a.serial_id is not null then
        select serial_number into v_serial from public.inventory_serials_v483 where id=a.serial_id and tenant_id=p_tenant_id and status='in_transit' for update;
        if v_serial is null then raise exception 'In-transit serial allocation is missing';end if;
        update public.inventory_serials_v483
          set status='in_stock',current_location_id=v.to_location_id,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.serial_id,'transfer_in',1,v.to_location_id,v.transfer_number,
          'transfer:'||v.id::text||':in:serial:'||a.serial_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'serial_number',v_serial),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      elsif a.batch_id is not null then
        select batch_number into v_batch from public.inventory_batches_v483 where id=a.batch_id and tenant_id=p_tenant_id;
        insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
          values(p_tenant_id,a.batch_id,v.to_location_id,a.quantity,0,0,now())
          on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
        update public.inventory_batches_v483 set status='active',updated_at=now() where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.batch_id,'transfer_in',a.quantity,v.to_location_id,v.transfer_number,
          'transfer:'||v.id::text||':in:batch:'||a.batch_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'batch_number',v_batch),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      end if;
      update public.stock_transfer_allocations_v485 set status='received',received_at=now(),updated_at=now() where id=a.id;
    end loop;
    update public.stock_transfer_items set received_quantity=r.dispatched_quantity,updated_at=now() where id=r.id;
  end loop;

  update public.stock_transfers set status='received',received_by=auth.uid(),received_at=now(),receive_note=nullif(trim(coalesce(p_receive_note,'')),''),updated_at=now() where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'received',v.status,'received',p_receive_note);
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'received');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','received');
end$$;
grant execute on function public.inventory_transfer_receive_v485(uuid,uuid,uuid,text) to authenticated;

-- Keep legacy RPC names safe while old clients are phased out.
create or replace function public.inventory_transfer_dispatch_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_dispatch_v485(p_tenant_id,p_transfer_id,p_device_id,null,null);
end$$;
grant execute on function public.inventory_transfer_dispatch_v4(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_receive_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_receive_v485(p_tenant_id,p_transfer_id,p_device_id,null);
end$$;
grant execute on function public.inventory_transfer_receive_v4(uuid,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(149,'4.8.5','Warehouse & Transfers','Dispatch removes source stock and moves allocated serials/batches to In Transit; receive alone adds destination stock and completes tracked provenance.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 149 dispatch/in-transit/receive applied' as status;

-- ============================================================================
-- 150_v485_transfer_history_warehouse_inventory.sql
-- ============================================================================
-- THQ ERP V4.8.5 — transfer history and warehouse inventory reporting.
begin;

create or replace function public.inventory_transfers_list_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500
) returns table(
  id uuid,transfer_number text,from_location_id uuid,from_location text,from_is_warehouse boolean,
  to_location_id uuid,to_location text,to_is_warehouse boolean,status text,notes text,expected_arrival_date date,transport_reference text,
  created_at timestamptz,requested_at timestamptz,approved_at timestamptz,in_transit_at timestamptz,received_at timestamptz,
  item_count bigint,total_quantity numeric,serial_count bigint,batch_quantity numeric,in_transit_quantity numeric,reservation_applied boolean
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  perform private.warehouse_v485_permission(p_tenant_id,false);
  return query
  select t.id,t.transfer_number,t.from_location_id,fl.location_code||' • '||fl.name,(fl.hierarchy_role='warehouse' or fl.location_type='warehouse'),
    t.to_location_id,tl.location_code||' • '||tl.name,(tl.hierarchy_role='warehouse' or tl.location_type='warehouse'),
    case when t.status='dispatched' then 'in_transit' else t.status end,t.notes,t.expected_arrival_date,t.transport_reference,
    t.created_at,t.requested_at,t.approved_at,coalesce(t.in_transit_at,t.dispatched_at),t.received_at,
    count(distinct i.id),coalesce(sum(i.quantity),0),
    coalesce((select count(*) from public.stock_transfer_allocations_v485 a where a.transfer_id=t.id and a.serial_id is not null and a.status<>'released'),0),
    coalesce((select sum(a.quantity) from public.stock_transfer_allocations_v485 a where a.transfer_id=t.id and a.batch_id is not null and a.status<>'released'),0),
    coalesce(sum(case when t.status in('dispatched','in_transit') then greatest(i.dispatched_quantity-i.received_quantity,0) else 0 end),0),t.reservation_applied
  from public.stock_transfers t
  join public.business_locations fl on fl.id=t.from_location_id
  join public.business_locations tl on tl.id=t.to_location_id
  left join public.stock_transfer_items i on i.transfer_id=t.id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
    and (p_status is null or trim(p_status)='' or (case when t.status='dispatched' then 'in_transit' else t.status end)=lower(trim(p_status)))
    and (trim(coalesce(p_query,''))='' or lower(t.transfer_number) like q or lower(fl.name) like q or lower(tl.name) like q or lower(coalesce(t.transport_reference,'')) like q or lower(coalesce(t.notes,'')) like q)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view') or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'))
  group by t.id,fl.location_code,fl.name,fl.hierarchy_role,fl.location_type,tl.location_code,tl.name,tl.hierarchy_role,tl.location_type
  order by t.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.inventory_transfers_list_v485(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.inventory_transfer_history_v485(p_tenant_id uuid,p_transfer_id uuid)
returns table(event_id uuid,event_type text,from_status text,to_status text,note text,metadata jsonb,changed_by uuid,occurred_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_from uuid;v_to uuid;
begin
  select from_location_id,to_location_id into v_from,v_to from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id;
  if v_from is null then raise exception 'Transfer not found';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,v_from,'view') or private.erp_user_location_allowed(p_tenant_id,v_to,'view')) then raise exception 'Access denied';end if;
  return query select h.id,h.event_type,h.from_status,h.to_status,h.note,h.metadata,h.changed_by,h.created_at
    from public.stock_transfer_history_v485 h where h.tenant_id=p_tenant_id and h.transfer_id=p_transfer_id order by h.created_at,h.id;
end$$;
grant execute on function public.inventory_transfer_history_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_detail_v485(p_tenant_id uuid,p_transfer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_from uuid;v_to uuid;
begin
  select from_location_id,to_location_id into v_from,v_to from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id;
  if v_from is null then raise exception 'Transfer not found';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,v_from,'view') or private.erp_user_location_allowed(p_tenant_id,v_to,'view')) then raise exception 'Access denied';end if;
  select jsonb_build_object(
    'transfer',to_jsonb(t)||jsonb_build_object(
      'status',case when t.status='dispatched' then 'in_transit' else t.status end,
      'from_location',fl.location_code||' • '||fl.name,'to_location',tl.location_code||' • '||tl.name,
      'from_is_warehouse',(fl.hierarchy_role='warehouse' or fl.location_type='warehouse'),
      'to_is_warehouse',(tl.hierarchy_role='warehouse' or tl.location_type='warehouse')
    ),
    'items',coalesce((select jsonb_agg(
      to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku,
        'allocations',coalesce((select jsonb_agg(jsonb_build_object(
          'id',a.id,'status',a.status,'quantity',a.quantity,'serial_id',a.serial_id,'serial_number',s.serial_number,
          'batch_id',a.batch_id,'batch_number',b.batch_number,'expiry_on',b.expiry_on
        ) order by coalesce(s.serial_number,b.batch_number),a.id)
        from public.stock_transfer_allocations_v485 a
        left join public.inventory_serials_v483 s on s.id=a.serial_id
        left join public.inventory_batches_v483 b on b.id=a.batch_id
        where a.transfer_item_id=i.id),'[]'::jsonb))
      ) order by p.name,pv.sku)
      from public.stock_transfer_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.transfer_id=t.id),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at,h.id) from public.stock_transfer_history_v485 h where h.transfer_id=t.id),'[]'::jsonb)
  ) into v
  from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id
  where t.tenant_id=p_tenant_id and t.id=p_transfer_id;
  return v;
end$$;
grant execute on function public.inventory_transfer_detail_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_tracking_options_v485(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v jsonb;
begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'view');
  v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);
  if v_mode='serial' then
    select jsonb_build_object('tracking_mode','serial','serials',coalesce(jsonb_agg(jsonb_build_object('id',s.id,'serial_number',s.serial_number,'status',s.status) order by s.serial_number),'[]'::jsonb)) into v
    from public.inventory_serials_v483 s
    where s.tenant_id=p_tenant_id and s.variant_id=p_variant_id and s.current_location_id=p_location_id and s.status='in_stock' and s.reserved_transfer_id is null;
  elsif v_mode='batch' then
    select jsonb_build_object('tracking_mode','batch','batches',coalesce(jsonb_agg(jsonb_build_object(
      'id',b.id,'batch_number',b.batch_number,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
      'quantity',bb.quantity,'reserved_quantity',coalesce(bb.reserved_quantity,0),'available_quantity',greatest(bb.quantity-coalesce(bb.reserved_quantity,0),0)
    ) order by (b.expiry_on is null),b.expiry_on,b.batch_number),'[]'::jsonb)) into v
    from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
    where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and bb.quantity-coalesce(bb.reserved_quantity,0)>0 and b.status in('active','quarantine');
  else
    v:=jsonb_build_object('tracking_mode','none','serials','[]'::jsonb,'batches','[]'::jsonb);
  end if;
  return coalesce(v,jsonb_build_object('tracking_mode',v_mode,'serials','[]'::jsonb,'batches','[]'::jsonb));
end$$;
grant execute on function public.inventory_transfer_tracking_options_v485(uuid,uuid,uuid) to authenticated;

create or replace function public.warehouse_inventory_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns table(
  location_id uuid,location_code text,location_name text,variant_id uuid,product_name text,sku text,tracking_mode text,
  on_hand numeric,reserved numeric,available numeric,damaged numeric,quarantine numeric,in_transit_in numeric,in_transit_out numeric,average_cost numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  perform private.warehouse_v485_permission(p_tenant_id,false);
  return query
  select l.id,l.location_code,l.name,b.variant_id,p.name,pv.sku,private.v483_tracking_mode(p_tenant_id,b.variant_id),
    b.quantity,b.reserved_quantity,greatest(b.quantity-b.reserved_quantity-b.damaged_quantity-b.quarantine_quantity,0),b.damaged_quantity,b.quarantine_quantity,
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0)) from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.to_location_id=l.id and i.variant_id=b.variant_id and t.status in('dispatched','in_transit')),0),
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0)) from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.from_location_id=l.id and i.variant_id=b.variant_id and t.status in('dispatched','in_transit')),0),b.average_cost
  from public.location_stock_balances b
  join public.business_locations l on l.id=b.location_id and l.tenant_id=b.tenant_id
  join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
  join public.products p on p.id=pv.product_id
  where b.tenant_id=p_tenant_id and l.active and (l.hierarchy_role='warehouse' or l.location_type='warehouse')
    and (p_location_id is null or l.id=p_location_id)
    and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
  order by l.name,p.name,pv.sku
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end$$;
grant execute on function public.warehouse_inventory_v485(uuid,uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(150,'4.8.5','Warehouse & Transfers','Transfer list/detail/history, available serial/batch allocation options, warehouse stock summary and in-transit inventory visibility.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 150 transfer history/warehouse inventory applied' as status;

-- ============================================================================
-- 151_v485_stock_count_trace_reconciliation.sql
-- ============================================================================
-- THQ ERP V4.8.5 — trace-aware physical stock count.
begin;

create or replace function public.inventory_stock_count_snapshot_v485(
  p_tenant_id uuid,p_location_id uuid,p_query text default ''
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';v_mode text;v_tracking jsonb;
begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'view');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  for r in
    select b.variant_id,p.name product_name,pv.sku,coalesce(b.quantity,0) system_quantity,coalesce(b.reserved_quantity,0) reserved_quantity,
      coalesce(b.damaged_quantity,0) damaged_quantity,coalesce(b.quarantine_quantity,0) quarantine_quantity
    from public.location_stock_balances b
    join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
    join public.products p on p.id=pv.product_id
    where b.tenant_id=p_tenant_id and b.location_id=p_location_id and p.item_type='stock'
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
    order by p.name,pv.sku
  loop
    v_mode:=private.v483_tracking_mode(p_tenant_id,r.variant_id);
    if v_mode='serial' then
      select jsonb_build_object('serial_numbers',coalesce(jsonb_agg(jsonb_build_object('serial_number',s.serial_number,'status',s.status) order by s.serial_number),'[]'::jsonb)) into v_tracking
      from public.inventory_serials_v483 s
      where s.tenant_id=p_tenant_id and s.variant_id=r.variant_id and s.current_location_id=p_location_id and s.status in('in_stock','quarantine');
    elsif v_mode='batch' then
      select jsonb_build_object('batches',coalesce(jsonb_agg(jsonb_build_object(
        'batch_id',b.id,'batch_number',b.batch_number,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
        'quantity',bb.quantity,'damaged_quantity',coalesce(bb.damaged_quantity,0),'reserved_quantity',coalesce(bb.reserved_quantity,0)
      ) order by (b.expiry_on is null),b.expiry_on,b.batch_number),'[]'::jsonb)) into v_tracking
      from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
      where b.tenant_id=p_tenant_id and b.variant_id=r.variant_id and bb.location_id=p_location_id and (bb.quantity<>0 or coalesce(bb.damaged_quantity,0)<>0 or coalesce(bb.reserved_quantity,0)<>0);
    else
      v_tracking:='{}'::jsonb;
    end if;
    return next jsonb_build_object(
      'variant_id',r.variant_id,'product_name',r.product_name,'sku',r.sku,'tracking_mode',v_mode,
      'system_quantity',r.system_quantity,'reserved_quantity',r.reserved_quantity,'damaged_quantity',r.damaged_quantity,'quarantine_quantity',r.quarantine_quantity,
      'available_quantity',greatest(r.system_quantity-r.reserved_quantity-r.damaged_quantity-r.quarantine_quantity,0),
      'count_blocked',r.reserved_quantity>0,'tracking',coalesce(v_tracking,'{}'::jsonb)
    );
  end loop;
end$$;
grant execute on function public.inventory_stock_count_snapshot_v485(uuid,uuid,text) to authenticated;

create or replace function public.inventory_stock_count_post_v485(
  p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_existing jsonb;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_variant uuid;v_mode text;v_system numeric;v_reserved numeric;v_damage numeric;v_quarantine numeric;
  v_counted numeric;v_delta numeric;v_any_variance boolean:=false;v_tracking jsonb;
  v_serials jsonb;s jsonb;v_serial text;v_serial_row public.inventory_serials_v483%rowtype;v_seen_serial uuid[]:='{}'::uuid[];sr record;v_serial_damage numeric:=0;
  v_batches jsonb;b jsonb;v_batch_id uuid;v_batch_no text;v_batch_qty numeric;v_batch_damage numeric;v_old_qty numeric;v_old_damage numeric;v_old_reserved numeric;
  v_batch_total numeric;v_batch_damage_total numeric;v_seen_batch uuid[]:='{}'::uuid[];br record;v_mfg date;v_exp date;v_event_qty numeric;v_require_expiry boolean:=false;
  v_result jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'warehouse.stock_count');
    if v_existing is not null then return v_existing;end if;
  end if;
  perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one counted product';end if;

  v_no:='CNT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.stock_count_number_seq')::text,6,'0');
  insert into public.stock_counts(id,tenant_id,location_id,count_number,status,notes,created_by,request_key,reconciliation_status,updated_at)
  values(v_id,p_tenant_id,p_location_id,v_no,'draft',nullif(trim(coalesce(p_notes,'')),''),auth.uid(),nullif(trim(coalesce(p_request_id,'')),''),'pending',now());

  for x in select value from jsonb_array_elements(p_items) loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    if v_variant is null or not exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.tenant_id=p_tenant_id and pv.id=v_variant and p.item_type='stock') then raise exception 'Stock-count product is invalid';end if;
    insert into public.location_stock_balances(tenant_id,location_id,variant_id) values(p_tenant_id,p_location_id,v_variant) on conflict do nothing;
    select quantity,reserved_quantity,damaged_quantity,quarantine_quantity into v_system,v_reserved,v_damage,v_quarantine
      from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant for update;
    v_system:=coalesce(v_system,0);v_reserved:=coalesce(v_reserved,0);v_damage:=coalesce(v_damage,0);v_quarantine:=coalesce(v_quarantine,0);
    if v_reserved>0.000001 then raise exception 'Cannot post a stock count while product % has reserved transfer stock. Dispatch/cancel the transfer first.',v_variant;end if;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    v_tracking:=coalesce(x->'tracking','{}'::jsonb);

    if v_mode='none' then
      v_counted:=coalesce(nullif(x->>'counted_quantity','')::numeric,-1);
      if v_counted<0 then raise exception 'Counted quantity cannot be negative';end if;

    elsif v_mode='serial' then
      v_serials:=coalesce(x->'serial_numbers',v_tracking->'serial_numbers','[]'::jsonb);
      if jsonb_typeof(v_serials)<>'array' then raise exception 'Serial count must provide serial_numbers as an array';end if;
      v_seen_serial:='{}'::uuid[];
      for s in select value from jsonb_array_elements(v_serials) loop
        v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
        if v_serial='' then raise exception 'Serial number cannot be blank';end if;
        select * into v_serial_row from public.inventory_serials_v483 where tenant_id=p_tenant_id and lower(trim(serial_number))=lower(v_serial) for update;
        if found then
          if v_serial_row.variant_id<>v_variant then raise exception 'Serial % belongs to another product',v_serial;end if;
          if v_serial_row.id=any(v_seen_serial) then raise exception 'Serial % is duplicated in this stock count',v_serial;end if;
          if v_serial_row.reserved_transfer_id is not null then raise exception 'Serial % is reserved for transfer and cannot be counted now',v_serial;end if;
          if v_serial_row.status in('sold','in_transit','recalled','void') then raise exception 'Serial % has status % and cannot be counted as local stock',v_serial,v_serial_row.status;end if;
          if v_serial_row.current_location_id is not null and v_serial_row.current_location_id<>p_location_id then raise exception 'Serial % is registered at another location',v_serial;end if;
          if v_serial_row.status='missing' or v_serial_row.current_location_id is null then
            update public.inventory_serials_v483 set status='in_stock',current_location_id=p_location_id,updated_at=now() where id=v_serial_row.id;
            insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
            values(p_tenant_id,v_variant,v_serial_row.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-in:'||v_serial_row.id::text,jsonb_build_object('direction','in','reason','serial recovered/found during count'),auth.uid()) on conflict do nothing;
          end if;
          v_seen_serial:=array_append(v_seen_serial,v_serial_row.id);
        else
          insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,notes,created_by)
          values(p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,now(),'Created by physical stock count '||v_no,auth.uid()) returning * into v_serial_row;
          v_seen_serial:=array_append(v_seen_serial,v_serial_row.id);
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,v_serial_row.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-new:'||v_serial_row.id::text,jsonb_build_object('direction','in','reason','unregistered serial found during count'),auth.uid());
        end if;
      end loop;
      for sr in
        select id,serial_number,status from public.inventory_serials_v483
        where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status in('in_stock','quarantine')
          and not (id=any(v_seen_serial)) for update
      loop
        update public.inventory_serials_v483 set status='missing',current_location_id=null,reserved_transfer_id=null,updated_at=now() where id=sr.id;
        insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
        values(p_tenant_id,v_variant,sr.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-out:'||sr.id::text,jsonb_build_object('direction','out','reason','serial missing during count','serial_number',sr.serial_number),auth.uid()) on conflict do nothing;
      end loop;
      v_counted:=coalesce(cardinality(v_seen_serial),0);
      select count(*)::numeric into v_serial_damage from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='quarantine';
      v_tracking:=jsonb_build_object('serial_numbers',v_serials,'counted_serials',v_counted);

    else
      v_batches:=coalesce(x->'batches',v_tracking->'batches','[]'::jsonb);
      if jsonb_typeof(v_batches)<>'array' then raise exception 'Batch count must provide batches as an array';end if;
      v_batch_total:=0;v_batch_damage_total:=0;v_seen_batch:='{}'::uuid[];
      for b in select value from jsonb_array_elements(v_batches) loop
        v_batch_id:=null;v_batch_no:=trim(coalesce(b->>'batch_number',''));
        v_batch_qty:=coalesce(nullif(b->>'quantity','')::numeric,0);v_batch_damage:=coalesce(nullif(b->>'damaged_quantity','')::numeric,0);
        if v_batch_qty<0 or v_batch_damage<0 then raise exception 'Batch counted quantities cannot be negative';end if;
        if nullif(b->>'batch_id','') is not null then v_batch_id:=(b->>'batch_id')::uuid;end if;
        if v_batch_id is not null and not exists(
          select 1 from public.inventory_batches_v483 ib where ib.id=v_batch_id and ib.tenant_id=p_tenant_id and ib.variant_id=v_variant
        ) then raise exception 'Batch does not belong to the selected product/business';end if;
        if v_batch_id is null and v_batch_no<>'' then select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=v_variant and lower(trim(batch_number))=lower(v_batch_no);end if;
        if v_batch_id is null then
          if v_batch_no='' then raise exception 'Batch number is required';end if;
          v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
          select coalesce(require_batch_expiry,false) into v_require_expiry from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant;
          if coalesce(v_require_expiry,false) and v_exp is null then raise exception 'Expiry date is required for batch %',v_batch_no;end if;
          insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,status,notes,created_by)
          values(p_tenant_id,v_variant,v_batch_no,v_mfg,v_exp,'active','Created by physical stock count '||v_no,auth.uid()) returning id into v_batch_id;
        else
          v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
          if exists(
            select 1 from public.inventory_batches_v483 ib where ib.id=v_batch_id
              and ((v_mfg is not null and ib.manufactured_on is distinct from v_mfg) or (v_exp is not null and ib.expiry_on is distinct from v_exp))
          ) then raise exception 'Batch dates conflict with the registered batch';end if;
        end if;
        if v_batch_id=any(v_seen_batch) then raise exception 'The same batch cannot appear twice in a stock count';end if;
        v_seen_batch:=array_append(v_seen_batch,v_batch_id);
        select coalesce(quantity,0),coalesce(damaged_quantity,0),coalesce(reserved_quantity,0) into v_old_qty,v_old_damage,v_old_reserved
          from public.inventory_batch_balances_v483 where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id for update;
        v_old_qty:=coalesce(v_old_qty,0);v_old_damage:=coalesce(v_old_damage,0);v_old_reserved:=coalesce(v_old_reserved,0);
        if v_old_reserved>0.000001 then raise exception 'Batch % is reserved for transfer and cannot be counted now',coalesce(v_batch_no,v_batch_id::text);end if;
        insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
        values(p_tenant_id,v_batch_id,p_location_id,v_batch_qty,v_batch_damage,0,now())
        on conflict(tenant_id,batch_id,location_id) do update set quantity=excluded.quantity,damaged_quantity=excluded.damaged_quantity,reserved_quantity=0,updated_at=now();
        v_event_qty:=abs(v_batch_qty-v_old_qty)+abs(v_batch_damage-v_old_damage);
        if v_event_qty>0.000001 then
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,v_batch_id,'adjustment',v_event_qty,p_location_id,v_no,'stock-count:'||v_id::text||':batch:'||v_batch_id::text,
            jsonb_build_object('before_quantity',v_old_qty,'before_damaged',v_old_damage,'after_quantity',v_batch_qty,'after_damaged',v_batch_damage,'direction',case when v_batch_qty+v_batch_damage>=v_old_qty+v_old_damage then 'in' else 'out' end),auth.uid()) on conflict do nothing;
        end if;
        v_batch_total:=v_batch_total+v_batch_qty;v_batch_damage_total:=v_batch_damage_total+v_batch_damage;
      end loop;
      for br in
        select bb.batch_id,bb.quantity,coalesce(bb.damaged_quantity,0) damaged_quantity,b.batch_number
        from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id and b.tenant_id=bb.tenant_id
        where bb.tenant_id=p_tenant_id and bb.location_id=p_location_id and b.variant_id=v_variant and (bb.quantity<>0 or coalesce(bb.damaged_quantity,0)<>0)
          and not (bb.batch_id=any(v_seen_batch)) for update of bb
      loop
        v_event_qty:=br.quantity+br.damaged_quantity;
        update public.inventory_batch_balances_v483 set quantity=0,damaged_quantity=0,reserved_quantity=0,updated_at=now() where tenant_id=p_tenant_id and batch_id=br.batch_id and location_id=p_location_id;
        if v_event_qty>0.000001 then
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,br.batch_id,'adjustment',v_event_qty,p_location_id,v_no,'stock-count:'||v_id::text||':batch-zero:'||br.batch_id::text,jsonb_build_object('direction','out','reason','batch missing during count','batch_number',br.batch_number),auth.uid()) on conflict do nothing;
        end if;
      end loop;
      update public.inventory_batches_v483 ib set status=case when exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=ib.tenant_id and bb.batch_id=ib.id and bb.quantity+coalesce(bb.damaged_quantity,0)>0) then 'active' else 'exhausted' end,updated_at=now()
      where ib.tenant_id=p_tenant_id and ib.variant_id=v_variant and ib.status in('active','exhausted');
      v_counted:=v_batch_total+v_batch_damage_total;
      v_tracking:=jsonb_build_object('batches',v_batches,'counted_saleable_quantity',v_batch_total,'counted_damaged_quantity',v_batch_damage_total);
    end if;

    v_delta:=v_counted-v_system;
    if abs(v_delta)>0.000001 then v_any_variance:=true;end if;
    insert into public.stock_count_items(count_id,variant_id,system_quantity,counted_quantity,tracking_mode,tracking_payload,system_reserved_quantity,system_damaged_quantity,system_quarantine_quantity,reconciliation_note)
    values(v_id,v_variant,v_system,v_counted,v_mode,coalesce(v_tracking,'{}'::jsonb),v_reserved,v_damage,v_quarantine,
      case when abs(v_delta)<=0.000001 then 'No quantity variance' else 'Ledger adjusted by '||v_delta::text end);

    if abs(v_delta)>0.000001 then
      perform public.inventory_adjust_stock(p_tenant_id,v_variant,v_delta,'Stock count • '||v_no);
      perform private.v4_location_stock_apply(p_tenant_id,p_location_id,v_variant,v_delta,'stock_count','stock_count',v_id,v_no,'Physical stock reconciliation',p_device_id,true);
    end if;
    if v_mode='serial' then
      update public.location_stock_balances set damaged_quantity=coalesce(v_serial_damage,0),quarantine_quantity=0,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant;
    elsif v_mode='batch' then
      update public.location_stock_balances set damaged_quantity=coalesce(v_batch_damage_total,0),quarantine_quantity=0,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant;
    end if;
  end loop;

  update public.stock_counts set status='posted',posted_by=auth.uid(),posted_at=now(),reconciliation_status=case when v_any_variance then 'variance' else 'reconciled' end,updated_at=now() where id=v_id;
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_count',v_id::text,'posted');
  v_result:=jsonb_build_object('success',true,'count_id',v_id,'count_number',v_no,'status','posted','had_variance',v_any_variance);
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then v_result:=private.v47_request_complete(p_tenant_id,p_request_id,'warehouse.stock_count',v_result);end if;
  return v_result;
end$$;
grant execute on function public.inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text) to authenticated;

-- Compatibility: the pre-v4.8.5 name now uses the trace-aware count engine.
create or replace function public.inventory_stock_count_post_v483(p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text,p_device_id uuid)
returns jsonb language sql security definer set search_path=public,private,pg_temp as $$
  select public.inventory_stock_count_post_v485($1,$2,$3,$4,$5,null)
$$;
grant execute on function public.inventory_stock_count_post_v483(uuid,uuid,jsonb,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(151,'4.8.5','Warehouse & Transfers','Physical stock count now reconciles aggregate inventory together with exact serial lists or per-batch saleable/damaged quantities; reserved transfer stock blocks unsafe counting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 151 trace-aware stock count applied' as status;

-- ============================================================================
-- 152_v485_reconciliation_api_contract.sql
-- ============================================================================
-- THQ ERP V4.8.5 — stock reconciliation/reporting and THQ API contract.
begin;

create or replace function public.stock_counts_list_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_from date default null,p_to date default null,p_limit integer default 500
) returns table(
  id uuid,count_number text,location_id uuid,location_name text,status text,reconciliation_status text,notes text,
  line_count bigint,total_system_quantity numeric,total_counted_quantity numeric,total_variance numeric,created_at timestamptz,posted_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  return query
  select c.id,c.count_number,c.location_id,l.location_code||' • '||l.name,c.status,c.reconciliation_status,c.notes,
    count(i.id),coalesce(sum(i.system_quantity),0),coalesce(sum(i.counted_quantity),0),coalesce(sum(i.variance),0),c.created_at,c.posted_at
  from public.stock_counts c join public.business_locations l on l.id=c.location_id left join public.stock_count_items i on i.count_id=c.id
  where c.tenant_id=p_tenant_id and (p_location_id is null or c.location_id=p_location_id)
    and (p_from is null or c.created_at::date>=p_from) and (p_to is null or c.created_at::date<=p_to)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,c.location_id,'view'))
  group by c.id,l.location_code,l.name order by c.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.stock_counts_list_v485(uuid,uuid,date,date,integer) to authenticated;

create or replace function public.stock_count_detail_v485(p_tenant_id uuid,p_count_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;
begin
  select location_id into v_loc from public.stock_counts where tenant_id=p_tenant_id and id=p_count_id;
  if v_loc is null then raise exception 'Stock count not found';end if;
  perform private.v4_location_access(p_tenant_id,v_loc,'view');
  select jsonb_build_object(
    'count',to_jsonb(c)||jsonb_build_object('location_name',l.location_code||' • '||l.name),
    'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku) order by p.name,pv.sku)
      from public.stock_count_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.count_id=c.id),'[]'::jsonb)
  ) into v from public.stock_counts c join public.business_locations l on l.id=c.location_id where c.tenant_id=p_tenant_id and c.id=p_count_id;
  return v;
end$$;
grant execute on function public.stock_count_detail_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_stock_reconciliation_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_only_variance boolean default false,p_limit integer default 2000
) returns table(
  location_id uuid,location_name text,variant_id uuid,product_name text,sku text,tracking_mode text,
  location_quantity numeric,tracked_quantity numeric,reserved_quantity numeric,damaged_quantity numeric,quarantine_quantity numeric,available_quantity numeric,
  company_stock_quantity numeric,all_locations_quantity numeric,tracked_reconciled boolean,company_reconciled boolean,
  latest_count_number text,latest_counted_quantity numeric,latest_count_variance numeric,latest_count_at timestamptz,reconciliation_status text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with base as (
    select b.location_id,l.location_code||' • '||l.name location_name,b.variant_id,p.name product_name,pv.sku,
      private.v483_tracking_mode(p_tenant_id,b.variant_id) tracking_mode,b.quantity,b.reserved_quantity,b.damaged_quantity,b.quarantine_quantity,
      coalesce((select sum(sb.quantity) from public.stock_balances sb where sb.tenant_id=p_tenant_id and sb.variant_id=b.variant_id),0) company_qty,
      coalesce((select sum(lb.quantity) from public.location_stock_balances lb where lb.tenant_id=p_tenant_id and lb.variant_id=b.variant_id),0) locations_qty
    from public.location_stock_balances b join public.business_locations l on l.id=b.location_id join public.product_variants pv on pv.id=b.variant_id join public.products p on p.id=pv.product_id
    where b.tenant_id=p_tenant_id and (p_location_id is null or b.location_id=p_location_id)
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
      and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,b.location_id,'view'))
  ), calc as (
    select base.*,
      case when base.tracking_mode='none' then base.quantity else private.v483_location_tracked_quantity(p_tenant_id,base.variant_id,base.location_id,base.tracking_mode) end tracked_qty,
      lc.count_number latest_count_number,li.counted_quantity latest_counted_quantity,li.variance latest_count_variance,lc.posted_at latest_count_at
    from base
    left join lateral (
      select c.id,c.count_number,c.posted_at from public.stock_counts c join public.stock_count_items ci on ci.count_id=c.id
      where c.tenant_id=p_tenant_id and c.location_id=base.location_id and ci.variant_id=base.variant_id and c.status='posted'
      order by c.posted_at desc nulls last,c.created_at desc limit 1
    ) lc on true
    left join public.stock_count_items li on li.count_id=lc.id and li.variant_id=base.variant_id
  )
  select calc.location_id,calc.location_name,calc.variant_id,calc.product_name,calc.sku,calc.tracking_mode,
    calc.quantity,calc.tracked_qty,calc.reserved_quantity,calc.damaged_quantity,calc.quarantine_quantity,
    greatest(calc.quantity-calc.reserved_quantity-calc.damaged_quantity-calc.quarantine_quantity,0),calc.company_qty,calc.locations_qty,
    abs(calc.quantity-calc.tracked_qty)<=0.000001,abs(calc.company_qty-calc.locations_qty)<=0.000001,
    calc.latest_count_number,calc.latest_counted_quantity,calc.latest_count_variance,calc.latest_count_at,
    case
      when abs(calc.company_qty-calc.locations_qty)>0.000001 then 'COMPANY/LOCATION MISMATCH'
      when calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001 then 'TRACKING MISMATCH'
      when calc.reserved_quantity>0.000001 then 'RESERVED / PENDING TRANSFER'
      when calc.latest_count_variance is not null and abs(calc.latest_count_variance)>0.000001 then 'COUNT VARIANCE RECONCILED'
      else 'OK'
    end
  from calc
  where not coalesce(p_only_variance,false)
     or abs(calc.company_qty-calc.locations_qty)>0.000001
     or (calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001)
     or abs(coalesce(calc.latest_count_variance,0))>0.000001
  order by case when abs(calc.company_qty-calc.locations_qty)>0.000001 or (calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001) then 0 else 1 end,calc.location_name,calc.product_name,calc.sku
  limit greatest(1,least(coalesce(p_limit,2000),10000));
end$$;
grant execute on function public.inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer) to authenticated;

create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
  'resources',jsonb_build_array(
    'sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
    'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
    'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
    'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary'
  ),
  'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3',
  'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','transfer_stock_event','dispatch_receive','stock_count_engine','trace_aware',
  'stock_receipt_event','goods_receipt','supplier_liability_event','purchase_invoice','mobile_ready',true
 )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(152,'4.8.5','Warehouse & Transfers','Stock-count history/detail, company-vs-location and serial/batch reconciliation reporting, and THQ API v1 warehouse/transfer/count resources.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 152 reconciliation/API contract applied' as status;

-- ============================================================================
-- 153_v485_release_contract.sql
-- ============================================================================
-- THQ ERP V4.8.5 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP',
  'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
  'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
  'minimum_app_version','4.8.5','release','Warehouse & Transfers','api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v485_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regclass('public.stock_transfer_allocations_v485') is null then v_missing:=array_append(v_missing,'stock_transfer_allocations_v485');end if;
  if to_regclass('public.stock_transfer_history_v485') is null then v_missing:=array_append(v_missing,'stock_transfer_history_v485');end if;
  if to_regprocedure('public.warehouse_locations_v485(uuid)') is null then v_missing:=array_append(v_missing,'warehouse_locations_v485');end if;
  if to_regprocedure('public.warehouse_inventory_v485(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'warehouse_inventory_v485');end if;
  if to_regprocedure('public.inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_request_v485');end if;
  if to_regprocedure('public.inventory_transfer_decide_v485(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_decide_v485');end if;
  if to_regprocedure('public.inventory_transfer_cancel_v485(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_cancel_v485');end if;
  if to_regprocedure('public.inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_dispatch_v485');end if;
  if to_regprocedure('public.inventory_transfer_receive_v485(uuid,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_receive_v485');end if;
  if to_regprocedure('public.inventory_transfers_list_v485(uuid,uuid,text,text,integer)') is null then v_missing:=array_append(v_missing,'inventory_transfers_list_v485');end if;
  if to_regprocedure('public.inventory_transfer_detail_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_detail_v485');end if;
  if to_regprocedure('public.inventory_transfer_history_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_history_v485');end if;
  if to_regprocedure('public.inventory_transfer_tracking_options_v485(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_tracking_options_v485');end if;
  if to_regprocedure('public.inventory_stock_count_snapshot_v485(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_stock_count_snapshot_v485');end if;
  if to_regprocedure('public.inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_stock_count_post_v485');end if;
  if to_regprocedure('public.stock_counts_list_v485(uuid,uuid,date,date,integer)') is null then v_missing:=array_append(v_missing,'stock_counts_list_v485');end if;
  if to_regprocedure('public.stock_count_detail_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'stock_count_detail_v485');end if;
  if to_regprocedure('public.inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer)') is null then v_missing:=array_append(v_missing,'inventory_stock_reconciliation_v485');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.5','migration_no',153,'api_version','v1',
    'warehouse_locations',true,'stock_transfer_request',true,'transfer_approval',true,'dispatch',true,'in_transit',true,'receive',true,
    'transfer_history',true,'serial_batch_transfer',true,'stock_count',true,'stock_reconciliation',true
  );
end$$;
grant execute on function public.thq_v485_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(153,'4.8.5','Warehouse & Transfers','Warehouse locations, tracked-safe stock transfer request/approval/dispatch/in-transit/receive/history, physical stock counts and stock reconciliation.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 153 release contract applied' as status;

