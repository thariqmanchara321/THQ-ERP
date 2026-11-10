-- THQ ERP v7.1.9
-- Dynamic Expense Categories Management and Advanced Expense Report Infrastructure

-- 1. Safely add description column to expense_categories if not present
alter table public.expense_categories add column if not exists description text;

-- 2. Create Category RPC
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
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not private.erp_module_enabled(p_tenant_id, 'expenses') then
    raise exception 'Expenses module is disabled' using errcode='42501';
  end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id, 'expenses.manage')) then
    raise exception 'Permission denied: expenses.manage required' using errcode='42501';
  end if;
  if v_name = '' then
    raise exception 'Category name cannot be empty';
  end if;

  -- Check if active category already exists with same name (case-insensitive)
  select id, active, name into v_existing
  from public.expense_categories
  where tenant_id = p_tenant_id and lower(name) = lower(v_name)
  limit 1;

  if found then
    if v_existing.active then
      raise exception 'An active expense category named "%" already exists.', v_existing.name;
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

-- 3. Update Category RPC
create or replace function public.expenses_category_update(
  p_tenant_id uuid,
  p_category_id uuid,
  p_name text default null,
  p_active boolean default null,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_desc text := trim(coalesce(p_description, ''));
  v_existing record;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not private.erp_module_enabled(p_tenant_id, 'expenses') then
    raise exception 'Expenses module is disabled' using errcode='42501';
  end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id, 'expenses.manage')) then
    raise exception 'Permission denied: expenses.manage required' using errcode='42501';
  end if;

  select * into v_existing
  from public.expense_categories
  where id = p_category_id and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Expense category not found';
  end if;

  if v_name is not null and lower(v_name) <> lower(v_existing.name) then
    if exists (
      select 1 from public.expense_categories
      where tenant_id = p_tenant_id and id <> p_category_id and lower(name) = lower(v_name)
    ) then
      raise exception 'Another expense category with name "%" already exists', v_name;
    end if;
  end if;

  update public.expense_categories
  set name = coalesce(v_name, name),
      active = coalesce(p_active, active),
      description = coalesce(nullif(v_desc, ''), description)
  where id = p_category_id and tenant_id = p_tenant_id;

  return jsonb_build_object(
    'id', p_category_id,
    'category_id', p_category_id,
    'name', coalesce(v_name, v_existing.name),
    'category_name', coalesce(v_name, v_existing.name),
    'active', coalesce(p_active, v_existing.active),
    'description', coalesce(nullif(v_desc, ''), v_existing.description, ''),
    'updated', true
  );
end;
$$;

-- 4. Manage Categories List (returns active + inactive + expense count)
create or replace function public.expenses_categories_manage_list(p_tenant_id uuid)
returns table(
  category_id uuid,
  category_name text,
  active boolean,
  description text,
  expense_count bigint
)
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not private.erp_module_enabled(p_tenant_id, 'expenses') then
    raise exception 'Expenses module is disabled' using errcode='42501';
  end if;

  return query
  select
    ec.id as category_id,
    ec.name as category_name,
    ec.active,
    coalesce(ec.description, '') as description,
    count(e.id) as expense_count
  from public.expense_categories ec
  left join public.expenses e on e.category_id = ec.id and e.tenant_id = ec.tenant_id
  where ec.tenant_id = p_tenant_id
  group by ec.id, ec.name, ec.active, ec.description
  order by ec.active desc, ec.name asc;
end;
$$;

