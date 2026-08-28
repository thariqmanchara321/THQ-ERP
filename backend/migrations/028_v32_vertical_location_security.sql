-- FLEXI ERP V3.2
-- Final location-security pass for Production, Transport Service and Restaurant.
-- Shared master data (production recipes and tenant product/customer/supplier masters)
-- remains tenant-wide; transactional/live operational records are store-scoped.
begin;

create schema if not exists private;

-- Registered system + per-terminal module validation for Restaurant reads/writes.
-- Client systems may use any location granted to the user; POS systems are locked
-- to their assigned store and terminal module selection.
create or replace function private.erp_validate_vertical_device_scope(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_module_key text,
  p_required_access text default 'view'
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_app text;
  v_device_location uuid;
  v_modules text[];
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_device_id is null then raise exception 'A registered system is required'; end if;

  select d.app_type,d.location_id,d.allowed_modules
    into v_app,v_device_location,v_modules
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if not found then raise exception 'Registered system is invalid or revoked'; end if;

  if v_app='pos' then
    if p_location_id is null or p_location_id is distinct from v_device_location then
      raise exception 'POS terminals can only access their assigned store';
    end if;
    if p_module_key is not null and not (p_module_key = any(coalesce(v_modules,'{}'::text[]))) then
      raise exception 'This POS terminal is not enabled for %',p_module_key;
    end if;
    if not private.erp_user_location_allowed(p_tenant_id,p_location_id,p_required_access) then
      raise exception 'Location access denied';
    end if;
  elsif v_app='client' then
    if p_location_id is null then
      if lower(coalesce(p_required_access,'view'))<>'view'
         or not (private.erp_user_is_owner(p_tenant_id)
                 or private.erp_has_permission(p_tenant_id,'locations.view_all')
                 or private.erp_has_permission(p_tenant_id,'locations.manage_all')) then
        raise exception 'Choose an accessible store';
      end if;
    elsif not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,p_required_access) then
      raise exception 'Location access denied';
    end if;
  else
    raise exception 'Unsupported system type';
  end if;
end $$;
revoke all on function private.erp_validate_vertical_device_scope(uuid,uuid,uuid,text,text) from public;

-- ---------------------------------------------------------------------------
-- Production: recipes/BOMs are tenant-wide configuration; runs are store-scoped.
-- ---------------------------------------------------------------------------
create or replace function public.production_recipes_list_v32(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'production.view')
          or private.erp_has_permission(p_tenant_id,'production.run')
          or private.erp_has_permission(p_tenant_id,'production.manage')) then
    raise exception 'Permission denied';
  end if;
  return public.production_recipes_list(p_tenant_id);
end $$;
grant execute on function public.production_recipes_list_v32(uuid) to authenticated;

create or replace function public.production_runs_list_v32(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_limit integer default 200
)
returns table(
  id uuid,tracking_code text,run_number text,recipe_id uuid,recipe_name text,
  location_id uuid,location_name text,planned_batches numeric,status text,notes text,
  started_at timestamptz,completed_at timestamptz
)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'production.view')
          or private.erp_has_permission(p_tenant_id,'production.run')
          or private.erp_has_permission(p_tenant_id,'production.manage')) then
    raise exception 'Permission denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'view') then
    raise exception 'Location access denied';
  end if;
  return query
  select pr.id,pr.tracking_code,pr.run_number,pr.recipe_id,r.name,pr.location_id,l.name,
         pr.planned_batches,pr.status,pr.notes,pr.started_at,pr.completed_at
  from public.production_runs pr
  join public.production_recipes r on r.id=pr.recipe_id
  left join public.business_locations l on l.id=pr.location_id
  where pr.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,pr.location_id,p_location_id,'view')
  order by pr.started_at desc
  limit greatest(1,least(coalesce(p_limit,200),1000));
end $$;
grant execute on function public.production_runs_list_v32(uuid,uuid,integer) to authenticated;

create or replace function public.production_run_execute_v32(
  p_tenant_id uuid,p_recipe_id uuid,p_location_id uuid,p_batches numeric,p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'operate')
     and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then
    raise exception 'You cannot post production for this store';
  end if;
  return public.production_run_execute(p_tenant_id,p_recipe_id,p_location_id,p_batches,p_notes);
