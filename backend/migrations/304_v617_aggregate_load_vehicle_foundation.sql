-- THQ ERP — Aggregate Load & Vehicle Foundation
-- Schema release 304.
--
-- IMPORTANT:
-- Aggregate Load Tickets are operational records only.
-- They DO NOT post stock, GST, accounting, receivables or payables.
-- Existing THQ Purchase/Sales/Transfer authorities remain the only posting paths.

begin;

insert into public.permissions(key,name,module_key,description)
values
 ('aggregate_yard.view','View Material Yard','aggregate_yard','View Material Yard loads, vehicles and operational context'),
 ('aggregate_yard.manage','Manage Material Yard','aggregate_yard','Create and manage Material Yard loads and vehicle profiles'),
 ('aggregate_yard.override_capacity','Override Material Load Capacity','aggregate_yard','Override configured truck CFT capacity with an audit reason')
on conflict(key) do update
set name=excluded.name,module_key=excluded.module_key,description=excluded.description;

create table if not exists public.aggregate_vehicle_profiles_v617(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  vehicle_id uuid not null references public.service_vehicles(id) on delete cascade,
  ownership_type text not null default 'hired'
    check(ownership_type in('owned','hired','supplier','customer')),
  owner_name text,
  owner_phone text,
  body_length_ft numeric check(body_length_ft is null or body_length_ft>0),
  body_width_ft numeric check(body_width_ft is null or body_width_ft>0),
  body_height_ft numeric check(body_height_ft is null or body_height_ft>0),
  nominal_capacity_cft numeric check(nominal_capacity_cft is null or nominal_capacity_cft>0),
  tare_weight_kg numeric check(tare_weight_kg is null or tare_weight_kg>=0),
  max_payload_kg numeric check(max_payload_kg is null or max_payload_kg>0),
  default_freight numeric not null default 0 check(default_freight>=0),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,vehicle_id)
);

create index if not exists aggregate_vehicle_profiles_v617_vehicle_idx
on public.aggregate_vehicle_profiles_v617(vehicle_id);

alter table public.aggregate_vehicle_profiles_v617 enable row level security;

drop policy if exists aggregate_vehicle_profiles_v617_read
on public.aggregate_vehicle_profiles_v617;

create policy aggregate_vehicle_profiles_v617_read
on public.aggregate_vehicle_profiles_v617
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
  )
);

revoke insert,update,delete
on public.aggregate_vehicle_profiles_v617
from authenticated,anon;

grant select on public.aggregate_vehicle_profiles_v617 to authenticated;

create sequence if not exists public.aggregate_load_number_seq_v617;

