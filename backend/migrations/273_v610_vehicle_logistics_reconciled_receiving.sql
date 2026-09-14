-- THQ ERP v6.1 - Vehicle Logistics reconciled receiving
-- The live flexi-erp-dev database received this feature through smaller
-- migrations because the connector limited large DDL payloads.
-- This is the consolidated source-control migration for clean environments.

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
);

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
  details jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (receipt_id, transfer_item_id),
  check (
    abs(
      (good_quantity + damaged_quantity + missing_quantity + returned_quantity)
      - dispatched_quantity
    ) <= 0.000001
  )
);

create index if not exists idx_transport_logistics_receipts_trip
  on public.transport_logistics_receipts(tenant_id, trip_id, received_at desc);
create index if not exists idx_transport_logistics_receipts_transfer
  on public.transport_logistics_receipts(tenant_id, stock_transfer_id);
create index if not exists idx_transport_logistics_receipt_lines_receipt
  on public.transport_logistics_receipt_lines(tenant_id, receipt_id);

alter table public.transport_logistics_trips enable row level security;
alter table public.transport_logistics_trip_documents enable row level security;
alter table public.transport_logistics_trip_events enable row level security;
alter table public.transport_logistics_receipts enable row level security;
alter table public.transport_logistics_receipt_lines enable row level security;

revoke select, insert, update, delete, truncate, references, trigger
  on public.transport_logistics_receipts from anon, authenticated;
revoke select, insert, update, delete, truncate, references, trigger
  on public.transport_logistics_receipt_lines from anon, authenticated;


create or replace function public.logistics_transfer_receipt_context_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $function$
declare
  t public.transport_logistics_trips%rowtype;
  st public.stock_transfers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select * into t from public.transport_logistics_trips
  where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Trip not found'; end if;

  if not exists (
    select 1 from public.transport_logistics_trip_documents d
    where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id
      and d.stock_transfer_id=p_transfer_id and d.active
  ) then raise exception 'Transfer is not linked to this trip'; end if;

  select * into st from public.stock_transfers
  where tenant_id=p_tenant_id and id=p_transfer_id;
  if not found then raise exception 'Transfer not found'; end if;

  if not (
    private.erp_document_scope_allowed(p_tenant_id,st.from_location_id,null,'view')
    or private.erp_document_scope_allowed(p_tenant_id,st.to_location_id,null,'view')
  ) then raise exception 'Location access denied'; end if;

  return jsonb_build_object(
    'trip_id',p_trip_id,
    'trip_number',t.trip_number,
    'trip_status',t.status,
    'transfer_id',st.id,
    'transfer_number',st.transfer_number,
    'transfer_status',case when st.status='dispatched' then 'in_transit' else st.status end,
    'from_location_id',st.from_location_id,
    'to_location_id',st.to_location_id,
    'items',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',i.id,
          'variant_id',i.variant_id,
          'product_name',p.name,
          'sku',pv.sku,
          'tracking_mode',i.tracking_mode,
          'dispatched_quantity',i.dispatched_quantity,
          'allocations',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id',a.id,
                'quantity',a.quantity,
                'status',a.status,
                'serial_id',a.serial_id,
                'serial_number',s.serial_number,
                'batch_id',a.batch_id,
                'batch_number',b.batch_number
              ) order by coalesce(s.serial_number,b.batch_number,a.id::text)
            )
            from public.stock_transfer_allocations_v485 a
            left join public.inventory_serials_v483 s on s.id=a.serial_id
            left join public.inventory_batches_v483 b on b.id=a.batch_id
            where a.transfer_item_id=i.id and a.status='in_transit'
          ),'[]'::jsonb)
        ) order by p.name,pv.sku
      )
      from public.stock_transfer_items i
      join public.product_variants pv on pv.id=i.variant_id
      join public.products p on p.id=pv.product_id
      where i.transfer_id=st.id
    ),'[]'::jsonb)
  );
end
$function$;

revoke execute on function public.logistics_transfer_receipt_context_v1(uuid,uuid,uuid)
  from public, anon;
grant execute on function public.logistics_transfer_receipt_context_v1(uuid,uuid,uuid)
  to authenticated, service_role;

