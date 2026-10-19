-- THQ ERP v6.1 Logistics Operations multi-run foundation
-- Non-breaking: existing transport_logistics_* tables and RPCs remain intact.

create sequence if not exists public.logistics_operation_number_seq;

create table if not exists public.logistics_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_number text not null default ('LOG-' || to_char(now(),'YYMMDD') || '-' || lpad(nextval('public.logistics_operation_number_seq')::text,6,'0')),
  operation_type text not null default 'general' check (operation_type in ('distribution','collection','mixed','stock_transfer','general')),
  status text not null default 'draft' check (status in ('draft','planned','active','completed','closed','cancelled')),
  operation_date date not null default current_date,
  home_location_id uuid null references public.business_locations(id) on delete set null,
  title text null,
  coordinator_name text null,
  coordinator_phone text null,
  primary_unit text not null default 'kg',
  secondary_unit text null,
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  updated_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,operation_number)
);

create table if not exists public.logistics_destinations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  destination_type text not null default 'other' check (destination_type in ('own_farm','farm','shop','customer','supplier','warehouse','store','processing_unit','market','collection_point','other')),
  linked_entity_type text null,
  linked_entity_id uuid null,
  address text null,
  contact_name text null,
  phone text null,
  latitude numeric null,
  longitude numeric null,
  active boolean not null default true,
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  updated_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.logistics_drivers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  phone text null,
  licence_number text null,
  active boolean not null default true,
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  updated_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.logistics_vehicle_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations(id) on delete cascade,
  run_sequence integer not null,
  vehicle_id uuid not null references public.service_vehicles(id) on delete restrict,
  driver_id uuid null references public.logistics_drivers(id) on delete set null,
  driver_name text null,
  driver_phone text null,
  status text not null default 'planned' check (status in ('planned','loading','in_transit','completed','cancelled')),
  planned_departure_at timestamptz null,
  loading_started_at timestamptz null,
  dispatched_at timestamptz null,
  completed_at timestamptz null,
  cancelled_at timestamptz null,
  cancel_reason text null,
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  updated_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(operation_id,run_sequence)
);

create table if not exists public.logistics_stops (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  run_id uuid not null references public.logistics_vehicle_runs(id) on delete cascade,
  stop_sequence integer not null,
  action text not null default 'waypoint' check (action in ('pickup','delivery','pickup_delivery','return_base','waypoint')),
  destination_id uuid null references public.logistics_destinations(id) on delete set null,
  destination_name text not null,
  status text not null default 'planned' check (status in ('planned','arrived','completed','skipped')),
  planned_arrival_at timestamptz null,
  actual_arrival_at timestamptz null,
  actual_departure_at timestamptz null,
  planned_pickup_primary numeric not null default 0 check (planned_pickup_primary >= 0),
  actual_pickup_primary numeric not null default 0 check (actual_pickup_primary >= 0),
  planned_delivery_primary numeric not null default 0 check (planned_delivery_primary >= 0),
  actual_delivery_primary numeric not null default 0 check (actual_delivery_primary >= 0),
  planned_pickup_secondary numeric not null default 0 check (planned_pickup_secondary >= 0),
  actual_pickup_secondary numeric not null default 0 check (actual_pickup_secondary >= 0),
  planned_delivery_secondary numeric not null default 0 check (planned_delivery_secondary >= 0),
  actual_delivery_secondary numeric not null default 0 check (actual_delivery_secondary >= 0),
  receiver_name text null,
  receiver_phone text null,
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  updated_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(run_id,stop_sequence)
);

create table if not exists public.logistics_variances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  run_id uuid not null references public.logistics_vehicle_runs(id) on delete cascade,
  stop_id uuid null references public.logistics_stops(id) on delete set null,
  variance_type text not null check (variance_type in ('mortality','damage','shortage','weight_variance','rejected','other')),
  primary_quantity numeric not null default 0 check (primary_quantity >= 0),
  secondary_quantity numeric not null default 0 check (secondary_quantity >= 0),
  note text null,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.logistics_document_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations(id) on delete cascade,
  run_id uuid null references public.logistics_vehicle_runs(id) on delete cascade,
  stop_id uuid null references public.logistics_stops(id) on delete cascade,
  document_type text not null,
  document_id uuid null,
  document_reference text null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.logistics_operation_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations(id) on delete cascade,
  run_id uuid null references public.logistics_vehicle_runs(id) on delete cascade,
  stop_id uuid null references public.logistics_stops(id) on delete cascade,
  event_type text not null,
  event_data jsonb not null default '{}'::jsonb,
  actor_user_id uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.logistics_stop_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null references public.logistics_operations(id) on delete cascade,
  run_id uuid null references public.logistics_vehicle_runs(id) on delete cascade,
  stop_id uuid null references public.logistics_stops(id) on delete cascade,
  evidence_type text not null default 'photo',
  file_name text not null,
  storage_path text not null,
  mime_type text not null,
  file_size bigint not null,
  note text null,
  captured_at timestamptz not null default now(),
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_logistics_operations_tenant_date on public.logistics_operations(tenant_id,operation_date desc,status);
create index if not exists idx_logistics_operations_home on public.logistics_operations(tenant_id,home_location_id,status);
create index if not exists idx_logistics_runs_operation on public.logistics_vehicle_runs(tenant_id,operation_id,run_sequence);
create index if not exists idx_logistics_runs_vehicle on public.logistics_vehicle_runs(tenant_id,vehicle_id,status);
create index if not exists idx_logistics_stops_run on public.logistics_stops(tenant_id,run_id,stop_sequence);
create index if not exists idx_logistics_stops_destination on public.logistics_stops(tenant_id,destination_id,status);
create index if not exists idx_logistics_variances_run on public.logistics_variances(tenant_id,run_id,created_at);
create index if not exists idx_logistics_events_operation on public.logistics_operation_events(tenant_id,operation_id,created_at);
create index if not exists idx_logistics_destinations_name on public.logistics_destinations(tenant_id,active,name);
create index if not exists idx_logistics_drivers_name on public.logistics_drivers(tenant_id,active,name);

alter table public.logistics_operations enable row level security;
alter table public.logistics_destinations enable row level security;
alter table public.logistics_drivers enable row level security;
alter table public.logistics_vehicle_runs enable row level security;
alter table public.logistics_stops enable row level security;
alter table public.logistics_variances enable row level security;
alter table public.logistics_document_links enable row level security;
alter table public.logistics_operation_events enable row level security;
alter table public.logistics_stop_evidence enable row level security;

revoke all on public.logistics_operations from anon,authenticated;
revoke all on public.logistics_destinations from anon,authenticated;
revoke all on public.logistics_drivers from anon,authenticated;
revoke all on public.logistics_vehicle_runs from anon,authenticated;
revoke all on public.logistics_stops from anon,authenticated;
revoke all on public.logistics_variances from anon,authenticated;
revoke all on public.logistics_document_links from anon,authenticated;
revoke all on public.logistics_operation_events from anon,authenticated;
revoke all on public.logistics_stop_evidence from anon,authenticated;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration,minimum_plan_key)
values ('logistics_operations','Logistics Operations','Create and execute multi-vehicle pickup and delivery operations','Operations',false,514,true,false,false,null)
on conflict (key) do update set name=excluded.name,description=excluded.description,category=excluded.category,sort_order=excluded.sort_order,is_active=true;

update public.modules set name='Vehicle Logistics',description='Logistics control center, live monitoring, history, exceptions and reports',category='Reports',sort_order=516,is_active=true where key='vehicle_logistics';