-- 5. Comprehensive Advanced Expense Report Dataset RPC
create or replace function public.expenses_advanced_report_dataset_v719(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_summary jsonb;
  v_prev_summary jsonb;
  v_expenses jsonb;
  v_yard_costs jsonb := '[]'::jsonb;
  v_has_yard boolean;
  v_period_days int;
  v_prev_from date;
  v_prev_to date;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not private.erp_module_enabled(p_tenant_id, 'expenses') then
    raise exception 'Expenses module is disabled' using errcode='42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Valid date range is required' using errcode='22023';
  end if;

  -- 5a. Current period summary
  v_summary := public.expense_summary_v600(p_tenant_id, p_from, p_to, p_location_id);

  -- 5b. Prior equivalent period for comparison
  v_period_days := (p_to - p_from) + 1;
  v_prev_to := p_from - 1;
  v_prev_from := v_prev_to - v_period_days + 1;
  v_prev_summary := public.expense_summary_v600(p_tenant_id, v_prev_from, v_prev_to, p_location_id);

  -- 5c. Detailed expense register with journal & tracking metadata
  select coalesce(jsonb_agg(to_jsonb(x) order by x.expense_date desc, x.expense_number desc), '[]'::jsonb)
  into v_expenses
  from (
    select
      e.id as expense_id,
      e.expense_number,
      coalesce(dn.terminal_number, ln.local_number, e.expense_number) as display_number,
      e.category_id,
      c.name as category_name,
      e.expense_date,
      coalesce(e.payee, '') as payee,
      coalesce(e.description, '') as description,
      round(e.amount, 2) as amount,
      round(e.tax_amount, 2) as tax_amount,
      round(coalesce(e.round_off, 0), 2) as round_off,
      round(e.total_amount, 2) as total_amount,
      coalesce(e.payment_method, 'cash') as payment_method,
      coalesce(e.reference_number, '') as reference_number,
      coalesce(e.notes, '') as notes,
      e.status,
      e.created_at,
      o.location_id,
      l.name as location_name,
      o.device_id,
      d.name as device_name,
      j.id as journal_id,
      j.entry_number as journal_number,
      j.status as journal_status
    from public.expenses e
    join public.expense_categories c on c.id = e.category_id
    left join public.document_origins o on o.tenant_id = e.tenant_id and o.entity_type = 'expense' and o.entity_id = e.id
    left join public.business_locations l on l.id = o.location_id
    left join public.business_devices d on d.id = o.device_id
    left join public.device_document_numbers dn on dn.tenant_id = e.tenant_id and dn.entity_type = 'expense' and dn.entity_id = e.id
    left join public.location_document_numbers ln on ln.tenant_id = e.tenant_id and ln.entity_type = 'expense' and ln.entity_id = e.id
    left join lateral (
      select j1.id, j1.entry_number, j1.status
      from public.journal_entries j1
      where j1.tenant_id = e.tenant_id and j1.source_type = 'expense' and j1.source_id = e.id and j1.status = 'posted'
      order by j1.created_at desc limit 1
    ) j on true
    where e.tenant_id = p_tenant_id
      and e.expense_date between p_from and p_to
      and (p_location_id is null or o.location_id = p_location_id)
  ) x;

  -- 5d. Material Yard load costs if aggregate_yard module is enabled
  v_has_yard := exists(
    select 1 from public.tenant_modules
    where tenant_id = p_tenant_id and module_key = 'aggregate_yard' and enabled
  ) and (
    private.erp_user_is_owner(p_tenant_id, auth.uid()) or
    private.erp_has_permission(p_tenant_id, 'aggregate_yard.view')
  );

  if v_has_yard then
    select coalesce(jsonb_agg(to_jsonb(y) order by y.load_date desc, y.load_number desc), '[]'::jsonb)
    into v_yard_costs
    from (
      select
        c.id as cost_id,
        c.load_id,
        l.load_number,
        coalesce(l.load_date, l.created_at::date) as load_date,
        coalesce(l.vehicle_registration_snapshot, '') as truck_number,
        coalesce(l.driver_name_snapshot, '') as driver_name,
        coalesce((select s.name from public.suppliers s where s.id = l.transporter_supplier_id), '') as carrier_name,
        coalesce(l.product_name_snapshot, '') as material_name,
        l.direction,
        c.cost_kind,
        c.description,
        c.payee,
        round(c.quantity, 2) as quantity,
        round(c.rate, 2) as rate,
        round(c.amount, 2) as amount,
        round(c.bill_amount, 2) as bill_amount,
        c.status as cost_status,
        c.payment_method,
        c.journal_id,
        c.created_at
      from public.material_load_costs_v630 c
      join public.aggregate_loads_v617 l on l.id = c.load_id and l.tenant_id = c.tenant_id
      where c.tenant_id = p_tenant_id
        and l.created_at::date between p_from and p_to
        and (p_location_id is null or l.location_id = p_location_id)
        and c.status <> 'void'
    ) y;
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'from', p_from,
    'to', p_to,
    'previous_from', v_prev_from,
    'previous_to', v_prev_to,
    'location_id', p_location_id,
    'summary', v_summary,
    'previous_summary', v_prev_summary,
    'expenses', v_expenses,
    'yard_costs', v_yard_costs,
    'yard_module_enabled', v_has_yard
  );
end;
$$;

-- 6. Permissions and Grants
revoke all on function public.expenses_category_create(uuid, text, text) from public, anon;
grant execute on function public.expenses_category_create(uuid, text, text) to authenticated, service_role;

revoke all on function public.expenses_category_update(uuid, uuid, text, boolean, text) from public, anon;
grant execute on function public.expenses_category_update(uuid, uuid, text, boolean, text) to authenticated, service_role;

revoke all on function public.expenses_categories_manage_list(uuid) from public, anon;
grant execute on function public.expenses_categories_manage_list(uuid) to authenticated, service_role;

revoke all on function public.expenses_advanced_report_dataset_v719(uuid, date, date, uuid) from public, anon;
grant execute on function public.expenses_advanced_report_dataset_v719(uuid, date, date, uuid) to authenticated, service_role;
