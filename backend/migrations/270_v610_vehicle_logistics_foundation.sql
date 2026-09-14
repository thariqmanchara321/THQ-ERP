-- THQ ERP Vehicle Logistics / Stock Movement foundation
-- Applied to flexi-erp-dev as Supabase migration: v610_vehicle_logistics_foundation
-- Logistics orchestrates existing stock transfer writers; it never posts stock directly.

create table if not exists public.transport_logistics_trips (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_number text not null,
  trip_type text not null default 'stock_transfer',
  status text not null default 'planned',
  vehicle_id uuid not null references public.service_vehicles(id),
  driver_name text,
  driver_phone text,
  from_location_id uuid not null references public.business_locations(id),
  to_location_id uuid not null references public.business_locations(id),
  planned_departure_at timestamptz,
  loading_started_at timestamptz,
  dispatched_at timestamptz,
  arrived_at timestamptz,
  received_at timestamptz,
  closed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transport_logistics_trip_type_chk check (trip_type in ('stock_transfer')),
  constraint transport_logistics_trip_status_chk check (status in ('planned','loading','in_transit','arrived','received','closed','cancelled')),
  constraint transport_logistics_trip_route_chk check (from_location_id <> to_location_id),
  constraint transport_logistics_trip_number_uq unique (tenant_id, trip_number)
);

create table if not exists public.transport_logistics_trip_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  document_type text not null default 'stock_transfer',
  stock_transfer_id uuid not null references public.stock_transfers(id),
  active boolean not null default true,
  added_by uuid default auth.uid(),
  added_at timestamptz not null default now(),
  constraint transport_logistics_document_type_chk check (document_type in ('stock_transfer')),
  constraint transport_logistics_trip_document_uq unique (trip_id, stock_transfer_id)
);

create unique index if not exists transport_logistics_transfer_active_uq
  on public.transport_logistics_trip_documents(tenant_id, stock_transfer_id) where active;

create table if not exists public.transport_logistics_trip_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  event_data jsonb not null default '{}'::jsonb,
  actor_user_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists transport_logistics_trips_tenant_status_idx on public.transport_logistics_trips(tenant_id,status,created_at desc);
create index if not exists transport_logistics_trips_vehicle_idx on public.transport_logistics_trips(tenant_id,vehicle_id,created_at desc);
create index if not exists transport_logistics_trips_from_idx on public.transport_logistics_trips(tenant_id,from_location_id,created_at desc);
create index if not exists transport_logistics_trips_to_idx on public.transport_logistics_trips(tenant_id,to_location_id,created_at desc);
create index if not exists transport_logistics_docs_trip_idx on public.transport_logistics_trip_documents(tenant_id,trip_id,active);
create index if not exists transport_logistics_events_trip_idx on public.transport_logistics_trip_events(tenant_id,trip_id,created_at,id);

revoke all on public.transport_logistics_trips from anon, authenticated;
revoke all on public.transport_logistics_trip_documents from anon, authenticated;
revoke all on public.transport_logistics_trip_events from anon, authenticated;

