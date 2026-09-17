-- THQ ERP v6.1 Logistics Operations contract hardening
-- Canonical source mirror of the live v610_logistics_operations_contract_hardening change.
-- IMPORTANT: already applied to flexi-erp-dev. Do not manually re-run there.

update public.modules set name='Logistics Operations',description='Create and execute multi-vehicle, multi-run, multi-stop pickup and delivery operations',category='Operations',sort_order=514,is_active=true,is_beta=false where key='logistics_operations';
update public.modules set name='Vehicle Logistics',description='Logistics control center, live monitoring, history, exceptions and reports',category='Reports',sort_order=516,is_active=true,is_beta=false where key='vehicle_logistics';

insert into public.permissions(key,module_key,name,description) values
 ('logistics_operations.view','logistics_operations','View Logistics Operations','View logistics operations, runs and stops'),
 ('logistics_operations.create','logistics_operations','Create Logistics Operations','Create operations, vehicle runs and stops'),
 ('logistics_operations.execute','logistics_operations','Execute Logistics Operations','Record loading, dispatch, pickup, delivery, variances and completion'),
 ('logistics_operations.manage','logistics_operations','Manage Logistics Operations','Manage logistics master data and operations'),
 ('vehicle_logistics.view','vehicle_logistics','View Vehicle Logistics','View logistics control center and history'),
 ('vehicle_logistics.reports','vehicle_logistics','View Vehicle Logistics Reports','View logistics reports and KPIs')
on conflict(key) do update set module_key=excluded.module_key,name=excluded.name,description=excluded.description;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key from public.roles r cross join (values
 ('logistics_operations.view'),('logistics_operations.create'),('logistics_operations.execute'),('logistics_operations.manage'),('vehicle_logistics.view'),('vehicle_logistics.reports')
) p(permission_key) where r.key in ('owner','manager') on conflict do nothing;
insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key from public.roles r cross join (values
 ('logistics_operations.view'),('logistics_operations.create'),('logistics_operations.execute'),('vehicle_logistics.view')
) p(permission_key) where r.key='store_keeper' on conflict do nothing;

-- Logistics Operations is independent. Vehicle Logistics is its reporting/control layer.
delete from public.module_dependencies
where (module_key='logistics_operations' and depends_on_module_key='vehicle_logistics')
   or (module_key='vehicle_logistics' and depends_on_module_key='stock_transfers');
insert into public.module_dependencies(module_key,depends_on_module_key)
values('vehicle_logistics','logistics_operations') on conflict do nothing;

-- Normalize menu placement to the operational/reporting split.
do $$
declare v_ops uuid;v_mgmt uuid;v_daily uuid;v_pos_mgmt uuid;
begin
  select id into v_ops from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='operations' and node_type='group' limit 1;
  select id into v_mgmt from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='management' and node_type='group' limit 1;
  select id into v_daily from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_key='daily' and node_type='group' limit 1;
  select id into v_pos_mgmt from public.app_menu_nodes_v45 where tenant_id is null and app_key='pos' and node_key='pos_management' and node_type='group' limit 1;
  if v_ops is not null then
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'client','logistics_operations','module','logistics_operations',v_ops,'Logistics Operations','route',56,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do update set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
  end if;
  if v_mgmt is not null then
    update public.app_menu_nodes_v45 set parent_id=v_mgmt,label='Vehicle Logistics',icon_key='analytics',sort_order=35,enabled=true,updated_at=now()
    where tenant_id is null and app_key='client' and node_key='vehicle_logistics';
  end if;
  if v_daily is not null then
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'pos','logistics_operations','module','logistics_operations',v_daily,'Logistics Operations','route',35,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do update set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
  end if;
  if v_pos_mgmt is not null then
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
    values(null,'pos','vehicle_logistics','module','vehicle_logistics',v_pos_mgmt,'Vehicle Logistics','analytics',55,true,false,'{}'::jsonb)
    on conflict (coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key) do update set module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=true,updated_at=now();
  end if;
end $$;

create or replace function private.logistics_can_view_v61(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
  select private.erp_user_has_tenant_access(p_tenant_id) and (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'logistics_operations.view')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.create')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.execute')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.manage')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports')
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
  select private.erp_user_has_tenant_access(p_tenant_id) and (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'logistics_operations.create')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.execute')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.manage')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
  );
$$;