create table if not exists public.aggregate_loads_v617(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  load_number text not null,
  load_date date not null default current_date,
  direction text not null
    check(direction in('inbound','outbound','direct_delivery')),
  status text not null default 'draft'
    check(status in(
      'draft','loading','dispatched','in_transit','arrived',
      'received','delivered','completed','cancelled'
    )),
  location_id uuid references public.business_locations(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  product_name_snapshot text not null,
  unit_code text not null default 'CFT',
  quantity numeric not null check(quantity>0),
  measurement_method text not null default 'manual'
    check(measurement_method in('manual','dimensions','weighbridge')),
  body_length_ft numeric check(body_length_ft is null or body_length_ft>0),
  body_width_ft numeric check(body_width_ft is null or body_width_ft>0),
  body_height_ft numeric check(body_height_ft is null or body_height_ft>0),
  gross_weight_kg numeric check(gross_weight_kg is null or gross_weight_kg>=0),
  tare_weight_kg numeric check(tare_weight_kg is null or tare_weight_kg>=0),
  net_weight_kg numeric check(net_weight_kg is null or net_weight_kg>=0),
  vehicle_id uuid references public.service_vehicles(id) on delete set null,
  driver_id uuid references public.logistics_drivers_v61(id) on delete set null,
  vehicle_registration_snapshot text,
  driver_name_snapshot text,
  driver_phone_snapshot text,
  supplier_id uuid references public.suppliers(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  source_name text,
  destination_name text,
  source_reference text,
  purchase_id uuid references public.purchases(id) on delete set null,
  sale_id uuid references public.sales(id) on delete set null,
  freight_mode text not null default 'none'
    check(freight_mode in('none','own','hired','supplier','customer','included')),
  freight_amount numeric not null default 0 check(freight_amount>=0),
  capacity_override boolean not null default false,
  capacity_override_reason text,
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,load_number),
  check(
    net_weight_kg is null
    or gross_weight_kg is null
    or tare_weight_kg is null
    or abs(net_weight_kg-(gross_weight_kg-tare_weight_kg))<=0.01
  ),
  check(
    not capacity_override
    or nullif(trim(coalesce(capacity_override_reason,'')),'') is not null
  )
);

create index if not exists aggregate_loads_v617_tenant_date_idx
on public.aggregate_loads_v617(tenant_id,load_date desc,created_at desc);

create index if not exists aggregate_loads_v617_vehicle_idx
on public.aggregate_loads_v617(tenant_id,vehicle_id,created_at desc);

create index if not exists aggregate_loads_v617_status_idx
on public.aggregate_loads_v617(tenant_id,status,created_at desc);

create index if not exists aggregate_loads_v617_purchase_idx
on public.aggregate_loads_v617(tenant_id,purchase_id)
where purchase_id is not null;

create index if not exists aggregate_loads_v617_sale_idx
on public.aggregate_loads_v617(tenant_id,sale_id)
where sale_id is not null;

alter table public.aggregate_loads_v617 enable row level security;

drop policy if exists aggregate_loads_v617_read
on public.aggregate_loads_v617;

create policy aggregate_loads_v617_read
on public.aggregate_loads_v617
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
  )
);

revoke insert,update,delete
on public.aggregate_loads_v617
from authenticated,anon;

grant select on public.aggregate_loads_v617 to authenticated;

create table if not exists public.aggregate_load_events_v617(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  load_id uuid not null references public.aggregate_loads_v617(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists aggregate_load_events_v617_load_idx
on public.aggregate_load_events_v617(tenant_id,load_id,created_at);

alter table public.aggregate_load_events_v617 enable row level security;

drop policy if exists aggregate_load_events_v617_read
on public.aggregate_load_events_v617;

create policy aggregate_load_events_v617_read
on public.aggregate_load_events_v617
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
  )
);

revoke insert,update,delete
on public.aggregate_load_events_v617
from authenticated,anon;

grant select on public.aggregate_load_events_v617 to authenticated;

create or replace function private.aggregate_yard_grant_default_permissions_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  insert into public.role_permissions(role_id,permission_key)
  select r.id,p.key
  from public.roles r
  join public.permissions p on p.module_key='aggregate_yard'
  where r.tenant_id=p_tenant_id
    and (
      r.key='owner'
      or (
        r.key='manager'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.override_capacity'
        )
      )
      or (
        r.key='store_keeper'
        and p.key in('aggregate_yard.view','aggregate_yard.manage')
      )
      or (
        r.key in('salesperson','accountant')
        and p.key='aggregate_yard.view'
      )
    )
  on conflict do nothing;
end
$$;