create or replace function public.logistics_trips_list_v1(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path to 'public','private','pg_temp' as $$
declare q text := '%'||lower(trim(coalesce(p_query,'')))||'%';
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 if not (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'inventory.transfer') or private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Logistics view permission required'; end if;
 return query
 select jsonb_build_object(
  'id',t.id,'trip_number',t.trip_number,'trip_type',t.trip_type,'status',t.status,
  'vehicle_id',t.vehicle_id,'vehicle_registration',v.registration_number,'vehicle_type',v.vehicle_type,'make_model',v.make_model,
  'driver_name',t.driver_name,'driver_phone',t.driver_phone,
  'from_location_id',t.from_location_id,'from_location',fl.location_code||' • '||fl.name,
  'to_location_id',t.to_location_id,'to_location',tl.location_code||' • '||tl.name,
  'planned_departure_at',t.planned_departure_at,'loading_started_at',t.loading_started_at,'dispatched_at',t.dispatched_at,
  'arrived_at',t.arrived_at,'received_at',t.received_at,'closed_at',t.closed_at,'notes',t.notes,'created_at',t.created_at,
  'document_count',(select count(*) from public.transport_logistics_trip_documents d where d.trip_id=t.id and d.active),
  'transfer_numbers',coalesce((select jsonb_agg(st.transfer_number order by st.transfer_number) from public.transport_logistics_trip_documents d join public.stock_transfers st on st.id=d.stock_transfer_id and st.tenant_id=d.tenant_id where d.trip_id=t.id and d.active),'[]'::jsonb),
  'total_quantity',coalesce((select sum(i.quantity) from public.transport_logistics_trip_documents d join public.stock_transfer_items i on i.transfer_id=d.stock_transfer_id where d.trip_id=t.id and d.active),0),
  'in_transit_quantity',coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0)) from public.transport_logistics_trip_documents d join public.stock_transfer_items i on i.transfer_id=d.stock_transfer_id where d.trip_id=t.id and d.active),0)
 )
 from public.transport_logistics_trips t
 join public.service_vehicles v on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
 join public.business_locations fl on fl.id=t.from_location_id and fl.tenant_id=t.tenant_id
 join public.business_locations tl on tl.id=t.to_location_id and tl.tenant_id=t.tenant_id
 where t.tenant_id=p_tenant_id
 and (p_status is null or trim(p_status)='' or t.status=lower(trim(p_status)))
 and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
 and (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,p_location_id,'view') or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,p_location_id,'view'))
 and (trim(coalesce(p_query,''))='' or lower(t.trip_number) like q or lower(v.registration_number) like q or lower(coalesce(t.driver_name,'')) like q or lower(fl.name) like q or lower(tl.name) like q or exists(select 1 from public.transport_logistics_trip_documents d join public.stock_transfers st on st.id=d.stock_transfer_id where d.trip_id=t.id and d.active and lower(st.transfer_number) like q))
 order by t.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;

create or replace function public.logistics_trip_detail_v1(p_tenant_id uuid,p_trip_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype; v_result jsonb;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Trip not found'; end if;
 if not (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,null,'view') or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,null,'view')) then raise exception 'Location access denied'; end if;
 select jsonb_build_object(
  'trip',to_jsonb(t)||jsonb_build_object('vehicle_registration',v.registration_number,'vehicle_type',v.vehicle_type,'make_model',v.make_model,'from_location',fl.location_code||' • '||fl.name,'to_location',tl.location_code||' • '||tl.name),
  'documents',coalesce((select jsonb_agg(jsonb_build_object(
    'id',d.id,'document_type',d.document_type,'stock_transfer_id',st.id,'transfer_number',st.transfer_number,
    'status',case when st.status='dispatched' then 'in_transit' else st.status end,'expected_arrival_date',st.expected_arrival_date,'transport_reference',st.transport_reference,
    'item_count',(select count(*) from public.stock_transfer_items i where i.transfer_id=st.id),
    'total_quantity',(select coalesce(sum(i.quantity),0) from public.stock_transfer_items i where i.transfer_id=st.id),
    'in_transit_quantity',(select coalesce(sum(greatest(i.dispatched_quantity-i.received_quantity,0)),0) from public.stock_transfer_items i where i.transfer_id=st.id),
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'variant_id',i.variant_id,'product_name',p.name,'sku',pv.sku,'tracking_mode',i.tracking_mode,'quantity',i.quantity,'dispatched_quantity',i.dispatched_quantity,'received_quantity',i.received_quantity) order by p.name,pv.sku) from public.stock_transfer_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.transfer_id=st.id),'[]'::jsonb)
  ) order by st.transfer_number) from public.transport_logistics_trip_documents d join public.stock_transfers st on st.id=d.stock_transfer_id and st.tenant_id=d.tenant_id where d.trip_id=t.id and d.active),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id) from public.transport_logistics_trip_events e where e.trip_id=t.id and e.tenant_id=t.tenant_id),'[]'::jsonb)
 ) into v_result
 from public.service_vehicles v join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id where v.id=t.vehicle_id;
 return v_result;
end $$;

