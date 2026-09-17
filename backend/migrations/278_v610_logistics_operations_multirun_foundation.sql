-- THQ ERP v6.1 Logistics Operations canonical multi-run foundation
-- Canonical source migration for the v6.1 RPC contract used by Client/POS desktop and mobile.
-- IMPORTANT: equivalent backend functionality is already live on flexi-erp-dev.
-- Do not manually re-run this file against the current dev project.

create table if not exists public.logistics_operations_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_number text not null,
  operation_date date not null default current_date,
  base_location_id uuid null references public.business_locations(id) on delete restrict,
  title text null,
  purpose text not null default 'delivery' check (purpose in ('delivery','collection','mixed','transfer','other')),
  status text not null default 'planned' check (status in ('planned','active','completed','closed','cancelled')),
  primary_unit text not null default 'kg',
  secondary_unit text null,
  coordinator_name text null,
  notes text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  closed_at timestamptz null,
  cancelled_at timestamptz null,
  cancelled_reason text null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, operation_number)
);
create index if not exists idx_logistics_operations_v61_tenant_status_date
  on public.logistics_operations_v61(tenant_id,status,operation_date desc);

create table if not exists public.logistics_drivers_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  phone text null,
  license_number text null,
  notes text null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_logistics_drivers_v61_tenant_active
  on public.logistics_drivers_v61(tenant_id,active,name);

create table if not exists public.logistics_destinations_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  destination_type text not null default 'other' check (destination_type in ('farm','shop','customer','supplier','store','warehouse','processing','market','other')),
  name text not null,
  code text null,
  linked_entity_type text null,
  linked_entity_id uuid null,
  address text null,
  contact_person text null,
  phone text null,
  latitude numeric null,
  longitude numeric null,
  notes text null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_logistics_destinations_v61_tenant_active
  on public.logistics_destinations_v61(tenant_id,active,destination_type,name);

create table if not exists public.logistics_vehicle_runs_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations_v61(id) on delete cascade,
  run_no integer not null,
  vehicle_id uuid null references public.service_vehicles(id) on delete restrict,
  driver_id uuid null references public.logistics_drivers_v61(id) on delete restrict,
  driver_name_snapshot text null,
  driver_phone_snapshot text null,
  status text not null default 'planned' check (status in ('planned','loading','in_transit','completed','cancelled')),
  planned_departure_at timestamptz null,
  departed_at timestamptz null,
  completed_at timestamptz null,
  starting_primary_qty numeric not null default 0 check (starting_primary_qty >= 0),
  starting_secondary_qty numeric null check (starting_secondary_qty is null or starting_secondary_qty >= 0),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(operation_id,run_no)
);
create index if not exists idx_logistics_vehicle_runs_v61_operation
  on public.logistics_vehicle_runs_v61(tenant_id,operation_id,run_no);
create index if not exists idx_logistics_vehicle_runs_v61_vehicle_status
  on public.logistics_vehicle_runs_v61(tenant_id,vehicle_id,status);

create table if not exists public.logistics_run_stops_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  run_id uuid not null references public.logistics_vehicle_runs_v61(id) on delete cascade,
  sequence_no integer not null,
  action_type text not null default 'delivery' check (action_type in ('pickup','delivery','pickup_delivery','return','waypoint')),
  destination_id uuid null references public.logistics_destinations_v61(id) on delete restrict,
  destination_name_snapshot text not null,
  linked_document_type text null,
  linked_document_id uuid null,
  linked_document_reference text null,
  planned_pickup_primary_qty numeric not null default 0 check (planned_pickup_primary_qty >= 0),
  planned_delivery_primary_qty numeric not null default 0 check (planned_delivery_primary_qty >= 0),
  planned_pickup_secondary_qty numeric null check (planned_pickup_secondary_qty is null or planned_pickup_secondary_qty >= 0),
  planned_delivery_secondary_qty numeric null check (planned_delivery_secondary_qty is null or planned_delivery_secondary_qty >= 0),
  actual_pickup_primary_qty numeric not null default 0 check (actual_pickup_primary_qty >= 0),
  actual_delivery_primary_qty numeric not null default 0 check (actual_delivery_primary_qty >= 0),
  actual_pickup_secondary_qty numeric null check (actual_pickup_secondary_qty is null or actual_pickup_secondary_qty >= 0),
  actual_delivery_secondary_qty numeric null check (actual_delivery_secondary_qty is null or actual_delivery_secondary_qty >= 0),
  variance_primary_qty numeric not null default 0 check (variance_primary_qty >= 0),
  variance_secondary_qty numeric null check (variance_secondary_qty is null or variance_secondary_qty >= 0),
  variance_reason text null check (variance_reason is null or variance_reason in ('mortality','shortage','damage','weight_variance','rejected','other')),
  receiver_name text null,
  note text null,
  status text not null default 'planned' check (status in ('planned','arrived','completed','skipped','cancelled')),
  arrived_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(run_id,sequence_no)
);
create index if not exists idx_logistics_run_stops_v61_run
  on public.logistics_run_stops_v61(tenant_id,run_id,sequence_no);

