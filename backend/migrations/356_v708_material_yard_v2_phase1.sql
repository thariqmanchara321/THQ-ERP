-- THQ ERP — MATERIAL YARD V2: COMPLETE UX, WORKFLOW AND SYSTEM INTEGRATION UPGRADE (PHASE 1)
-- Migration 356_v708_material_yard_v2_phase1.sql

-- 1. logistics_drivers_v61 enhancement (Driver Master)
alter table public.logistics_drivers_v61 add column if not exists driver_code text;
alter table public.logistics_drivers_v61 add column if not exists license_expiry date;
alter table public.logistics_drivers_v61 add column if not exists address text;
alter table public.logistics_drivers_v61 add column if not exists default_wage numeric default 0;

create index if not exists idx_logistics_drivers_v61_search 
on public.logistics_drivers_v61(tenant_id, active, name);

-- 2. service_vehicles default driver link
alter table public.service_vehicles add column if not exists default_driver_id uuid references public.logistics_drivers_v61(id) on delete set null;

-- 3. aggregate_loads_v617 measurement audit columns
alter table public.aggregate_loads_v617 add column if not exists raw_dimensions jsonb;
alter table public.aggregate_loads_v617 add column if not exists dimension_unit text default 'ft';
alter table public.aggregate_loads_v617 add column if not exists calculated_cft numeric;
alter table public.aggregate_loads_v617 add column if not exists heap_adjustment_cft numeric default 0;
alter table public.aggregate_loads_v617 add column if not exists approved_billable_qty numeric;
alter table public.aggregate_loads_v617 add column if not exists approved_by uuid;
alter table public.aggregate_loads_v617 add column if not exists measurement_notes text;

-- 4. material_daily_rates_v708 & history
create table if not exists public.material_daily_rates_v708 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  effective_date date not null default current_date,
  purchase_rate numeric not null default 0,
  selling_rate numeric not null default 0,
  wholesale_rate numeric not null default 0,
  min_selling_rate numeric not null default 0,
  partner_id uuid,
  partner_type text not null default 'all' check (partner_type in ('supplier', 'customer', 'all')),
  unit_code text not null default 'CFT',
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create unique index if not exists uq_material_daily_rates_v708 
on public.material_daily_rates_v708(tenant_id, coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid), variant_id, coalesce(partner_id, '00000000-0000-0000-0000-000000000000'::uuid), partner_type, effective_date);

create table if not exists public.material_daily_rate_history_v708 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  rate_id uuid not null references public.material_daily_rates_v708(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  old_purchase_rate numeric,
  new_purchase_rate numeric,
  old_selling_rate numeric,
  new_selling_rate numeric,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default clock_timestamp(),
  change_reason text
);

alter table public.material_daily_rates_v708 enable row level security;
alter table public.material_daily_rate_history_v708 enable row level security;

drop policy if exists material_daily_rates_v708_read on public.material_daily_rates_v708;
create policy material_daily_rates_v708_read on public.material_daily_rates_v708
  for select using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists material_daily_rates_v708_write on public.material_daily_rates_v708;
create policy material_daily_rates_v708_write on public.material_daily_rates_v708
  for all using (private.erp_user_has_tenant_access(tenant_id) and (private.erp_has_permission(tenant_id, 'aggregate_yard.manage') or private.erp_has_permission(tenant_id, 'inventory.manage')));

drop policy if exists material_daily_rate_history_v708_read on public.material_daily_rate_history_v708;
create policy material_daily_rate_history_v708_read on public.material_daily_rate_history_v708
  for select using (private.erp_user_has_tenant_access(tenant_id));

-- 5. RPC Functions