create or replace function public.logistics_trip_create_v1(p_tenant_id uuid,p_vehicle_id uuid,p_transfer_ids uuid[],p_planned_departure_at timestamptz default null,p_driver_name text default null,p_driver_phone text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare v_vehicle public.service_vehicles%rowtype; v_first public.stock_transfers%rowtype; v_transfer public.stock_transfers%rowtype; v_trip public.transport_logistics_trips%rowtype; v_transfer_id uuid; v_trip_number text;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 if not (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'inventory.transfer') or private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Logistics create permission required'; end if;
 if p_transfer_ids is null or coalesce(array_length(p_transfer_ids,1),0)=0 then raise exception 'Select at least one approved stock transfer'; end if;
 select * into v_vehicle from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id and active for update; if not found then raise exception 'Active vehicle not found'; end if;
 select * into v_first from public.stock_transfers where id=p_transfer_ids[1] and tenant_id=p_tenant_id for update; if not found then raise exception 'Stock transfer not found'; end if;
 if v_first.status<>'approved' then raise exception 'Only approved stock transfers can be assigned to a new trip'; end if;
 perform private.v4_location_access(p_tenant_id,v_first.from_location_id,'operate');
 foreach v_transfer_id in array p_transfer_ids loop
  select * into v_transfer from public.stock_transfers where id=v_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Stock transfer % not found',v_transfer_id; end if;
  if v_transfer.status<>'approved' then raise exception 'Transfer % must be approved before trip assignment',v_transfer.transfer_number; end if;
  if v_transfer.from_location_id<>v_first.from_location_id or v_transfer.to_location_id<>v_first.to_location_id then raise exception 'All transfers in one trip must use the same origin and destination'; end if;
  if exists(select 1 from public.transport_logistics_trip_documents d where d.tenant_id=p_tenant_id and d.stock_transfer_id=v_transfer.id and d.active) then raise exception 'Transfer % is already assigned to an active logistics trip',v_transfer.transfer_number; end if;
 end loop;
 v_trip_number := 'TRIP-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.transport_logistics_trips(tenant_id,trip_number,vehicle_id,driver_name,driver_phone,from_location_id,to_location_id,planned_departure_at,notes,created_by,updated_by)
 values(p_tenant_id,v_trip_number,v_vehicle.id,coalesce(nullif(trim(coalesce(p_driver_name,'')),''),v_vehicle.driver_name),coalesce(nullif(trim(coalesce(p_driver_phone,'')),''),v_vehicle.driver_phone),v_first.from_location_id,v_first.to_location_id,p_planned_departure_at,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid()) returning * into v_trip;
 foreach v_transfer_id in array p_transfer_ids loop insert into public.transport_logistics_trip_documents(tenant_id,trip_id,stock_transfer_id,added_by) values(p_tenant_id,v_trip.id,v_transfer_id,auth.uid()); end loop;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,to_status,event_data,actor_user_id) values(p_tenant_id,v_trip.id,'trip_created','planned',jsonb_build_object('vehicle_id',v_vehicle.id,'transfer_ids',to_jsonb(p_transfer_ids)),auth.uid());
 perform private.business_audit_write_v471(p_tenant_id,'logistics.trip.create','logistics_trip',v_trip.id,v_trip.trip_number,null,to_jsonb(v_trip));
 return jsonb_build_object('success',true,'trip_id',v_trip.id,'trip_number',v_trip.trip_number,'status',v_trip.status);
end $$;

create or replace function public.logistics_trip_start_loading_v1(p_tenant_id uuid,p_trip_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.from_location_id,'operate');
 if t.status='loading' then return jsonb_build_object('success',true,'trip_id',t.id,'status','loading','idempotent',true); end if;
 if t.status<>'planned' then raise exception 'Only planned trips can start loading'; end if;
 update public.transport_logistics_trips set status='loading',loading_started_at=now(),updated_by=auth.uid(),updated_at=now() where id=t.id;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,actor_user_id) values(p_tenant_id,t.id,'loading_started','planned','loading',auth.uid());
 return jsonb_build_object('success',true,'trip_id',t.id,'trip_number',t.trip_number,'status','loading');
end $$;

