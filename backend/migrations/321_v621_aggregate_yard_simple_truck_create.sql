begin;

create or replace function public.aggregate_vehicle_create_v621(
  p_tenant_id uuid,
  p_location_id uuid,
  p_registration_number text,
  p_vehicle_type text default 'Truck',
  p_make_model text default null,
  p_driver_name text default null,
  p_driver_phone text default null,
  p_capacity_cft numeric default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_id uuid;
  v_reg text := upper(trim(coalesce(p_registration_number,'')));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if v_reg = '' then
    raise exception 'Registration number is required';
  end if;

  if p_location_id is null or not exists(
    select 1
    from public.business_locations l
    where l.id=p_location_id
      and l.tenant_id=p_tenant_id
      and l.active
  ) then
    raise exception 'Active yard/store is required';
  end if;

  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');

  if coalesce(p_capacity_cft,0) < 0 then
    raise exception 'Capacity cannot be negative';
  end if;

  if exists(
    select 1
    from public.service_vehicles v
    where v.tenant_id=p_tenant_id
      and upper(trim(v.registration_number))=v_reg
  ) then
    raise exception 'Vehicle registration number already exists';
  end if;

  insert into public.service_vehicles(
    tenant_id, location_id, registration_number, vehicle_type, make_model,
    capacity, capacity_unit, driver_name, driver_phone, active
  )
  values(
    p_tenant_id, p_location_id, v_reg,
    nullif(trim(coalesce(p_vehicle_type,'')),''),
    nullif(trim(coalesce(p_make_model,'')),''),
    coalesce(p_capacity_cft,0), 'CFT',
    nullif(trim(coalesce(p_driver_name,'')),''),
    nullif(trim(coalesce(p_driver_phone,'')),''),
    true
  )
  returning id into v_id;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate.vehicle.create',
    'service_vehicle',
    v_id,
    v_reg,
    null,
    jsonb_build_object(
      'location_id',p_location_id,
      'vehicle_type',nullif(trim(coalesce(p_vehicle_type,'')),''),
      'capacity_cft',coalesce(p_capacity_cft,0)
    )
  );

  return v_id;
end
$function$;

revoke all on function public.aggregate_vehicle_create_v621(
  uuid,uuid,text,text,text,text,text,numeric
) from public,anon;

grant execute on function public.aggregate_vehicle_create_v621(
  uuid,uuid,text,text,text,text,text,numeric
) to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  321,
  '6.2.1-aggregate-yard-simple-truck-create',
  'Aggregate Yard Simple Truck Create',
  'Adds a minimal Material Yard truck-create RPC using aggregate-yard manage permission, location scope checks, duplicate registration protection and audit logging. Existing service vehicle and aggregate profile tables remain authoritative.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