insert into public.tenant_modules(tenant_id,module_key,enabled,config,created_at,updated_at)
select tm.tenant_id,'logistics_operations',tm.enabled,tm.config,now(),now()
from public.tenant_modules tm where tm.module_key='vehicle_logistics'
on conflict (tenant_id,module_key) do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select spm.plan_id,'logistics_operations' from public.subscription_plan_modules spm where spm.module_key='vehicle_logistics'
on conflict (plan_id,module_key) do nothing;

insert into public.business_template_modules(template_id,module_key)
select btm.template_id,'logistics_operations' from public.business_template_modules btm where btm.module_key='vehicle_logistics'
on conflict (template_id,module_key) do nothing;

insert into public.module_business_types(module_key,business_type)
select 'logistics_operations',mbt.business_type from public.module_business_types mbt where mbt.module_key='vehicle_logistics'
on conflict do nothing;

insert into public.permissions(key,module_key,name,description) values
 ('logistics_operations.view','logistics_operations','View Logistics Operations','View logistics operations, runs and stops'),
 ('logistics_operations.create','logistics_operations','Create Logistics Operations','Create operations, vehicle runs and stops'),
 ('logistics_operations.execute','logistics_operations','Execute Logistics Operations','Record loading, dispatch, pickup, delivery, variances and completion'),
 ('logistics_operations.manage','logistics_operations','Manage Logistics Operations','Manage logistics master data and operations'),
 ('vehicle_logistics.view','vehicle_logistics','View Vehicle Logistics','View logistics control center and history'),
 ('vehicle_logistics.reports','vehicle_logistics','View Vehicle Logistics Reports','View logistics reports and KPIs')
on conflict (key) do update set module_key=excluded.module_key,name=excluded.name,description=excluded.description;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key
from public.roles r
cross join (values
 ('logistics_operations.view'),('logistics_operations.create'),('logistics_operations.execute'),('logistics_operations.manage'),('vehicle_logistics.view'),('vehicle_logistics.reports')
) p(permission_key)
where r.key in ('owner','manager')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key
from public.roles r
cross join (values ('logistics_operations.view'),('logistics_operations.create'),('logistics_operations.execute'),('vehicle_logistics.view')) p(permission_key)
where r.key='store_keeper'
on conflict do nothing;

-- Move/create menu nodes. Global client Logistics Operations under Operations; Vehicle Logistics under Management.
do $$
declare v_ops uuid; v_mgmt uuid; v_daily uuid; v_pos_mgmt uuid;
begin
 select id into v_ops from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='operations' and node_type='group' limit 1;
 select id into v_mgmt from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='management' and node_type='group' limit 1;
 select id into v_daily from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_key='daily' and node_type='group' limit 1;
 select id into v_pos_mgmt from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_key='pos_management' and node_type='group' limit 1;

 if v_ops is not null then
   insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
   values(null,'client','logistics_operations','module','logistics_operations',v_ops,'Logistics Operations','route',56,true,false,'{}'::jsonb)
   on conflict ((coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid)),app_key,node_key) do update
   set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
 end if;
 if v_mgmt is not null then
   update public.app_menu_nodes_v45 set parent_id=v_mgmt,label='Vehicle Logistics',icon_key='analytics',sort_order=35,enabled=true,updated_at=now()
   where tenant_id is null and app_key='client' and node_key='vehicle_logistics';
 end if;
 if v_daily is not null then
   insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
   values(null,'pos','logistics_operations','module','logistics_operations',v_daily,'Logistics Operations','route',35,true,false,'{}'::jsonb)
   on conflict ((coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid)),app_key,node_key) do update
   set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
 end if;
 if v_pos_mgmt is not null then
   insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
   values(null,'pos','vehicle_logistics','module','vehicle_logistics',v_pos_mgmt,'Vehicle Logistics','analytics',55,true,false,'{}'::jsonb)
   on conflict ((coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid)),app_key,node_key) do update
   set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
 end if;
end $$;

create or replace function private.logistics_allowed_v610(p_tenant_id uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
 select private.erp_user_has_tenant_access(p_tenant_id)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,p_permission));
$$;

create or replace function private.logistics_event_v610(p_tenant_id uuid,p_operation_id uuid,p_run_id uuid,p_stop_id uuid,p_event_type text,p_event_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 insert into public.logistics_operation_events(tenant_id,operation_id,run_id,stop_id,event_type,event_data)
 values(p_tenant_id,p_operation_id,p_run_id,p_stop_id,p_event_type,coalesce(p_event_data,'{}'::jsonb));
end $$;

create or replace function public.logistics_destinations_list_v610(p_tenant_id uuid,p_query text default '',p_active_only boolean default true)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.view') then raise exception 'Logistics operations view permission required'; end if;
 return query select to_jsonb(d) from public.logistics_destinations d
 where d.tenant_id=p_tenant_id and (not p_active_only or d.active)
 and (coalesce(trim(p_query),'')='' or d.name ilike '%'||trim(p_query)||'%' or coalesce(d.address,'') ilike '%'||trim(p_query)||'%' or coalesce(d.phone,'') ilike '%'||trim(p_query)||'%')
 order by d.active desc,d.name;
end $$;

create or replace function public.logistics_destination_save_v610(
 p_tenant_id uuid,p_destination_id uuid,p_name text,p_destination_type text,p_address text default null,p_contact_name text default null,p_phone text default null,p_latitude numeric default null,p_longitude numeric default null,p_active boolean default true,p_notes text default null,p_linked_entity_type text default null,p_linked_entity_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Destination name is required'; end if;
 if p_destination_type not in ('own_farm','farm','shop','customer','supplier','warehouse','store','processing_unit','market','collection_point','other') then raise exception 'Invalid destination type'; end if;
 if p_destination_id is null then
   insert into public.logistics_destinations(tenant_id,name,destination_type,address,contact_name,phone,latitude,longitude,active,notes,linked_entity_type,linked_entity_id)
   values(p_tenant_id,trim(p_name),p_destination_type,nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_contact_name,'')),''),nullif(trim(coalesce(p_phone,'')),''),p_latitude,p_longitude,coalesce(p_active,true),nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_linked_entity_type,'')),''),p_linked_entity_id)
   returning id into v_id;
 else
   update public.logistics_destinations set name=trim(p_name),destination_type=p_destination_type,address=nullif(trim(coalesce(p_address,'')),''),contact_name=nullif(trim(coalesce(p_contact_name,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),latitude=p_latitude,longitude=p_longitude,active=coalesce(p_active,true),notes=nullif(trim(coalesce(p_notes,'')),''),linked_entity_type=nullif(trim(coalesce(p_linked_entity_type,'')),''),linked_entity_id=p_linked_entity_id,updated_by=auth.uid(),updated_at=now()
   where id=p_destination_id and tenant_id=p_tenant_id returning id into v_id;
   if v_id is null then raise exception 'Destination not found'; end if;
 end if;
 return v_id;
end $$;

create or replace function public.logistics_drivers_list_v610(p_tenant_id uuid,p_query text default '',p_active_only boolean default true)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.view') then raise exception 'Logistics operations view permission required'; end if;
 return query select to_jsonb(d) from public.logistics_drivers d
 where d.tenant_id=p_tenant_id and (not p_active_only or d.active)
 and (coalesce(trim(p_query),'')='' or d.name ilike '%'||trim(p_query)||'%' or coalesce(d.phone,'') ilike '%'||trim(p_query)||'%' or coalesce(d.licence_number,'') ilike '%'||trim(p_query)||'%')
 order by d.active desc,d.name;
end $$;

create or replace function public.logistics_driver_save_v610(p_tenant_id uuid,p_driver_id uuid,p_name text,p_phone text default null,p_licence_number text default null,p_active boolean default true,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Driver name is required'; end if;
 if p_driver_id is null then
   insert into public.logistics_drivers(tenant_id,name,phone,licence_number,active,notes) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_licence_number,'')),''),coalesce(p_active,true),nullif(trim(coalesce(p_notes,'')),'')) returning id into v_id;
 else
   update public.logistics_drivers set name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),licence_number=nullif(trim(coalesce(p_licence_number,'')),''),active=coalesce(p_active,true),notes=nullif(trim(coalesce(p_notes,'')),''),updated_by=auth.uid(),updated_at=now() where id=p_driver_id and tenant_id=p_tenant_id returning id into v_id;
   if v_id is null then raise exception 'Driver not found'; end if;
 end if;
 return v_id;