create table if not exists public.logistics_operation_events_v61 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations_v61(id) on delete cascade,
  run_id uuid null references public.logistics_vehicle_runs_v61(id) on delete cascade,
  stop_id uuid null references public.logistics_run_stops_v61(id) on delete cascade,
  event_type text not null,
  message text null,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_logistics_operation_events_v61_operation
  on public.logistics_operation_events_v61(tenant_id,operation_id,created_at desc);

alter table public.logistics_operations_v61 enable row level security;
alter table public.logistics_drivers_v61 enable row level security;
alter table public.logistics_destinations_v61 enable row level security;
alter table public.logistics_vehicle_runs_v61 enable row level security;
alter table public.logistics_run_stops_v61 enable row level security;
alter table public.logistics_operation_events_v61 enable row level security;

revoke all on public.logistics_operations_v61 from anon,authenticated;
revoke all on public.logistics_drivers_v61 from anon,authenticated;
revoke all on public.logistics_destinations_v61 from anon,authenticated;
revoke all on public.logistics_vehicle_runs_v61 from anon,authenticated;
revoke all on public.logistics_run_stops_v61 from anon,authenticated;
revoke all on public.logistics_operation_events_v61 from anon,authenticated;

grant select on public.logistics_operations_v61 to service_role;
grant select on public.logistics_drivers_v61 to service_role;
grant select on public.logistics_destinations_v61 to service_role;
grant select on public.logistics_vehicle_runs_v61 to service_role;
grant select on public.logistics_run_stops_v61 to service_role;
grant select on public.logistics_operation_events_v61 to service_role;