end $$;
grant execute on function public.production_run_execute_v32(uuid,uuid,uuid,numeric,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Transport Service: vehicles and jobs become store-aware.
-- ---------------------------------------------------------------------------
alter table public.service_vehicles
  add column if not exists location_id uuid references public.business_locations(id) on delete set null;

update public.service_vehicles v
set location_id=(
  select l.id from public.business_locations l
  where l.tenant_id=v.tenant_id and l.location_code='MAIN'
  order by l.created_at limit 1
)
where v.location_id is null;

create index if not exists idx_service_vehicles_tenant_location
  on public.service_vehicles(tenant_id,location_id,active,registration_number);

create or replace function public.service_vehicles_list_v32(
  p_tenant_id uuid,p_location_id uuid default null
)
returns setof public.service_vehicles
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'transport_service.view')
          or private.erp_has_permission(p_tenant_id,'transport_service.create')
          or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then
    raise exception 'Permission denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'view') then
    raise exception 'Location access denied';
  end if;
  return query
  select v.* from public.service_vehicles v
  where v.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,v.location_id,p_location_id,'view')
  order by v.active desc,v.registration_number;
end $$;
grant execute on function public.service_vehicles_list_v32(uuid,uuid) to authenticated;

create or replace function public.service_vehicle_save_v32(
  p_tenant_id uuid,p_vehicle_id uuid,p_location_id uuid,p_registration_number text,
  p_vehicle_type text,p_make_model text,p_capacity numeric,p_capacity_unit text,
  p_driver_name text,p_driver_phone text,p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
  v_old_location uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'transport_service.manage') then raise exception 'Permission denied';end if;
  if p_location_id is null or not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then
    raise exception 'Location access denied';
  end if;
  if p_vehicle_id is not null then
    select location_id into v_old_location from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id;
    if v_old_location is null then raise exception 'Vehicle not found';end if;
    if not private.erp_document_scope_allowed(p_tenant_id,v_old_location,v_old_location,'operate') then
      raise exception 'You cannot edit this vehicle';
    end if;
  end if;

  if p_vehicle_id is null then
    insert into public.service_vehicles(
      tenant_id,location_id,registration_number,vehicle_type,make_model,capacity,
      capacity_unit,driver_name,driver_phone,active
    ) values(
      p_tenant_id,p_location_id,upper(trim(p_registration_number)),nullif(trim(p_vehicle_type),''),
      nullif(trim(p_make_model),''),p_capacity,nullif(trim(p_capacity_unit),''),
      nullif(trim(p_driver_name),''),nullif(trim(p_driver_phone),''),coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.service_vehicles
    set location_id=p_location_id,registration_number=upper(trim(p_registration_number)),
        vehicle_type=nullif(trim(p_vehicle_type),''),make_model=nullif(trim(p_make_model),''),
        capacity=p_capacity,capacity_unit=nullif(trim(p_capacity_unit),''),
        driver_name=nullif(trim(p_driver_name),''),driver_phone=nullif(trim(p_driver_phone),''),
        active=coalesce(p_active,true),updated_at=now()
    where id=p_vehicle_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;
  if v_id is null then raise exception 'Vehicle not found';end if;
  perform private.business_audit_write(p_tenant_id,'save','service_vehicle',v_id,null,null,
    jsonb_build_object('location_id',p_location_id,'registration_number',p_registration_number));
  return v_id;
end $$;
grant execute on function public.service_vehicle_save_v32(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean) to authenticated;

create or replace function public.service_jobs_list_v32(
  p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 300
)
returns table(
  id uuid,tracking_code text,job_number text,service_date date,location_id uuid,location_name text,
  customer_id uuid,customer_name text,vehicle_id uuid,registration_number text,from_location text,to_location text,
  distance_km numeric,quantity numeric,quantity_unit text,rate numeric,total_amount numeric,notes text,status text,sale_id uuid
)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'transport_service.view')
          or private.erp_has_permission(p_tenant_id,'transport_service.create')
          or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then
    raise exception 'Permission denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'view') then
    raise exception 'Location access denied';
  end if;
  return query
  select j.id,j.tracking_code,j.job_number,j.service_date,j.location_id,l.name,j.customer_id,c.name,
         j.vehicle_id,v.registration_number,j.from_location,j.to_location,j.distance_km,j.quantity,
         j.quantity_unit,j.rate,j.total_amount,j.notes,j.status,j.sale_id
  from public.service_jobs j
  left join public.business_locations l on l.id=j.location_id
  left join public.customers c on c.id=j.customer_id
  left join public.service_vehicles v on v.id=j.vehicle_id
  where j.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
  order by j.service_date desc,j.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),2000));