-- Get rate board
create or replace function public.material_daily_rates_get_v708(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_date date default current_date
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'variant_id', v.id,
    'product_id', p.id,
    'product_name', p.name,
    'variant_name', v.name,
    'sku', v.sku,
    'base_unit_code', coalesce(bu.code, 'CFT'),
    'effective_date', p_date,
    'purchase_rate', coalesce(r.purchase_rate, v.cost_price, 0),
    'selling_rate', coalesce(r.selling_rate, v.selling_price, 0),
    'wholesale_rate', coalesce(r.wholesale_rate, v.selling_price, 0),
    'min_selling_rate', coalesce(r.min_selling_rate, v.cost_price, 0),
    'notes', coalesce(r.notes, ''),
    'rate_id', r.id,
    'prev_purchase_rate', pr.purchase_rate,
    'prev_selling_rate', pr.selling_rate,
    'margin_pct', case
      when coalesce(r.purchase_rate, v.cost_price, 0) > 0
      then round(((coalesce(r.selling_rate, v.selling_price, 0) - coalesce(r.purchase_rate, v.cost_price, 0)) / coalesce(r.purchase_rate, v.cost_price, 1)) * 100, 2)
      else 0
    end,
    'margin_warning', case
      when coalesce(r.selling_rate, v.selling_price, 0) < coalesce(r.min_selling_rate, v.cost_price, 0)
        or coalesce(r.selling_rate, v.selling_price, 0) < coalesce(r.purchase_rate, v.cost_price, 0)
      then true
      else false
    end
  ) order by p.name, v.name), '[]'::jsonb)
  into v_result
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id
  left join public.product_units_v481 pbu on pbu.tenant_id = v.tenant_id and pbu.variant_id = v.id and pbu.is_base and pbu.active
  left join public.inventory_units_v481 bu on bu.id = pbu.unit_id and bu.tenant_id = pbu.tenant_id and bu.active
  left join public.material_daily_rates_v708 r on r.tenant_id = p_tenant_id
    and (p_location_id is null or r.location_id is null or r.location_id = p_location_id)
    and r.variant_id = v.id
    and r.effective_date = p_date
    and r.partner_type = 'all'
  left join lateral (
    select purchase_rate, selling_rate
    from public.material_daily_rates_v708
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and variant_id = v.id
      and effective_date < p_date
      and partner_type = 'all'
    order by effective_date desc
    limit 1
  ) pr on true
  where v.tenant_id = p_tenant_id
    and v.status = 'active'
    and p.status = 'active'
    and (p.item_type is null or p.item_type in ('inventory', 'raw_material', 'product'));

  return v_result;
end;
$$;

