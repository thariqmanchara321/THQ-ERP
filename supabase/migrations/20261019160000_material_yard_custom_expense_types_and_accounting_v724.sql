-- ============================================================================
-- THQ ERP Migration v7.2.4
-- Material Yard Custom Expense Types, Dynamic Categories, and Accounting
-- ============================================================================

-- 1. Upgrade material_load_costs_v630 table
alter table public.material_load_costs_v630
  add column if not exists category_id uuid references public.expense_categories(id);

alter table public.material_load_costs_v630
  drop constraint if exists material_load_costs_v630_cost_kind_check;

alter table public.material_load_costs_v630
  add constraint material_load_costs_v630_cost_kind_check
  check(length(trim(cost_kind)) > 0);

create index if not exists material_load_costs_v630_category_idx
  on public.material_load_costs_v630(tenant_id, category_id);

-- 2. Ensure default standard expense categories exist for tenants using Material Yard
create or replace function private.ensure_standard_yard_categories_v724(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  insert into public.expense_categories (tenant_id, name, active, description)
  values
    (p_tenant_id, 'Diesel', true, 'Fuel and diesel for trucks and machinery'),
    (p_tenant_id, 'Driver Wages', true, 'Trip or shift wages for drivers'),
    (p_tenant_id, 'Vehicle Rent', true, 'Rent or hire charges for transport vehicles'),
    (p_tenant_id, 'Freight', true, 'Third-party transport and freight expenses'),
    (p_tenant_id, 'Loading Charges', true, 'Loading and quarry dispatch handling charges'),
    (p_tenant_id, 'Unloading Charges', true, 'Yard and site unloading charges'),
    (p_tenant_id, 'Repairs & Maintenance', true, 'Equipment, vehicle and yard maintenance'),
    (p_tenant_id, 'Toll & Transit', true, 'Toll plaza, weighing, and road transit charges'),
    (p_tenant_id, 'Other Expense', true, 'General operational yard expenses')
  on conflict (tenant_id, lower(name)) do update
    set active = true
  where public.expense_categories.tenant_id = p_tenant_id;
exception when others then
  -- In case unique index on lower(name) is named differently or missing
  null;
end;
$$;

-- 3. Upgrade expenses_category_create to permit Material Yard managers/operators
create or replace function public.expenses_category_create(
  p_tenant_id uuid,
  p_name text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_desc text := trim(coalesce(p_description, ''));
  v_id uuid;
  v_existing record;
  v_allowed boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  v_allowed := private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'expenses.manage')
    or private.erp_has_permission(p_tenant_id, 'aggregate_yard.costs')
    or private.erp_has_permission(p_tenant_id, 'aggregate_yard.manage');

  if not v_allowed then
    raise exception 'Permission denied: expenses.manage or aggregate_yard.costs required' using errcode='42501';
  end if;

  if v_name = '' then
    raise exception 'Category name cannot be empty';
  end if;

  -- Check if category already exists with same name (case-insensitive)
  select id, active, name into v_existing
  from public.expense_categories
  where tenant_id = p_tenant_id and lower(name) = lower(v_name)
  limit 1;

  if found then
    if v_existing.active then
      return jsonb_build_object(
        'id', v_existing.id,
        'category_id', v_existing.id,
        'name', v_existing.name,
        'category_name', v_existing.name,
        'active', true,
        'description', coalesce(nullif(v_desc, ''), ''),
        'reactivated', false
      );
    else
      -- Reactivate existing category and update description if provided
      update public.expense_categories
      set active = true,
          description = coalesce(nullif(v_desc, ''), description)
      where id = v_existing.id and tenant_id = p_tenant_id
      returning id into v_id;

      return jsonb_build_object(
        'id', v_id,
        'category_id', v_id,
        'name', v_existing.name,
        'category_name', v_existing.name,
        'active', true,
        'description', coalesce(nullif(v_desc, ''), ''),
        'reactivated', true
      );
    end if;
  end if;

  -- Insert new category
  insert into public.expense_categories (tenant_id, name, active, description)
  values (p_tenant_id, v_name, true, nullif(v_desc, ''))
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'category_id', v_id,
    'name', v_name,
    'category_name', v_name,
    'active', true,
    'description', v_desc,
    'reactivated', false
  );
end;
$$;

