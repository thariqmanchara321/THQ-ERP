-- THQ ERP Migration 20261013123000_business_audit_write_unique_signature_v712.sql
-- Fix ambiguous function private.business_audit_write overload ambiguity (error 42725).
--
-- 1. Drop the unused conflicting overload private.business_audit_write(uuid, text, text, uuid, text, uuid, jsonb)
--    so private.business_audit_write uniquely has one 7-parameter signature: (uuid, text, text, uuid, text, jsonb, jsonb).
-- 2. Update all functions that passed un-cast null as 6th argument to explicitly pass null::jsonb.

-- 1. Drop conflicting overload
drop function if exists private.business_audit_write(uuid, text, text, uuid, text, uuid, jsonb);

-- 2. Ensure canonical private.business_audit_write has clean defaults and casting
create or replace function private.business_audit_write(
  p_tenant_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_reference text,
  p_before jsonb,
  p_after jsonb
) returns void
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_location uuid;
  v_device uuid;
begin
  select o.location_id, o.device_id
  into v_location, v_device
  from public.document_origins o
  where o.tenant_id = p_tenant_id
    and o.entity_type = p_entity_type
    and o.entity_id = p_entity_id
  limit 1;

  if v_location is null and p_after ? 'location_id' then
    begin
      v_location := nullif(p_after->>'location_id','')::uuid;
    exception when others then null;
    end;
  end if;

  if v_device is null and p_after ? 'device_id' then
    begin
      v_device := nullif(p_after->>'device_id','')::uuid;
    exception when others then null;
    end;
  end if;

  insert into public.business_audit_log(
    tenant_id, user_id, action, entity_type, entity_id, entity_reference,
    before_data, after_data, location_id, device_id, metadata
  ) values (
    p_tenant_id, auth.uid(), p_action, p_entity_type, p_entity_id, p_reference,
    p_before, p_after, v_location, v_device,
    jsonb_build_object('source', 'erp', 'recorded_at', now(), 'version', '8.1')
  );
end;
$$;

-- 3. Update public.tenant_invoice_template_save_v45
create or replace function public.tenant_invoice_template_save_v45(
  p_tenant_id uuid,
  p_paper_type text,
  p_template_id uuid,
  p_overrides jsonb
) returns void
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v jsonb := coalesce(p_overrides, '{}'::jsonb);
begin
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'settings.manage') then
    raise exception 'Settings permission required';
  end if;

  if p_paper_type not in ('a4', '80mm') then
    raise exception 'Invalid paper type';
  end if;

  if not exists(
    select 1
    from public.invoice_templates
    where id = p_template_id
      and paper_type = p_paper_type
      and is_active
      and (owner_tenant_id is null or owner_tenant_id = p_tenant_id)
  ) then
    raise exception 'Invoice template not found';
  end if;

  insert into public.tenant_invoice_templates(
    tenant_id, paper_type, template_id, overrides, updated_at, updated_by
  ) values (
    p_tenant_id, p_paper_type, p_template_id, v, now(), auth.uid()
  )
  on conflict (tenant_id, paper_type) do update
  set template_id = excluded.template_id,
      overrides = excluded.overrides,
      updated_at = now(),
      updated_by = auth.uid();

  perform private.business_audit_write(
    p_tenant_id,
    'invoice_template.default',
    'invoice_template',
    p_template_id,
    p_paper_type,
    null::jsonb,
    jsonb_build_object('paper_type', p_paper_type, 'overrides', v)
  );
end;
$$;

-- 4. Update public.tenant_invoice_template_clone_v45
create or replace function public.tenant_invoice_template_clone_v45(
  p_tenant_id uuid,
  p_source_template_id uuid,
  p_name text,
  p_paper_type text,
  p_config jsonb default null
) returns uuid
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  src public.invoice_templates%rowtype;
  v_id uuid;
  v_key text;