end $$;
grant execute on function public.service_jobs_list_v32(uuid,uuid,integer) to authenticated;

create or replace function public.service_job_create_v32(
  p_tenant_id uuid,p_location_id uuid,p_customer_id uuid,p_vehicle_id uuid,p_service_date date,
  p_from_location text,p_to_location text,p_distance_km numeric,p_quantity numeric,p_quantity_unit text,
  p_rate numeric,p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_vehicle_location uuid;
begin
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then
    raise exception 'You cannot create jobs for this store';
  end if;
  if p_vehicle_id is not null then
    select location_id into v_vehicle_location from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id;
    if v_vehicle_location is null then raise exception 'Vehicle not found';end if;
    if v_vehicle_location is distinct from p_location_id then raise exception 'Choose a vehicle assigned to this store';end if;
  end if;
  return public.service_job_create(
    p_tenant_id,p_location_id,p_customer_id,p_vehicle_id,p_service_date,p_from_location,p_to_location,
    p_distance_km,p_quantity,p_quantity_unit,p_rate,p_notes
  );
end $$;
grant execute on function public.service_job_create_v32(uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text) to authenticated;

create or replace function public.service_job_link_sale_by_reference_v32(
  p_tenant_id uuid,p_job_id uuid,p_sale_number text
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_job_location uuid;
  v_sale_id uuid;
  v_sale_location uuid;
begin
  select location_id into v_job_location from public.service_jobs where id=p_job_id and tenant_id=p_tenant_id;
  if v_job_location is null then raise exception 'Service job not found';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,v_job_location,v_job_location,'operate') then
    raise exception 'Location access denied';
  end if;
  select s.id,o.location_id into v_sale_id,v_sale_location
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_number=p_sale_number;
  if v_sale_id is null then raise exception 'Sale not found';end if;
  if v_sale_location is null then
    if not private.erp_user_is_owner(p_tenant_id) then raise exception 'Legacy sale has no store origin';end if;
  elsif v_sale_location is distinct from v_job_location then
    raise exception 'Service job and sale must belong to the same store';
  end if;
  perform public.service_job_link_sale(p_tenant_id,p_job_id,v_sale_id);
end $$;
grant execute on function public.service_job_link_sale_by_reference_v32(uuid,uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Restaurant: all operational/table/KOT actions are location + device scoped.
-- ---------------------------------------------------------------------------
create or replace function public.restaurant_tables_list_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid
)
returns setof public.restaurant_tables
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','view');
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'restaurant.view')
          or private.erp_has_permission(p_tenant_id,'restaurant.order')
          or private.erp_has_permission(p_tenant_id,'restaurant.kot')
          or private.erp_has_permission(p_tenant_id,'restaurant.manage')) then
    raise exception 'Permission denied';
  end if;
  return query
  select t.* from public.restaurant_tables t
  where t.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,t.location_id,p_location_id,'view')
  order by t.area nulls first,t.table_code;
end $$;
grant execute on function public.restaurant_tables_list_v32(uuid,uuid,uuid) to authenticated;