-- 4. Upgrade load_cost_save_v630 to support dynamic category_id and custom expense types
create or replace function private.load_cost_save_v630(
  t uuid,
  load uuid,
  costs jsonb,
  replace_draft boolean default true
)
returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  l public.aggregate_loads_v617%rowtype;
  c public.material_load_costs_v630%rowtype;
  member public.staff_members_v630%rowtype;
  cat record;
  x jsonb;
  v_cost_id uuid;
  staff uuid;
  variant uuid;
  v_cat_id uuid;
  v_cost_kind text;
  amount numeric;
  quantity numeric;
  rate numeric;
  bill numeric;
  seen uuid[] := '{}';
  old jsonb;
begin
  select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load for update;
  if not found then raise exception 'Load not found'; end if;
  perform private.yard_cost_assert_v630(t, l.location_id, true);

  if l.status = 'cancelled' or l.direction = 'direct_delivery' then
    raise exception 'This load cannot accept costs';
  end if;

  -- Rule 4: Only lock costs if the authoritative invoice is finalized
  if replace_draft and (l.sale_id is not null or l.purchase_id is not null) then
    raise exception 'Costs linked to a finalized invoice are locked; add an internal cost instead';
  end if;

  if jsonb_typeof(costs) <> 'array' or jsonb_array_length(costs) > 100 then
    raise exception 'Supply at most 100 cost lines';
  end if;

  for x in select value from jsonb_array_elements(costs) loop
    v_cost_id := coalesce(nullif(x->>'id', '')::uuid, gen_random_uuid());
    staff := nullif(x->>'staff_id', '')::uuid;
    variant := nullif(x->>'billing_variant_id', '')::uuid;
    v_cat_id := nullif(x->>'category_id', '')::uuid;
    quantity := coalesce((x->>'quantity')::numeric, 1);
    rate := coalesce((x->>'rate')::numeric, (x->>'amount')::numeric);
    amount := coalesce((x->>'amount')::numeric, round(quantity * rate, 2));
    bill := round(coalesce((x->>'bill_amount')::numeric, 0), 2);

    -- Resolve category and cost_kind
    v_cost_kind := nullif(trim(x->>'cost_kind'), '');
    if v_cat_id is not null then
      select id, name into cat from public.expense_categories where id = v_cat_id and tenant_id = t;
      if found and (v_cost_kind is null or v_cost_kind = '' or v_cost_kind = 'other') then
        v_cost_kind := lower(regexp_replace(cat.name, '[^a-zA-Z0-9]+', '_', 'g'));
      end if;
    end if;

    if v_cost_kind is null or v_cost_kind = '' then
      v_cost_kind := 'other';
    end if;

    if v_cost_id = any(seen) then raise exception 'Duplicate cost line ID'; end if;
    seen := array_append(seen, v_cost_id);

    if amount is null or amount <= 0 or amount > 1000000000000 or quantity <= 0 or bill < 0 or bill > 1000000000000 then
      raise exception 'Enter a valid quantity, rate and customer charge';
    end if;

    if nullif(trim(x->>'description'), '') is null then
      raise exception 'Cost description is required';
    end if;

    select * into c from public.material_load_costs_v630 where id = v_cost_id for update;
    if found and (c.tenant_id <> t or c.load_id <> load) then
      raise exception 'Cost belongs to a different load' using errcode = '42501';
    end if;

    old := case when c.id is null then null else to_jsonb(c) end;

    if (l.sale_id is not null or l.purchase_id is not null) and bill > 0 then
      raise exception 'A linked invoice is immutable; subsequent costs must be internal';
    end if;

    if bill > 0 and not exists(
      select 1 from public.product_variants v
      join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id
      where v.id = variant and v.tenant_id = t and v.status = 'active' and p.status = 'active' and p.item_type = 'service'
    ) then
      raise exception 'Select an active service product for the customer charge';
    end if;

    if l.direction <> 'outbound' and bill > 0 then
      raise exception 'Customer charges are available on dispatch loads only';
    end if;

    if staff is not null then
      if not exists(select 1 from public.tenant_modules where tenant_id = t and module_key = 'staff' and enabled) then
        raise exception 'Staff module is not enabled';
      end if;
      select * into member from public.staff_members_v630 where tenant_id = t and id = staff and active;
      if not found or (member.location_id is not null and member.location_id <> l.location_id) then
        raise exception 'Staff is inactive or belongs to a different store';
      end if;
      if v_cost_kind not in ('driver_wage', 'staff_wage', 'wage') and not (v_cost_kind like '%wage%') then
        v_cost_kind := 'driver_wage';
      end if;
      if x->>'staff_mode' = 'salary_allocation' and member.wage_basis <> 'monthly' then
        raise exception 'Salary allocation requires a salaried staff member';
      end if;
    end if;

    insert into public.material_load_costs_v630(
      id, tenant_id, load_id, cost_kind, category_id, description, payee, staff_id, staff_mode,
      quantity, rate, amount, bill_amount, billing_variant_id, receipt_reference,
      notes, initial_payment, payment_method, payment_reference
    ) values (
      v_cost_id, t, load, v_cost_kind, v_cat_id, trim(x->>'description'),
      coalesce(member.name, nullif(trim(x->>'payee'), '')), staff,
      coalesce(x->>'staff_mode', 'extra_wage'), quantity, rate, amount, bill, variant,
      x->>'receipt_reference', x->>'notes', coalesce((x->>'initial_payment')::numeric, 0),
      coalesce(x->>'payment_method', 'cash'), x->>'payment_reference'
    )
    on conflict(id) do update set
      cost_kind = excluded.cost_kind,
      category_id = excluded.category_id,
      description = excluded.description,
      payee = excluded.payee,
      staff_id = excluded.staff_id,
      staff_mode = excluded.staff_mode,
      quantity = excluded.quantity,
      rate = excluded.rate,
      amount = excluded.amount,
      bill_amount = excluded.bill_amount,
      billing_variant_id = excluded.billing_variant_id,
      receipt_reference = excluded.receipt_reference,
      notes = excluded.notes,
      initial_payment = excluded.initial_payment,
      payment_method = excluded.payment_method,
      payment_reference = excluded.payment_reference,
      updated_at = now();

    insert into public.workforce_audit_v630(tenant_id, load_id, action, before_data, after_data)
    values(t, load, 'cost.save', old, (select to_jsonb(z) from public.material_load_costs_v630 z where z.id = v_cost_id));

    member := null;
    c := null;
    cat := null;
  end loop;

  if replace_draft then
    for c in select * from public.material_load_costs_v630 where tenant_id = t and load_id = load and status = 'draft' and not(id = any(seen)) for update loop
      update public.material_load_costs_v630 set status = 'void', updated_at = now() where id = c.id;
      insert into public.workforce_audit_v630(tenant_id, load_id, action, before_data, after_data)
      values(t, load, 'cost.remove', to_jsonb(c), jsonb_build_object('status', 'void'));
    end loop;
  end if;