begin
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'settings.manage') then
    raise exception 'Settings permission required';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Template name is required';
  end if;

  if p_paper_type not in ('a4', '80mm') then
    raise exception 'Invalid paper type';
  end if;

  select * into src
  from public.invoice_templates
  where id = p_source_template_id
    and is_active
    and (owner_tenant_id is null or owner_tenant_id = p_tenant_id);

  if not found then
    raise exception 'Source template not found';
  end if;

  v_key := 'tenant_' || replace(p_tenant_id::text, '-', '') || '_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

  insert into public.invoice_templates(
    key, name, paper_type, description, config, sample_logo_key, is_system, is_active, owner_tenant_id
  ) values (
    v_key, trim(p_name), p_paper_type, 'Custom THQ invoice template',
    coalesce(p_config, src.config), src.sample_logo_key, false, true, p_tenant_id
  )
  returning id into v_id;

  perform private.business_audit_write(
    p_tenant_id,
    'invoice_template.create',
    'invoice_template',
    v_id,
    p_name,
    null::jsonb,
    jsonb_build_object('source_template_id', p_source_template_id, 'paper_type', p_paper_type)
  );

  return v_id;
end;
$$;

-- 5. Update public.tenant_invoice_template_update_v45
create or replace function public.tenant_invoice_template_update_v45(
  p_tenant_id uuid,
  p_template_id uuid,
  p_name text,
  p_config jsonb,
  p_is_active boolean default true
) returns void
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'settings.manage') then
    raise exception 'Settings permission required';
  end if;

  update public.invoice_templates
  set name = coalesce(nullif(trim(p_name), ''), name),
      config = coalesce(p_config, config),
      is_active = p_is_active,
      updated_at = now()
  where id = p_template_id
    and owner_tenant_id = p_tenant_id;

  if not found then
    raise exception 'Only business-owned custom templates can be edited directly';
  end if;

  perform private.business_audit_write(
    p_tenant_id,
    'invoice_template.update',
    'invoice_template',
    p_template_id,
    p_name,
    null::jsonb,
    jsonb_build_object('active', p_is_active)
  );
end;
$$;

-- 6. Update public.tenant_invoice_template_save_v44
create or replace function public.tenant_invoice_template_save_v44(
  p_tenant_id uuid,
  p_paper_type text,
  p_template_id uuid,
  p_overrides jsonb
) returns void
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'settings.manage') then
    raise exception 'Settings permission required';
  end if;

  if p_paper_type not in ('a4', '80mm') then
    raise exception 'Invalid paper type';
  end if;

  if not exists(
    select 1
    from public.invoice_templates
    where id = p_template_id
      and paper_type = p_paper_type
      and is_active
  ) then
    raise exception 'Invoice template not found';
  end if;

  insert into public.tenant_invoice_templates(
    tenant_id, paper_type, template_id, overrides, updated_at, updated_by
  ) values (
    p_tenant_id, p_paper_type, p_template_id, coalesce(p_overrides, '{}'::jsonb), now(), auth.uid()
  )
  on conflict (tenant_id, paper_type) do update
  set template_id = excluded.template_id,
      overrides = excluded.overrides,
      updated_at = now(),
      updated_by = auth.uid();

  perform private.business_audit_write(
    p_tenant_id,
    'invoice_template.save',
    'invoice_template',
    p_template_id,
    p_paper_type,
    null::jsonb,
    jsonb_build_object('paper_type', p_paper_type, 'overrides', coalesce(p_overrides, '{}'::jsonb))
  );
end;
$$;