create or replace function private.v610_logistics_receive_line(
  p_tenant_id uuid,
  p_receipt_id uuid,
  p_transfer_id uuid,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_transfer_number text,
  p_device_id uuid,
  p_transfer_item_id uuid,
  p_line jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $function$
declare
  r public.stock_transfer_items%rowtype;
  a public.stock_transfer_allocations_v485%rowtype;
  v_mode text;
  v_good numeric := 0;
  v_damaged numeric := 0;
  v_missing numeric := 0;
  v_returned numeric := 0;
  v_agood numeric;
  v_adamaged numeric;
  v_amissing numeric;
  v_areturned numeric;
  v_outcome text;
  v_alloc_input jsonb;
  v_details jsonb := '[]'::jsonb;
  v_alloc_count integer;
  v_input_count integer;
  v_serial_number text;
  v_batch_number text;
begin
  select * into r
  from public.stock_transfer_items
  where id=p_transfer_item_id and transfer_id=p_transfer_id
  for update;
  if not found then raise exception 'Transfer line not found'; end if;
  if r.dispatched_quantity<=0 then raise exception 'Transfer line % was not dispatched',r.id; end if;

  v_mode:=coalesce(r.tracking_mode,'none');

  if v_mode='none' then
    v_good:=coalesce(nullif(p_line->>'good_quantity','')::numeric,0);
    v_damaged:=coalesce(nullif(p_line->>'damaged_quantity','')::numeric,0);
    v_missing:=coalesce(nullif(p_line->>'missing_quantity','')::numeric,0);
    v_returned:=coalesce(nullif(p_line->>'returned_quantity','')::numeric,0);

    if least(v_good,v_damaged,v_missing,v_returned)<0 then
      raise exception 'Receipt quantities cannot be negative for transfer line %',r.id;
    end if;
    if abs((v_good+v_damaged+v_missing+v_returned)-r.dispatched_quantity)>0.000001 then
      raise exception 'Receipt quantities must equal dispatched quantity for transfer line %',r.id;
    end if;

  elsif v_mode in ('serial','batch') then
    if jsonb_typeof(coalesce(p_line->'allocations','[]'::jsonb))<>'array' then
      raise exception 'Tracked allocations must be a JSON array for transfer line %',r.id;
    end if;

    select count(*) into v_alloc_count
    from public.stock_transfer_allocations_v485
    where transfer_item_id=r.id and status='in_transit';

    v_input_count:=jsonb_array_length(coalesce(p_line->'allocations','[]'::jsonb));
    if v_input_count<>v_alloc_count then
      raise exception 'Every tracked allocation must be included for transfer line %',r.id;
    end if;

    if exists(
      select 1
      from (
        select x->>'allocation_id' as allocation_id,count(*) as c
        from jsonb_array_elements(coalesce(p_line->'allocations','[]'::jsonb)) x
        group by x->>'allocation_id'
        having count(*)<>1
      ) q
    ) then
      raise exception 'Each tracked allocation must appear exactly once for transfer line %',r.id;
    end if;

    for a in
      select *
      from public.stock_transfer_allocations_v485
      where transfer_item_id=r.id and status='in_transit'
      order by id
      for update
    loop
      select x into v_alloc_input
      from jsonb_array_elements(p_line->'allocations') x
      where x->>'allocation_id'=a.id::text
      limit 1;
      if v_alloc_input is null then
        raise exception 'Tracked allocation % is missing from receipt payload',a.id;
      end if;

      v_agood:=0;v_adamaged:=0;v_amissing:=0;v_areturned:=0;
      v_serial_number:=null;v_batch_number:=null;

      if a.serial_id is not null then
        v_outcome:=lower(trim(coalesce(v_alloc_input->>'outcome','')));
        if v_outcome not in ('good','damaged','missing','returned') then
          raise exception 'Serial allocation % requires outcome good, damaged, missing or returned',a.id;
        end if;

        if v_outcome='good' then v_agood:=a.quantity;
        elsif v_outcome='damaged' then v_adamaged:=a.quantity;
        elsif v_outcome='missing' then v_amissing:=a.quantity;
        else v_areturned:=a.quantity;
        end if;

        select serial_number into v_serial_number
        from public.inventory_serials_v483
        where id=a.serial_id
          and tenant_id=p_tenant_id
          and variant_id=r.variant_id
          and status='in_transit'
        for update;
        if v_serial_number is null then
          raise exception 'In-transit serial allocation is missing or already resolved: %',a.id;
        end if;

        if v_agood>0 then
          update public.inventory_serials_v483
          set status='in_stock',current_location_id=p_to_location_id,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;

          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.serial_id,'transfer_in',a.quantity,p_to_location_id,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':good',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','good','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;

        elsif v_adamaged>0 then
          update public.inventory_serials_v483
          set status='quarantine',current_location_id=p_to_location_id,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;

          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.serial_id,'quarantine',a.quantity,p_to_location_id,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':damaged',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','damaged','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;

        elsif v_amissing>0 then
          update public.inventory_serials_v483
          set status='missing',current_location_id=null,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;

          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.serial_id,'adjustment',a.quantity,null,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':missing',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','missing','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;

        else
          update public.inventory_serials_v483
          set status='in_stock',current_location_id=p_from_location_id,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;

          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.serial_id,'transfer_in',a.quantity,p_from_location_id,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':returned',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','returned_to_origin','from_location_id',p_to_location_id,'to_location_id',p_from_location_id),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;
        end if;

      elsif a.batch_id is not null then
        v_agood:=coalesce(nullif(v_alloc_input->>'good_quantity','')::numeric,0);
        v_adamaged:=coalesce(nullif(v_alloc_input->>'damaged_quantity','')::numeric,0);
        v_amissing:=coalesce(nullif(v_alloc_input->>'missing_quantity','')::numeric,0);
        v_areturned:=coalesce(nullif(v_alloc_input->>'returned_quantity','')::numeric,0);

        if least(v_agood,v_adamaged,v_amissing,v_areturned)<0 then
          raise exception 'Batch quantities cannot be negative for allocation %',a.id;
        end if;
        if abs((v_agood+v_adamaged+v_amissing+v_areturned)-a.quantity)>0.000001 then
          raise exception 'Batch quantities must equal dispatched allocation quantity for allocation %',a.id;
        end if;

        select batch_number into v_batch_number
        from public.inventory_batches_v483
        where id=a.batch_id and tenant_id=p_tenant_id and variant_id=r.variant_id
        for update;
        if v_batch_number is null then raise exception 'Batch allocation is missing: %',a.id; end if;

        if v_agood+v_adamaged>0 then
          insert into public.inventory_batch_balances_v483(
            tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at
          ) values(
            p_tenant_id,a.batch_id,p_to_location_id,v_agood+v_adamaged,v_adamaged,0,now()
          )
          on conflict(tenant_id,batch_id,location_id) do update
          set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,
              damaged_quantity=public.inventory_batch_balances_v483.damaged_quantity+excluded.damaged_quantity,
              updated_at=now();

          update public.inventory_batches_v483
          set status='active',updated_at=now()
          where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';

          if v_agood>0 then
            insert into public.inventory_trace_events_v483(
              tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
            ) values(
              p_tenant_id,r.variant_id,a.batch_id,'transfer_in',v_agood,p_to_location_id,p_transfer_number,
              'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':good',
              jsonb_build_object('receipt_id',p_receipt_id,'outcome','good','batch_number',v_batch_number),
              p_transfer_id,r.id,auth.uid()
            ) on conflict do nothing;
          end if;

          if v_adamaged>0 then
            insert into public.inventory_trace_events_v483(
              tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
            ) values(
              p_tenant_id,r.variant_id,a.batch_id,'quarantine',v_adamaged,p_to_location_id,p_transfer_number,
              'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':damaged',
              jsonb_build_object('receipt_id',p_receipt_id,'outcome','damaged','batch_number',v_batch_number),
              p_transfer_id,r.id,auth.uid()
            ) on conflict do nothing;
          end if;
        end if;

        if v_areturned>0 then
          insert into public.inventory_batch_balances_v483(
            tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at
          ) values(
            p_tenant_id,a.batch_id,p_from_location_id,v_areturned,0,0,now()
          )
          on conflict(tenant_id,batch_id,location_id) do update
          set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,
              updated_at=now();

          update public.inventory_batches_v483
          set status='active',updated_at=now()
          where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';

          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.batch_id,'transfer_in',v_areturned,p_from_location_id,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':returned',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','returned_to_origin','batch_number',v_batch_number),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;
        end if;

        if v_amissing>0 then
          insert into public.inventory_trace_events_v483(
            tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
          ) values(
            p_tenant_id,r.variant_id,a.batch_id,'adjustment',v_amissing,null,p_transfer_number,
            'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':missing',
            jsonb_build_object('receipt_id',p_receipt_id,'outcome','missing','batch_number',v_batch_number),
            p_transfer_id,r.id,auth.uid()
          ) on conflict do nothing;
        end if;

        v_outcome:=case
          when ((case when v_agood>0 then 1 else 0 end)
               +(case when v_adamaged>0 then 1 else 0 end)
               +(case when v_amissing>0 then 1 else 0 end)
               +(case when v_areturned>0 then 1 else 0 end))>1 then 'mixed'
          when v_agood>0 then 'good'
          when v_adamaged>0 then 'damaged'
          when v_amissing>0 then 'missing'
          else 'returned'
        end;
      else
        raise exception 'Tracked allocation % has no serial or batch',a.id;
      end if;

      v_good:=v_good+v_agood;
      v_damaged:=v_damaged+v_adamaged;
      v_missing:=v_missing+v_amissing;
      v_returned:=v_returned+v_areturned;

      v_details:=v_details||jsonb_build_array(
        jsonb_build_object(
          'allocation_id',a.id,
          'quantity',a.quantity,
          'serial_id',a.serial_id,
          'serial_number',v_serial_number,
          'batch_id',a.batch_id,
          'batch_number',v_batch_number,
          'outcome',case when a.serial_id is not null then v_outcome else v_outcome end,
          'good_quantity',v_agood,
          'damaged_quantity',v_adamaged,
          'missing_quantity',v_amissing,
          'returned_quantity',v_areturned
        )
      );
    end loop;

    if abs((v_good+v_damaged+v_missing+v_returned)-r.dispatched_quantity)>0.000001 then
      raise exception 'Tracked receipt does not reconcile to dispatched quantity for transfer line %',r.id;
    end if;
  else
    raise exception 'Unsupported tracking mode % for transfer line %',v_mode,r.id;
  end if;

  if v_good+v_damaged>0 then
    perform public.inventory_location_assign_v4(p_tenant_id,p_to_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(
      p_tenant_id,p_to_location_id,r.variant_id,v_good+v_damaged,
      'transfer_in','stock_transfer',p_transfer_id,p_transfer_number,
      case when v_damaged>0
        then 'Logistics receipt: good '||v_good::text||', damaged '||v_damaged::text
        else 'Logistics receipt'
      end,
      p_device_id,false
    );

    if v_damaged>0 then
      update public.location_stock_balances
      set damaged_quantity=damaged_quantity+v_damaged,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_to_location_id and variant_id=r.variant_id;
    end if;
  end if;

  if v_returned>0 then
    perform public.inventory_location_assign_v4(p_tenant_id,p_from_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(
      p_tenant_id,p_from_location_id,r.variant_id,v_returned,
      'transfer_in','stock_transfer',p_transfer_id,p_transfer_number,
      'Returned to origin during logistics receipt reconciliation',
      p_device_id,false
    );
  end if;

  insert into public.transport_logistics_receipt_lines(
    tenant_id,receipt_id,transfer_item_id,variant_id,tracking_mode,dispatched_quantity,
    good_quantity,damaged_quantity,missing_quantity,returned_quantity,details
  ) values(
    p_tenant_id,p_receipt_id,r.id,r.variant_id,v_mode,r.dispatched_quantity,
    v_good,v_damaged,v_missing,v_returned,v_details
  );

  update public.stock_transfer_items
  set received_quantity=r.dispatched_quantity,updated_at=now()
  where id=r.id;

  return jsonb_build_object(
    'transfer_item_id',r.id,
    'good_quantity',v_good,
    'damaged_quantity',v_damaged,
    'missing_quantity',v_missing,
    'returned_quantity',v_returned
  );
end
$function$;

create or replace function public.logistics_trip_receive_transfer_reconciled_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_transfer_id uuid,
  p_device_id uuid default null,
  p_lines jsonb default '[]'::jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $function$
declare
  t public.transport_logistics_trips%rowtype;
  st public.stock_transfers%rowtype;
  rr public.transport_logistics_receipts%rowtype;
  r public.stock_transfer_items%rowtype;
  v_line jsonb;
  v_result jsonb;
  v_receipt_id uuid := gen_random_uuid();
  v_receipt_number text;
  v_good numeric := 0;
  v_damaged numeric := 0;
  v_missing numeric := 0;
  v_returned numeric := 0;
  v_all_received boolean;
  v_event_type text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select * into t
  from public.transport_logistics_trips
  where id=p_trip_id and tenant_id=p_tenant_id
  for update;
  if not found then raise exception 'Trip not found'; end if;

  select * into rr
  from public.transport_logistics_receipts
  where tenant_id=p_tenant_id and trip_id=p_trip_id and stock_transfer_id=p_transfer_id;
  if found then
    return jsonb_build_object(
      'success',true,'idempotent',true,'status','received',
      'trip_id',p_trip_id,'transfer_id',p_transfer_id,
      'receipt_id',rr.id,'receipt_number',rr.receipt_number,
      'good_quantity',rr.good_quantity,'damaged_quantity',rr.damaged_quantity,
      'missing_quantity',rr.missing_quantity,'returned_quantity',rr.returned_quantity
    );
  end if;

  if t.status<>'arrived' then raise exception 'Trip must be ARRIVED before receiving stock'; end if;

  if not exists(
    select 1 from public.transport_logistics_trip_documents d
    where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id
      and d.stock_transfer_id=p_transfer_id and d.active
  ) then raise exception 'Transfer is not linked to this trip'; end if;

  select * into st
  from public.stock_transfers
  where tenant_id=p_tenant_id and id=p_transfer_id
  for update;
  if not found then raise exception 'Transfer not found'; end if;

  perform private.v4_location_access(p_tenant_id,st.to_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'inventory.transfer')
     and not private.erp_has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Stock transfer permission required';
  end if;

  if st.status not in ('in_transit','dispatched') then
    raise exception 'Only in-transit transfers can be reconciled';
  end if;

  if jsonb_typeof(coalesce(p_lines,'[]'::jsonb))<>'array' then
    raise exception 'Receipt lines must be a JSON array';
  end if;

  if jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) <>
     (select count(*) from public.stock_transfer_items where transfer_id=p_transfer_id) then
    raise exception 'Every dispatched transfer line must be included exactly once';
  end if;

  if exists(
    select 1
    from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) x
    where nullif(x->>'transfer_item_id','') is null
       or not exists(
         select 1 from public.stock_transfer_items i
         where i.transfer_id=p_transfer_id and i.id::text=x->>'transfer_item_id'
       )
  ) then raise exception 'Receipt contains an invalid transfer item'; end if;

  if exists(
    select 1
    from (
      select x->>'transfer_item_id' as item_id,count(*) as c
      from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) x
      group by x->>'transfer_item_id'
      having count(*)<>1
    ) q
  ) then raise exception 'Each transfer item must appear exactly once'; end if;

  v_receipt_number:='RCV-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_receipt_id::text,'-',''),1,8));

  insert into public.transport_logistics_receipts(
    id,tenant_id,trip_id,stock_transfer_id,receipt_number,status,note
  ) values(
    v_receipt_id,p_tenant_id,p_trip_id,p_transfer_id,v_receipt_number,'finalized',
    nullif(trim(coalesce(p_note,'')),'')
  );

  for r in
    select * from public.stock_transfer_items
    where transfer_id=p_transfer_id
    order by id
  loop
    select x into v_line
    from jsonb_array_elements(p_lines) x
    where x->>'transfer_item_id'=r.id::text
    limit 1;

    v_result:=private.v610_logistics_receive_line(
      p_tenant_id,v_receipt_id,p_transfer_id,st.from_location_id,st.to_location_id,
      st.transfer_number,p_device_id,r.id,v_line
    );

    v_good:=v_good+coalesce((v_result->>'good_quantity')::numeric,0);
    v_damaged:=v_damaged+coalesce((v_result->>'damaged_quantity')::numeric,0);
    v_missing:=v_missing+coalesce((v_result->>'missing_quantity')::numeric,0);
    v_returned:=v_returned+coalesce((v_result->>'returned_quantity')::numeric,0);
  end loop;

  update public.stock_transfer_allocations_v485
  set status='received',received_at=now(),updated_at=now()
  where tenant_id=p_tenant_id and transfer_id=p_transfer_id and status='in_transit';

  update public.transport_logistics_receipts
  set good_quantity=v_good,damaged_quantity=v_damaged,
      missing_quantity=v_missing,returned_quantity=v_returned
  where id=v_receipt_id;

  update public.stock_transfers
  set status='received',received_by=auth.uid(),received_at=now(),
      receive_note=nullif(trim(coalesce(p_note,'')),''),
      updated_at=now()
  where id=p_transfer_id;

  v_event_type:=case when v_damaged+v_missing+v_returned>0
    then 'received_with_variance' else 'received' end;

  perform private.v485_transfer_history_add(
    p_tenant_id,p_transfer_id,v_event_type,
    case when st.status='dispatched' then 'in_transit' else st.status end,
    'received',p_note,
    jsonb_build_object(
      'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,
      'good_quantity',v_good,'damaged_quantity',v_damaged,
      'missing_quantity',v_missing,'returned_quantity',v_returned
    )
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,'inventory','stock_transfer',p_transfer_id::text,'received'
  );

  insert into public.transport_logistics_trip_events(
    tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id
  ) values(
    p_tenant_id,p_trip_id,
    case when v_event_type='received' then 'transfer_received'
         else 'transfer_received_with_variance' end,
    t.status,t.status,
    jsonb_build_object(
      'transfer_id',p_transfer_id,'transfer_number',st.transfer_number,
      'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,
      'good_quantity',v_good,'damaged_quantity',v_damaged,
      'missing_quantity',v_missing,'returned_quantity',v_returned
    ),
    auth.uid()
  );

  select not exists(
    select 1
    from public.transport_logistics_trip_documents d
    join public.stock_transfers x on x.id=d.stock_transfer_id and x.tenant_id=d.tenant_id
    where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id and d.active and x.status<>'received'
  ) into v_all_received;

  if v_all_received then
    update public.transport_logistics_trips
    set status='received',received_at=coalesce(received_at,now()),
        updated_by=auth.uid(),updated_at=now()
    where id=p_trip_id;

    insert into public.transport_logistics_trip_events(
      tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id
    ) values(
      p_tenant_id,p_trip_id,'trip_received',t.status,'received',
      jsonb_build_object('receipt_id',v_receipt_id,'last_transfer_id',p_transfer_id),
      auth.uid()
    );
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,'logistics_receipt_finalized','transport_logistics_receipt',
    v_receipt_id,v_receipt_number,null,
    jsonb_build_object(
      'trip_id',p_trip_id,'transfer_id',p_transfer_id,'transfer_number',st.transfer_number,
      'good_quantity',v_good,'damaged_quantity',v_damaged,
      'missing_quantity',v_missing,'returned_quantity',v_returned
    )
  );

  return jsonb_build_object(
    'success',true,'status','received',
    'trip_status',case when v_all_received then 'received' else t.status end,
    'trip_id',p_trip_id,'transfer_id',p_transfer_id,
    'transfer_number',st.transfer_number,
    'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,
    'good_quantity',v_good,'damaged_quantity',v_damaged,
    'missing_quantity',v_missing,'returned_quantity',v_returned,
    'has_variance',(v_damaged+v_missing+v_returned)>0
  );
end
$function$;

revoke execute on function public.logistics_trip_receive_transfer_reconciled_v1(uuid,uuid,uuid,uuid,jsonb,text) from public, anon;
grant execute on function public.logistics_trip_receive_transfer_reconciled_v1(uuid,uuid,uuid,uuid,jsonb,text) to authenticated, service_role;