create or replace function public.restaurant_table_save_v32(
  p_tenant_id uuid,p_table_id uuid,p_location_id uuid,p_device_id uuid,p_table_code text,
  p_name text,p_capacity integer,p_area text,p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_old_location uuid;
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','operate');
  if not private.erp_has_permission(p_tenant_id,'restaurant.manage') and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Permission denied';
  end if;
  if p_table_id is not null then
    select location_id into v_old_location from public.restaurant_tables where id=p_table_id and tenant_id=p_tenant_id;
    if v_old_location is null then raise exception 'Table not found';end if;
    if not private.erp_document_scope_allowed(p_tenant_id,v_old_location,v_old_location,'operate') then
      raise exception 'You cannot edit this table';
    end if;
  end if;
  return public.restaurant_table_save(p_tenant_id,p_table_id,p_location_id,p_table_code,p_name,p_capacity,p_area,p_active);
end $$;
grant execute on function public.restaurant_table_save_v32(uuid,uuid,uuid,uuid,text,text,integer,text,boolean) to authenticated;

create or replace function public.restaurant_orders_list_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_live_only boolean default true,p_limit integer default 200
)
returns table(
  id uuid,tracking_code text,order_number text,order_type text,table_id uuid,table_name text,
  customer_id uuid,customer_name text,status text,preparation_minutes integer,chef_note text,
  delivery_address text,opened_at timestamptz,kitchen_sent_at timestamptz,ready_at timestamptz,
  sale_id uuid,total numeric
)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','view');
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'restaurant.view')
          or private.erp_has_permission(p_tenant_id,'restaurant.order')
          or private.erp_has_permission(p_tenant_id,'restaurant.kot')
          or private.erp_has_permission(p_tenant_id,'restaurant.manage')) then
    raise exception 'Permission denied';
  end if;
  return query
  select o.id,o.tracking_code,o.order_number,o.order_type,o.table_id,t.name,o.customer_id,c.name,
         o.status,o.preparation_minutes,o.chef_note,o.delivery_address,o.opened_at,o.kitchen_sent_at,
         o.ready_at,o.sale_id,
         coalesce((select sum(greatest(i.quantity*i.unit_price-i.discount_amount,0)*(1+i.tax_rate/100))
                   from public.restaurant_order_items i where i.order_id=o.id),0)::numeric
  from public.restaurant_orders o
  left join public.restaurant_tables t on t.id=o.table_id
  left join public.customers c on c.id=o.customer_id
  where o.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    and (not p_live_only or o.status not in ('billed','cancelled'))
  order by o.opened_at desc
  limit greatest(1,least(coalesce(p_limit,200),1000));
end $$;
grant execute on function public.restaurant_orders_list_v32(uuid,uuid,uuid,boolean,integer) to authenticated;

create or replace function public.restaurant_order_detail_v32(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_location uuid;
begin
  select location_id into v_location from public.restaurant_orders where id=p_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,v_location,p_device_id,'restaurant','view');
  return public.restaurant_order_detail(p_tenant_id,p_order_id);
end $$;
grant execute on function public.restaurant_order_detail_v32(uuid,uuid,uuid) to authenticated;

create or replace function public.restaurant_order_create_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_order_type text,p_table_id uuid,p_customer_id uuid,
  p_preparation_minutes integer,p_chef_note text,p_delivery_address text,p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','operate');
  if p_table_id is not null and not exists(
    select 1 from public.restaurant_tables t where t.id=p_table_id and t.tenant_id=p_tenant_id and t.location_id=p_location_id and t.active
  ) then raise exception 'Choose a table from this store';end if;
  return public.restaurant_order_create(
    p_tenant_id,p_location_id,p_device_id,p_order_type,p_table_id,p_customer_id,p_preparation_minutes,
    p_chef_note,p_delivery_address,p_items
  );
end $$;
grant execute on function public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb) to authenticated;

create or replace function public.restaurant_kot_send_v32(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid,p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_location uuid;
begin
  select location_id into v_location from public.restaurant_orders where id=p_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,v_location,p_device_id,'restaurant','operate');
  return public.restaurant_kot_send(p_tenant_id,p_order_id,p_note);
end $$;
grant execute on function public.restaurant_kot_send_v32(uuid,uuid,uuid,text) to authenticated;

create or replace function public.restaurant_order_set_status_v32(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid,p_status text
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_location uuid;
begin
  select location_id into v_location from public.restaurant_orders where id=p_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,v_location,p_device_id,'restaurant','operate');
  perform public.restaurant_order_set_status(p_tenant_id,p_order_id,p_status);
end $$;
grant execute on function public.restaurant_order_set_status_v32(uuid,uuid,uuid,text) to authenticated;

create or replace function public.restaurant_order_mark_billed_by_reference_v32(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid,p_sale_number text
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_location uuid;
  v_sale_id uuid;
  v_sale_location uuid;
begin
  select location_id into v_location from public.restaurant_orders where id=p_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,v_location,p_device_id,'restaurant','operate');
  select s.id,o.location_id into v_sale_id,v_sale_location
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_number=p_sale_number;
  if v_sale_id is null then raise exception 'Sale not found';end if;
  if v_sale_location is not null and v_sale_location is distinct from v_location then
    raise exception 'Restaurant order and sale must belong to the same store';
  end if;
  if v_sale_location is null and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Legacy sale has no store origin';
  end if;
  perform public.restaurant_order_mark_billed(p_tenant_id,p_order_id,v_sale_id);
end $$;
grant execute on function public.restaurant_order_mark_billed_by_reference_v32(uuid,uuid,uuid,text) to authenticated;

commit;
select 'Flexi ERP V3.2 vertical location security ready' as status;