end $$;

create or replace function public.logistics_operation_save_v610(
 p_tenant_id uuid,p_operation_id uuid,p_home_location_id uuid,p_operation_type text,p_operation_date date,p_title text default null,p_primary_unit text default 'kg',p_secondary_unit text default null,p_coordinator_name text default null,p_coordinator_phone text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_operations%rowtype; v_create boolean := p_operation_id is null;
begin
 if v_create then
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.create') then raise exception 'Logistics operations create permission required'; end if;
 else
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 end if;
 if p_operation_type not in ('distribution','collection','mixed','stock_transfer','general') then raise exception 'Invalid operation type'; end if;
 if nullif(trim(coalesce(p_primary_unit,'')),'') is null then raise exception 'Primary unit is required'; end if;
 if p_home_location_id is not null then
   if not exists(select 1 from public.business_locations l where l.id=p_home_location_id and l.tenant_id=p_tenant_id and l.active) then raise exception 'Active home location is required'; end if;
   if not private.erp_document_scope_allowed(p_tenant_id,p_home_location_id,p_home_location_id,'operate') then raise exception 'Location access denied'; end if;
 end if;
 if v_create then
   insert into public.logistics_operations(tenant_id,operation_type,operation_date,home_location_id,title,primary_unit,secondary_unit,coordinator_name,coordinator_phone,notes,status)
   values(p_tenant_id,p_operation_type,coalesce(p_operation_date,current_date),p_home_location_id,nullif(trim(coalesce(p_title,'')),''),trim(p_primary_unit),nullif(trim(coalesce(p_secondary_unit,'')),''),nullif(trim(coalesce(p_coordinator_name,'')),''),nullif(trim(coalesce(p_coordinator_phone,'')),''),nullif(trim(coalesce(p_notes,'')),''),'draft') returning * into v;
   perform private.logistics_event_v610(p_tenant_id,v.id,null,null,'operation_created',jsonb_build_object('operation_number',v.operation_number,'operation_type',v.operation_type));
 else
   select * into v from public.logistics_operations where id=p_operation_id and tenant_id=p_tenant_id for update;
   if not found then raise exception 'Logistics operation not found'; end if;
   if v.status in ('closed','cancelled') then raise exception 'Closed or cancelled operation cannot be edited'; end if;
   update public.logistics_operations set operation_type=p_operation_type,operation_date=coalesce(p_operation_date,operation_date),home_location_id=p_home_location_id,title=nullif(trim(coalesce(p_title,'')),''),primary_unit=trim(p_primary_unit),secondary_unit=nullif(trim(coalesce(p_secondary_unit,'')),''),coordinator_name=nullif(trim(coalesce(p_coordinator_name,'')),''),coordinator_phone=nullif(trim(coalesce(p_coordinator_phone,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_by=auth.uid(),updated_at=now() where id=p_operation_id returning * into v;
   perform private.logistics_event_v610(p_tenant_id,v.id,null,null,'operation_updated','{}'::jsonb);
 end if;
 return to_jsonb(v);
end $$;

create or replace function public.logistics_run_save_v610(
 p_tenant_id uuid,p_operation_id uuid,p_run_id uuid,p_vehicle_id uuid,p_driver_id uuid default null,p_driver_name text default null,p_driver_phone text default null,p_planned_departure_at timestamptz default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_vehicle_runs%rowtype; v_op public.logistics_operations%rowtype; v_seq int; v_driver public.logistics_drivers%rowtype;
begin
 if p_run_id is null then
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.create') then raise exception 'Logistics operations create permission required'; end if;
 else
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 end if;
 select * into v_op from public.logistics_operations where id=p_operation_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Logistics operation not found'; end if;
 if v_op.status in ('closed','cancelled') then raise exception 'Closed or cancelled operation cannot be changed'; end if;
 if not exists(select 1 from public.service_vehicles x where x.id=p_vehicle_id and x.tenant_id=p_tenant_id and x.active) then raise exception 'Active vehicle is required'; end if;
 if p_driver_id is not null then
   select * into v_driver from public.logistics_drivers where id=p_driver_id and tenant_id=p_tenant_id and active;
   if not found then raise exception 'Active driver not found'; end if;
 end if;
 if p_run_id is null then
   select coalesce(max(run_sequence),0)+1 into v_seq from public.logistics_vehicle_runs where operation_id=p_operation_id;
   insert into public.logistics_vehicle_runs(tenant_id,operation_id,run_sequence,vehicle_id,driver_id,driver_name,driver_phone,planned_departure_at,notes)
   values(p_tenant_id,p_operation_id,v_seq,p_vehicle_id,p_driver_id,coalesce(nullif(trim(coalesce(p_driver_name,'')),''),v_driver.name),coalesce(nullif(trim(coalesce(p_driver_phone,'')),''),v_driver.phone),p_planned_departure_at,nullif(trim(coalesce(p_notes,'')),'')) returning * into v;
   update public.logistics_operations set status=case when status='draft' then 'planned' else status end,updated_at=now(),updated_by=auth.uid() where id=p_operation_id;
   perform private.logistics_event_v610(p_tenant_id,p_operation_id,v.id,null,'run_created',jsonb_build_object('run_sequence',v.run_sequence,'vehicle_id',v.vehicle_id));
 else
   select * into v from public.logistics_vehicle_runs where id=p_run_id and operation_id=p_operation_id and tenant_id=p_tenant_id for update;
   if not found then raise exception 'Vehicle run not found'; end if;
   if v.status in ('completed','cancelled') then raise exception 'Completed or cancelled run cannot be edited'; end if;
   update public.logistics_vehicle_runs set vehicle_id=p_vehicle_id,driver_id=p_driver_id,driver_name=coalesce(nullif(trim(coalesce(p_driver_name,'')),''),v_driver.name),driver_phone=coalesce(nullif(trim(coalesce(p_driver_phone,'')),''),v_driver.phone),planned_departure_at=p_planned_departure_at,notes=nullif(trim(coalesce(p_notes,'')),''),updated_by=auth.uid(),updated_at=now() where id=p_run_id returning * into v;
   perform private.logistics_event_v610(p_tenant_id,p_operation_id,v.id,null,'run_updated','{}'::jsonb);
 end if;
 return to_jsonb(v);
end $$;

create or replace function public.logistics_stop_save_v610(
 p_tenant_id uuid,p_run_id uuid,p_stop_id uuid,p_stop_sequence integer,p_action text,p_destination_id uuid,p_destination_name text,p_planned_arrival_at timestamptz default null,p_planned_pickup_primary numeric default 0,p_planned_delivery_primary numeric default 0,p_planned_pickup_secondary numeric default 0,p_planned_delivery_secondary numeric default 0,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_stops%rowtype; v_run public.logistics_vehicle_runs%rowtype; v_dest public.logistics_destinations%rowtype; v_seq int;
begin
 if p_stop_id is null then
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.create') then raise exception 'Logistics operations create permission required'; end if;
 else
   if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 end if;
 if p_action not in ('pickup','delivery','pickup_delivery','return_base','waypoint') then raise exception 'Invalid stop action'; end if;
 if least(coalesce(p_planned_pickup_primary,0),coalesce(p_planned_delivery_primary,0),coalesce(p_planned_pickup_secondary,0),coalesce(p_planned_delivery_secondary,0)) < 0 then raise exception 'Stop quantities cannot be negative'; end if;
 select * into v_run from public.logistics_vehicle_runs where id=p_run_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Vehicle run not found'; end if;
 if v_run.status in ('completed','cancelled') then raise exception 'Completed or cancelled run cannot be changed'; end if;
 if p_destination_id is not null then
   select * into v_dest from public.logistics_destinations where id=p_destination_id and tenant_id=p_tenant_id and active;
   if not found then raise exception 'Destination not found'; end if;
 end if;
 if nullif(trim(coalesce(p_destination_name,'')),'') is null and p_destination_id is null then raise exception 'Destination is required'; end if;
 if p_stop_id is null then
   if p_stop_sequence is null or p_stop_sequence < 1 then select coalesce(max(stop_sequence),0)+1 into v_seq from public.logistics_stops where run_id=p_run_id; else v_seq:=p_stop_sequence; end if;
   insert into public.logistics_stops(tenant_id,run_id,stop_sequence,action,destination_id,destination_name,planned_arrival_at,planned_pickup_primary,planned_delivery_primary,planned_pickup_secondary,planned_delivery_secondary,notes)
   values(p_tenant_id,p_run_id,v_seq,p_action,p_destination_id,coalesce(nullif(trim(coalesce(p_destination_name,'')),''),v_dest.name),p_planned_arrival_at,coalesce(p_planned_pickup_primary,0),coalesce(p_planned_delivery_primary,0),coalesce(p_planned_pickup_secondary,0),coalesce(p_planned_delivery_secondary,0),nullif(trim(coalesce(p_notes,'')),'')) returning * into v;
   perform private.logistics_event_v610(p_tenant_id,v_run.operation_id,p_run_id,v.id,'stop_created',jsonb_build_object('sequence',v.stop_sequence,'action',v.action,'destination',v.destination_name));
 else
   select * into v from public.logistics_stops where id=p_stop_id and run_id=p_run_id and tenant_id=p_tenant_id for update;
   if not found then raise exception 'Stop not found'; end if;
   if v.status in ('completed','skipped') then raise exception 'Completed or skipped stop cannot be edited'; end if;
   update public.logistics_stops set stop_sequence=coalesce(p_stop_sequence,stop_sequence),action=p_action,destination_id=p_destination_id,destination_name=coalesce(nullif(trim(coalesce(p_destination_name,'')),''),v_dest.name,destination_name),planned_arrival_at=p_planned_arrival_at,planned_pickup_primary=coalesce(p_planned_pickup_primary,0),planned_delivery_primary=coalesce(p_planned_delivery_primary,0),planned_pickup_secondary=coalesce(p_planned_pickup_secondary,0),planned_delivery_secondary=coalesce(p_planned_delivery_secondary,0),notes=nullif(trim(coalesce(p_notes,'')),''),updated_by=auth.uid(),updated_at=now() where id=p_stop_id returning * into v;
   perform private.logistics_event_v610(p_tenant_id,v_run.operation_id,p_run_id,v.id,'stop_updated','{}'::jsonb);
 end if;
 return to_jsonb(v);
end $$;

create or replace function public.logistics_operation_detail_v610(p_tenant_id uuid,p_operation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_op public.logistics_operations%rowtype; v_runs jsonb; v_events jsonb; v_links jsonb;
begin
 if not (private.logistics_allowed_v610(p_tenant_id,'logistics_operations.view') or private.logistics_allowed_v610(p_tenant_id,'vehicle_logistics.view')) then raise exception 'Logistics view permission required'; end if;
 select * into v_op from public.logistics_operations where id=p_operation_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Logistics operation not found'; end if;
 select coalesce(jsonb_agg(rj order by (rj->>'run_sequence')::int),'[]'::jsonb) into v_runs from (
   select jsonb_build_object(
    'id',r.id,'run_sequence',r.run_sequence,'status',r.status,'vehicle_id',r.vehicle_id,'vehicle_registration',v.registration_number,'vehicle_type',v.vehicle_type,'make_model',v.make_model,'driver_id',r.driver_id,'driver_name',r.driver_name,'driver_phone',r.driver_phone,'planned_departure_at',r.planned_departure_at,'loading_started_at',r.loading_started_at,'dispatched_at',r.dispatched_at,'completed_at',r.completed_at,'notes',r.notes,
    'pickup_primary',coalesce((select sum(s.actual_pickup_primary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0),
    'delivery_primary',coalesce((select sum(s.actual_delivery_primary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0),
    'variance_primary',coalesce((select sum(x.primary_quantity) from public.logistics_variances x where x.run_id=r.id),0),
    'current_load_primary',coalesce((select sum(s.actual_pickup_primary-s.actual_delivery_primary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0)-coalesce((select sum(x.primary_quantity) from public.logistics_variances x where x.run_id=r.id),0),
    'pickup_secondary',coalesce((select sum(s.actual_pickup_secondary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0),
    'delivery_secondary',coalesce((select sum(s.actual_delivery_secondary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0),
    'variance_secondary',coalesce((select sum(x.secondary_quantity) from public.logistics_variances x where x.run_id=r.id),0),
    'current_load_secondary',coalesce((select sum(s.actual_pickup_secondary-s.actual_delivery_secondary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0)-coalesce((select sum(x.secondary_quantity) from public.logistics_variances x where x.run_id=r.id),0),
    'stops',coalesce((select jsonb_agg(to_jsonb(s) order by s.stop_sequence) from public.logistics_stops s where s.run_id=r.id),'[]'::jsonb),
    'variances',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.logistics_variances x where x.run_id=r.id),'[]'::jsonb)
   ) rj
   from public.logistics_vehicle_runs r join public.service_vehicles v on v.id=r.vehicle_id
   where r.operation_id=p_operation_id and r.tenant_id=p_tenant_id
 ) q;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at),'[]'::jsonb) into v_events from public.logistics_operation_events e where e.operation_id=p_operation_id and e.tenant_id=p_tenant_id;
 select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at),'[]'::jsonb) into v_links from public.logistics_document_links l where l.operation_id=p_operation_id and l.tenant_id=p_tenant_id and l.active;
 return jsonb_build_object('operation',to_jsonb(v_op),'runs',v_runs,'events',v_events,'links',v_links);
end $$;

create or replace function public.logistics_operations_list_v610(p_tenant_id uuid,p_home_location_id uuid default null,p_status text default null,p_query text default '',p_from_date date default null,p_to_date date default null,p_limit integer default 300)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if not (private.logistics_allowed_v610(p_tenant_id,'logistics_operations.view') or private.logistics_allowed_v610(p_tenant_id,'vehicle_logistics.view')) then raise exception 'Logistics view permission required'; end if;
 return query
 select jsonb_build_object(
  'id',o.id,'operation_number',o.operation_number,'operation_type',o.operation_type,'status',o.status,'operation_date',o.operation_date,'home_location_id',o.home_location_id,'home_location',bl.name,'title',o.title,'coordinator_name',o.coordinator_name,'primary_unit',o.primary_unit,'secondary_unit',o.secondary_unit,'notes',o.notes,'created_at',o.created_at,'updated_at',o.updated_at,
  'run_count',(select count(*) from public.logistics_vehicle_runs r where r.operation_id=o.id),
  'active_runs',(select count(*) from public.logistics_vehicle_runs r where r.operation_id=o.id and r.status in ('loading','in_transit')),
  'pickup_primary',coalesce((select sum(s.actual_pickup_primary) from public.logistics_vehicle_runs r join public.logistics_stops s on s.run_id=r.id where r.operation_id=o.id and s.status='completed'),0),
  'delivery_primary',coalesce((select sum(s.actual_delivery_primary) from public.logistics_vehicle_runs r join public.logistics_stops s on s.run_id=r.id where r.operation_id=o.id and s.status='completed'),0),
  'variance_primary',coalesce((select sum(x.primary_quantity) from public.logistics_vehicle_runs r join public.logistics_variances x on x.run_id=r.id where r.operation_id=o.id),0),
  'stop_count',(select count(*) from public.logistics_vehicle_runs r join public.logistics_stops s on s.run_id=r.id where r.operation_id=o.id)
 )
 from public.logistics_operations o
 left join public.business_locations bl on bl.id=o.home_location_id and bl.tenant_id=o.tenant_id
 where o.tenant_id=p_tenant_id
   and (p_home_location_id is null or o.home_location_id=p_home_location_id)
   and (p_status is null or p_status='' or o.status=p_status)
   and (p_from_date is null or o.operation_date>=p_from_date)
   and (p_to_date is null or o.operation_date<=p_to_date)
   and (coalesce(trim(p_query),'')='' or o.operation_number ilike '%'||trim(p_query)||'%' or coalesce(o.title,'') ilike '%'||trim(p_query)||'%' or coalesce(o.coordinator_name,'') ilike '%'||trim(p_query)||'%' or exists(select 1 from public.logistics_vehicle_runs r join public.service_vehicles v on v.id=r.vehicle_id where r.operation_id=o.id and (v.registration_number ilike '%'||trim(p_query)||'%' or coalesce(r.driver_name,'') ilike '%'||trim(p_query)||'%')))
 order by o.operation_date desc,o.created_at desc
 limit greatest(1,least(coalesce(p_limit,300),1000));
end $$;

create or replace function public.logistics_run_status_v610(p_tenant_id uuid,p_run_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_vehicle_runs%rowtype; v_op public.logistics_operations%rowtype; v_now timestamptz:=now();
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.execute') then raise exception 'Logistics operations execute permission required'; end if;
 select * into v from public.logistics_vehicle_runs where id=p_run_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Vehicle run not found'; end if;
 select * into v_op from public.logistics_operations where id=v.operation_id and tenant_id=p_tenant_id for update;
 if p_status='loading' then
   if v.status<>'planned' then raise exception 'Only a planned run can start loading'; end if;
   update public.logistics_vehicle_runs set status='loading',loading_started_at=coalesce(loading_started_at,v_now),notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_run_id returning * into v;
   update public.logistics_operations set status='active',updated_by=auth.uid(),updated_at=v_now where id=v.operation_id and status in ('draft','planned');
 elsif p_status='in_transit' then
   if v.status not in ('planned','loading') then raise exception 'Run cannot be dispatched from its current status'; end if;
   if not exists(select 1 from public.logistics_stops s where s.run_id=p_run_id) then raise exception 'Add at least one pickup or delivery stop before dispatch'; end if;
   update public.logistics_vehicle_runs set status='in_transit',loading_started_at=coalesce(loading_started_at,v_now),dispatched_at=coalesce(dispatched_at,v_now),notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_run_id returning * into v;
   update public.logistics_operations set status='active',updated_by=auth.uid(),updated_at=v_now where id=v.operation_id and status in ('draft','planned');
 elsif p_status='cancelled' then
   if v.status='completed' then raise exception 'Completed run cannot be cancelled'; end if;
   update public.logistics_vehicle_runs set status='cancelled',cancelled_at=v_now,cancel_reason=nullif(trim(coalesce(p_note,'')),''),updated_by=auth.uid(),updated_at=v_now where id=p_run_id returning * into v;
 else
   raise exception 'Invalid run status action';
 end if;
 perform private.logistics_event_v610(p_tenant_id,v.operation_id,v.id,null,'run_status_changed',jsonb_build_object('status',v.status,'note',nullif(trim(coalesce(p_note,'')),'')));
 return to_jsonb(v);
end $$;

create or replace function public.logistics_stop_execute_v610(
 p_tenant_id uuid,p_stop_id uuid,p_status text,p_actual_pickup_primary numeric default 0,p_actual_delivery_primary numeric default 0,p_actual_pickup_secondary numeric default 0,p_actual_delivery_secondary numeric default 0,p_receiver_name text default null,p_receiver_phone text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_stops%rowtype; v_run public.logistics_vehicle_runs%rowtype; v_now timestamptz:=now();
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.execute') then raise exception 'Logistics operations execute permission required'; end if;
 if least(coalesce(p_actual_pickup_primary,0),coalesce(p_actual_delivery_primary,0),coalesce(p_actual_pickup_secondary,0),coalesce(p_actual_delivery_secondary,0)) < 0 then raise exception 'Actual quantities cannot be negative'; end if;
 select * into v from public.logistics_stops where id=p_stop_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Stop not found'; end if;
 select * into v_run from public.logistics_vehicle_runs where id=v.run_id and tenant_id=p_tenant_id;
 if v_run.status not in ('loading','in_transit') then raise exception 'Run must be loading or in transit'; end if;
 if p_status='arrived' then
   if v.status<>'planned' then raise exception 'Only a planned stop can be marked arrived'; end if;
   update public.logistics_stops set status='arrived',actual_arrival_at=coalesce(actual_arrival_at,v_now),updated_by=auth.uid(),updated_at=v_now where id=p_stop_id returning * into v;
 elsif p_status='completed' then
   if v.status not in ('planned','arrived') then raise exception 'Stop cannot be completed from its current status'; end if;
   update public.logistics_stops set status='completed',actual_arrival_at=coalesce(actual_arrival_at,v_now),actual_departure_at=v_now,actual_pickup_primary=coalesce(p_actual_pickup_primary,0),actual_delivery_primary=coalesce(p_actual_delivery_primary,0),actual_pickup_secondary=coalesce(p_actual_pickup_secondary,0),actual_delivery_secondary=coalesce(p_actual_delivery_secondary,0),receiver_name=nullif(trim(coalesce(p_receiver_name,'')),''),receiver_phone=nullif(trim(coalesce(p_receiver_phone,'')),''),notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_stop_id returning * into v;
 elsif p_status='skipped' then
   if v.status='completed' then raise exception 'Completed stop cannot be skipped'; end if;
   update public.logistics_stops set status='skipped',actual_departure_at=v_now,notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_stop_id returning * into v;
 else
   raise exception 'Invalid stop status action';
 end if;
 perform private.logistics_event_v610(p_tenant_id,v_run.operation_id,v_run.id,v.id,'stop_status_changed',jsonb_build_object('status',v.status,'pickup_primary',v.actual_pickup_primary,'delivery_primary',v.actual_delivery_primary,'pickup_secondary',v.actual_pickup_secondary,'delivery_secondary',v.actual_delivery_secondary));
 return to_jsonb(v);
end $$;

create or replace function public.logistics_variance_add_v610(p_tenant_id uuid,p_run_id uuid,p_stop_id uuid,p_variance_type text,p_primary_quantity numeric default 0,p_secondary_quantity numeric default 0,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_variances%rowtype; v_run public.logistics_vehicle_runs%rowtype;
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.execute') then raise exception 'Logistics operations execute permission required'; end if;
 if p_variance_type not in ('mortality','damage','shortage','weight_variance','rejected','other') then raise exception 'Invalid variance type'; end if;
 if coalesce(p_primary_quantity,0)<0 or coalesce(p_secondary_quantity,0)<0 then raise exception 'Variance quantity cannot be negative'; end if;
 if coalesce(p_primary_quantity,0)=0 and coalesce(p_secondary_quantity,0)=0 then raise exception 'Variance quantity is required'; end if;
 select * into v_run from public.logistics_vehicle_runs where id=p_run_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Vehicle run not found'; end if;
 if v_run.status in ('completed','cancelled') then raise exception 'Cannot add variance to completed or cancelled run'; end if;
 if p_stop_id is not null and not exists(select 1 from public.logistics_stops s where s.id=p_stop_id and s.run_id=p_run_id and s.tenant_id=p_tenant_id) then raise exception 'Stop not found'; end if;
 insert into public.logistics_variances(tenant_id,run_id,stop_id,variance_type,primary_quantity,secondary_quantity,note) values(p_tenant_id,p_run_id,p_stop_id,p_variance_type,coalesce(p_primary_quantity,0),coalesce(p_secondary_quantity,0),nullif(trim(coalesce(p_note,'')),'')) returning * into v;
 perform private.logistics_event_v610(p_tenant_id,v_run.operation_id,p_run_id,p_stop_id,'variance_recorded',jsonb_build_object('variance_type',v.variance_type,'primary_quantity',v.primary_quantity,'secondary_quantity',v.secondary_quantity));
 return to_jsonb(v);
end $$;

create or replace function public.logistics_run_complete_v610(p_tenant_id uuid,p_run_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_vehicle_runs%rowtype; v_pickup numeric; v_delivery numeric; v_variance numeric; v_pickup2 numeric; v_delivery2 numeric; v_variance2 numeric; v_now timestamptz:=now();
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.execute') then raise exception 'Logistics operations execute permission required'; end if;
 select * into v from public.logistics_vehicle_runs where id=p_run_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Vehicle run not found'; end if;
 if v.status='completed' then return to_jsonb(v); end if;
 if v.status='cancelled' then raise exception 'Cancelled run cannot be completed'; end if;
 if exists(select 1 from public.logistics_stops s where s.run_id=p_run_id and s.status not in ('completed','skipped')) then raise exception 'Complete or skip every stop before completing the run'; end if;
 select coalesce(sum(actual_pickup_primary),0),coalesce(sum(actual_delivery_primary),0),coalesce(sum(actual_pickup_secondary),0),coalesce(sum(actual_delivery_secondary),0) into v_pickup,v_delivery,v_pickup2,v_delivery2 from public.logistics_stops where run_id=p_run_id and status='completed';
 select coalesce(sum(primary_quantity),0),coalesce(sum(secondary_quantity),0) into v_variance,v_variance2 from public.logistics_variances where run_id=p_run_id;
 if abs(v_pickup-v_delivery-v_variance)>0.001 then raise exception 'Primary quantity is not reconciled. Remaining load: %',v_pickup-v_delivery-v_variance; end if;
 if abs(v_pickup2-v_delivery2-v_variance2)>0.001 then raise exception 'Secondary quantity is not reconciled. Remaining load: %',v_pickup2-v_delivery2-v_variance2; end if;
 update public.logistics_vehicle_runs set status='completed',completed_at=v_now,notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_run_id returning * into v;
 perform private.logistics_event_v610(p_tenant_id,v.operation_id,v.id,null,'run_completed',jsonb_build_object('pickup_primary',v_pickup,'delivery_primary',v_delivery,'variance_primary',v_variance,'pickup_secondary',v_pickup2,'delivery_secondary',v_delivery2,'variance_secondary',v_variance2));
 if not exists(select 1 from public.logistics_vehicle_runs r where r.operation_id=v.operation_id and r.status not in ('completed','cancelled')) then update public.logistics_operations set status='completed',updated_by=auth.uid(),updated_at=v_now where id=v.operation_id and status not in ('closed','cancelled'); end if;
 return to_jsonb(v);
end $$;

create or replace function public.logistics_operation_status_v610(p_tenant_id uuid,p_operation_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_operations%rowtype; v_now timestamptz:=now();
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.manage') then raise exception 'Logistics operations manage permission required'; end if;
 select * into v from public.logistics_operations where id=p_operation_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Logistics operation not found'; end if;
 if p_status='closed' then
   if exists(select 1 from public.logistics_vehicle_runs r where r.operation_id=p_operation_id and r.status not in ('completed','cancelled')) then raise exception 'Complete or cancel every vehicle run before closing operation'; end if;
   if not exists(select 1 from public.logistics_vehicle_runs r where r.operation_id=p_operation_id) then raise exception 'Operation has no vehicle runs'; end if;
   update public.logistics_operations set status='closed',notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_operation_id returning * into v;
 elsif p_status='cancelled' then
   if exists(select 1 from public.logistics_vehicle_runs r where r.operation_id=p_operation_id and r.status in ('loading','in_transit')) then raise exception 'Cancel active vehicle runs first'; end if;
   update public.logistics_operations set status='cancelled',notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_by=auth.uid(),updated_at=v_now where id=p_operation_id returning * into v;
 else
   raise exception 'Invalid operation status action';
 end if;
 perform private.logistics_event_v610(p_tenant_id,p_operation_id,null,null,'operation_status_changed',jsonb_build_object('status',v.status,'note',nullif(trim(coalesce(p_note,'')),'')));
 return to_jsonb(v);
end $$;

create or replace function public.logistics_document_link_v610(p_tenant_id uuid,p_operation_id uuid,p_run_id uuid,p_stop_id uuid,p_document_type text,p_document_id uuid default null,p_document_reference text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.logistics_document_links%rowtype;
begin
 if not private.logistics_allowed_v610(p_tenant_id,'logistics_operations.create') then raise exception 'Logistics operations create permission required'; end if;
 if not exists(select 1 from public.logistics_operations o where o.id=p_operation_id and o.tenant_id=p_tenant_id) then raise exception 'Operation not found'; end if;
 if nullif(trim(coalesce(p_document_type,'')),'') is null then raise exception 'Document type is required'; end if;
 insert into public.logistics_document_links(tenant_id,operation_id,run_id,stop_id,document_type,document_id,document_reference,metadata)
 values(p_tenant_id,p_operation_id,p_run_id,p_stop_id,trim(p_document_type),p_document_id,nullif(trim(coalesce(p_document_reference,'')),''),coalesce(p_metadata,'{}'::jsonb)) returning * into v;
 perform private.logistics_event_v610(p_tenant_id,p_operation_id,p_run_id,p_stop_id,'document_linked',jsonb_build_object('document_type',v.document_type,'document_reference',v.document_reference));
 return to_jsonb(v);
end $$;

create or replace function public.vehicle_logistics_control_center_v610(p_tenant_id uuid,p_from_date date default null,p_to_date date default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_from date:=coalesce(p_from_date,current_date); v_to date:=coalesce(p_to_date,current_date); v_summary jsonb; v_active jsonb; v_recent jsonb; v_by_vehicle jsonb; v_by_destination jsonb; v_variances jsonb;
begin
 if not (private.logistics_allowed_v610(p_tenant_id,'vehicle_logistics.view') or private.logistics_allowed_v610(p_tenant_id,'vehicle_logistics.reports')) then raise exception 'Vehicle logistics view permission required'; end if;
 select jsonb_build_object(
  'operations',count(*),
  'active_operations',count(*) filter(where status in ('planned','active','completed')),
  'closed_operations',count(*) filter(where status='closed'),
  'cancelled_operations',count(*) filter(where status='cancelled'),
  'vehicle_runs',(select count(*) from public.logistics_vehicle_runs r join public.logistics_operations x on x.id=r.operation_id where x.tenant_id=p_tenant_id and x.operation_date between v_from and v_to),
  'active_runs',(select count(*) from public.logistics_vehicle_runs r join public.logistics_operations x on x.id=r.operation_id where x.tenant_id=p_tenant_id and x.operation_date between v_from and v_to and r.status in ('loading','in_transit')),
  'pickup_primary',coalesce((select sum(s.actual_pickup_primary) from public.logistics_stops s join public.logistics_vehicle_runs r on r.id=s.run_id join public.logistics_operations x on x.id=r.operation_id where x.tenant_id=p_tenant_id and x.operation_date between v_from and v_to and s.status='completed'),0),
  'delivery_primary',coalesce((select sum(s.actual_delivery_primary) from public.logistics_stops s join public.logistics_vehicle_runs r on r.id=s.run_id join public.logistics_operations x on x.id=r.operation_id where x.tenant_id=p_tenant_id and x.operation_date between v_from and v_to and s.status='completed'),0),
  'variance_primary',coalesce((select sum(z.primary_quantity) from public.logistics_variances z join public.logistics_vehicle_runs r on r.id=z.run_id join public.logistics_operations x on x.id=r.operation_id where x.tenant_id=p_tenant_id and x.operation_date between v_from and v_to),0),
  'legacy_transfer_trips',(select count(*) from public.transport_logistics_trips t where t.tenant_id=p_tenant_id and t.created_at::date between v_from and v_to)
 ) into v_summary from public.logistics_operations o where o.tenant_id=p_tenant_id and o.operation_date between v_from and v_to;
 select coalesce(jsonb_agg(q order by q->>'operation_number'),'[]'::jsonb) into v_active from (
  select jsonb_build_object('operation_id',o.id,'operation_number',o.operation_number,'title',o.title,'operation_type',o.operation_type,'operation_date',o.operation_date,'run_id',r.id,'run_sequence',r.run_sequence,'run_status',r.status,'vehicle_registration',v.registration_number,'driver_name',r.driver_name,'current_load_primary',coalesce((select sum(s.actual_pickup_primary-s.actual_delivery_primary) from public.logistics_stops s where s.run_id=r.id and s.status='completed'),0)-coalesce((select sum(z.primary_quantity) from public.logistics_variances z where z.run_id=r.id),0),'next_stop',(select s.destination_name from public.logistics_stops s where s.run_id=r.id and s.status in ('planned','arrived') order by s.stop_sequence limit 1)) q
  from public.logistics_operations o join public.logistics_vehicle_runs r on r.operation_id=o.id join public.service_vehicles v on v.id=r.vehicle_id
  where o.tenant_id=p_tenant_id and r.status in ('loading','in_transit')
 ) x;
 select coalesce(jsonb_agg(q order by (q->>'operation_date') desc),'[]'::jsonb) into v_recent from (
  select jsonb_build_object('id',o.id,'operation_number',o.operation_number,'operation_date',o.operation_date,'operation_type',o.operation_type,'status',o.status,'title',o.title,'run_count',(select count(*) from public.logistics_vehicle_runs r where r.operation_id=o.id),'pickup_primary',coalesce((select sum(s.actual_pickup_primary) from public.logistics_vehicle_runs r join public.logistics_stops s on s.run_id=r.id where r.operation_id=o.id and s.status='completed'),0),'delivery_primary',coalesce((select sum(s.actual_delivery_primary) from public.logistics_vehicle_runs r join public.logistics_stops s on s.run_id=r.id where r.operation_id=o.id and s.status='completed'),0)) q
  from public.logistics_operations o where o.tenant_id=p_tenant_id order by o.operation_date desc,o.created_at desc limit 50
 ) x;
 select coalesce(jsonb_agg(q order by (q->>'total_primary')::numeric desc),'[]'::jsonb) into v_by_vehicle from (
  select jsonb_build_object('vehicle_id',v.id,'registration_number',v.registration_number,'run_count',count(distinct r.id),'total_primary',coalesce(sum(s.actual_pickup_primary),0),'delivered_primary',coalesce(sum(s.actual_delivery_primary),0)) q
  from public.logistics_operations o join public.logistics_vehicle_runs r on r.operation_id=o.id join public.service_vehicles v on v.id=r.vehicle_id left join public.logistics_stops s on s.run_id=r.id and s.status='completed'
  where o.tenant_id=p_tenant_id and o.operation_date between v_from and v_to group by v.id,v.registration_number
 ) x;
 select coalesce(jsonb_agg(q order by (q->>'delivered_primary')::numeric desc),'[]'::jsonb) into v_by_destination from (
  select jsonb_build_object('destination_id',s.destination_id,'destination_name',s.destination_name,'stop_count',count(*),'picked_primary',sum(s.actual_pickup_primary),'delivered_primary',sum(s.actual_delivery_primary)) q
  from public.logistics_operations o join public.logistics_vehicle_runs r on r.operation_id=o.id join public.logistics_stops s on s.run_id=r.id
  where o.tenant_id=p_tenant_id and o.operation_date between v_from and v_to and s.status='completed' group by s.destination_id,s.destination_name
 ) x;
 select coalesce(jsonb_agg(q order by (q->>'quantity')::numeric desc),'[]'::jsonb) into v_variances from (
  select jsonb_build_object('variance_type',z.variance_type,'quantity',sum(z.primary_quantity),'secondary_quantity',sum(z.secondary_quantity),'count',count(*)) q
  from public.logistics_operations o join public.logistics_vehicle_runs r on r.operation_id=o.id join public.logistics_variances z on z.run_id=r.id
  where o.tenant_id=p_tenant_id and o.operation_date between v_from and v_to group by z.variance_type
 ) x;
 return jsonb_build_object('from_date',v_from,'to_date',v_to,'summary',v_summary,'active_runs',v_active,'recent_operations',v_recent,'by_vehicle',v_by_vehicle,'by_destination',v_by_destination,'variances',v_variances);
end $$;

-- Vehicle master is shared by Transport Service and Logistics Operations.
create or replace function public.service_vehicles_list_v51(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'logistics_operations.view') or private.erp_has_permission(p_tenant_id,'logistics_operations.create') or private.erp_has_permission(p_tenant_id,'logistics_operations.execute') or private.erp_has_permission(p_tenant_id,'logistics_operations.manage') or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')) then raise exception 'Permission denied';end if;
 return query
 select jsonb_build_object('id',v.id,'tracking_code',v.tracking_code,'registration_number',v.registration_number,'vehicle_type',v.vehicle_type,'make_model',v.make_model,'capacity',v.capacity,'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,'driver_phone',v.driver_phone,'active',v.active,'location_id',v.location_id,'location_name',l.name,'open_jobs',(select count(*) from public.service_jobs j where j.tenant_id=v.tenant_id and j.vehicle_id=v.id and j.status in('planned','in_progress')),'created_at',v.created_at,'updated_at',v.updated_at)
 from public.service_vehicles v left join public.business_locations l on l.id=v.location_id and l.tenant_id=v.tenant_id
 where v.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,v.location_id,p_location_id,'view') order by v.active desc,v.registration_number;
end $$;

create or replace function public.service_vehicle_save_v51(p_tenant_id uuid,p_vehicle_id uuid,p_location_id uuid,p_registration_number text,p_vehicle_type text,p_make_model text,p_capacity numeric,p_capacity_unit text,p_driver_name text,p_driver_phone text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_old public.service_vehicles%rowtype;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'logistics_operations.manage')) then raise exception 'Transport service or logistics manage permission required';end if;
 if nullif(trim(coalesce(p_registration_number,'')),'') is null then raise exception 'Registration number is required';end if;
 if coalesce(p_capacity,0)<0 then raise exception 'Capacity cannot be negative';end if;
 if p_location_id is null or not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then raise exception 'Active store/location is required';end if;
 if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
 if exists(select 1 from public.service_vehicles x where x.tenant_id=p_tenant_id and upper(trim(x.registration_number))=upper(trim(p_registration_number)) and x.id is distinct from p_vehicle_id) then raise exception 'Vehicle registration number already exists';end if;
 if p_vehicle_id is not null then
   select * into v_old from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id for update;
   if not found then raise exception 'Vehicle not found';end if;
   if not private.erp_document_scope_allowed(p_tenant_id,v_old.location_id,v_old.location_id,'operate') then raise exception 'You cannot edit this vehicle';end if;
   if not coalesce(p_active,true) and (exists(select 1 from public.service_jobs j where j.tenant_id=p_tenant_id and j.vehicle_id=p_vehicle_id and j.status in('planned','in_progress')) or exists(select 1 from public.logistics_vehicle_runs r where r.tenant_id=p_tenant_id and r.vehicle_id=p_vehicle_id and r.status in('planned','loading','in_transit'))) then raise exception 'Complete/cancel open service jobs or logistics runs before deactivating this vehicle';end if;
 end if;
 if p_vehicle_id is null then
   insert into public.service_vehicles(tenant_id,location_id,registration_number,vehicle_type,make_model,capacity,capacity_unit,driver_name,driver_phone,active)
   values(p_tenant_id,p_location_id,upper(trim(p_registration_number)),nullif(trim(coalesce(p_vehicle_type,'')),''),nullif(trim(coalesce(p_make_model,'')),''),coalesce(p_capacity,0),nullif(trim(coalesce(p_capacity_unit,'')),''),nullif(trim(coalesce(p_driver_name,'')),''),nullif(trim(coalesce(p_driver_phone,'')),''),coalesce(p_active,true)) returning id into v_id;
 else
   update public.service_vehicles set location_id=p_location_id,registration_number=upper(trim(p_registration_number)),vehicle_type=nullif(trim(coalesce(p_vehicle_type,'')),''),make_model=nullif(trim(coalesce(p_make_model,'')),''),capacity=coalesce(p_capacity,0),capacity_unit=nullif(trim(coalesce(p_capacity_unit,'')),''),driver_name=nullif(trim(coalesce(p_driver_name,'')),''),driver_phone=nullif(trim(coalesce(p_driver_phone,'')),''),active=coalesce(p_active,true),updated_at=now() where id=p_vehicle_id and tenant_id=p_tenant_id returning id into v_id;
 end if;
 perform private.business_audit_write_v471(p_tenant_id,'service.vehicle.save','service_vehicle',v_id,upper(trim(p_registration_number)),case when p_vehicle_id is null then null else to_jsonb(v_old) end,jsonb_build_object('location_id',p_location_id,'active',coalesce(p_active,true)));
 return v_id;
end $$;

revoke all on function public.logistics_destinations_list_v610(uuid,text,boolean) from public,anon;
revoke all on function public.logistics_destination_save_v610(uuid,uuid,text,text,text,text,text,numeric,numeric,boolean,text,text,uuid) from public,anon;
revoke all on function public.logistics_drivers_list_v610(uuid,text,boolean) from public,anon;
revoke all on function public.logistics_driver_save_v610(uuid,uuid,text,text,text,boolean,text) from public,anon;
revoke all on function public.logistics_operation_save_v610(uuid,uuid,uuid,text,date,text,text,text,text,text,text) from public,anon;
revoke all on function public.logistics_run_save_v610(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,text) from public,anon;
revoke all on function public.logistics_stop_save_v610(uuid,uuid,uuid,integer,text,uuid,text,timestamptz,numeric,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.logistics_operation_detail_v610(uuid,uuid) from public,anon;
revoke all on function public.logistics_operations_list_v610(uuid,uuid,text,text,date,date,integer) from public,anon;
revoke all on function public.logistics_run_status_v610(uuid,uuid,text,text) from public,anon;
revoke all on function public.logistics_stop_execute_v610(uuid,uuid,text,numeric,numeric,numeric,numeric,text,text,text) from public,anon;
revoke all on function public.logistics_variance_add_v610(uuid,uuid,uuid,text,numeric,numeric,text) from public,anon;
revoke all on function public.logistics_run_complete_v610(uuid,uuid,text) from public,anon;
revoke all on function public.logistics_operation_status_v610(uuid,uuid,text,text) from public,anon;
revoke all on function public.logistics_document_link_v610(uuid,uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon;
revoke all on function public.vehicle_logistics_control_center_v610(uuid,date,date) from public,anon;

grant execute on function public.logistics_destinations_list_v610(uuid,text,boolean) to authenticated,service_role;
grant execute on function public.logistics_destination_save_v610(uuid,uuid,text,text,text,text,text,numeric,numeric,boolean,text,text,uuid) to authenticated,service_role;
grant execute on function public.logistics_drivers_list_v610(uuid,text,boolean) to authenticated,service_role;
grant execute on function public.logistics_driver_save_v610(uuid,uuid,text,text,text,boolean,text) to authenticated,service_role;
grant execute on function public.logistics_operation_save_v610(uuid,uuid,uuid,text,date,text,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.logistics_run_save_v610(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,text) to authenticated,service_role;
grant execute on function public.logistics_stop_save_v610(uuid,uuid,uuid,integer,text,uuid,text,timestamptz,numeric,numeric,numeric,numeric,text) to authenticated,service_role;
grant execute on function public.logistics_operation_detail_v610(uuid,uuid) to authenticated,service_role;
grant execute on function public.logistics_operations_list_v610(uuid,uuid,text,text,date,date,integer) to authenticated,service_role;
grant execute on function public.logistics_run_status_v610(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.logistics_stop_execute_v610(uuid,uuid,text,numeric,numeric,numeric,numeric,text,text,text) to authenticated,service_role;
grant execute on function public.logistics_variance_add_v610(uuid,uuid,uuid,text,numeric,numeric,text) to authenticated,service_role;
grant execute on function public.logistics_run_complete_v610(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.logistics_operation_status_v610(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.logistics_document_link_v610(uuid,uuid,uuid,uuid,text,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.vehicle_logistics_control_center_v610(uuid,date,date) to authenticated,service_role;
;