create or replace function public.logistics_stop_complete_v61(
  p_tenant_id uuid,p_stop_id uuid,p_actual_pickup_primary_qty numeric default 0,p_actual_delivery_primary_qty numeric default 0,
  p_actual_pickup_secondary_qty numeric default null,p_actual_delivery_secondary_qty numeric default null,p_variance_primary_qty numeric default 0,
  p_variance_secondary_qty numeric default null,p_variance_reason text default null,p_receiver_name text default null,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_stop public.logistics_run_stops_v61%rowtype;v_run public.logistics_vehicle_runs_v61%rowtype;v_before_primary numeric:=0;v_before_secondary numeric:=0;v_after_primary numeric:=0;v_after_secondary numeric:=0;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required'; end if;
  select * into v_stop from public.logistics_run_stops_v61 where id=p_stop_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Route stop not found';end if;
  select * into v_run from public.logistics_vehicle_runs_v61 where id=v_stop.run_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Vehicle run not found';end if;
  if v_stop.status='completed' then raise exception 'Stop is already completed';end if;
  if v_run.status not in ('loading','in_transit') then raise exception 'Run must be loading or in transit before completing a stop';end if;
  if least(coalesce(p_actual_pickup_primary_qty,0),coalesce(p_actual_delivery_primary_qty,0),coalesce(p_actual_pickup_secondary_qty,0),coalesce(p_actual_delivery_secondary_qty,0),coalesce(p_variance_primary_qty,0),coalesce(p_variance_secondary_qty,0))<0 then raise exception 'Actual quantities cannot be negative';end if;
  if (coalesce(p_variance_primary_qty,0)>0 or coalesce(p_variance_secondary_qty,0)>0) and coalesce(p_variance_reason,'') not in ('mortality','shortage','damage','weight_variance','rejected','other') then raise exception 'Variance reason is required';end if;
  select v_run.starting_primary_qty+coalesce(sum(s.actual_pickup_primary_qty-s.actual_delivery_primary_qty-s.variance_primary_qty),0),coalesce(v_run.starting_secondary_qty,0)+coalesce(sum(coalesce(s.actual_pickup_secondary_qty,0)-coalesce(s.actual_delivery_secondary_qty,0)-coalesce(s.variance_secondary_qty,0)),0)
    into v_before_primary,v_before_secondary from public.logistics_run_stops_v61 s where s.run_id=v_run.id and s.status='completed';
  v_after_primary:=v_before_primary+coalesce(p_actual_pickup_primary_qty,0)-coalesce(p_actual_delivery_primary_qty,0)-coalesce(p_variance_primary_qty,0);
  v_after_secondary:=v_before_secondary+coalesce(p_actual_pickup_secondary_qty,0)-coalesce(p_actual_delivery_secondary_qty,0)-coalesce(p_variance_secondary_qty,0);
  if v_after_primary < -0.001 then raise exception 'Primary delivery/variance exceeds the truck load. Resulting load: %',v_after_primary;end if;
  if v_after_secondary < -0.001 then raise exception 'Secondary delivery/variance exceeds the truck load. Resulting load: %',v_after_secondary;end if;
  update public.logistics_run_stops_v61 set actual_pickup_primary_qty=coalesce(p_actual_pickup_primary_qty,0),actual_delivery_primary_qty=coalesce(p_actual_delivery_primary_qty,0),actual_pickup_secondary_qty=p_actual_pickup_secondary_qty,actual_delivery_secondary_qty=p_actual_delivery_secondary_qty,variance_primary_qty=coalesce(p_variance_primary_qty,0),variance_secondary_qty=p_variance_secondary_qty,variance_reason=nullif(trim(coalesce(p_variance_reason,'')),''),receiver_name=nullif(trim(coalesce(p_receiver_name,'')),''),note=coalesce(nullif(trim(coalesce(p_note,'')),''),note),status='completed',arrived_at=coalesce(arrived_at,now()),completed_at=now(),updated_at=now() where id=p_stop_id;
  perform private.logistics_event_v61(p_tenant_id,v_run.operation_id,v_run.id,p_stop_id,'stop_completed','Route stop completed',jsonb_build_object('pickup_primary',coalesce(p_actual_pickup_primary_qty,0),'delivery_primary',coalesce(p_actual_delivery_primary_qty,0),'variance_primary',coalesce(p_variance_primary_qty,0),'variance_reason',p_variance_reason,'remaining_primary',v_after_primary,'remaining_secondary',v_after_secondary));
  return jsonb_build_object('id',p_stop_id,'status','completed','remaining_primary',v_after_primary,'remaining_secondary',v_after_secondary);
end $$;

create or replace function public.logistics_run_status_v61(p_tenant_id uuid,p_run_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_run public.logistics_vehicle_runs_v61%rowtype;v_op public.logistics_operations_v61%rowtype;v_remaining_primary numeric:=0;v_remaining_secondary numeric:=0;
begin
  if not private.logistics_can_operate_v61(p_tenant_id) then raise exception 'Logistics operate permission required';end if;
  select * into v_run from public.logistics_vehicle_runs_v61 where id=p_run_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Vehicle run not found';end if;
  select * into v_op from public.logistics_operations_v61 where id=v_run.operation_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Logistics operation not found';end if;
  if p_status not in ('loading','in_transit','completed','cancelled') then raise exception 'Invalid run status';end if;
  if v_run.status in ('completed','cancelled') then raise exception 'Run is already final';end if;
  if p_status='loading' and v_run.status<>'planned' then raise exception 'Only a planned run can start loading';end if;
  if p_status='in_transit' and v_run.status not in ('planned','loading') then raise exception 'Run cannot be dispatched from its current status';end if;
  if p_status='completed' and v_run.status not in ('loading','in_transit') then raise exception 'Only a loading or in-transit run can be completed';end if;
  if p_status in ('loading','in_transit') then
    if v_run.vehicle_id is null then raise exception 'Assign an active vehicle before starting this run';end if;
    if not exists(select 1 from public.service_vehicles v where v.id=v_run.vehicle_id and v.tenant_id=p_tenant_id and v.active) then raise exception 'Assigned vehicle is not active';end if;
    if exists(select 1 from public.logistics_vehicle_runs_v61 x where x.tenant_id=p_tenant_id and x.vehicle_id=v_run.vehicle_id and x.id<>v_run.id and x.status in ('loading','in_transit')) then raise exception 'Vehicle is already assigned to another active logistics run';end if;
  end if;
  if p_status='in_transit' and not exists(select 1 from public.logistics_run_stops_v61 s where s.run_id=v_run.id) then raise exception 'Add at least one pickup or delivery stop before dispatch';end if;
  if p_status='completed' then
    if exists(select 1 from public.logistics_run_stops_v61 s where s.run_id=v_run.id and s.status not in ('completed','skipped','cancelled')) then raise exception 'Complete, skip or cancel every stop before completing the run';end if;
    if not exists(select 1 from public.logistics_run_stops_v61 s where s.run_id=v_run.id) then raise exception 'Vehicle run has no route stops';end if;
    select v_run.starting_primary_qty+coalesce(sum(s.actual_pickup_primary_qty-s.actual_delivery_primary_qty-s.variance_primary_qty) filter(where s.status='completed'),0),coalesce(v_run.starting_secondary_qty,0)+coalesce(sum(coalesce(s.actual_pickup_secondary_qty,0)-coalesce(s.actual_delivery_secondary_qty,0)-coalesce(s.variance_secondary_qty,0)) filter(where s.status='completed'),0)
      into v_remaining_primary,v_remaining_secondary from public.logistics_run_stops_v61 s where s.run_id=v_run.id;
    if abs(v_remaining_primary)>0.001 then raise exception 'Primary quantity is not reconciled. Remaining truck load: %',v_remaining_primary;end if;
    if abs(v_remaining_secondary)>0.001 then raise exception 'Secondary quantity is not reconciled. Remaining truck load: %',v_remaining_secondary;end if;
  end if;
  update public.logistics_vehicle_runs_v61 set status=p_status,departed_at=case when p_status='in_transit' then coalesce(departed_at,now()) else departed_at end,completed_at=case when p_status='completed' then now() else completed_at end,notes=coalesce(nullif(trim(coalesce(p_note,'')),''),notes),updated_at=now() where id=v_run.id;
  if v_op.status='planned' and p_status in ('loading','in_transit') then update public.logistics_operations_v61 set status='active',started_at=coalesce(started_at,now()),updated_at=now() where id=v_op.id;end if;
  if p_status='completed' and not exists(select 1 from public.logistics_vehicle_runs_v61 x where x.operation_id=v_op.id and x.id<>v_run.id and x.status not in ('completed','cancelled')) then update public.logistics_operations_v61 set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now() where id=v_op.id and status not in ('closed','cancelled');end if;
  perform private.logistics_event_v61(p_tenant_id,v_op.id,v_run.id,null,'run_'||p_status,'Vehicle run '||replace(p_status,'_',' '),jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),''),'remaining_primary',v_remaining_primary,'remaining_secondary',v_remaining_secondary));
  return jsonb_build_object('id',v_run.id,'status',p_status,'remaining_primary',v_remaining_primary,'remaining_secondary',v_remaining_secondary);