revoke all
on function private.aggregate_yard_grant_default_permissions_v617(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_module_permissions_trigger_v617()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.module_key='aggregate_yard' and new.enabled then
    perform private.aggregate_yard_grant_default_permissions_v617(new.tenant_id);
  end if;
  return new;
end
$$;

revoke all
on function private.aggregate_yard_module_permissions_trigger_v617()
from public,anon,authenticated;

drop trigger if exists trg_aggregate_yard_module_permissions_v617
on public.tenant_modules;

create trigger trg_aggregate_yard_module_permissions_v617
after insert or update of enabled,module_key
on public.tenant_modules
for each row
execute function private.aggregate_yard_module_permissions_trigger_v617();

do $$
declare r record;
begin
  for r in
    select tenant_id
    from public.tenant_modules
    where module_key='aggregate_yard'
      and enabled
  loop
    perform private.aggregate_yard_grant_default_permissions_v617(r.tenant_id);
  end loop;
end
$$;

create or replace function private.aggregate_yard_assert_view_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access required' using errcode='42501';
  end if;

  if not exists(
    select 1
    from public.tenant_modules
    where tenant_id=p_tenant_id
      and module_key='aggregate_yard'
      and enabled
  ) then
    raise exception 'Material Yard module is not enabled' using errcode='42501';
  end if;

  if not (
    private.erp_has_permission(p_tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Material Yard view permission required' using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_view_v617(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_assert_manage_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  if not private.erp_has_permission(p_tenant_id,'aggregate_yard.manage') then
    raise exception 'Material Yard manage permission required' using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_manage_v617(uuid)
from public,anon,authenticated;

create or replace function public.aggregate_yard_context_v617(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'products',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id',v.id,
          'name',p.name,
          'variant_name',v.name,
          'sku',v.sku,
          'cost_price',v.cost_price,
          'selling_price',v.selling_price
        )
        order by p.name,v.name
      )
      from public.product_variants v
      join public.products p
        on p.id=v.product_id
       and p.tenant_id=v.tenant_id
      where v.tenant_id=p_tenant_id
        and v.status='active'
        and p.status='active'
    ),'[]'::jsonb),

    'vehicles',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vehicle_id',v.id,
          'registration_number',v.registration_number,
          'vehicle_type',v.vehicle_type,
          'capacity',v.capacity,
          'capacity_unit',v.capacity_unit,
          'driver_name',v.driver_name,
          'driver_phone',v.driver_phone,
          'ownership_type',coalesce(ap.ownership_type,'hired'),
          'owner_name',ap.owner_name,
          'owner_phone',ap.owner_phone,
          'body_length_ft',ap.body_length_ft,
          'body_width_ft',ap.body_width_ft,
          'body_height_ft',ap.body_height_ft,
          'nominal_capacity_cft',coalesce(
            ap.nominal_capacity_cft,
            case
              when upper(coalesce(v.capacity_unit,''))='CFT'
              then v.capacity
              else null
            end
          ),
          'tare_weight_kg',ap.tare_weight_kg,
          'max_payload_kg',ap.max_payload_kg,
          'default_freight',coalesce(ap.default_freight,0)
        )
        order by v.registration_number
      )
      from public.service_vehicles v
      left join public.aggregate_vehicle_profiles_v617 ap
        on ap.tenant_id=v.tenant_id
       and ap.vehicle_id=v.id
       and ap.active
      where v.tenant_id=p_tenant_id
        and v.active
    ),'[]'::jsonb),

    'drivers',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'driver_id',d.id,
          'name',d.name,
          'phone',d.phone,
          'license_number',d.license_number
        )
        order by d.name
      )
      from public.logistics_drivers_v61 d
      where d.tenant_id=p_tenant_id
        and d.active
    ),'[]'::jsonb),

    'suppliers',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'supplier_id',s.id,
          'name',s.name,
          'phone',s.phone
        )
        order by s.name
      )
      from public.suppliers s
      where s.tenant_id=p_tenant_id
        and s.status='active'
    ),'[]'::jsonb),

    'customers',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'customer_id',c.id,
          'name',c.name,
          'phone',c.phone,
          'is_walk_in',c.is_walk_in
        )
        order by c.name
      )
      from public.customers c
      where c.tenant_id=p_tenant_id
        and c.status='active'
    ),'[]'::jsonb),

    'locations',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'location_id',l.id,
          'code',l.location_code,
          'name',l.name,
          'type',l.location_type
        )
        order by l.sort_order,l.name
      )
      from public.business_locations l
      where l.tenant_id=p_tenant_id
        and l.active
    ),'[]'::jsonb)
  )
  into v_result;

  return v_result;
end
$$;

revoke all
on function public.aggregate_yard_context_v617(uuid)
from public,anon;

grant execute
on function public.aggregate_yard_context_v617(uuid)
to authenticated,service_role;