end;
$$;

-- 5. Upgrade material_load_workspace_v630 context to include dynamic expense categories
create or replace function public.material_load_workspace_v630(
  p_tenant_id uuid,
  p_action text,
  p_data jsonb default '{}'::jsonb,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  t uuid := p_tenant_id;
  load uuid := nullif(p_data->>'load_id', '')::uuid;
  location uuid := p_location_id;
  l public.aggregate_loads_v617%rowtype;
  data jsonb := coalesce(p_data->'load', p_data);
  result jsonb;
  prior public.material_load_requests_v630%rowtype;
  costs jsonb := coalesce(p_data->'costs', '[]'::jsonb);
  req text := p_data->>'request_id';
  variant uuid;
  v_sku text;
  mode text;
  name text;
begin
  if p_action = 'context' then
    perform private.aggregate_yard_assert_view_v617(t);
    if location is not null then perform private.v4_location_access(t, location, 'view'); end if;

    -- Ensure baseline categories exist if empty
    if not exists(select 1 from public.expense_categories where tenant_id = t and active) then
      perform private.ensure_standard_yard_categories_v724(t);
    end if;

    return jsonb_build_object(
      'staff', coalesce((select jsonb_agg(jsonb_build_object('staff_id', s.id, 'driver_id', s.driver_id, 'name', s.name, 'phone', s.phone, 'wage_basis', s.wage_basis, 'base_rate', case when private.erp_has_permission(t, 'staff.view') then s.base_rate else null end, 'location_id', s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id = t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t, s.location_id, location, 'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id = t and m.module_key = 'staff' and m.enabled)), '[]'::jsonb),
      'billing_services', coalesce((select jsonb_agg(jsonb_build_object('variant_id', v.id, 'name', p.name, 'tax_rate', p.tax_rate, 'hsn_sac', g.hsn_sac, 'taxability', g.taxability, 'gst_rate', g.gst_rate, 'validation_status', g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t, v.id, current_date)) g on true where v.tenant_id = t and v.status = 'active' and p.status = 'active' and p.item_type = 'service'), '[]'::jsonb),
      'expense_categories', coalesce((select jsonb_agg(jsonb_build_object('id', ec.id, 'category_id', ec.id, 'name', ec.name, 'category_name', ec.name, 'description', coalesce(ec.description, '')) order by ec.name) from public.expense_categories ec where ec.tenant_id = t and ec.active), '[]'::jsonb),
      'tax_mode', private.gst_tax_mode_resolve_v520(t, current_date),
      'can_manage_costs', private.erp_has_permission(t, 'aggregate_yard.costs'),
      'can_create_billing_service', private.erp_has_permission(t, 'inventory.manage') and private.erp_has_permission(t, 'gst_compliance.manage')
    );
  elsif p_action = 'billing_service' then
    perform private.yard_cost_assert_v630(t, location, true);
    name := nullif(trim(data->>'name'), '');
    if name is null then raise exception 'Charge service name is required'; end if;
    mode := private.gst_tax_mode_resolve_v520(t, current_date);
    if mode = 'unconfigured' then raise exception 'Configure the business tax mode first'; end if;
    if mode = 'non_gst' and coalesce((data->>'gst_rate')::numeric, 0) <> 0 then raise exception 'Non-GST charges must have zero GST'; end if;
    if mode = 'gst_registered' and nullif(trim(data->>'hsn_sac'), '') is null then raise exception 'Select the correct SAC for this charge service'; end if;
    v_sku := 'YARD-SVC-' || upper(left(coalesce(nullif(data->>'new_id', ''), gen_random_uuid()::text), 12));
    if exists(select 1 from public.product_variants where tenant_id = t and sku = v_sku) then raise exception 'Charge service already exists; refresh the list'; end if;
    result := public.inventory_create_product_v481(p_tenant_id => t, p_location_id => location, p_device_id => nullif(data->>'device_id', '')::uuid, p_name => name, p_sku => v_sku, p_item_type => 'service', p_description => coalesce(data->>'description', name), p_category_name => 'Load Charges', p_brand_name => '', p_barcode => '', p_part_number => '', p_cost_price => 0, p_selling_price => 0, p_list_price => null, p_tax_rate => coalesce((data->>'gst_rate')::numeric, 0), p_reorder_level => 0, p_opening_stock => 0, p_base_unit_code => 'PCS', p_units => '[]'::jsonb);
    variant := (result->>'variant_id')::uuid;
    if mode = 'gst_registered' then perform public.gst_product_profile_save_v520(t, variant, 'service', data->>'hsn_sac', coalesce(data->>'taxability', 'taxable'), coalesce((data->>'gst_rate')::numeric, 0), 0, 0, false, false, 'Load charge service setup', current_date); end if;
    return jsonb_build_object('variant_id', variant, 'recorded', true);
  elsif p_action = 'report' then
    perform private.aggregate_yard_assert_view_v617(t);
    if location is not null then perform private.v4_location_access(t, location, 'view'); end if;
    if coalesce((data->>'to')::date, current_date) < coalesce((data->>'from')::date, date_trunc('month', current_date)::date) then raise exception 'End date must follow start date'; end if;
    return jsonb_build_object('loads', coalesce((select jsonb_agg(private.load_evidence_v630(t, x.id) order by x.load_date desc, x.load_number) from public.aggregate_loads_v617 x where x.tenant_id = t and x.direction <> 'direct_delivery' and x.load_date between coalesce((data->>'from')::date, date_trunc('month', current_date)::date) and coalesce((data->>'to')::date, current_date) and private.erp_document_scope_allowed(t, x.location_id, location, 'view') and (nullif(data->>'vehicle_id', '') is null or x.vehicle_id = (data->>'vehicle_id')::uuid) and (nullif(data->>'driver_id', '') is null or x.driver_id = (data->>'driver_id')::uuid)), '[]'::jsonb));
  end if;

  if p_action = 'create' then
    perform private.aggregate_yard_assert_manage_v617(t);
    if req is null or length(req) > 256 then raise exception 'A stable load request ID is required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(t::text || ':load:' || req, 0));
    select * into prior from public.material_load_requests_v630 where tenant_id = t and request_id = req;
    if found then
      if prior.payload <> p_data then raise exception 'Load retry has different data'; end if;
      return jsonb_build_object('load_id', prior.load_id, 'replayed', true);
    end if;
    result := public.aggregate_load_create_v617(t, data->>'p_direction', nullif(data->>'p_location_id', '')::uuid, (data->>'p_variant_id')::uuid, (data->>'p_quantity')::numeric, data->>'p_unit_code', data->>'p_measurement_method', (data->>'p_body_length_ft')::numeric, (data->>'p_body_width_ft')::numeric, (data->>'p_body_height_ft')::numeric, (data->>'p_gross_weight_kg')::numeric, (data->>'p_tare_weight_kg')::numeric, (data->>'p_net_weight_kg')::numeric, nullif(data->>'p_vehicle_id', '')::uuid, nullif(data->>'p_driver_id', '')::uuid, nullif(data->>'p_supplier_id', '')::uuid, nullif(data->>'p_customer_id', '')::uuid, data->>'p_source_name', data->>'p_destination_name', data->>'p_source_reference', data->>'p_freight_mode', (data->>'p_freight_amount')::numeric, (data->>'p_capacity_override')::boolean, data->>'p_capacity_override_reason', data->>'p_notes');
    load := (result->>'load_id')::uuid;

    update public.aggregate_loads_v617
    set raw_dimensions = data->'p_raw_dimensions',
        dimension_unit = coalesce(data->>'p_dimension_unit', 'ft'),
        calculated_cft = (data->>'p_calculated_cft')::numeric,
        heap_adjustment_cft = coalesce((data->>'p_heap_adjustment_cft')::numeric, 0),
        approved_billable_qty = (data->>'p_approved_billable_qty')::numeric,
        approved_by = nullif(data->>'p_approved_by', '')::uuid,
        measurement_notes = data->>'p_measurement_notes',
        load_date = coalesce((data->>'p_load_date')::date, load_date)
    where id = load and tenant_id = t;

    select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load;
    perform private.v4_location_access(t, l.location_id, 'operate');
    if jsonb_array_length(costs) > 0 then perform private.load_cost_save_v630(t, load, costs); end if;
    perform private.load_delivery_save_v630(t, load, jsonb_build_object('driver_license_snapshot', (select license_number from public.logistics_drivers_v61 where id = l.driver_id and tenant_id = t)) || coalesce(p_data->'delivery', '{}'::jsonb));
    insert into public.material_load_requests_v630(tenant_id, request_id, payload, load_id) values(t, req, p_data, load);
    return result;
  end if;

  select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load for update;
  if not found then raise exception 'Load not found'; end if;
  if p_action = 'detail' then return private.load_evidence_v630(t, load); end if;

  perform private.aggregate_yard_assert_manage_v617(t);
  perform private.v4_location_access(t, l.location_id, 'operate');

  if p_action = 'reopen' then
    return public.aggregate_load_reopen_v722(t, load, data->>'reason');
  elsif p_action = 'edit' then
    result := public.aggregate_load_edit_v628(
      t, load, data->>'p_direction', nullif(data->>'p_location_id', '')::uuid,
      (data->>'p_variant_id')::uuid, (data->>'p_quantity')::numeric, data->>'p_unit_code',
      data->>'p_measurement_method', (data->>'p_body_length_ft')::numeric,
      (data->>'p_body_width_ft')::numeric, (data->>'p_body_height_ft')::numeric,
      (data->>'p_gross_weight_kg')::numeric, (data->>'p_tare_weight_kg')::numeric,
      (data->>'p_net_weight_kg')::numeric, nullif(data->>'p_vehicle_id', '')::uuid,
      nullif(data->>'p_driver_id', '')::uuid, nullif(data->>'p_supplier_id', '')::uuid,
      nullif(data->>'p_customer_id', '')::uuid, data->>'p_source_name',
      data->>'p_destination_name', data->>'p_source_reference', data->>'p_freight_mode',
      (data->>'p_freight_amount')::numeric, (data->>'p_capacity_override')::boolean,
      data->>'p_capacity_override_reason', data->>'p_notes',
      (data->>'p_load_date')::date
    );

    update public.aggregate_loads_v617
    set raw_dimensions = coalesce(data->'p_raw_dimensions', raw_dimensions),
        dimension_unit = coalesce(data->>'p_dimension_unit', dimension_unit),
        calculated_cft = coalesce((data->>'p_calculated_cft')::numeric, calculated_cft),
        heap_adjustment_cft = coalesce((data->>'p_heap_adjustment_cft')::numeric, heap_adjustment_cft),
        approved_billable_qty = coalesce((data->>'p_approved_billable_qty')::numeric, approved_billable_qty),
        approved_by = coalesce(nullif(data->>'p_approved_by', '')::uuid, approved_by),
        measurement_notes = coalesce(data->>'p_measurement_notes', measurement_notes),
        load_date = coalesce((data->>'p_load_date')::date, load_date)
    where id = load and tenant_id = t;

    perform private.v4_location_access(t, (select location_id from public.aggregate_loads_v617 where id = load), 'operate');
    if p_data ? 'costs' and private.erp_has_permission(t, 'aggregate_yard.costs') then
      perform private.load_cost_save_v630(t, load, costs);
    end if;
    if p_data ? 'delivery' then
      perform private.load_delivery_save_v630(t, load, p_data->'delivery');
    end if;
  elsif p_action = 'confirm' then
    result := public.aggregate_load_confirm_v628(t, load);
    perform private.load_costs_post_v630(t, load);
  elsif p_action = 'delivery' then
    perform private.load_delivery_save_v630(t, load, data);
    result := jsonb_build_object('recorded', true);
  elsif p_action = 'payment' then
    result := jsonb_build_object('payment_id', private.load_cost_payment_v630(t, (data->>'cost_id')::uuid, data));
  elsif p_action = 'add_cost' then
    if req is null or length(req) > 256 then raise exception 'A stable expense submission request ID is required'; end if;
    select * into prior from public.material_load_requests_v630 where tenant_id = t and request_id = 'add-cost:' || req;
    if found then
      if prior.load_id <> load or prior.payload <> p_data then raise exception 'Expense retry has different data'; end if;
      return jsonb_build_object('recorded', true, 'replayed', true);
    end if;
    perform private.load_cost_save_v630(t, load, case when p_data ? 'costs' then costs else jsonb_build_array(p_data->'cost') end, false);
    if l.status = 'completed' then perform private.load_costs_post_v630(t, load); end if;
    insert into public.material_load_requests_v630(tenant_id, request_id, payload, load_id) values(t, 'add-cost:' || req, p_data, load);
    result := jsonb_build_object('recorded', true);
  elsif p_action = 'cancel' then
    if l.status = 'completed' or l.sale_id is not null or l.purchase_id is not null then
      raise exception 'Only an unconfirmed load can be cancelled. Confirmed costs and linked documents retain their financial history.';
    end if;
    result := public.aggregate_load_status_v617(t, load, 'cancelled', coalesce(p_data->>'reason', 'Cancelled before confirmation'));
  elsif p_action = 'delete' then
    if exists(select 1 from public.material_load_costs_v630 where tenant_id = t and load_id = load) or exists(select 1 from public.material_load_delivery_v630 where tenant_id = t and load_id = load) then
      raise exception 'This load has saved costs or delivery records. Cancel it to retain its history instead of deleting it.';
    end if;
    result := public.aggregate_load_delete_v628(t, load);
  else
    raise exception 'Unknown material load action: %', p_action;
  end if;
  return result;
end;
$$;

-- 6. Upgrade load_evidence_v630 to return category_id and category_name
create or replace function private.load_evidence_v630(t uuid, load uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  l public.aggregate_loads_v617%rowtype;
  result jsonb;
begin
  select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load;
  if not found then raise exception 'Load not found'; end if;
  perform private.yard_cost_assert_v630(t, l.location_id, false);
  result := public.aggregate_load_detail_v629(t, load);
  return result || jsonb_build_object(
    'load_record', to_jsonb(l),
    'trip', coalesce((select to_jsonb(h) from public.transport_trip_hub_v611 h where h.tenant_id = t and h.material_load_id = load), '{}'::jsonb),
    'driver_current', coalesce((select to_jsonb(d) from public.logistics_drivers_v61 d where d.tenant_id = t and d.id = l.driver_id), '{}'::jsonb),
    'vehicle_current', coalesce((select to_jsonb(v) || jsonb_build_object('yard_profile', (select to_jsonb(p) from public.aggregate_vehicle_profiles_v617 p where p.tenant_id = t and p.vehicle_id = v.id)) from public.service_vehicles v where v.tenant_id = t and v.id = l.vehicle_id), '{}'::jsonb),
    'load_events', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at, e.id) from public.aggregate_load_events_v617 e where e.tenant_id = t and e.load_id = load), '[]'::jsonb),
    'location_name', (select name from public.business_locations where tenant_id = t and id = l.location_id),
    'legacy_freight_payments', coalesce((select jsonb_agg(to_jsonb(f) order by f.settled_at) from public.aggregate_freight_settlements_v620 f where f.tenant_id = t and f.load_id = load), '[]'::jsonb),
    'sale', coalesce((
      select to_jsonb(s) || jsonb_build_object(
        'items', coalesce((
          select jsonb_agg(to_jsonb(si) order by si.created_at, si.id)
          from public.sale_items si
          where si.tenant_id = t and si.sale_id = s.id
        ), '[]'::jsonb)
      )
      from public.sales s
      where s.tenant_id = t and s.id = l.sale_id
    ), '{}'::jsonb),
    'purchase', coalesce((
      select to_jsonb(p) || jsonb_build_object(
        'items', coalesce((
          select jsonb_agg(to_jsonb(pi) order by pi.created_at, pi.id)
          from public.purchase_items pi
          where pi.tenant_id = t and pi.purchase_id = p.id
        ), '[]'::jsonb)
      )
      from public.purchases p
      where p.tenant_id = t and p.id = l.purchase_id
    ), '{}'::jsonb),
    'customer_payments', coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.tenant_id = t and p.sale_id = l.sale_id), '[]'::jsonb),
    'delivery', coalesce((select details from public.material_load_delivery_v630 where tenant_id = t and load_id = load), '{}'::jsonb),
    'costs', coalesce((
      select jsonb_agg(
        to_jsonb(c) || jsonb_build_object(
          'paid_amount', coalesce(private.load_cost_paid_v630(c.id), 0),
          'outstanding', case when c.staff_mode = 'salary_allocation' or c.status <> 'posted' then 0 else c.amount - coalesce(private.load_cost_paid_v630(c.id), 0) end,
          'category_name', coalesce((select ec.name from public.expense_categories ec where ec.id = c.category_id and ec.tenant_id = t), initcap(replace(c.cost_kind, '_', ' '))),
          'billing_service', (select p.name from public.product_variants v join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id where v.id = c.billing_variant_id and v.tenant_id = t)
        )
        order by c.created_at, c.id
      )
      from public.material_load_costs_v630 c
      where c.tenant_id = t and c.load_id = load
    ), '[]'::jsonb),
    'cost_payments', coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('cost_description', c.description, 'payee', c.payee) order by p.payment_date, p.created_at) from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id = p.cost_id and c.tenant_id = p.tenant_id where c.tenant_id = t and c.load_id = load), '[]'::jsonb),
    'staff_payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'payment_date', p.payment_date, 'amount', a.amount, 'payment_method', p.payment_method, 'reference', p.reference, 'payee', p.payee_snapshot, 'cost_id', c.id, 'cost_description', c.description, 'from_advance', a.from_advance, 'journal_id', a.journal_id, 'notes', p.notes) order by p.payment_date, p.created_at) from public.material_load_costs_v630 c join public.staff_payment_allocations_v630 a on a.earning_id = c.staff_earning_id join public.staff_payments_v630 p on p.id = a.payment_id and p.tenant_id = c.tenant_id where c.tenant_id = t and c.load_id = load), '[]'::jsonb),
    'cost_total', coalesce((select sum(amount) from public.material_load_costs_v630 where tenant_id = t and load_id = load and status <> 'void'), 0),
    'customer_charge_total', coalesce((select sum(bill_amount) from public.material_load_costs_v630 where tenant_id = t and load_id = load and status <> 'void'), 0),
    'history', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.workforce_audit_v630 a where a.tenant_id = t and a.load_id = load), '[]'::jsonb)
  );
end $$;