create or replace function public.logistics_trip_dispatch_v1(p_tenant_id uuid,p_trip_id uuid,p_device_id uuid default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype; d record;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.from_location_id,'operate');
 if t.status='in_transit' then return jsonb_build_object('success',true,'trip_id',t.id,'status','in_transit','idempotent',true); end if;
 if t.status not in('planned','loading') then raise exception 'Only planned/loading trips can be dispatched'; end if;
 if not exists(select 1 from public.transport_logistics_trip_documents x where x.trip_id=t.id and x.active) then raise exception 'Trip has no stock transfers'; end if;
 for d in select st.id,st.transfer_number,st.status from public.transport_logistics_trip_documents x join public.stock_transfers st on st.id=x.stock_transfer_id and st.tenant_id=x.tenant_id where x.trip_id=t.id and x.active order by st.transfer_number loop
  if d.status<>'approved' then raise exception 'Transfer % is not approved for dispatch',d.transfer_number; end if;
  perform public.inventory_transfer_dispatch_v485(p_tenant_id,d.id,p_device_id,p_note,t.trip_number);
 end loop;
 update public.transport_logistics_trips set status='in_transit',dispatched_at=now(),updated_by=auth.uid(),updated_at=now() where id=t.id;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id) values(p_tenant_id,t.id,'trip_dispatched',t.status,'in_transit',jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
 perform private.business_audit_write_v471(p_tenant_id,'logistics.trip.dispatch','logistics_trip',t.id,t.trip_number,to_jsonb(t),jsonb_build_object('status','in_transit'));
 return jsonb_build_object('success',true,'trip_id',t.id,'trip_number',t.trip_number,'status','in_transit');
end $$;

create or replace function public.logistics_trip_arrive_v1(p_tenant_id uuid,p_trip_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.to_location_id,'operate');
 if t.status='arrived' then return jsonb_build_object('success',true,'trip_id',t.id,'status','arrived','idempotent',true); end if;
 if t.status<>'in_transit' then raise exception 'Only in-transit trips can be marked arrived'; end if;
 update public.transport_logistics_trips set status='arrived',arrived_at=now(),updated_by=auth.uid(),updated_at=now() where id=t.id;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id) values(p_tenant_id,t.id,'trip_arrived','in_transit','arrived',jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
 return jsonb_build_object('success',true,'trip_id',t.id,'trip_number',t.trip_number,'status','arrived');
end $$;

create or replace function public.logistics_trip_receive_transfer_v1(p_tenant_id uuid,p_trip_id uuid,p_transfer_id uuid,p_device_id uuid default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype; st public.stock_transfers%rowtype; v_remaining bigint;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 if t.status not in('arrived','received') then raise exception 'Mark the trip arrived before receiving stock'; end if;
 perform private.v4_location_access(p_tenant_id,t.to_location_id,'operate');
 if not exists(select 1 from public.transport_logistics_trip_documents d where d.trip_id=t.id and d.tenant_id=p_tenant_id and d.stock_transfer_id=p_transfer_id and d.active) then raise exception 'Transfer is not assigned to this trip'; end if;
 select * into st from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Stock transfer not found'; end if;
 if st.status<>'received' then perform public.inventory_transfer_receive_v485(p_tenant_id,p_transfer_id,p_device_id,p_note); end if;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id) values(p_tenant_id,t.id,'transfer_received',t.status,t.status,jsonb_build_object('stock_transfer_id',p_transfer_id,'transfer_number',st.transfer_number,'note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
 select count(*) into v_remaining from public.transport_logistics_trip_documents d join public.stock_transfers x on x.id=d.stock_transfer_id and x.tenant_id=d.tenant_id where d.trip_id=t.id and d.active and x.status<>'received';
 if v_remaining=0 and t.status<>'received' then
  update public.transport_logistics_trips set status='received',received_at=now(),updated_by=auth.uid(),updated_at=now() where id=t.id;
  insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,actor_user_id) values(p_tenant_id,t.id,'trip_received',t.status,'received',auth.uid());
 end if;
 return jsonb_build_object('success',true,'trip_id',t.id,'transfer_id',p_transfer_id,'status',case when v_remaining=0 then 'received' else t.status end,'remaining_transfers',v_remaining);
end $$;

create or replace function public.logistics_trip_close_v1(p_tenant_id uuid,p_trip_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype; v_remaining bigint;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.to_location_id,'operate');
 if t.status='closed' then return jsonb_build_object('success',true,'trip_id',t.id,'status','closed','idempotent',true); end if;
 select count(*) into v_remaining from public.transport_logistics_trip_documents d join public.stock_transfers st on st.id=d.stock_transfer_id where d.trip_id=t.id and d.active and st.status<>'received';
 if v_remaining>0 then raise exception 'Receive all stock transfers before closing the trip'; end if;
 if t.status not in('received','arrived') then raise exception 'Trip is not ready to close'; end if;
 update public.transport_logistics_trips set status='closed',received_at=coalesce(received_at,now()),closed_at=now(),updated_by=auth.uid(),updated_at=now() where id=t.id;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,actor_user_id) values(p_tenant_id,t.id,'trip_closed',t.status,'closed',auth.uid());
 perform private.business_audit_write_v471(p_tenant_id,'logistics.trip.close','logistics_trip',t.id,t.trip_number,to_jsonb(t),jsonb_build_object('status','closed'));
 return jsonb_build_object('success',true,'trip_id',t.id,'trip_number',t.trip_number,'status','closed');
end $$;

create or replace function public.logistics_trip_cancel_v1(p_tenant_id uuid,p_trip_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare t public.transport_logistics_trips%rowtype;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update; if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.from_location_id,'operate');
 if t.status='cancelled' then return jsonb_build_object('success',true,'trip_id',t.id,'status','cancelled','idempotent',true); end if;
 if t.status not in('planned','loading') then raise exception 'Only planned/loading trips can be cancelled. In-transit stock must be resolved through the transfer workflow.'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
 update public.transport_logistics_trips set status='cancelled',cancelled_at=now(),cancel_reason=trim(p_reason),updated_by=auth.uid(),updated_at=now() where id=t.id;
 update public.transport_logistics_trip_documents set active=false where trip_id=t.id and tenant_id=p_tenant_id and active;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id) values(p_tenant_id,t.id,'trip_cancelled',t.status,'cancelled',jsonb_build_object('reason',trim(p_reason)),auth.uid());
 perform private.business_audit_write_v471(p_tenant_id,'logistics.trip.cancel','logistics_trip',t.id,t.trip_number,to_jsonb(t),jsonb_build_object('status','cancelled','reason',trim(p_reason)));
 return jsonb_build_object('success',true,'trip_id',t.id,'trip_number',t.trip_number,'status','cancelled');