create or replace function public.aggregate_vehicle_profile_save_v617(
  p_tenant_id uuid,
  p_vehicle_id uuid,
  p_ownership_type text,
  p_owner_name text,
  p_owner_phone text,
  p_body_length_ft numeric,
  p_body_width_ft numeric,
  p_body_height_ft numeric,
  p_nominal_capacity_cft numeric,
  p_tare_weight_kg numeric,
  p_max_payload_kg numeric,
  p_default_freight numeric,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_calc numeric;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if not exists(
    select 1
    from public.service_vehicles v
    where v.id=p_vehicle_id
      and v.tenant_id=p_tenant_id
  ) then
    raise exception 'Vehicle not found';
  end if;

  if coalesce(p_ownership_type,'')
     not in('owned','hired','supplier','customer') then
    raise exception 'Invalid ownership type';
  end if;

  if p_body_length_ft is not null
     and p_body_width_ft is not null
     and p_body_height_ft is not null then
    v_calc:=round(
      p_body_length_ft*p_body_width_ft*p_body_height_ft,
      3
    );
  end if;

  insert into public.aggregate_vehicle_profiles_v617(
    tenant_id,vehicle_id,ownership_type,owner_name,owner_phone,
    body_length_ft,body_width_ft,body_height_ft,nominal_capacity_cft,
    tare_weight_kg,max_payload_kg,default_freight,notes,active,updated_at
  )
  values(
    p_tenant_id,
    p_vehicle_id,
    p_ownership_type,
    nullif(trim(p_owner_name),''),
    nullif(trim(p_owner_phone),''),
    p_body_length_ft,
    p_body_width_ft,
    p_body_height_ft,
    coalesce(p_nominal_capacity_cft,v_calc),
    p_tare_weight_kg,
    p_max_payload_kg,
    greatest(coalesce(p_default_freight,0),0),
    nullif(trim(p_notes),''),
    true,
    now()
  )
  on conflict(tenant_id,vehicle_id) do update
  set ownership_type=excluded.ownership_type,
      owner_name=excluded.owner_name,
      owner_phone=excluded.owner_phone,
      body_length_ft=excluded.body_length_ft,
      body_width_ft=excluded.body_width_ft,
      body_height_ft=excluded.body_height_ft,
      nominal_capacity_cft=excluded.nominal_capacity_cft,
      tare_weight_kg=excluded.tare_weight_kg,
      max_payload_kg=excluded.max_payload_kg,
      default_freight=excluded.default_freight,
      notes=excluded.notes,
      active=true,
      updated_at=now();

  update public.service_vehicles
  set capacity=coalesce(p_nominal_capacity_cft,v_calc,capacity),
      capacity_unit=case
        when coalesce(p_nominal_capacity_cft,v_calc) is not null
        then 'CFT'
        else capacity_unit
      end,
      updated_at=now()
  where id=p_vehicle_id
    and tenant_id=p_tenant_id;

  return jsonb_build_object(
    'vehicle_id',p_vehicle_id,
    'calculated_capacity_cft',v_calc,
    'nominal_capacity_cft',coalesce(p_nominal_capacity_cft,v_calc)
  );
end
$$;

revoke all
on function public.aggregate_vehicle_profile_save_v617(
  uuid,uuid,text,text,text,
  numeric,numeric,numeric,numeric,numeric,numeric,numeric,text
)
from public,anon;

grant execute
on function public.aggregate_vehicle_profile_save_v617(
  uuid,uuid,text,text,text,
  numeric,numeric,numeric,numeric,numeric,numeric,numeric,text
)
to authenticated,service_role;

create or replace function public.aggregate_load_create_v617(
  p_tenant_id uuid,
  p_direction text,
  p_location_id uuid,
  p_variant_id uuid,
  p_quantity numeric,
  p_unit_code text,
  p_measurement_method text,
  p_body_length_ft numeric,
  p_body_width_ft numeric,
  p_body_height_ft numeric,
  p_gross_weight_kg numeric,
  p_tare_weight_kg numeric,
  p_net_weight_kg numeric,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_supplier_id uuid,
  p_customer_id uuid,
  p_source_name text,
  p_destination_name text,
  p_source_reference text,
  p_freight_mode text,
  p_freight_amount numeric,
  p_capacity_override boolean,
  p_capacity_override_reason text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_qty numeric;
  v_product text;
  v_vehicle public.service_vehicles%rowtype;
  v_driver public.logistics_drivers_v61%rowtype;
  v_capacity numeric;
  v_number text;
  v_id uuid;
  v_measure text:=lower(coalesce(p_measurement_method,'manual'));
  v_unit text:=upper(coalesce(nullif(trim(p_unit_code),''),'CFT'));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if lower(coalesce(p_direction,''))
     not in('inbound','outbound','direct_delivery') then
    raise exception 'Invalid load direction';
  end if;

  if p_location_id is not null
     and not exists(
       select 1
       from public.business_locations l
       where l.id=p_location_id
         and l.tenant_id=p_tenant_id
         and l.active
     ) then
    raise exception 'Location not found';
  end if;

  select
    p.name
    || case
         when nullif(trim(v.name),'') is not null
              and lower(trim(v.name)) not in('default','standard')
         then ' - '||v.name
         else ''
       end
  into v_product
  from public.product_variants v
  join public.products p
    on p.id=v.product_id
   and p.tenant_id=v.tenant_id
  where v.id=p_variant_id
    and v.tenant_id=p_tenant_id
    and v.status='active'
    and p.status='active';

  if v_product is null then
    raise exception 'Product variant not found';
  end if;

  if v_measure='dimensions' then
    if coalesce(p_body_length_ft,0)<=0
       or coalesce(p_body_width_ft,0)<=0
       or coalesce(p_body_height_ft,0)<=0 then
      raise exception
        'Length, width and height are required for dimension measurement';
    end if;

    v_qty:=round(
      p_body_length_ft*p_body_width_ft*p_body_height_ft,
      3
    );
    v_unit:='CFT';

  elsif v_measure='weighbridge' then

    if coalesce(
         p_net_weight_kg,
         coalesce(p_gross_weight_kg,0)-coalesce(p_tare_weight_kg,0)
       )<=0 then
      raise exception
        'Positive net weight is required for weighbridge measurement';
    end if;

    v_qty:=coalesce(p_quantity,p_net_weight_kg);

    if coalesce(v_qty,0)<=0 then
      raise exception 'Positive quantity is required';
    end if;

  elsif v_measure='manual' then

    v_qty:=p_quantity;

    if coalesce(v_qty,0)<=0 then
      raise exception 'Positive quantity is required';
    end if;

  else
    raise exception 'Invalid measurement method';
  end if;

  if p_vehicle_id is not null then
    select *
    into v_vehicle
    from public.service_vehicles
    where id=p_vehicle_id
      and tenant_id=p_tenant_id
      and active;

    if v_vehicle.id is null then
      raise exception 'Vehicle not found';
    end if;

    select coalesce(
      ap.nominal_capacity_cft,
      case
        when upper(coalesce(v_vehicle.capacity_unit,''))='CFT'
        then v_vehicle.capacity
        else null
      end
    )
    into v_capacity
    from (select 1) x
    left join public.aggregate_vehicle_profiles_v617 ap
      on ap.tenant_id=p_tenant_id
     and ap.vehicle_id=p_vehicle_id
     and ap.active;
  end if;

  if p_driver_id is not null then
    select *
    into v_driver
    from public.logistics_drivers_v61
    where id=p_driver_id
      and tenant_id=p_tenant_id
      and active;

    if v_driver.id is null then
      raise exception 'Driver not found';
    end if;
  end if;

  if p_supplier_id is not null
     and not exists(
       select 1
       from public.suppliers
       where id=p_supplier_id
         and tenant_id=p_tenant_id
     ) then
    raise exception 'Supplier not found';
  end if;

  if p_customer_id is not null
     and not exists(
       select 1
       from public.customers
       where id=p_customer_id
         and tenant_id=p_tenant_id
     ) then
    raise exception 'Customer not found';
  end if;

  if v_unit='CFT'
     and v_capacity is not null
     and v_qty>v_capacity*1.05 then

    if not coalesce(p_capacity_override,false) then
      raise exception
        'Load quantity % CFT exceeds vehicle capacity % CFT',
        v_qty,
        v_capacity;
    end if;

    if not private.erp_has_permission(
      p_tenant_id,
      'aggregate_yard.override_capacity'
    ) then
      raise exception
        'Capacity override permission required'
        using errcode='42501';
    end if;

    if nullif(
      trim(coalesce(p_capacity_override_reason,'')),
      ''
    ) is null then
      raise exception 'Capacity override reason is required';
    end if;
  end if;

  if lower(coalesce(p_freight_mode,'none'))
     not in('none','own','hired','supplier','customer','included') then
    raise exception 'Invalid freight mode';
  end if;

  v_number:=
    'LOAD-'
    ||to_char(current_date,'YYYYMMDD')
    ||'-'
    ||lpad(
      nextval('public.aggregate_load_number_seq_v617')::text,
      6,
      '0'
    );

  insert into public.aggregate_loads_v617(
    tenant_id,
    load_number,
    direction,
    status,
    location_id,
    variant_id,
    product_name_snapshot,
    unit_code,
    quantity,
    measurement_method,
    body_length_ft,
    body_width_ft,
    body_height_ft,
    gross_weight_kg,
    tare_weight_kg,
    net_weight_kg,
    vehicle_id,
    driver_id,
    vehicle_registration_snapshot,
    driver_name_snapshot,
    driver_phone_snapshot,
    supplier_id,
    customer_id,
    source_name,
    destination_name,
    source_reference,
    freight_mode,
    freight_amount,
    capacity_override,
    capacity_override_reason,
    notes,
    created_by,
    updated_by
  )
  values(
    p_tenant_id,
    v_number,
    lower(p_direction),
    'draft',
    p_location_id,
    p_variant_id,
    v_product,
    v_unit,
    v_qty,
    v_measure,
    p_body_length_ft,
    p_body_width_ft,
    p_body_height_ft,
    p_gross_weight_kg,
    p_tare_weight_kg,
    coalesce(
      p_net_weight_kg,
      case
        when p_gross_weight_kg is not null
             and p_tare_weight_kg is not null
        then p_gross_weight_kg-p_tare_weight_kg
      end
    ),
    p_vehicle_id,
    p_driver_id,
    v_vehicle.registration_number,
    coalesce(v_driver.name,v_vehicle.driver_name),
    coalesce(v_driver.phone,v_vehicle.driver_phone),
    p_supplier_id,
    p_customer_id,
    nullif(trim(p_source_name),''),
    nullif(trim(p_destination_name),''),
    nullif(trim(p_source_reference),''),
    lower(coalesce(p_freight_mode,'none')),
    greatest(coalesce(p_freight_amount,0),0),
    coalesce(p_capacity_override,false),
    nullif(trim(p_capacity_override_reason),''),
    nullif(trim(p_notes),''),
    auth.uid(),
    auth.uid()
  )
  returning id into v_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    to_status,
    note,
    created_by
  )
  values(
    p_tenant_id,
    v_id,
    'created',
    'draft',
    'Load ticket created',
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',v_id,
    'load_number',v_number,
    'quantity',v_qty,
    'unit_code',v_unit,
    'vehicle_capacity_cft',v_capacity,
    'status','draft'
  );
end
$$;

revoke all
on function public.aggregate_load_create_v617(
  uuid,text,uuid,uuid,numeric,text,text,
  numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
)
from public,anon;

grant execute
on function public.aggregate_load_create_v617(
  uuid,text,uuid,uuid,numeric,text,text,
  numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
)
to authenticated,service_role;

create or replace function public.aggregate_load_status_v617(
  p_tenant_id uuid,
  p_load_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_next text:=lower(trim(coalesce(p_status,'')));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  if not (
    (v_row.status='draft'
      and v_next in('loading','cancelled'))
    or
    (v_row.status='loading'
      and v_next in('dispatched','in_transit','cancelled'))
    or
    (v_row.status='dispatched'
      and v_next in('in_transit','arrived','cancelled'))
    or
    (v_row.status='in_transit'
      and v_next in('arrived','cancelled'))
    or
    (
      v_row.status='arrived'
      and (
        (
          v_row.direction='inbound'
          and v_next in('received','cancelled')
        )
        or
        (
          v_row.direction in('outbound','direct_delivery')
          and v_next in('delivered','cancelled')
        )
      )
    )
    or
    (v_row.status='received' and v_next='completed')
    or
    (v_row.status='delivered' and v_next='completed')
  ) then
    raise exception
      'Invalid load status transition: % -> %',
      v_row.status,
      v_next;
  end if;

  update public.aggregate_loads_v617
  set status=v_next,
      updated_by=auth.uid(),
      updated_at=now()
  where id=p_load_id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    from_status,
    to_status,
    note,
    created_by
  )
  values(
    p_tenant_id,
    p_load_id,
    'status_changed',
    v_row.status,
    v_next,
    nullif(trim(p_note),''),
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_row.load_number,
    'status',v_next
  );
end
$$;

revoke all
on function public.aggregate_load_status_v617(uuid,uuid,text,text)
from public,anon;

grant execute
on function public.aggregate_load_status_v617(uuid,uuid,text,text)
to authenticated,service_role;

create or replace function public.aggregate_load_link_document_v617(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_ref text;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if not exists(
    select 1
    from public.aggregate_loads_v617
    where id=p_load_id
      and tenant_id=p_tenant_id
  ) then
    raise exception 'Load not found';
  end if;

  if v_type='purchase' then

    select purchase_number
    into v_ref
    from public.purchases
    where id=p_document_id
      and tenant_id=p_tenant_id;

    if v_ref is null then
      raise exception 'Purchase not found';
    end if;

    update public.aggregate_loads_v617
    set purchase_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  elsif v_type='sale' then

    select sale_number
    into v_ref
    from public.sales
    where id=p_document_id
      and tenant_id=p_tenant_id;

    if v_ref is null then
      raise exception 'Sale not found';
    end if;

    update public.aggregate_loads_v617
    set sale_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  else
    raise exception 'Document type must be purchase or sale';
  end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    p_load_id,
    'document_linked',
    initcap(v_type)||' '||v_ref||' linked',
    jsonb_build_object(
      'document_type',v_type,
      'document_id',p_document_id,
      'reference',v_ref
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,
    'document_type',v_type,
    'document_id',p_document_id,
    'reference',v_ref
  );
end
$$;

revoke all
on function public.aggregate_load_link_document_v617(uuid,uuid,text,uuid)
from public,anon;

grant execute
on function public.aggregate_load_link_document_v617(uuid,uuid,text,uuid)
to authenticated,service_role;

create or replace function public.aggregate_load_list_v617(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default null,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  product_name text,
  quantity numeric,
  unit_code text,
  measurement_method text,
  vehicle_id uuid,
  vehicle_registration text,
  driver_name text,
  supplier_name text,
  customer_name text,
  source_name text,
  destination_name text,
  source_reference text,
  freight_mode text,
  freight_amount numeric,
  purchase_id uuid,
  sale_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,
    l.load_number,
    l.load_date,
    l.direction,
    l.status,
    l.location_id,
    l.product_name_snapshot,
    l.quantity,
    l.unit_code,
    l.measurement_method,
    l.vehicle_id,
    l.vehicle_registration_snapshot,
    l.driver_name_snapshot,
    s.name,
    c.name,
    l.source_name,
    l.destination_name,
    l.source_reference,
    l.freight_mode,
    l.freight_amount,
    l.purchase_id,
    l.sale_id,
    l.created_at
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id=l.supplier_id
   and s.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id
   and c.tenant_id=l.tenant_id
  where l.tenant_id=p_tenant_id
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      p_status is null
      or trim(p_status)=''
      or l.status=lower(trim(p_status))
    )
    and (
      p_query is null
      or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(l.driver_name_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(s.name,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'')
           ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_load_list_v617(uuid,uuid,text,text,integer)
from public,anon;

grant execute
on function public.aggregate_load_list_v617(uuid,uuid,text,text,integer)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  304,
  '6.1.7-aggregate-load-foundation',
  'Aggregate Load & Vehicle Foundation',
  'Adds tenant-scoped operational Load Tickets, immutable load event history, Aggregate vehicle profile extensions, CFT capacity validation and read/write RPCs. Load status has no stock/accounting authority. Existing Sales/Purchase/GST/Inventory writers remain authoritative.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