create or replace function private.logistics_can_view_v61(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
  select private.erp_user_has_tenant_access(p_tenant_id)
    and (
      private.erp_user_is_owner(p_tenant_id)
      or private.erp_has_permission(p_tenant_id,'transport_service.view')
      or private.erp_has_permission(p_tenant_id,'transport_service.create')
      or private.erp_has_permission(p_tenant_id,'transport_service.manage')
      or private.erp_has_permission(p_tenant_id,'inventory.view')
      or private.erp_has_permission(p_tenant_id,'inventory.manage')
      or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    );
$$;

create or replace function private.logistics_can_operate_v61(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
  select private.erp_user_has_tenant_access(p_tenant_id)
    and (
      private.erp_user_is_owner(p_tenant_id)
      or private.erp_has_permission(p_tenant_id,'transport_service.create')
      or private.erp_has_permission(p_tenant_id,'transport_service.manage')
      or private.erp_has_permission(p_tenant_id,'inventory.manage')
      or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    );
$$;

create or replace function private.logistics_event_v61(
  p_tenant_id uuid,p_operation_id uuid,p_run_id uuid,p_stop_id uuid,
  p_event_type text,p_message text,p_payload jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.logistics_operation_events_v61(tenant_id,operation_id,run_id,stop_id,event_type,message,payload,created_by)
  values(p_tenant_id,p_operation_id,p_run_id,p_stop_id,p_event_type,nullif(trim(coalesce(p_message,'')),''),coalesce(p_payload,'{}'::jsonb),auth.uid());
end $$;

create or replace function public.logistics_operations_list_v61(
  p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default null,p_limit integer default 300
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.logistics_can_view_v61(p_tenant_id) then raise exception 'Logistics view permission required'; end if;
  return query
  select jsonb_build_object(
    'id',o.id,'operation_number',o.operation_number,'operation_date',o.operation_date,
    'base_location_id',o.base_location_id,'base_location_name',l.name,
    'title',o.title,'purpose',o.purpose,'status',o.status,'primary_unit',o.primary_unit,'secondary_unit',o.secondary_unit,
    'coordinator_name',o.coordinator_name,'notes',o.notes,
    'run_count',(select count(*) from public.logistics_vehicle_runs_v61 r where r.operation_id=o.id),
    'active_run_count',(select count(*) from public.logistics_vehicle_runs_v61 r where r.operation_id=o.id and r.status in ('loading','in_transit')),
    'stop_count',(select count(*) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id),
    'pickup_primary_qty',coalesce((select sum(s.actual_pickup_primary_qty) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id),0),
    'delivery_primary_qty',coalesce((select sum(case when s.action_type='return' then 0 else s.actual_delivery_primary_qty end) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id),0),
    'returned_primary_qty',coalesce((select sum(case when s.action_type='return' then s.actual_delivery_primary_qty else 0 end) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id),0),
    'variance_primary_qty',coalesce((select sum(s.variance_primary_qty) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id),0),
    'created_at',o.created_at,'updated_at',o.updated_at
  )
  from public.logistics_operations_v61 o
  left join public.business_locations l on l.id=o.base_location_id and l.tenant_id=o.tenant_id
  where o.tenant_id=p_tenant_id
    and (p_location_id is null or o.base_location_id is null or o.base_location_id=p_location_id)
    and (p_status is null or p_status='' or o.status=p_status)
    and (
      nullif(trim(coalesce(p_query,'')),'') is null
      or o.operation_number ilike '%'||trim(p_query)||'%'
      or coalesce(o.title,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.coordinator_name,'') ilike '%'||trim(p_query)||'%'
      or exists(select 1 from public.logistics_vehicle_runs_v61 r left join public.service_vehicles v on v.id=r.vehicle_id
                where r.operation_id=o.id and (coalesce(v.registration_number,'') ilike '%'||trim(p_query)||'%' or coalesce(r.driver_name_snapshot,'') ilike '%'||trim(p_query)||'%'))
    )
  order by o.operation_date desc,o.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end $$;

create or replace function public.logistics_operation_detail_v61(p_tenant_id uuid,p_operation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_result jsonb;
begin
  if not private.logistics_can_view_v61(p_tenant_id) then raise exception 'Logistics view permission required'; end if;
  if not exists(select 1 from public.logistics_operations_v61 o where o.id=p_operation_id and o.tenant_id=p_tenant_id) then raise exception 'Logistics operation not found'; end if;
  select jsonb_build_object(
    'operation',to_jsonb(o)||jsonb_build_object('base_location_name',l.name),
    'runs',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object(
      'vehicle_registration',v.registration_number,'vehicle_make_model',v.make_model,
      'driver_name',coalesce(d.name,r.driver_name_snapshot),'driver_phone',coalesce(d.phone,r.driver_phone_snapshot),
      'current_primary_qty',r.starting_primary_qty+coalesce((select sum(s.actual_pickup_primary_qty-s.actual_delivery_primary_qty-s.variance_primary_qty) from public.logistics_run_stops_v61 s where s.run_id=r.id and s.status='completed'),0),
      'current_secondary_qty',coalesce(r.starting_secondary_qty,0)+coalesce((select sum(coalesce(s.actual_pickup_secondary_qty,0)-coalesce(s.actual_delivery_secondary_qty,0)-coalesce(s.variance_secondary_qty,0)) from public.logistics_run_stops_v61 s where s.run_id=r.id and s.status='completed'),0),
      'stops',coalesce((select jsonb_agg(to_jsonb(s) order by s.sequence_no) from public.logistics_run_stops_v61 s where s.run_id=r.id),'[]'::jsonb)
    ) order by r.run_no) from public.logistics_vehicle_runs_v61 r
      left join public.service_vehicles v on v.id=r.vehicle_id
      left join public.logistics_drivers_v61 d on d.id=r.driver_id
      where r.operation_id=o.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.logistics_operation_events_v61 e where e.operation_id=o.id),'[]'::jsonb)
  ) into v_result
  from public.logistics_operations_v61 o
  left join public.business_locations l on l.id=o.base_location_id and l.tenant_id=o.tenant_id
  where o.id=p_operation_id and o.tenant_id=p_tenant_id;
  return v_result;
end $$;

create or replace function public.logistics_operation_save_v61(
  p_tenant_id uuid,p_operation_id uuid default null,p_operation_date date default current_date,p_base_location_id uuid default null,
  p_title text default null,p_purpose text default 'delivery',p_primary_unit text default 'kg',p_secondary_unit text default null,
  p_coordinator_name text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_number text;v_existing public.logistics_operations_v61%rowtype;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  if p_base_location_id is not null and not exists(select 1 from public.business_locations l where l.id=p_base_location_id and l.tenant_id=p_tenant_id and l.active) then raise exception 'Active base location is required'; end if;
  if p_purpose not in ('delivery','collection','mixed','transfer','other') then raise exception 'Invalid logistics purpose'; end if;
  if nullif(trim(coalesce(p_primary_unit,'')),'') is null then raise exception 'Primary unit is required'; end if;
  if p_operation_id is null then
    v_id:=gen_random_uuid();
    v_number:='LOG-'||to_char(coalesce(p_operation_date,current_date),'YYYYMMDD')||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
    insert into public.logistics_operations_v61(id,tenant_id,operation_number,operation_date,base_location_id,title,purpose,primary_unit,secondary_unit,coordinator_name,notes,created_by)
    values(v_id,p_tenant_id,v_number,coalesce(p_operation_date,current_date),p_base_location_id,nullif(trim(coalesce(p_title,'')),''),p_purpose,trim(p_primary_unit),nullif(trim(coalesce(p_secondary_unit,'')),''),nullif(trim(coalesce(p_coordinator_name,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
    perform private.logistics_event_v61(p_tenant_id,v_id,null,null,'operation_created','Logistics operation created',jsonb_build_object('operation_number',v_number));
  else
    select * into v_existing from public.logistics_operations_v61 where id=p_operation_id and tenant_id=p_tenant_id for update;
    if not found then raise exception 'Logistics operation not found'; end if;
    if v_existing.status in ('closed','cancelled') then raise exception 'Closed or cancelled operation cannot be edited'; end if;
    update public.logistics_operations_v61 set operation_date=coalesce(p_operation_date,operation_date),base_location_id=p_base_location_id,
      title=nullif(trim(coalesce(p_title,'')),''),purpose=p_purpose,primary_unit=trim(p_primary_unit),secondary_unit=nullif(trim(coalesce(p_secondary_unit,'')),''),
      coordinator_name=nullif(trim(coalesce(p_coordinator_name,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now()
    where id=p_operation_id and tenant_id=p_tenant_id;
    v_id:=p_operation_id;v_number:=v_existing.operation_number;
    perform private.logistics_event_v61(p_tenant_id,v_id,null,null,'operation_updated','Logistics operation updated','{}'::jsonb);
  end if;
  return jsonb_build_object('id',v_id,'operation_number',v_number);
end $$;

create or replace function public.logistics_run_save_v61(
  p_tenant_id uuid,p_operation_id uuid,p_run_id uuid default null,p_vehicle_id uuid default null,p_driver_id uuid default null,
  p_driver_name text default null,p_driver_phone text default null,p_planned_departure_at timestamptz default null,
  p_starting_primary_qty numeric default 0,p_starting_secondary_qty numeric default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_run_no int;v_op public.logistics_operations_v61%rowtype;v_old public.logistics_vehicle_runs_v61%rowtype;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_op from public.logistics_operations_v61 where id=p_operation_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Logistics operation not found'; end if;
  if v_op.status in ('closed','cancelled') then raise exception 'Closed or cancelled operation cannot be changed'; end if;
  if coalesce(p_starting_primary_qty,0)<0 or coalesce(p_starting_secondary_qty,0)<0 then raise exception 'Starting quantity cannot be negative'; end if;
  if p_vehicle_id is not null and not exists(select 1 from public.service_vehicles v where v.id=p_vehicle_id and v.tenant_id=p_tenant_id and v.active) then raise exception 'Active vehicle not found'; end if;
  if p_driver_id is not null and not exists(select 1 from public.logistics_drivers_v61 d where d.id=p_driver_id and d.tenant_id=p_tenant_id and d.active) then raise exception 'Active driver not found'; end if;
  if p_run_id is null then
    select coalesce(max(run_no),0)+1 into v_run_no from public.logistics_vehicle_runs_v61 where operation_id=p_operation_id;
    insert into public.logistics_vehicle_runs_v61(tenant_id,operation_id,run_no,vehicle_id,driver_id,driver_name_snapshot,driver_phone_snapshot,planned_departure_at,starting_primary_qty,starting_secondary_qty,notes)
    values(p_tenant_id,p_operation_id,v_run_no,p_vehicle_id,p_driver_id,nullif(trim(coalesce(p_driver_name,'')),''),nullif(trim(coalesce(p_driver_phone,'')),''),p_planned_departure_at,coalesce(p_starting_primary_qty,0),p_starting_secondary_qty,nullif(trim(coalesce(p_notes,'')),'')) returning id into v_id;
    perform private.logistics_event_v61(p_tenant_id,p_operation_id,v_id,null,'run_created','Vehicle run created',jsonb_build_object('run_no',v_run_no));
  else
    select * into v_old from public.logistics_vehicle_runs_v61 where id=p_run_id and tenant_id=p_tenant_id and operation_id=p_operation_id for update;
    if not found then raise exception 'Vehicle run not found'; end if;
    if v_old.status in ('completed','cancelled') then raise exception 'Completed or cancelled run cannot be edited'; end if;
    update public.logistics_vehicle_runs_v61 set vehicle_id=p_vehicle_id,driver_id=p_driver_id,driver_name_snapshot=nullif(trim(coalesce(p_driver_name,'')),''),driver_phone_snapshot=nullif(trim(coalesce(p_driver_phone,'')),''),planned_departure_at=p_planned_departure_at,starting_primary_qty=coalesce(p_starting_primary_qty,0),starting_secondary_qty=p_starting_secondary_qty,notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=p_run_id;
    v_id:=p_run_id;v_run_no:=v_old.run_no;
    perform private.logistics_event_v61(p_tenant_id,p_operation_id,v_id,null,'run_updated','Vehicle run updated','{}'::jsonb);
  end if;
  return jsonb_build_object('id',v_id,'run_no',v_run_no);
end $$;

create or replace function public.logistics_stop_save_v61(
  p_tenant_id uuid,p_run_id uuid,p_stop_id uuid default null,p_action_type text default 'delivery',p_destination_id uuid default null,
  p_destination_name text default null,p_linked_document_type text default null,p_linked_document_id uuid default null,p_linked_document_reference text default null,
  p_planned_pickup_primary_qty numeric default 0,p_planned_delivery_primary_qty numeric default 0,p_planned_pickup_secondary_qty numeric default null,
  p_planned_delivery_secondary_qty numeric default null,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_seq int;v_run public.logistics_vehicle_runs_v61%rowtype;v_op public.logistics_operations_v61%rowtype;v_old public.logistics_run_stops_v61%rowtype;v_name text;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_run from public.logistics_vehicle_runs_v61 where id=p_run_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Vehicle run not found'; end if;
  select * into v_op from public.logistics_operations_v61 where id=v_run.operation_id and tenant_id=p_tenant_id;
  if v_op.status in ('closed','cancelled') or v_run.status in ('completed','cancelled') then raise exception 'This operation/run cannot be changed'; end if;
  if p_action_type not in ('pickup','delivery','pickup_delivery','return','waypoint') then raise exception 'Invalid stop action'; end if;
  if least(coalesce(p_planned_pickup_primary_qty,0),coalesce(p_planned_delivery_primary_qty,0),coalesce(p_planned_pickup_secondary_qty,0),coalesce(p_planned_delivery_secondary_qty,0))<0 then raise exception 'Planned quantities cannot be negative'; end if;
  if p_destination_id is not null then
    select name into v_name from public.logistics_destinations_v61 where id=p_destination_id and tenant_id=p_tenant_id and active;
    if v_name is null then raise exception 'Active logistics destination not found'; end if;
  else v_name:=nullif(trim(coalesce(p_destination_name,'')),''); end if;
  if v_name is null then raise exception 'Destination name is required'; end if;
  if p_stop_id is null then
    select coalesce(max(sequence_no),0)+1 into v_seq from public.logistics_run_stops_v61 where run_id=p_run_id;
    insert into public.logistics_run_stops_v61(tenant_id,run_id,sequence_no,action_type,destination_id,destination_name_snapshot,linked_document_type,linked_document_id,linked_document_reference,planned_pickup_primary_qty,planned_delivery_primary_qty,planned_pickup_secondary_qty,planned_delivery_secondary_qty,note)
    values(p_tenant_id,p_run_id,v_seq,p_action_type,p_destination_id,v_name,nullif(trim(coalesce(p_linked_document_type,'')),''),p_linked_document_id,nullif(trim(coalesce(p_linked_document_reference,'')),''),coalesce(p_planned_pickup_primary_qty,0),coalesce(p_planned_delivery_primary_qty,0),p_planned_pickup_secondary_qty,p_planned_delivery_secondary_qty,nullif(trim(coalesce(p_note,'')),'')) returning id into v_id;
    perform private.logistics_event_v61(p_tenant_id,v_run.operation_id,p_run_id,v_id,'stop_created','Route stop created',jsonb_build_object('sequence_no',v_seq,'action_type',p_action_type,'destination',v_name));
  else
    select * into v_old from public.logistics_run_stops_v61 where id=p_stop_id and tenant_id=p_tenant_id and run_id=p_run_id for update;
    if not found then raise exception 'Route stop not found'; end if;
    if v_old.status in ('completed','cancelled') then raise exception 'Completed or cancelled stop cannot be edited'; end if;
    update public.logistics_run_stops_v61 set action_type=p_action_type,destination_id=p_destination_id,destination_name_snapshot=v_name,linked_document_type=nullif(trim(coalesce(p_linked_document_type,'')),''),linked_document_id=p_linked_document_id,linked_document_reference=nullif(trim(coalesce(p_linked_document_reference,'')),''),planned_pickup_primary_qty=coalesce(p_planned_pickup_primary_qty,0),planned_delivery_primary_qty=coalesce(p_planned_delivery_primary_qty,0),planned_pickup_secondary_qty=p_planned_pickup_secondary_qty,planned_delivery_secondary_qty=p_planned_delivery_secondary_qty,note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=p_stop_id;
    v_id:=p_stop_id;v_seq:=v_old.sequence_no;
    perform private.logistics_event_v61(p_tenant_id,v_run.operation_id,p_run_id,v_id,'stop_updated','Route stop updated','{}'::jsonb);
  end if;
  return jsonb_build_object('id',v_id,'sequence_no',v_seq);
end $$;

create or replace function public.logistics_stop_complete_v61(
  p_tenant_id uuid,p_stop_id uuid,p_actual_pickup_primary_qty numeric default 0,p_actual_delivery_primary_qty numeric default 0,
  p_actual_pickup_secondary_qty numeric default null,p_actual_delivery_secondary_qty numeric default null,p_variance_primary_qty numeric default 0,
  p_variance_secondary_qty numeric default null,p_variance_reason text default null,p_receiver_name text default null,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_stop public.logistics_run_stops_v61%rowtype;v_run public.logistics_vehicle_runs_v61%rowtype;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_stop from public.logistics_run_stops_v61 where id=p_stop_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Route stop not found'; end if;
  select * into v_run from public.logistics_vehicle_runs_v61 where id=v_stop.run_id and tenant_id=p_tenant_id;
  if v_stop.status='completed' then raise exception 'Stop is already completed'; end if;
  if v_run.status not in ('loading','in_transit') then raise exception 'Run must be loading or in transit before completing a stop'; end if;
  if least(coalesce(p_actual_pickup_primary_qty,0),coalesce(p_actual_delivery_primary_qty,0),coalesce(p_actual_pickup_secondary_qty,0),coalesce(p_actual_delivery_secondary_qty,0),coalesce(p_variance_primary_qty,0),coalesce(p_variance_secondary_qty,0))<0 then raise exception 'Actual quantities cannot be negative'; end if;
  if coalesce(p_variance_primary_qty,0)>0 and coalesce(p_variance_reason,'') not in ('mortality','shortage','damage','weight_variance','rejected','other') then raise exception 'Variance reason is required'; end if;
  update public.logistics_run_stops_v61 set actual_pickup_primary_qty=coalesce(p_actual_pickup_primary_qty,0),actual_delivery_primary_qty=coalesce(p_actual_delivery_primary_qty,0),actual_pickup_secondary_qty=p_actual_pickup_secondary_qty,actual_delivery_secondary_qty=p_actual_delivery_secondary_qty,variance_primary_qty=coalesce(p_variance_primary_qty,0),variance_secondary_qty=p_variance_secondary_qty,variance_reason=nullif(trim(coalesce(p_variance_reason,'')),''),receiver_name=nullif(trim(coalesce(p_receiver_name,'')),''),note=coalesce(nullif(trim(coalesce(p_note,'')),''),note),status='completed',arrived_at=coalesce(arrived_at,now()),completed_at=now(),updated_at=now() where id=p_stop_id;
  perform private.logistics_event_v61(p_tenant_id,v_run.operation_id,v_run.id,p_stop_id,'stop_completed','Route stop completed',jsonb_build_object('pickup_primary',coalesce(p_actual_pickup_primary_qty,0),'delivery_primary',coalesce(p_actual_delivery_primary_qty,0),'variance_primary',coalesce(p_variance_primary_qty,0),'variance_reason',p_variance_reason));
  return jsonb_build_object('id',p_stop_id,'status','completed');
end $$;

create or replace function public.logistics_run_status_v61(p_tenant_id uuid,p_run_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_run public.logistics_vehicle_runs_v61%rowtype;v_op public.logistics_operations_v61%rowtype;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_run from public.logistics_vehicle_runs_v61 where id=p_run_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Vehicle run not found'; end if;
  select * into v_op from public.logistics_operations_v61 where id=v_run.operation_id and tenant_id=p_tenant_id for update;
  if p_status not in ('loading','in_transit','completed','cancelled') then raise exception 'Invalid run status'; end if;
  if v_run.status in ('completed','cancelled') then raise exception 'Run is already final'; end if;
  if p_status='in_transit' and v_run.vehicle_id is not null and exists(select 1 from public.logistics_vehicle_runs_v61 x where x.tenant_id=p_tenant_id and x.vehicle_id=v_run.vehicle_id and x.id<>v_run.id and x.status='in_transit') then raise exception 'Vehicle is already on another active logistics run'; end if;
  if p_status='completed' and exists(select 1 from public.logistics_run_stops_v61 s where s.run_id=v_run.id and s.status='planned') then raise exception 'Complete or cancel all planned stops before completing the run'; end if;
  update public.logistics_vehicle_runs_v61 set status=p_status,departed_at=case when p_status='in_transit' then coalesce(departed_at,now()) else departed_at end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where id=v_run.id;
  if v_op.status='planned' and p_status in ('loading','in_transit') then update public.logistics_operations_v61 set status='active',started_at=coalesce(started_at,now()),updated_at=now() where id=v_op.id; end if;
  perform private.logistics_event_v61(p_tenant_id,v_op.id,v_run.id,null,'run_'||p_status,'Vehicle run '||replace(p_status,'_',' '),jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')));
  return jsonb_build_object('id',v_run.id,'status',p_status);
end $$;

create or replace function public.logistics_operation_status_v61(p_tenant_id uuid,p_operation_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_op public.logistics_operations_v61%rowtype;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_op from public.logistics_operations_v61 where id=p_operation_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Logistics operation not found'; end if;
  if p_status not in ('active','completed','closed','cancelled') then raise exception 'Invalid operation status'; end if;
  if v_op.status in ('closed','cancelled') then raise exception 'Operation is already final'; end if;
  if p_status in ('completed','closed') and exists(select 1 from public.logistics_vehicle_runs_v61 r where r.operation_id=v_op.id and r.status not in ('completed','cancelled')) then raise exception 'Complete or cancel every vehicle run first'; end if;
  if p_status='closed' and not exists(select 1 from public.logistics_vehicle_runs_v61 r where r.operation_id=v_op.id) then raise exception 'Operation must contain at least one vehicle run'; end if;
  if p_status='cancelled' and nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required'; end if;
  update public.logistics_operations_v61 set status=p_status,started_at=case when p_status='active' then coalesce(started_at,now()) else started_at end,completed_at=case when p_status='completed' then now() else completed_at end,closed_at=case when p_status='closed' then now() else closed_at end,cancelled_at=case when p_status='cancelled' then now() else cancelled_at end,cancelled_reason=case when p_status='cancelled' then trim(p_reason) else cancelled_reason end,updated_at=now() where id=v_op.id;
  perform private.logistics_event_v61(p_tenant_id,v_op.id,null,null,'operation_'||p_status,'Logistics operation '||p_status,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
  return jsonb_build_object('id',v_op.id,'status',p_status);
end $$;

create or replace function public.logistics_drivers_list_v61(p_tenant_id uuid,p_active_only boolean default true)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.logistics_can_view_v61(p_tenant_id) then raise exception 'Logistics view permission required'; end if;
  return query select to_jsonb(d) from public.logistics_drivers_v61 d where d.tenant_id=p_tenant_id and (not coalesce(p_active_only,true) or d.active) order by d.active desc,d.name;
end $$;

create or replace function public.logistics_driver_save_v61(p_tenant_id uuid,p_driver_id uuid default null,p_name text default null,p_phone text default null,p_license_number text default null,p_notes text default null,p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Driver name is required'; end if;
  if p_driver_id is null then insert into public.logistics_drivers_v61(tenant_id,name,phone,license_number,notes,active) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_license_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),coalesce(p_active,true)) returning id into v_id;
  else update public.logistics_drivers_v61 set name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),license_number=nullif(trim(coalesce(p_license_number,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),active=coalesce(p_active,true),updated_at=now() where id=p_driver_id and tenant_id=p_tenant_id returning id into v_id;if v_id is null then raise exception 'Driver not found'; end if;end if;
  return jsonb_build_object('id',v_id);
end $$;

create or replace function public.logistics_destinations_list_v61(p_tenant_id uuid,p_active_only boolean default true)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.logistics_can_view_v61(p_tenant_id) then raise exception 'Logistics view permission required'; end if;
  return query select to_jsonb(d) from public.logistics_destinations_v61 d where d.tenant_id=p_tenant_id and (not coalesce(p_active_only,true) or d.active) order by d.active desc,d.destination_type,d.name;
end $$;

create or replace function public.logistics_destination_save_v61(p_tenant_id uuid,p_destination_id uuid default null,p_destination_type text default 'other',p_name text default null,p_code text default null,p_address text default null,p_contact_person text default null,p_phone text default null,p_notes text default null,p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  if p_destination_type not in ('farm','shop','customer','supplier','store','warehouse','processing','market','other') then raise exception 'Invalid destination type'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Destination name is required'; end if;
  if p_destination_id is null then insert into public.logistics_destinations_v61(tenant_id,destination_type,name,code,address,contact_person,phone,notes,active) values(p_tenant_id,p_destination_type,trim(p_name),nullif(trim(coalesce(p_code,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_contact_person,'')),''),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_notes,'')),''),coalesce(p_active,true)) returning id into v_id;
  else update public.logistics_destinations_v61 set destination_type=p_destination_type,name=trim(p_name),code=nullif(trim(coalesce(p_code,'')),''),address=nullif(trim(coalesce(p_address,'')),''),contact_person=nullif(trim(coalesce(p_contact_person,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),active=coalesce(p_active,true),updated_at=now() where id=p_destination_id and tenant_id=p_tenant_id returning id into v_id;if v_id is null then raise exception 'Destination not found'; end if;end if;
  return jsonb_build_object('id',v_id);
end $$;

create or replace function public.logistics_dashboard_v61(p_tenant_id uuid,p_from_date date default current_date,p_to_date date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;
begin
  if not private.logistics_can_view_v61(p_tenant_id) then raise exception 'Logistics view permission required'; end if;
  select jsonb_build_object(
    'operations_total',count(*),'operations_active',count(*) filter(where o.status='active'),'operations_closed',count(*) filter(where o.status='closed'),
    'runs_total',coalesce(sum((select count(*) from public.logistics_vehicle_runs_v61 r where r.operation_id=o.id)),0),
    'runs_on_road',coalesce(sum((select count(*) from public.logistics_vehicle_runs_v61 r where r.operation_id=o.id and r.status='in_transit')),0),
    'pickup_primary_qty',coalesce(sum((select sum(s.actual_pickup_primary_qty) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id)),0),
    'delivery_primary_qty',coalesce(sum((select sum(case when s.action_type='return' then 0 else s.actual_delivery_primary_qty end) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id)),0),
    'returned_primary_qty',coalesce(sum((select sum(case when s.action_type='return' then s.actual_delivery_primary_qty else 0 end) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id)),0),
    'variance_primary_qty',coalesce(sum((select sum(s.variance_primary_qty) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id)),0),
    'variance_stops',coalesce(sum((select count(*) from public.logistics_run_stops_v61 s join public.logistics_vehicle_runs_v61 r on r.id=s.run_id where r.operation_id=o.id and s.variance_primary_qty>0)),0)
  ) into v from public.logistics_operations_v61 o where o.tenant_id=p_tenant_id and o.operation_date between coalesce(p_from_date,current_date) and coalesce(p_to_date,current_date);
  return coalesce(v,'{}'::jsonb);
end $$;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration,minimum_plan_key)
values('logistics_operations','Logistics Operations','Create and execute multi-vehicle, multi-run, multi-stop pickup and delivery operations','Operations',false,514,true,false,false,null)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,sort_order=excluded.sort_order,is_active=true;

insert into public.tenant_modules(tenant_id,module_key,enabled,config,created_at,updated_at)
select tm.tenant_id,'logistics_operations',tm.enabled,tm.config,now(),now() from public.tenant_modules tm where tm.module_key='vehicle_logistics'
on conflict(tenant_id,module_key) do nothing;
insert into public.subscription_plan_modules(plan_id,module_key)
select plan_id,'logistics_operations' from public.subscription_plan_modules where module_key='vehicle_logistics'
on conflict(plan_id,module_key) do nothing;
insert into public.business_template_modules(template_id,module_key)
select template_id,'logistics_operations' from public.business_template_modules where module_key='vehicle_logistics'
on conflict(template_id,module_key) do nothing;
insert into public.module_business_types(module_key,business_type)
select 'logistics_operations',business_type from public.module_business_types where module_key='vehicle_logistics'
on conflict do nothing;

-- Initial dependency is normalized by migration 280 so standalone Operations remains independent.
insert into public.module_dependencies(module_key,depends_on_module_key)
values('logistics_operations','vehicle_logistics') on conflict do nothing;

-- Baseline menu entries. Migration 280 normalizes final parent groups/sort orders.
do $$
declare v_client_parent uuid;v_pos_parent uuid;
begin
  select id into v_client_parent from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='operations' and node_type='group' limit 1;
  if v_client_parent is null then select id into v_client_parent from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='industry' and node_type='group' limit 1; end if;
  if v_client_parent is not null then
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'client','logistics_operations','module','logistics_operations',v_client_parent,'Logistics Operations','route',54,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do nothing;
  end if;
  select id into v_pos_parent from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_key='operations' and node_type='group' limit 1;
  if v_pos_parent is null then select id into v_pos_parent from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_type='group' order by sort_order limit 1; end if;
  if v_pos_parent is not null then
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'pos','logistics_operations','module','logistics_operations',v_pos_parent,'Logistics Operations','route',54,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do nothing;
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'pos','vehicle_logistics','module','vehicle_logistics',v_pos_parent,'Vehicle Logistics','logistics',55,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do nothing;
  end if;
end $$;

grant execute on function public.logistics_operations_list_v61(uuid,uuid,text,text,integer) to authenticated,service_role;
grant execute on function public.logistics_operation_detail_v61(uuid,uuid) to authenticated,service_role;
grant execute on function public.logistics_operation_save_v61(uuid,uuid,date,uuid,text,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.logistics_run_save_v61(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,numeric,numeric,text) to authenticated,service_role;
grant execute on function public.logistics_stop_save_v61(uuid,uuid,uuid,text,uuid,text,text,uuid,text,numeric,numeric,numeric,numeric,text) to authenticated,service_role;
grant execute on function public.logistics_stop_complete_v61(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text) to authenticated,service_role;
grant execute on function public.logistics_run_status_v61(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.logistics_operation_status_v61(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.logistics_drivers_list_v61(uuid,boolean) to authenticated,service_role;
grant execute on function public.logistics_driver_save_v61(uuid,uuid,text,text,text,text,boolean) to authenticated,service_role;
grant execute on function public.logistics_destinations_list_v61(uuid,boolean) to authenticated,service_role;
grant execute on function public.logistics_destination_save_v61(uuid,uuid,text,text,text,text,text,text,text,boolean) to authenticated,service_role;
grant execute on function public.logistics_dashboard_v61(uuid,date,date) to authenticated,service_role;