-- 7. Update public.service_vehicle_save_v32
create or replace function public.service_vehicle_save_v32(
  p_tenant_id uuid,
  p_vehicle_id uuid,
  p_location_id uuid,
  p_registration_number text,
  p_vehicle_type text,
  p_make_model text,
  p_capacity numeric,
  p_capacity_unit text,
  p_driver_name text,
  p_driver_phone text,
  p_active boolean
) returns uuid
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  v_old_location uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not private.erp_has_permission(p_tenant_id, 'transport_service.manage') then
    raise exception 'Permission denied';
  end if;

  if p_location_id is null or not private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'operate') then
    raise exception 'Location access denied';
  end if;

  if p_vehicle_id is not null then
    select location_id into v_old_location
    from public.service_vehicles
    where id = p_vehicle_id and tenant_id = p_tenant_id;

    if v_old_location is null then
      raise exception 'Vehicle not found';
    end if;

    if not private.erp_document_scope_allowed(p_tenant_id, v_old_location, v_old_location, 'operate') then
      raise exception 'You cannot edit this vehicle';
    end if;
  end if;

  if p_vehicle_id is null then
    insert into public.service_vehicles(
      tenant_id, location_id, registration_number, vehicle_type, make_model, capacity,
      capacity_unit, driver_name, driver_phone, active
    ) values (
      p_tenant_id, p_location_id, upper(trim(p_registration_number)), nullif(trim(p_vehicle_type), ''),
      nullif(trim(p_make_model), ''), p_capacity, nullif(trim(p_capacity_unit), ''),
      nullif(trim(p_driver_name), ''), nullif(trim(p_driver_phone), ''), coalesce(p_active, true)
    ) returning id into v_id;
  else
    update public.service_vehicles
    set location_id = p_location_id,
        registration_number = upper(trim(p_registration_number)),
        vehicle_type = nullif(trim(p_vehicle_type), ''),
        make_model = nullif(trim(p_make_model), ''),
        capacity = p_capacity,
        capacity_unit = nullif(trim(p_capacity_unit), ''),
        driver_name = nullif(trim(p_driver_name), ''),
        driver_phone = nullif(trim(p_driver_phone), ''),
        active = coalesce(p_active, true),
        updated_at = now()
    where id = p_vehicle_id and tenant_id = p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Vehicle not found';
  end if;

  perform private.business_audit_write(
    p_tenant_id,
    'save',
    'service_vehicle',
    v_id,
    null,
    null::jsonb,
    jsonb_build_object('location_id', p_location_id, 'registration_number', p_registration_number)
  );

  return v_id;
end;
$$;

-- 8. Update public.production_recipe_save
create or replace function public.production_recipe_save(
  p_tenant_id uuid,
  p_recipe_id uuid,
  p_name text,
  p_output_variant_id uuid,
  p_output_quantity numeric,
  p_notes text,
  p_active boolean,
  p_items jsonb
) returns uuid
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  x jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not private.erp_has_permission(p_tenant_id, 'production.manage') then
    raise exception 'Permission denied';
  end if;

  if trim(coalesce(p_name, '')) = '' or coalesce(p_output_quantity, 0) <= 0 then
    raise exception 'Invalid recipe';
  end if;

  if p_recipe_id is null then
    insert into public.production_recipes(tenant_id, name, output_variant_id, output_quantity, notes, active)
    values (p_tenant_id, trim(p_name), p_output_variant_id, p_output_quantity, nullif(trim(p_notes), ''), coalesce(p_active, true))
    returning id into v_id;
  else
    update public.production_recipes
    set name = trim(p_name),
        output_variant_id = p_output_variant_id,
        output_quantity = p_output_quantity,
        notes = nullif(trim(p_notes), ''),
        active = coalesce(p_active, true),
        updated_at = now()
    where id = p_recipe_id and tenant_id = p_tenant_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Recipe not found';
    end if;

    delete from public.production_recipe_items where recipe_id = v_id;
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Recipe items must be array';
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if coalesce((x->>'quantity')::numeric, 0) <= 0 then
      continue;
    end if;
    insert into public.production_recipe_items(recipe_id, tenant_id, input_variant_id, quantity, waste_percent)
    values (v_id, p_tenant_id, (x->>'input_variant_id')::uuid, (x->>'quantity')::numeric, coalesce(nullif(x->>'waste_percent', '')::numeric, 0));
  end loop;

  perform private.business_audit_write(
    p_tenant_id,
    'save',
    'production_recipe',
    v_id,
    null,
    null::jsonb,
    jsonb_build_object('name', p_name)
  );

  return v_id;