end $$;

-- Shared fleet access and deactivation safety for v6.1 Logistics.
create or replace function public.service_vehicles_list_v51(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'logistics_operations.view') or private.erp_has_permission(p_tenant_id,'logistics_operations.create') or private.erp_has_permission(p_tenant_id,'logistics_operations.execute') or private.erp_has_permission(p_tenant_id,'logistics_operations.manage') or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view') or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports')) then raise exception 'Permission denied';end if;
 return query select jsonb_build_object('id',v.id,'tracking_code',v.tracking_code,'registration_number',v.registration_number,'vehicle_type',v.vehicle_type,'make_model',v.make_model,'capacity',v.capacity,'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,'driver_phone',v.driver_phone,'active',v.active,'location_id',v.location_id,'location_name',l.name,'open_jobs',(select count(*) from public.service_jobs j where j.tenant_id=v.tenant_id and j.vehicle_id=v.id and j.status in('planned','in_progress')),'created_at',v.created_at,'updated_at',v.updated_at)
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
   select * into v_old from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Vehicle not found';end if;
   if not private.erp_document_scope_allowed(p_tenant_id,v_old.location_id,v_old.location_id,'operate') then raise exception 'You cannot edit this vehicle';end if;
   if not coalesce(p_active,true) and (exists(select 1 from public.service_jobs j where j.tenant_id=p_tenant_id and j.vehicle_id=p_vehicle_id and j.status in('planned','in_progress')) or exists(select 1 from public.logistics_vehicle_runs r where r.tenant_id=p_tenant_id and r.vehicle_id=p_vehicle_id and r.status in('planned','loading','in_transit')) or exists(select 1 from public.logistics_vehicle_runs_v61 r where r.tenant_id=p_tenant_id and r.vehicle_id=p_vehicle_id and r.status in('planned','loading','in_transit'))) then raise exception 'Complete/cancel open service jobs or logistics runs before deactivating this vehicle';end if;
 end if;
 if p_vehicle_id is null then insert into public.service_vehicles(tenant_id,location_id,registration_number,vehicle_type,make_model,capacity,capacity_unit,driver_name,driver_phone,active) values(p_tenant_id,p_location_id,upper(trim(p_registration_number)),nullif(trim(coalesce(p_vehicle_type,'')),''),nullif(trim(coalesce(p_make_model,'')),''),coalesce(p_capacity,0),nullif(trim(coalesce(p_capacity_unit,'')),''),nullif(trim(coalesce(p_driver_name,'')),''),nullif(trim(coalesce(p_driver_phone,'')),''),coalesce(p_active,true)) returning id into v_id;
 else update public.service_vehicles set location_id=p_location_id,registration_number=upper(trim(p_registration_number)),vehicle_type=nullif(trim(coalesce(p_vehicle_type,'')),''),make_model=nullif(trim(coalesce(p_make_model,'')),''),capacity=coalesce(p_capacity,0),capacity_unit=nullif(trim(coalesce(p_capacity_unit,'')),''),driver_name=nullif(trim(coalesce(p_driver_name,'')),''),driver_phone=nullif(trim(coalesce(p_driver_phone,'')),''),active=coalesce(p_active,true),updated_at=now() where id=p_vehicle_id and tenant_id=p_tenant_id returning id into v_id;end if;
 perform private.business_audit_write_v471(p_tenant_id,'service.vehicle.save','service_vehicle',v_id,upper(trim(p_registration_number)),case when p_vehicle_id is null then null else to_jsonb(v_old) end,jsonb_build_object('location_id',p_location_id,'active',coalesce(p_active,true)));
 return v_id;
end $$;

-- SECURITY DEFINER RPCs are authenticated/service-role only.
revoke all on function public.logistics_operations_list_v61(uuid,uuid,text,text,integer) from public,anon;
revoke all on function public.logistics_operation_detail_v61(uuid,uuid) from public,anon;
revoke all on function public.logistics_operation_save_v61(uuid,uuid,date,uuid,text,text,text,text,text,text) from public,anon;
revoke all on function public.logistics_run_save_v61(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,numeric,numeric,text) from public,anon;
revoke all on function public.logistics_stop_save_v61(uuid,uuid,uuid,text,uuid,text,text,uuid,text,numeric,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.logistics_stop_complete_v61(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text) from public,anon;
revoke all on function public.logistics_run_status_v61(uuid,uuid,text,text) from public,anon;
revoke all on function public.logistics_operation_status_v61(uuid,uuid,text,text) from public,anon;
revoke all on function public.logistics_drivers_list_v61(uuid,boolean) from public,anon;
revoke all on function public.logistics_driver_save_v61(uuid,uuid,text,text,text,text,boolean) from public,anon;
revoke all on function public.logistics_destinations_list_v61(uuid,boolean) from public,anon;
revoke all on function public.logistics_destination_save_v61(uuid,uuid,text,text,text,text,text,text,text,boolean) from public,anon;
revoke all on function public.logistics_dashboard_v61(uuid,date,date) from public,anon;
revoke all on function public.service_vehicles_list_v51(uuid,uuid) from public,anon;
revoke all on function public.service_vehicle_save_v51(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean) from public,anon;

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
grant execute on function public.service_vehicles_list_v51(uuid,uuid) to authenticated,service_role;
grant execute on function public.service_vehicle_save_v51(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean) to authenticated,service_role;
