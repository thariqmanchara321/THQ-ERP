-- THQ ERP — MATERIAL YARD: FULL EDITABILITY BEFORE FINAL SALE/PURCHASE POSTING (v722)
-- Migration: 20261016180000_material_yard_pre_posting_full_editability_v722.sql
--
-- Objective:
-- 1. Make draft and confirmed-unbilled Material Yard loads fully editable until authoritative Sale/Purchase is posted.
-- 2. Provide explicit Reopen for Editing action preserving full audit trails.
-- 3. Allow editing quantities, rates, suppliers, customers, and expenses in the billing drafts.
-- 4. Detect concurrency conflicts if a load was edited elsewhere after a billing draft was opened.
-- 5. Enforce strict immutability once authoritative Sale/Purchase is finalized with inventory/journal effects.

-- ============================================================================
-- 1. Explicit Reopen Function: public.aggregate_load_reopen_v722
-- ============================================================================
create or replace function public.aggregate_load_reopen_v722(
  p_tenant_id uuid,
  p_load_id uuid,
  p_reason text default 'Reopened for editing before billing posting'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_cost public.material_load_costs_v630%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select * into v_row
  from public.aggregate_loads_v617
  where id = p_load_id and tenant_id = p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  perform private.v4_location_access(p_tenant_id, v_row.location_id, 'operate');

  -- Rule 4: Immutability once authoritative Sale/Purchase is posted
  if v_row.purchase_id is not null or v_row.sale_id is not null then
    raise exception 'Load linked to a finalized Purchase or Sale cannot be edited or reopened';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'Cancelled load cannot be reopened. Create a new load instead.';
  end if;

  if v_row.status = 'draft' then
    return jsonb_build_object(
      'success', true,
      'already_draft', true,
      'load_id', v_row.id,
      'load_number', v_row.load_number,
      'status', 'draft'
    );
  end if;

  -- Reopen costs: Return unpaid posted load costs back to draft so they can be modified
  for v_cost in
    select * from public.material_load_costs_v630
    where tenant_id = p_tenant_id and load_id = p_load_id and status = 'posted'
    for update
  loop
    if coalesce(private.load_cost_paid_v630(v_cost.id), 0) = 0 then
      if v_cost.journal_id is not null then
        update public.journal_entries set status = 'reversed' where id = v_cost.journal_id;
      end if;
      update public.material_load_costs_v630
      set status = 'draft',
          journal_id = null,
          staff_earning_id = null,
          updated_at = now()
      where id = v_cost.id;
    end if;
  end loop;

  update public.aggregate_loads_v617
  set status = 'draft',
      updated_by = auth.uid(),
      updated_at = now()
  where id = v_row.id and tenant_id = p_tenant_id;

  -- Audit event preservation
  insert into public.aggregate_load_events_v617(
    tenant_id, load_id, event_type, from_status, to_status, note, created_by
  ) values (
    p_tenant_id, v_row.id, 'reopened', v_row.status, 'draft',
    coalesce(p_reason, 'Reopened for editing before billing posting'),
    auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.reopen',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    jsonb_build_object(
      'status', 'draft',
      'prior_status', v_row.status,
      'reason', coalesce(p_reason, 'Reopened for editing before billing posting')
    )
  );

  return jsonb_build_object(
    'success', true,
    'load_id', v_row.id,
    'load_number', v_row.load_number,
    'status', 'draft',
    'reopened', true
  );
end;
$$;

revoke all on function public.aggregate_load_reopen_v722(uuid, uuid, text) from public, anon;
grant execute on function public.aggregate_load_reopen_v722(uuid, uuid, text) to authenticated, service_role;