end;
$$;

-- 9. Update public.production_run_complete
create or replace function public.production_run_complete(
  p_tenant_id uuid,
  p_run_id uuid
) returns void
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not private.erp_has_permission(p_tenant_id, 'production.run')
     and not private.erp_has_permission(p_tenant_id, 'production.manage') then
    raise exception 'Permission denied';
  end if;

  update public.production_runs
  set status = 'completed',
      completed_at = now()
  where id = p_run_id
    and tenant_id = p_tenant_id
    and status = 'started';

  if not found then
    raise exception 'Production run not found or already closed';
  end if;

  perform private.business_audit_write(
    p_tenant_id,
    'complete',
    'production_run',
    p_run_id,
    null,
    null::jsonb,
    '{}'::jsonb
  );
end;
$$;

-- 10. Update public.inventory_bulk_create_products
create or replace function public.inventory_bulk_create_products(
  p_tenant_id uuid,
  p_rows jsonb
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  r jsonb;
  ok int := 0;
  failed int := 0;
  errs jsonb := '[]'::jsonb;
  idx int := 0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not private.erp_has_permission(p_tenant_id, 'bulk_import.use')
     and not private.erp_has_permission(p_tenant_id, 'inventory.manage') then
    raise exception 'Permission denied';
  end if;

  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Rows must be an array';
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    idx := idx + 1;
    begin
      perform public.inventory_create_product(
        p_tenant_id,
        coalesce(r->>'name', ''),
        coalesce(r->>'sku', ''),
        coalesce(nullif(r->>'item_type', ''), 'stock'),
        coalesce(r->>'description', ''),
        coalesce(r->>'category', ''),
        coalesce(r->>'brand', ''),
        coalesce(r->>'barcode', ''),
        coalesce(r->>'part_number', ''),
        coalesce(nullif(r->>'cost_price', '')::numeric, 0),
        coalesce(nullif(r->>'selling_price', '')::numeric, 0),
        nullif(r->>'list_price', '')::numeric,
        coalesce(nullif(r->>'tax_rate', '')::numeric, 0),
        coalesce(nullif(r->>'reorder_level', '')::numeric, 0),
        coalesce(nullif(r->>'opening_stock', '')::numeric, 0)
      );
      ok := ok + 1;
    exception when others then
      failed := failed + 1;
      errs := errs || jsonb_build_array(jsonb_build_object('row', idx, 'sku', r->>'sku', 'error', sqlerrm));
    end;
  end loop;

  perform private.business_audit_write(
    p_tenant_id,
    'bulk_import',
    'product',
    null,
    null,
    null::jsonb,
    jsonb_build_object('success', ok, 'failed', failed)
  );

  return jsonb_build_object('success_count', ok, 'failed_count', failed, 'errors', errs);
end;
$$;

-- Permissions
grant execute on function public.tenant_invoice_template_save_v45(uuid, text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.tenant_invoice_template_clone_v45(uuid, uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function public.tenant_invoice_template_update_v45(uuid, uuid, text, jsonb, boolean) to authenticated, service_role;
grant execute on function public.tenant_invoice_template_save_v44(uuid, text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.service_vehicle_save_v32(uuid, uuid, uuid, text, text, text, numeric, text, text, text, boolean) to authenticated, service_role;
grant execute on function public.production_recipe_save(uuid, uuid, text, uuid, numeric, text, boolean, jsonb) to authenticated, service_role;
grant execute on function public.production_run_complete(uuid, uuid) to authenticated, service_role;
grant execute on function public.inventory_bulk_create_products(uuid, jsonb) to authenticated, service_role;