end $$;

revoke all on function public.logistics_trips_list_v1(uuid,uuid,text,text,integer) from public,anon;
revoke all on function public.logistics_trip_detail_v1(uuid,uuid) from public,anon;
revoke all on function public.logistics_trip_create_v1(uuid,uuid,uuid[],timestamptz,text,text,text) from public,anon;
revoke all on function public.logistics_trip_start_loading_v1(uuid,uuid) from public,anon;
revoke all on function public.logistics_trip_dispatch_v1(uuid,uuid,uuid,text) from public,anon;
revoke all on function public.logistics_trip_arrive_v1(uuid,uuid,text) from public,anon;
revoke all on function public.logistics_trip_receive_transfer_v1(uuid,uuid,uuid,uuid,text) from public,anon;
revoke all on function public.logistics_trip_close_v1(uuid,uuid) from public,anon;
revoke all on function public.logistics_trip_cancel_v1(uuid,uuid,text) from public,anon;

grant execute on function public.logistics_trips_list_v1(uuid,uuid,text,text,integer) to authenticated,service_role;
grant execute on function public.logistics_trip_detail_v1(uuid,uuid) to authenticated,service_role;
grant execute on function public.logistics_trip_create_v1(uuid,uuid,uuid[],timestamptz,text,text,text) to authenticated,service_role;
grant execute on function public.logistics_trip_start_loading_v1(uuid,uuid) to authenticated,service_role;
grant execute on function public.logistics_trip_dispatch_v1(uuid,uuid,uuid,text) to authenticated,service_role;
grant execute on function public.logistics_trip_arrive_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.logistics_trip_receive_transfer_v1(uuid,uuid,uuid,uuid,text) to authenticated,service_role;
grant execute on function public.logistics_trip_close_v1(uuid,uuid) to authenticated,service_role;
grant execute on function public.logistics_trip_cancel_v1(uuid,uuid,text) to authenticated,service_role;