-- Bulk save rate board
create or replace function public.material_daily_rates_bulk_save_v708(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_rates jsonb default '[]'::jsonb,
  p_effective_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_rate jsonb;
  v_variant_id uuid;
  v_purchase numeric;
  v_selling numeric;
  v_wholesale numeric;
  v_min_selling numeric;
  v_notes text;
  v_existing public.material_daily_rates_v708%rowtype;
  v_count int := 0;
  v_rate_id uuid;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  for v_rate in select * from jsonb_array_elements(p_rates)
  loop
    v_variant_id := (v_rate->>'variant_id')::uuid;
    v_purchase := coalesce((v_rate->>'purchase_rate')::numeric, 0);
    v_selling := coalesce((v_rate->>'selling_rate')::numeric, 0);
    v_wholesale := coalesce((v_rate->>'wholesale_rate')::numeric, v_selling);
    v_min_selling := coalesce((v_rate->>'min_selling_rate')::numeric, v_purchase);
    v_notes := trim(coalesce(v_rate->>'notes', ''));

    select * into v_existing
    from public.material_daily_rates_v708
    where tenant_id = p_tenant_id
      and coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_location_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and variant_id = v_variant_id
      and partner_type = 'all'
      and effective_date = p_effective_date;

    if found then
      if v_existing.purchase_rate <> v_purchase or v_existing.selling_rate <> v_selling then
        insert into public.material_daily_rate_history_v708(
          tenant_id, rate_id, variant_id,
          old_purchase_rate, new_purchase_rate,
          old_selling_rate, new_selling_rate,
          changed_by, change_reason
        ) values (
          p_tenant_id, v_existing.id, v_variant_id,
          v_existing.purchase_rate, v_purchase,
          v_existing.selling_rate, v_selling,
          auth.uid(), coalesce(v_notes, 'Daily rate update')
        );
      end if;

      update public.material_daily_rates_v708
      set purchase_rate = v_purchase,
          selling_rate = v_selling,
          wholesale_rate = v_wholesale,
          min_selling_rate = v_min_selling,
          notes = v_notes,
          updated_by = auth.uid(),
          updated_at = clock_timestamp()
      where id = v_existing.id;
    else
      insert into public.material_daily_rates_v708(
        tenant_id, location_id, variant_id, effective_date,
        purchase_rate, selling_rate, wholesale_rate, min_selling_rate,
        partner_type, notes, created_by, updated_by
      ) values (
        p_tenant_id, p_location_id, v_variant_id, p_effective_date,
        v_purchase, v_selling, v_wholesale, v_min_selling,
        'all', v_notes, auth.uid(), auth.uid()
      ) returning id into v_rate_id;

      insert into public.material_daily_rate_history_v708(
        tenant_id, rate_id, variant_id,
        old_purchase_rate, new_purchase_rate,
        old_selling_rate, new_selling_rate,
        changed_by, change_reason
      ) values (
        p_tenant_id, v_rate_id, v_variant_id,
        0, v_purchase,
        0, v_selling,
        auth.uid(), 'Initial rate entry'
      );
    end if;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('recorded', true, 'count', v_count);
end;
$$;

-- Driver save
create or replace function public.logistics_driver_save_v708(
  p_tenant_id uuid,
  p_driver jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid := nullif(p_driver->>'id', '')::uuid;
  v_name text := trim(coalesce(p_driver->>'name', ''));
  v_phone text := nullif(trim(coalesce(p_driver->>'phone', '')), '');
  v_license text := nullif(trim(coalesce(p_driver->>'license_number', '')), '');
  v_code text := nullif(trim(coalesce(p_driver->>'driver_code', '')), '');
  v_expiry date := nullif(p_driver->>'license_expiry', '')::date;
  v_address text := trim(coalesce(p_driver->>'address', ''));
  v_wage numeric := coalesce((p_driver->>'default_wage')::numeric, 0);
  v_notes text := trim(coalesce(p_driver->>'notes', ''));
  v_active boolean := coalesce((p_driver->>'active')::boolean, true);
  v_driver_id uuid;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if v_name = '' then
    raise exception 'Driver name is required';
  end if;

  if v_code is not null and exists (
    select 1 from public.logistics_drivers_v61
    where tenant_id = p_tenant_id
      and lower(driver_code) = lower(v_code)
      and (v_id is null or id <> v_id)
  ) then
    raise exception 'Another driver already has driver code %', v_code;
  end if;

  if v_id is not null then
    update public.logistics_drivers_v61
    set name = v_name,
        phone = v_phone,
        license_number = v_license,
        driver_code = v_code,
        license_expiry = v_expiry,
        address = v_address,
        default_wage = v_wage,
        notes = v_notes,
        active = v_active,
        updated_at = clock_timestamp()
    where id = v_id and tenant_id = p_tenant_id
    returning id into v_driver_id;

    if not found then
      raise exception 'Driver not found';
    end if;
  else
    insert into public.logistics_drivers_v61(
      tenant_id, name, phone, license_number,
      driver_code, license_expiry, address, default_wage,
      notes, active
    ) values (
      p_tenant_id, v_name, v_phone, v_license,
      v_code, v_expiry, v_address, v_wage,
      v_notes, v_active
    ) returning id into v_driver_id;
  end if;

  return jsonb_build_object('recorded', true, 'driver_id', v_driver_id);
end;
$$;

-- Driver search/list
create or replace function public.logistics_driver_list_v708(
  p_tenant_id uuid,
  p_query text default null,
  p_limit int default 100
)
returns table(
  id uuid,
  name text,
  phone text,
  license_number text,
  driver_code text,
  license_expiry date,
  address text,
  default_wage numeric,
  notes text,
  active boolean,
  created_at timestamptz
)
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    d.id, d.name, d.phone, d.license_number,
    d.driver_code, d.license_expiry, d.address,
    coalesce(d.default_wage, 0), d.notes, d.active, d.created_at
  from public.logistics_drivers_v61 d
  where d.tenant_id = p_tenant_id
    and (
      p_query is null or trim(p_query) = ''
      or d.name ilike '%' || trim(p_query) || '%'
      or coalesce(d.phone, '') ilike '%' || trim(p_query) || '%'
      or coalesce(d.driver_code, '') ilike '%' || trim(p_query) || '%'
      or coalesce(d.license_number, '') ilike '%' || trim(p_query) || '%'
    )
  order by d.active desc, d.name asc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

-- Update aggregate_yard_context_v617 with new driver and vehicle fields
CREATE OR REPLACE FUNCTION public.aggregate_yard_context_v617(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'products',coalesce((
      select jsonb_agg(jsonb_build_object(
        'variant_id',v.id,'name',p.name,'variant_name',v.name,'sku',v.sku,
        'cost_price',v.cost_price,'selling_price',v.selling_price,
        'base_unit_code',bu.code,
        'sale_units',coalesce((
          select jsonb_agg(jsonb_build_object(
            'unit_id',u.id,'code',u.code,'name',u.name,'is_base',pu.is_base,
            'is_default_sale',pu.is_default_sale,
            'conversion_to_base',pu.conversion_to_base,'sale_price',pu.sale_price
          ) order by pu.is_default_sale desc,pu.is_base desc,u.code)
          from public.product_units_v481 pu
          join public.inventory_units_v481 u
            on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
          where pu.tenant_id=p_tenant_id and pu.variant_id=v.id
            and pu.active and pu.allow_sale and u.active
        ),'[]'::jsonb)
      ) order by p.name,v.name)
      from public.product_variants v
      join public.products p
        on p.id=v.product_id and p.tenant_id=v.tenant_id
      left join public.product_units_v481 pbu
        on pbu.tenant_id=v.tenant_id
       and pbu.variant_id=v.id
       and pbu.is_base
       and pbu.active
      left join public.inventory_units_v481 bu
        on bu.id=pbu.unit_id
       and bu.tenant_id=pbu.tenant_id
       and bu.active
      where v.tenant_id=p_tenant_id and v.status='active' and p.status='active'
    ),'[]'::jsonb),
    'vehicles',coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehicle_id',v.id,'registration_number',v.registration_number,
        'vehicle_type',v.vehicle_type,'capacity',v.capacity,
        'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,
        'driver_phone',v.driver_phone,
        'default_driver_id',v.default_driver_id,
        'ownership_type',coalesce(ap.ownership_type,'hired'),
        'owner_name',ap.owner_name,'owner_phone',ap.owner_phone,
        'body_length_ft',ap.body_length_ft,'body_width_ft',ap.body_width_ft,
        'body_height_ft',ap.body_height_ft,
        'nominal_capacity_cft',coalesce(
          ap.nominal_capacity_cft,
          case when upper(coalesce(v.capacity_unit,''))='CFT'
               then v.capacity else null end
        ),
        'tare_weight_kg',ap.tare_weight_kg,
        'max_payload_kg',ap.max_payload_kg,
        'default_freight',coalesce(ap.default_freight,0)
      ) order by v.registration_number)
      from public.service_vehicles v
      left join public.aggregate_vehicle_profiles_v617 ap
        on ap.tenant_id=v.tenant_id and ap.vehicle_id=v.id and ap.active
      where v.tenant_id=p_tenant_id and v.active
    ),'[]'::jsonb),
    'drivers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'driver_id',d.id,'name',d.name,'phone',d.phone,
        'license_number',d.license_number,
        'driver_code',d.driver_code,
        'license_expiry',d.license_expiry,
        'address',d.address,
        'default_wage',coalesce(d.default_wage,0)
      ) order by d.name)
      from public.logistics_drivers_v61 d
      where d.tenant_id=p_tenant_id and d.active
    ),'[]'::jsonb),
    'suppliers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'supplier_id',s.id,'name',s.name,'phone',s.phone
      ) order by s.name)
      from public.suppliers s
      where s.tenant_id=p_tenant_id and s.status='active'
    ),'[]'::jsonb),
    'customers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'customer_id',c.id,'name',c.name,'phone',c.phone,'is_walk_in',c.is_walk_in
      ) order by c.name)
      from public.customers c
      where c.tenant_id=p_tenant_id and c.status='active'
    ),'[]'::jsonb),
    'locations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'location_id',l.id,'code',l.location_code,'name',l.name,'type',l.location_type
      ) order by l.sort_order,l.name)
      from public.business_locations l
      where l.tenant_id=p_tenant_id
        and l.active
        and not exists(
          select 1
          from public.aggregate_direct_transit_locations_v621 m
          where m.tenant_id=l.tenant_id
            and m.transit_location_id=l.id
        )
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- Update material_load_workspace_v630 to persist measurement audit fields
create or replace function public.material_load_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;load uuid:=nullif(p_data->>'load_id','')::uuid;location uuid:=p_location_id;
 l public.aggregate_loads_v617%rowtype;data jsonb:=coalesce(p_data->'load',p_data);result jsonb;prior public.material_load_requests_v630%rowtype;
 costs jsonb:=coalesce(p_data->'costs','[]'::jsonb);req text:=p_data->>'request_id';variant uuid;v_sku text;mode text;name text;
