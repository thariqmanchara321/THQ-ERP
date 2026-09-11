create index if not exists idx_restaurant_tables_reservation
  on public.restaurant_tables(tenant_id, location_id, reservation_at)
  where active = true and reservation_at is not null;

create or replace function public.restaurant_table_reservation_set_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid,
  p_reservation_name text,
  p_reservation_phone text,
  p_reservation_at timestamptz,
  p_reservation_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
  v_name text;
  v_phone text;
  v_note text;
begin
  v_name := nullif(trim(coalesce(p_reservation_name, '')), '');
  v_phone := nullif(trim(coalesce(p_reservation_phone, '')), '');
  v_note := nullif(trim(coalesce(p_reservation_note, '')), '');

  if v_name is null then
    raise exception 'Reservation name is required';
  end if;

  if p_reservation_at is null then
    raise exception 'Reservation date and time are required';
  end if;

  select *
  into t
  from public.restaurant_tables
  where id = p_table_id
    and tenant_id = p_tenant_id
    and active = true
  for update;

  if not found then
    raise exception 'Restaurant table not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    t.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant reservation permission denied';
  end if;

  if t.operational_status in ('cleaning', 'out_of_service') then
    raise exception 'Table is not available for reservation';
  end if;

  if exists (
    select 1
    from public.restaurant_orders o
    where o.tenant_id = p_tenant_id
      and o.location_id = t.location_id
      and o.table_id = p_table_id
      and o.status not in ('billed', 'cancelled')
  ) then
    raise exception 'Table currently has an active order';
  end if;

  update public.restaurant_tables
  set operational_status = 'reserved',
      reservation_name = v_name,
      reservation_phone = v_phone,
      reservation_at = p_reservation_at,
      reservation_note = v_note,
      updated_at = now()
  where id = p_table_id
    and tenant_id = p_tenant_id;

  insert into public.restaurant_table_events(
    tenant_id,
    order_id,
    from_table_id,
    to_table_id,
    event_type,
    note,
    created_by
  )
  values (
    p_tenant_id,
    null,
    p_table_id,
    p_table_id,
    'state',
    'reserved for ' || v_name || ' at ' || p_reservation_at::text ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'settings',
    'restaurant_table',
    p_table_id::text,
    'reservation_set'
  );

  return jsonb_build_object(
    'success', true,
    'table_id', p_table_id,
    'operational_status', 'reserved',
    'reservation_name', v_name,
    'reservation_phone', v_phone,
    'reservation_at', p_reservation_at,
    'reservation_note', v_note,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

create or replace function public.restaurant_table_reservation_clear_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
  v_note text;
begin
  v_note := nullif(trim(coalesce(p_note, '')), '');

  select *
  into t
  from public.restaurant_tables
  where id = p_table_id
    and tenant_id = p_tenant_id
    and active = true
  for update;

  if not found then
    raise exception 'Restaurant table not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    t.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant reservation permission denied';
  end if;

  update public.restaurant_tables
  set operational_status = case
        when operational_status = 'reserved' then 'available'
        else operational_status
      end,
      reservation_name = null,
      reservation_phone = null,
      reservation_at = null,
      reservation_note = null,
      updated_at = now()
  where id = p_table_id
    and tenant_id = p_tenant_id;

  insert into public.restaurant_table_events(
    tenant_id,
    order_id,
    from_table_id,
    to_table_id,
    event_type,
    note,
    created_by
  )
  values (
    p_tenant_id,
    null,
    p_table_id,
    p_table_id,
    'state',
    'reservation cleared' ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'settings',
    'restaurant_table',
    p_table_id::text,
    'reservation_clear'
  );

  return jsonb_build_object(
    'success', true,
    'table_id', p_table_id,
    'operational_status',
      case when t.operational_status = 'reserved'
        then 'available'
        else t.operational_status
      end,
    'reservation_cleared', true,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

create or replace function public.restaurant_table_status_set_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
  v_status text;
  v_note text;
begin
  v_status := lower(trim(coalesce(p_status, '')));
  v_note := nullif(trim(coalesce(p_note, '')), '');

  if v_status not in ('available', 'cleaning', 'out_of_service') then
    raise exception 'Invalid table status';
  end if;

  select *
  into t
  from public.restaurant_tables
  where id = p_table_id
    and tenant_id = p_tenant_id
    and active = true
  for update;

  if not found then
    raise exception 'Restaurant table not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    t.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant table management permission denied';
  end if;

  if v_status in ('cleaning', 'out_of_service') and exists (
    select 1
    from public.restaurant_orders o
    where o.tenant_id = p_tenant_id
      and o.location_id = t.location_id
      and o.table_id = p_table_id
      and o.status not in ('billed', 'cancelled')
  ) then
    raise exception 'Table has an active order';
  end if;

  update public.restaurant_tables
  set operational_status = v_status,
      reservation_name = null,
      reservation_phone = null,
      reservation_at = null,
      reservation_note = null,
      updated_at = now()
  where id = p_table_id
    and tenant_id = p_tenant_id;

  insert into public.restaurant_table_events(
    tenant_id,
    order_id,
    from_table_id,
    to_table_id,
    event_type,
    note,
    created_by
  )
  values (
    p_tenant_id,
    null,
    p_table_id,
    p_table_id,
    'state',
    'status ' || t.operational_status || ' -> ' || v_status ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'settings',
    'restaurant_table',
    p_table_id::text,
    'status_' || v_status
  );

  return jsonb_build_object(
    'success', true,
    'table_id', p_table_id,
    'operational_status', v_status,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_table_reservation_set_v610(
  uuid, uuid, uuid, text, text, timestamptz, text
) from public, anon;

revoke all on function public.restaurant_table_reservation_clear_v610(
  uuid, uuid, uuid, text
) from public, anon;

revoke all on function public.restaurant_table_status_set_v610(
  uuid, uuid, uuid, text, text
) from public, anon;

grant execute on function public.restaurant_table_reservation_set_v610(
  uuid, uuid, uuid, text, text, timestamptz, text
) to authenticated, service_role;

grant execute on function public.restaurant_table_reservation_clear_v610(
  uuid, uuid, uuid, text
) to authenticated, service_role;

grant execute on function public.restaurant_table_status_set_v610(
  uuid, uuid, uuid, text, text
) to authenticated, service_role;