-- ============================================================================
-- 2. Full Pre-Posting Editability in aggregate_load_edit_v628
-- ============================================================================
create or replace function public.aggregate_load_edit_v628(
  p_tenant_id uuid,
  p_load_id uuid,
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
  p_notes text,
  p_load_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_after public.aggregate_loads_v617%rowtype;
  v_qty numeric;
  v_product text;
  v_vehicle public.service_vehicles%rowtype;
  v_driver public.logistics_drivers_v61%rowtype;
  v_capacity numeric;
  v_measure text := lower(coalesce(p_measurement_method, 'manual'));
  v_unit text := upper(coalesce(nullif(trim(p_unit_code), ''), 'CFT'));
  v_direction text := lower(trim(coalesce(p_direction, '')));
  v_freight_mode text := lower(coalesce(p_freight_mode, 'none'));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id = p_load_id and tenant_id = p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'Cancelled load cannot be edited';
  end if;

  -- Rule 4: Once finalized with Sale or Purchase, locking is absolute
  if v_row.purchase_id is not null or v_row.sale_id is not null then
    raise exception 'Load linked to a finalized Purchase or Sale cannot be edited';
  end if;

  if v_row.order_id is not null or v_row.order_line_id is not null then
    raise exception 'Customer Order load cannot be edited from Load Register';
  end if;

  if exists(
    select 1
    from public.aggregate_freight_settlements_v620 f
    where f.tenant_id = p_tenant_id and f.load_id = p_load_id
  ) then
    raise exception 'Load has posted freight settlements and cannot be edited';
  end if;

  if v_direction not in ('inbound', 'outbound', 'direct_delivery') then
    raise exception 'Direction must be inbound, outbound, or direct_delivery';
  end if;

  if p_location_id is not null then
    perform private.v4_location_access(p_tenant_id, p_location_id, 'operate');
  end if;

  select p.name
  into v_product
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id
  where v.id = p_variant_id and v.tenant_id = p_tenant_id;

  if v_product is null then
    raise exception 'Product variant not found';
  end if;

  v_qty := coalesce(p_quantity, 0);
  if v_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  if v_measure not in ('manual', 'dimensions', 'weighbridge') then
    raise exception 'Measurement method must be manual, dimensions, or weighbridge';
  end if;

  if v_freight_mode not in ('none', 'own', 'hired', 'supplier', 'customer', 'included') then
    raise exception 'Invalid freight mode';
  end if;

  if coalesce(p_freight_amount, 0) < 0 then
    raise exception 'Freight amount cannot be negative';
  end if;

  if p_vehicle_id is not null then
    select * into v_vehicle
    from public.service_vehicles
    where id = p_vehicle_id and tenant_id = p_tenant_id;

    if v_vehicle.id is null then
      raise exception 'Vehicle not found';
    end if;

    if v_unit = 'CFT' and coalesce(v_vehicle.capacity, 0) > 0 and upper(coalesce(v_vehicle.capacity_unit, '')) = 'CFT' then
      v_capacity := v_vehicle.capacity;
      if v_qty > v_capacity and not coalesce(p_capacity_override, false) then
        raise exception 'Load volume (% CFT) exceeds vehicle capacity (% CFT). Enable capacity override to proceed.',
          v_qty, v_capacity;
      end if;
    end if;
  end if;

  if p_driver_id is not null then
    select * into v_driver
    from public.logistics_drivers_v61
    where id = p_driver_id and tenant_id = p_tenant_id;

    if v_driver.id is null then
      raise exception 'Driver not found';
    end if;
  end if;

  if coalesce(p_capacity_override, false) and nullif(trim(coalesce(p_capacity_override_reason, '')), '') is null then
    raise exception 'Capacity override reason is required';
  end if;

  update public.aggregate_loads_v617
  set direction = v_direction,
      location_id = coalesce(p_location_id, location_id),
      load_date = coalesce(p_load_date, load_date),
      variant_id = p_variant_id,
      product_name_snapshot = v_product,
      quantity = v_qty,
      unit_code = v_unit,
      measurement_method = v_measure,
      body_length_ft = case when v_measure = 'dimensions' then p_body_length_ft else null end,
      body_width_ft = case when v_measure = 'dimensions' then p_body_width_ft else null end,
      body_height_ft = case when v_measure = 'dimensions' then p_body_height_ft else null end,
      gross_weight_kg = case when v_measure = 'weighbridge' then p_gross_weight_kg else null end,
      tare_weight_kg = case when v_measure = 'weighbridge' then p_tare_weight_kg else null end,
      net_weight_kg = case when v_measure = 'weighbridge' then p_net_weight_kg else null end,
      vehicle_id = p_vehicle_id,
      vehicle_registration_snapshot = coalesce(v_vehicle.registration_number, vehicle_registration_snapshot),
      driver_id = p_driver_id,
      driver_name_snapshot = coalesce(v_driver.name, driver_name_snapshot),
      driver_phone_snapshot = coalesce(v_driver.phone, driver_phone_snapshot),
      supplier_id = p_supplier_id,
      customer_id = p_customer_id,
      source_name = nullif(trim(coalesce(p_source_name, '')), ''),
      destination_name = nullif(trim(coalesce(p_destination_name, '')), ''),
      source_reference = nullif(trim(coalesce(p_source_reference, '')), ''),
      freight_mode = v_freight_mode,
      freight_amount = coalesce(p_freight_amount, 0),
      capacity_override = coalesce(p_capacity_override, false),
      capacity_override_reason = case when p_capacity_override then trim(p_capacity_override_reason) else null end,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_load_id and tenant_id = p_tenant_id
  returning * into v_after;

  -- Record audit trail
  insert into public.aggregate_load_events_v617(
    tenant_id, load_id, event_type, from_status, to_status, note, created_by
  ) values (
    p_tenant_id, p_load_id,
    case when v_row.status = 'completed' then 'edited_confirmed' else 'edited' end,
    v_row.status, v_row.status,
    case when v_row.status = 'completed' then 'Load edited while confirmed-unbilled' else 'Draft load edited' end,
    auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.edit',
    'aggregate_load',
    p_load_id,
    v_after.load_number,
    to_jsonb(v_row),
    to_jsonb(v_after)
  );

  return jsonb_build_object(
    'load_id', v_after.id,
    'load_number', v_after.load_number,
    'status', v_after.status,
    'updated', true
  );
end;
$function$;

revoke all on function public.aggregate_load_edit_v628(uuid, uuid, text, uuid, uuid, numeric, text, text, numeric, numeric, numeric, numeric, numeric, numeric, uuid, uuid, uuid, uuid, text, text, text, text, numeric, boolean, text, text, date) from public, anon;
grant execute on function public.aggregate_load_edit_v628(uuid, uuid, text, uuid, uuid, numeric, text, text, numeric, numeric, numeric, numeric, numeric, numeric, uuid, uuid, uuid, uuid, text, text, text, text, numeric, boolean, text, text, date) to authenticated, service_role;

-- ============================================================================
-- 3. Update load_cost_save_v630 to Allow Cost Edits on Confirmed-Unbilled Loads
-- ============================================================================
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
  x jsonb;
  v_cost_id uuid;
  staff uuid;
  variant uuid;
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
    quantity := coalesce((x->>'quantity')::numeric, 1);
    rate := (x->>'rate')::numeric;
    amount := round(quantity * rate, 2);
    bill := round(coalesce((x->>'bill_amount')::numeric, 0), 2);

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
      if x->>'cost_kind' not in ('driver_wage', 'staff_wage') then
        raise exception 'Staff payees must use a wage cost type';
      end if;
      if x->>'staff_mode' = 'salary_allocation' and member.wage_basis <> 'monthly' then
        raise exception 'Salary allocation requires a salaried staff member';
      end if;
    end if;

    insert into public.material_load_costs_v630(
      id, tenant_id, load_id, cost_kind, description, payee, staff_id, staff_mode,
      quantity, rate, amount, bill_amount, billing_variant_id, receipt_reference,
      notes, initial_payment, payment_method, payment_reference
    ) values (
      v_cost_id, t, load, x->>'cost_kind', trim(x->>'description'),
      coalesce(member.name, nullif(trim(x->>'payee'), '')), staff,
      coalesce(x->>'staff_mode', 'extra_wage'), quantity, rate, amount, bill, variant,
      x->>'receipt_reference', x->>'notes', coalesce((x->>'initial_payment')::numeric, 0),
      coalesce(x->>'payment_method', 'cash'), x->>'payment_reference'
    )
    on conflict(id) do update set
      cost_kind = excluded.cost_kind,
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

-- ============================================================================
-- 4. Update material_load_workspace_v630 (reopen action + audit fields)
-- ============================================================================
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
    return jsonb_build_object(
      'staff', coalesce((select jsonb_agg(jsonb_build_object('staff_id', s.id, 'driver_id', s.driver_id, 'name', s.name, 'phone', s.phone, 'wage_basis', s.wage_basis, 'base_rate', case when private.erp_has_permission(t, 'staff.view') then s.base_rate else null end, 'location_id', s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id = t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t, s.location_id, location, 'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id = t and m.module_key = 'staff' and m.enabled)), '[]'::jsonb),
      'billing_services', coalesce((select jsonb_agg(jsonb_build_object('variant_id', v.id, 'name', p.name, 'tax_rate', p.tax_rate, 'hsn_sac', g.hsn_sac, 'taxability', g.taxability, 'gst_rate', g.gst_rate, 'validation_status', g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t, v.id, current_date)) g on true where v.tenant_id = t and v.status = 'active' and p.status = 'active' and p.item_type = 'service'), '[]'::jsonb),
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

-- ============================================================================
-- 5. Update private.aggregate_load_document_lock_v629
-- ============================================================================
create or replace function private.aggregate_load_document_lock_v629(
  p_tenant_id uuid,
  p_load_id uuid,
  p_direction text,
  p_location_id uuid
)
returns public.aggregate_loads_v617
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_load public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select * into v_load from public.aggregate_loads_v617
  where id = p_load_id and tenant_id = p_tenant_id for update;

  if not found then raise exception 'Load not found'; end if;

  perform private.v4_location_access(p_tenant_id, v_load.location_id, 'operate');

  if v_load.direction <> p_direction then
    raise exception 'Invoice type does not match the load direction';
  end if;

  -- Rule 4: Prevent duplicate posting if already finalized
  if p_direction = 'inbound' and v_load.purchase_id is not null then
    raise exception 'Load % has already been finalized and billed under purchase', v_load.load_number;
  end if;

  if p_direction = 'outbound' and v_load.sale_id is not null then
    raise exception 'Load % has already been finalized and billed under sale', v_load.load_number;
  end if;

  if v_load.status = 'cancelled' then
    raise exception 'Cancelled load cannot be billed';
  end if;

  if v_load.location_id is distinct from p_location_id then
    raise exception 'Invoice location must match the load yard/store';
  end if;

  return v_load;
end;
$$;

revoke all on function private.aggregate_load_document_lock_v629(uuid, uuid, text, uuid) from public, anon, authenticated;

-- ============================================================================
-- 6. Update private.load_sale_items_v630 (Remove Strict Quantity Lock)
-- ============================================================================
create or replace function private.load_sale_items_v630(
  t uuid,
  load uuid,
  items jsonb,
  document_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  l public.aggregate_loads_v617%rowtype;
  extra jsonb;
begin
  select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load;
  if not found then raise exception 'Load not found'; end if;
  perform private.yard_cost_assert_v630(t, l.location_id, false);

  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) = 0 then
    raise exception 'Invoice items are required';
  end if;

  if not exists(select 1 from jsonb_array_elements(items) x where (x->>'variant_id')::uuid = l.variant_id) then
    raise exception 'The invoice must include the load material';
  end if;

  -- Note: Quantity and rate are permitted to be edited in the billing draft.
  -- The physical load measurement remains historically preserved on aggregate_loads_v617.

  if exists(
    select 1 from public.material_load_costs_v630 c
    join lateral private.gst_profile_for_variant_v520(t, c.billing_variant_id, document_date) g on true
    where c.tenant_id = t and c.load_id = load and c.status = 'posted' and c.bill_amount > 0 and g.tax_inclusive
  ) then
    raise exception 'Load customer charges are entered before GST. Select a tax-exclusive service or create a separate invoice charge service.';
  end if;

  if exists(
    select 1 from public.material_load_costs_v630 c
    join jsonb_array_elements(items) x on (x->>'variant_id')::uuid = c.billing_variant_id
    where c.tenant_id = t and c.load_id = load and c.status = 'posted' and c.bill_amount > 0
  ) then
    raise exception 'A load billing service is already an invoice product; select a separate billing service for the load charges';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'variant_id', c.billing_variant_id,
    'unit_id', (select unit_id from public.product_units_v481 pu where pu.tenant_id = t and pu.variant_id = c.billing_variant_id and pu.is_base and pu.active and pu.allow_sale limit 1),
    'quantity', 1,
    'unit_price', c.bill_amount,
    'discount_amount', 0,
    'tax_rate', 0,
    'invoice_description', c.description,
    'material_cost_ids', c.ids
  ) order by c.description), '[]'::jsonb)
  into extra
  from (
    select billing_variant_id, sum(bill_amount) bill_amount,
           string_agg(description, '; ' order by created_at, id) description,
           jsonb_agg(id order by created_at, id) ids
    from public.material_load_costs_v630
    where tenant_id = t and load_id = load and status = 'posted' and bill_amount > 0
    group by billing_variant_id
  ) c;

  return items || extra;
end;
$$;

revoke all on function private.load_sale_items_v630(uuid, uuid, jsonb, date) from public, anon, authenticated;

-- ============================================================================
-- 7. Update public.aggregate_load_link_document_v617
-- ============================================================================
create or replace function public.aggregate_load_link_document_v617(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_type text := lower(trim(coalesce(p_document_type, '')));
  v_ref text;
  v_load public.aggregate_loads_v617%rowtype;
  v_document_qty numeric := 0;
  v_allocated_qty numeric := 0;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select * into v_load
  from public.aggregate_loads_v617
  where id = p_load_id and tenant_id = p_tenant_id
  for update;

  if v_load.id is null then raise exception 'Load not found'; end if;
  if v_load.status = 'cancelled' then
    raise exception 'Cancelled load cannot be linked to a transaction';
  end if;
  if v_load.direction = 'direct_delivery' then
    raise exception 'Direct-delivery commercial posting is disabled until the transit-stock workflow is installed';
  end if;

  if v_type = 'purchase' then
    if v_load.direction <> 'inbound' then
      raise exception 'Only inbound loads may link a Purchase';
    end if;
    if v_load.purchase_id is not null and v_load.purchase_id <> p_document_id then
      raise exception 'Load is already linked to another Purchase';
    end if;

    perform 1 from public.purchases p
    where p.id = p_document_id and p.tenant_id = p_tenant_id
    for update;
    if not found then raise exception 'Purchase not found'; end if;

    select p.purchase_number,
      coalesce(sum(
        case
          when upper(coalesce(pi.entered_unit_code, pi.unit_code, '')) = upper(v_load.unit_code)
          then coalesce(pi.entered_quantity, pi.quantity)
          else 0
        end
      ), 0)
    into v_ref, v_document_qty
    from public.purchases p
    join public.purchase_items pi on pi.purchase_id = p.id and pi.tenant_id = p.tenant_id and pi.variant_id = v_load.variant_id
    where p.id = p_document_id and p.tenant_id = p_tenant_id
    group by p.purchase_number;

    if v_ref is null then
      raise exception 'Purchase does not contain the load material';
    end if;

    select coalesce(sum(x.quantity), 0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id = p_tenant_id
      and x.id <> p_load_id
      and x.purchase_id = p_document_id
      and x.variant_id = v_load.variant_id
      and upper(x.unit_code) = upper(v_load.unit_code)
      and x.status <> 'cancelled';

    if v_allocated_qty > 0 and v_allocated_qty >= v_document_qty then
      raise exception 'Purchase quantity % % is already fully allocated by other loads.',
        v_document_qty, v_load.unit_code;
    end if;

    update public.aggregate_loads_v617
    set purchase_id = p_document_id,
        status = 'completed',
        updated_by = auth.uid(),
        updated_at = now()
    where id = p_load_id and tenant_id = p_tenant_id;

  elsif v_type = 'sale' then
    if v_load.direction <> 'outbound' then
      raise exception 'Only outbound loads may link a Sale';
    end if;
    if v_load.sale_id is not null and v_load.sale_id <> p_document_id then
      raise exception 'Load is already linked to another Sale';
    end if;

    perform 1 from public.sales s
    where s.id = p_document_id and s.tenant_id = p_tenant_id
    for update;
    if not found then raise exception 'Sale not found'; end if;

    select s.sale_number,
      coalesce(sum(
        case
          when upper(coalesce(si.entered_unit_code, si.unit_code, '')) = upper(v_load.unit_code)
          then coalesce(si.entered_quantity, si.quantity)
          else 0
        end
      ), 0)
    into v_ref, v_document_qty
    from public.sales s
    join public.sale_items si on si.sale_id = s.id and si.tenant_id = s.tenant_id and si.variant_id = v_load.variant_id
    where s.id = p_document_id and s.tenant_id = p_tenant_id
    group by s.sale_number;

    if v_ref is null then
      raise exception 'Sale does not contain the load material';
    end if;

    select coalesce(sum(x.quantity), 0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id = p_tenant_id
      and x.id <> p_load_id
      and x.sale_id = p_document_id
      and x.variant_id = v_load.variant_id
      and upper(x.unit_code) = upper(v_load.unit_code)
      and x.status <> 'cancelled';

    if v_allocated_qty > 0 and v_allocated_qty >= v_document_qty then
      raise exception 'Sale quantity % % is already fully allocated by other loads.',
        v_document_qty, v_load.unit_code;
    end if;

    update public.aggregate_loads_v617
    set sale_id = p_document_id,
        status = 'completed',
        updated_by = auth.uid(),
        updated_at = now()
    where id = p_load_id and tenant_id = p_tenant_id;
  else
    raise exception 'Document type must be purchase or sale';
  end if;

  insert into public.aggregate_load_events_v617(
    tenant_id, load_id, event_type, from_status, to_status, note, created_by
  ) values (
    p_tenant_id, p_load_id,
    v_type || '_linked',
    v_load.status, 'completed',
    'Linked to authoritative ' || v_type || ' ' || v_ref,
    auth.uid()
  );

  return jsonb_build_object(
    'load_id', p_load_id,
    'document_type', v_type,
    'document_id', p_document_id,
    'reference', v_ref,
    'linked', true
  );
end;
$$;

revoke all on function public.aggregate_load_link_document_v617(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.aggregate_load_link_document_v617(uuid, uuid, text, uuid) to authenticated, service_role;

-- ============================================================================
-- 8. Update aggregate_load_purchase_create_v629 (Concurrency & Supplier Flex)
-- ============================================================================
create or replace function public.aggregate_load_purchase_create_v629(
  p_tenant_id uuid,
  p_load_id uuid,
  p_supplier_id uuid,
  p_supplier_invoice_number text,
  p_purchase_date date,
  p_due_date date,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0,
  p_initial_payment numeric default 0,
  p_payment_method text default 'cash',
  p_payment_reference text default null,
  p_notes text default null,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_request_id text default null,
  p_supply_type text default null,
  p_place_of_supply_code text default null,
  p_load_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_load public.aggregate_loads_v617%rowtype;
  v_result jsonb;
  v_id uuid;
begin
  v_load := private.aggregate_load_document_lock_v629(p_tenant_id, p_load_id, 'inbound', p_location_id);

  -- Rule 3: Detect concurrency conflict if load was modified elsewhere after billing draft opened
  if p_load_updated_at is not null and v_load.updated_at > p_load_updated_at then
    raise exception 'The load was modified in Material Yard after this purchase draft was opened. Please refresh to inspect the latest load details before posting.';
  end if;

  -- Audit supplier divergence if edited in billing draft
  if v_load.supplier_id is not null and v_load.supplier_id is distinct from p_supplier_id then
    insert into public.aggregate_load_events_v617(
      tenant_id, load_id, event_type, from_status, to_status, note, created_by
    ) values (
      p_tenant_id, p_load_id, 'billing_supplier_divergence',
      v_load.status, v_load.status,
      'Purchase billed under different supplier than original load record',
      auth.uid()
    );
  end if;

  v_result := public.gst_purchase_create_v520(
    p_tenant_id => p_tenant_id,
    p_supplier_id => p_supplier_id,
    p_supplier_invoice_number => p_supplier_invoice_number,
    p_purchase_date => p_purchase_date,
    p_due_date => p_due_date,
    p_items => p_items,
    p_additional_charges => p_additional_charges,
    p_round_off => p_round_off,
    p_initial_payment => p_initial_payment,
    p_payment_method => p_payment_method,
    p_payment_reference => p_payment_reference,
    p_notes => p_notes,
    p_location_id => p_location_id,
    p_device_id => p_device_id,
    p_request_id => p_request_id,
    p_supply_type => p_supply_type,
    p_place_of_supply_code => p_place_of_supply_code
  );

  v_id := nullif(v_result->>'purchase_id', '')::uuid;
  if v_id is null then
    raise exception 'Authoritative Purchase did not return a purchase ID';
  end if;

  perform public.aggregate_load_link_document_v617(p_tenant_id, p_load_id, 'purchase', v_id);

  update public.aggregate_loads_v617
  set supplier_id = coalesce(supplier_id, p_supplier_id),
      status = 'completed',
      updated_at = now()
  where id = p_load_id and tenant_id = p_tenant_id;

  -- Post any load expenses associated with this load
  perform private.load_costs_post_v630(p_tenant_id, p_load_id);

  return v_result || jsonb_build_object(
    'material_load_id', p_load_id,
    'load_linked', true
  );
end;
$$;

revoke all on function public.aggregate_load_purchase_create_v629(uuid, uuid, uuid, text, date, date, jsonb, numeric, numeric, numeric, text, text, text, uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function public.aggregate_load_purchase_create_v629(uuid, uuid, uuid, text, date, date, jsonb, numeric, numeric, numeric, text, text, text, uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- ============================================================================
-- 9. Update aggregate_load_sale_create_v630 (Concurrency & Customer Flex)
-- ============================================================================
create or replace function public.aggregate_load_sale_create_v630(
  p_tenant_id uuid,
  p_load_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_due_date date,
  p_items jsonb,
  p_payment_allocations jsonb,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_supply_type text,
  p_place_of_supply_code text,
  p_charge_selections jsonb default '[]'::jsonb,
  p_load_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  l public.aggregate_loads_v617%rowtype;
  result jsonb;
  items jsonb;
  id uuid;
begin
  l := private.aggregate_load_document_lock_v629(p_tenant_id, p_load_id, 'outbound', p_location_id);

  -- Rule 3: Detect concurrency conflict if load was modified elsewhere after billing draft opened
  if p_load_updated_at is not null and l.updated_at > p_load_updated_at then
    raise exception 'The load was modified in Material Yard after this sale draft was opened. Please refresh to inspect the latest load details before posting.';
  end if;

  -- Audit customer divergence if edited in billing draft
  if l.customer_id is not null and l.customer_id is distinct from p_customer_id then
    insert into public.aggregate_load_events_v617(
      tenant_id, load_id, event_type, from_status, to_status, note, created_by
    ) values (
      p_tenant_id, p_load_id, 'billing_customer_divergence',
      l.status, l.status,
      'Sale billed under different customer than original load record',
      auth.uid()
    );
  end if;

  perform private.load_costs_post_v630(p_tenant_id, p_load_id);
  items := private.load_sale_items_v630(p_tenant_id, p_load_id, p_items, p_sale_date);

  result := private.aggregate_load_sale_core_v630(
    p_tenant_id, p_load_id, p_customer_id, p_sale_date, p_due_date, items,
    p_payment_allocations, p_notes, p_location_id, p_device_id, p_request_id,
    p_supply_type, p_place_of_supply_code, p_charge_selections
  );

  id := (result->>'sale_id')::uuid;

  insert into public.material_load_sale_snapshots_v630(sale_id, tenant_id, load_id, evidence)
  values (
    id, p_tenant_id, p_load_id,
    private.load_evidence_v630(p_tenant_id, p_load_id) || jsonb_build_object(
      'invoice_items_entered', p_items,
      'invoice_terms_entered', jsonb_build_object(
        'customer_id', p_customer_id,
        'sale_date', p_sale_date,
        'due_date', p_due_date,
        'notes', p_notes,
        'supply_type', p_supply_type,
        'place_of_supply_code', p_place_of_supply_code,
        'payment_allocations', p_payment_allocations,
        'charge_selections', p_charge_selections
      ),
      'snapshot_at', now()
    )
  )
  on conflict(sale_id) do nothing;

  update public.aggregate_loads_v617
  set customer_id = coalesce(customer_id, p_customer_id),
      status = 'completed',
      updated_at = now()
  where id = p_load_id and tenant_id = p_tenant_id;

  return result || jsonb_build_object('load_costs_recorded', true);
end $function$;

revoke all on function public.aggregate_load_sale_create_v630(uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb, timestamptz) from public, anon;
grant execute on function public.aggregate_load_sale_create_v630(uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb, timestamptz) to authenticated, service_role;

-- ============================================================================
-- 10. Update aggregate_load_list_v629 (Ensure Pricing Fallback for Unbilled)
-- ============================================================================
create or replace function public.aggregate_load_list_v629(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_status text default null::text,
  p_query text default null::text,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  variant_id uuid,
  supplier_id uuid,
  customer_id uuid,
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
  order_id uuid,
  order_line_id uuid,
  order_number text,
  created_at timestamp with time zone,
  invoice_rate numeric,
  invoice_amount numeric,
  invoice_number text
)
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
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
    l.variant_id,
    l.supplier_id,
    l.customer_id,
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
    l.order_id,
    l.order_line_id,
    o.order_number,
    l.created_at,
    -- Actual negotiated transaction rate
    case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select pi.unit_cost
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select si.unit_price
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      when l.direction = 'outbound' then (
        select nullif(d.details->>'selling_price', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id and d.load_id = l.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_price', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id and d.load_id = l.id
        limit 1
      )
    end as invoice_rate,
    -- Actual allocated invoice amount
    case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select round(l.quantity * pi.unit_cost, 2)
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select round(l.quantity * si.unit_price, 2)
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      when l.direction = 'outbound' then (
        select nullif(d.details->>'selling_total', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id and d.load_id = l.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_total', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id and d.load_id = l.id
        limit 1
      )
    end as invoice_amount,
    -- Linked invoice number
    case
      when l.direction = 'inbound' and l.purchase_id is not null then pd.purchase_number
      when l.direction = 'outbound' and l.sale_id is not null then sd.sale_number
      else null
    end as invoice_number
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id = l.supplier_id and s.tenant_id = l.tenant_id
  left join public.customers c
    on c.id = l.customer_id and c.tenant_id = l.tenant_id
  left join public.purchases pd
    on pd.id = l.purchase_id and pd.tenant_id = l.tenant_id
  left join public.sales sd
    on sd.id = l.sale_id and sd.tenant_id = l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id = l.order_id and o.tenant_id = l.tenant_id
  where l.tenant_id = p_tenant_id
    and (p_location_id is null or l.location_id = p_location_id)
    and (
      p_status is null
      or (p_status = 'draft' and l.status = 'draft')
      or (p_status = 'completed' and l.status = 'completed')
      or (p_status = 'cancelled' and l.status = 'cancelled')
      or l.status = p_status
    )
    and (
      p_query is null or trim(p_query) = ''
      or l.load_number ilike '%' || trim(p_query) || '%'
      or l.product_name_snapshot ilike '%' || trim(p_query) || '%'
      or coalesce(l.vehicle_registration_snapshot, '') ilike '%' || trim(p_query) || '%'
      or coalesce(l.driver_name_snapshot, '') ilike '%' || trim(p_query) || '%'
      or coalesce(s.name, '') ilike '%' || trim(p_query) || '%'
      or coalesce(c.name, '') ilike '%' || trim(p_query) || '%'
      or coalesce(l.source_reference, '') ilike '%' || trim(p_query) || '%'
      or coalesce(pd.purchase_number, '') ilike '%' || trim(p_query) || '%'
      or coalesce(sd.sale_number, '') ilike '%' || trim(p_query) || '%'
    )
  order by l.load_date desc, l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$function$;

revoke all on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer) from public, anon;
grant execute on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer) to authenticated, service_role;