begin
 if p_action='context' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'driver_id',s.driver_id,'name',s.name,'phone',s.phone,'wage_basis',s.wage_basis,'base_rate',case when private.erp_has_permission(t,'staff.view') then s.base_rate else null end,'location_id',s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id=t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t,s.location_id,location,'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id=t and m.module_key='staff' and m.enabled)),'[]'::jsonb),
   'billing_services',coalesce((select jsonb_agg(jsonb_build_object('variant_id',v.id,'name',p.name,'tax_rate',p.tax_rate,'hsn_sac',g.hsn_sac,'taxability',g.taxability,'gst_rate',g.gst_rate,'validation_status',g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t,v.id,current_date)) g on true where v.tenant_id=t and v.status='active' and p.status='active' and p.item_type='service'),'[]'::jsonb),
   'tax_mode',private.gst_tax_mode_resolve_v520(t,current_date),'can_manage_costs',private.erp_has_permission(t,'aggregate_yard.costs'),
   'can_create_billing_service',private.erp_has_permission(t,'inventory.manage') and private.erp_has_permission(t,'gst_compliance.manage')
  );
 elsif p_action='billing_service' then
  perform private.yard_cost_assert_v630(t,location,true);
  name:=nullif(trim(data->>'name'),'');if name is null then raise exception 'Charge service name is required';end if;
  mode:=private.gst_tax_mode_resolve_v520(t,current_date);
  if mode='unconfigured' then raise exception 'Configure the business tax mode first';end if;
  if mode='non_gst' and coalesce((data->>'gst_rate')::numeric,0)<>0 then raise exception 'Non-GST charges must have zero GST';end if;
  if mode='gst_registered' and nullif(trim(data->>'hsn_sac'),'') is null then raise exception 'Select the correct SAC for this charge service';end if;
  v_sku:='YARD-SVC-'||upper(left(coalesce(nullif(data->>'new_id',''),gen_random_uuid()::text),12));
  if exists(select 1 from public.product_variants where tenant_id=t and sku=v_sku) then raise exception 'Charge service already exists; refresh the list';end if;
  result:=public.inventory_create_product_v481(p_tenant_id=>t,p_location_id=>location,p_device_id=>nullif(data->>'device_id','')::uuid,p_name=>name,p_sku=>v_sku,p_item_type=>'service',p_description=>coalesce(data->>'description',name),p_category_name=>'Load Charges',p_brand_name=>'',p_barcode=>'',p_part_number=>'',p_cost_price=>0,p_selling_price=>0,p_list_price=>null,p_tax_rate=>coalesce((data->>'gst_rate')::numeric,0),p_reorder_level=>0,p_opening_stock=>0,p_base_unit_code=>'PCS',p_units=>'[]'::jsonb);
  variant:=(result->>'variant_id')::uuid;
  if mode='gst_registered' then perform public.gst_product_profile_save_v520(t,variant,'service',data->>'hsn_sac',coalesce(data->>'taxability','taxable'),coalesce((data->>'gst_rate')::numeric,0),0,0,false,false,'Load charge service setup',current_date);end if;
  return jsonb_build_object('variant_id',variant,'recorded',true);
 elsif p_action='report' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  if coalesce((data->>'to')::date,current_date)<coalesce((data->>'from')::date,date_trunc('month',current_date)::date) then raise exception 'End date must follow start date';end if;
  return jsonb_build_object('loads',coalesce((select jsonb_agg(private.load_evidence_v630(t,x.id) order by x.load_date desc,x.load_number) from public.aggregate_loads_v617 x where x.tenant_id=t and x.direction<>'direct_delivery' and x.load_date between coalesce((data->>'from')::date,date_trunc('month',current_date)::date) and coalesce((data->>'to')::date,current_date) and private.erp_document_scope_allowed(t,x.location_id,location,'view') and (nullif(data->>'vehicle_id','') is null or x.vehicle_id=(data->>'vehicle_id')::uuid) and (nullif(data->>'driver_id','') is null or x.driver_id=(data->>'driver_id')::uuid)),'[]'::jsonb));
 end if;
 if p_action='create' then
  perform private.aggregate_yard_assert_manage_v617(t);
  if req is null or length(req)>256 then raise exception 'A stable load request ID is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text||':load:'||req,0));
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id=req;
  if found then if prior.payload<>p_data then raise exception 'Load retry has different data';end if;return jsonb_build_object('load_id',prior.load_id,'replayed',true);end if;
  result:=public.aggregate_load_create_v617(t,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  load:=(result->>'load_id')::uuid;

  -- Phase 1: Persist full measurement audit fields
  update public.aggregate_loads_v617
  set raw_dimensions = data->'p_raw_dimensions',
      dimension_unit = coalesce(data->>'p_dimension_unit', 'ft'),
      calculated_cft = (data->>'p_calculated_cft')::numeric,
      heap_adjustment_cft = coalesce((data->>'p_heap_adjustment_cft')::numeric, 0),
      approved_billable_qty = (data->>'p_approved_billable_qty')::numeric,
      approved_by = nullif(data->>'p_approved_by','')::uuid,
      measurement_notes = data->>'p_measurement_notes'
  where id = load and tenant_id = t;

  select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
  perform private.v4_location_access(t,l.location_id,'operate');
  if jsonb_array_length(costs)>0 then perform private.load_cost_save_v630(t,load,costs);end if;
  perform private.load_delivery_save_v630(t,load,jsonb_build_object('driver_license_snapshot',(select license_number from public.logistics_drivers_v61 where id=l.driver_id and tenant_id=t))||coalesce(p_data->'delivery','{}'::jsonb));
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,req,p_data,load);
  return result;
 end if;
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 if p_action='detail' then return private.load_evidence_v630(t,load);end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 if p_action='edit' then
  result:=public.aggregate_load_edit_v628(t,load,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');

  -- Phase 1: Persist full measurement audit fields on edit
  update public.aggregate_loads_v617
  set raw_dimensions = coalesce(data->'p_raw_dimensions', raw_dimensions),
      dimension_unit = coalesce(data->>'p_dimension_unit', dimension_unit),
      calculated_cft = coalesce((data->>'p_calculated_cft')::numeric, calculated_cft),
      heap_adjustment_cft = coalesce((data->>'p_heap_adjustment_cft')::numeric, heap_adjustment_cft),
      approved_billable_qty = coalesce((data->>'p_approved_billable_qty')::numeric, approved_billable_qty),
      approved_by = coalesce(nullif(data->>'p_approved_by','')::uuid, approved_by),
      measurement_notes = coalesce(data->>'p_measurement_notes', measurement_notes)
  where id = load and tenant_id = t;

  perform private.v4_location_access(t,(select location_id from public.aggregate_loads_v617 where id=load),'operate');
  if p_data ? 'costs' and private.erp_has_permission(t,'aggregate_yard.costs') then perform private.load_cost_save_v630(t,load,costs);end if;
  if p_data ? 'delivery' then perform private.load_delivery_save_v630(t,load,p_data->'delivery');end if;
 elsif p_action='confirm' then
  result:=public.aggregate_load_confirm_v628(t,load);perform private.load_costs_post_v630(t,load);
 elsif p_action='delivery' then perform private.load_delivery_save_v630(t,load,data);result:=jsonb_build_object('recorded',true);
 elsif p_action='payment' then result:=jsonb_build_object('payment_id',private.load_cost_payment_v630(t,(data->>'cost_id')::uuid,data));
 elsif p_action='add_cost' then
  if req is null or length(req)>256 then raise exception 'A stable expense submission request ID is required';end if;
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id='add-cost:'||req;
  if found then if prior.load_id<>load or prior.payload<>p_data then raise exception 'Expense retry has different data';end if;return jsonb_build_object('recorded',true,'replayed',true);end if;
  perform private.load_cost_save_v630(t,load,case when p_data ? 'costs' then costs else jsonb_build_array(p_data->'cost') end,false);
  if l.status='completed' then perform private.load_costs_post_v630(t,load);end if;
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,'add-cost:'||req,p_data,load);
  result:=jsonb_build_object('recorded',true);
 elsif p_action='cancel' then
  if l.status='completed' or l.sale_id is not null or l.purchase_id is not null then raise exception 'Only an unconfirmed load can be cancelled. Confirmed costs and linked documents retain their financial history.';end if;
  result:=public.aggregate_load_status_v617(t,load,'cancelled',coalesce(p_data->>'reason','Cancelled before confirmation'));
 elsif p_action='delete' then
  if exists(select 1 from public.material_load_costs_v630 where tenant_id=t and load_id=load) or exists(select 1 from public.material_load_delivery_v630 where tenant_id=t and load_id=load) then raise exception 'This load has saved costs or delivery records. Cancel it to retain its history instead of deleting it.';end if;
  result:=public.aggregate_load_delete_v628(t,load);
 else raise exception 'Unknown material load action';end if;
 return result;
end $$;

