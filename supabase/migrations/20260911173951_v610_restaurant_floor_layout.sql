create or replace function public.restaurant_table_layout_batch_set_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_tables jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  x jsonb;
  v_table_id uuid;
  v_floor_name text;
  v_position_x numeric;
  v_position_y numeric;
  v_shape text;
  v_sort_order integer;
  v_count integer := 0;
  v_seen uuid[] := array[]::uuid[];
  v_rows jsonb;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  if jsonb_typeof(coalesce(p_tables, '[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant table layout payload must be an array';
  end if;

  if jsonb_array_length(coalesce(p_tables, '[]'::jsonb)) = 0 then
    raise exception 'Choose at least one restaurant table to update';
  end if;

  if jsonb_array_length(p_tables) > 500 then
    raise exception 'Restaurant table layout batch cannot exceed 500 tables';
  end if;

  for x in
    select value
    from jsonb_array_elements(p_tables)
  loop
    v_table_id := nullif(x->>'table_id', '')::uuid;
    if v_table_id is null then
      raise exception 'Each layout row requires table_id';
    end if;

    if v_table_id = any(v_seen) then
      raise exception 'Restaurant table % was supplied more than once', v_table_id;
    end if;
    v_seen := array_append(v_seen, v_table_id);

    if not exists (
      select 1
      from public.restaurant_tables t
      where t.id = v_table_id
        and t.tenant_id = p_tenant_id
        and t.location_id = p_location_id
    ) then
      raise exception 'Restaurant table % was not found in this location', v_table_id;
    end if;

    v_floor_name := nullif(trim(coalesce(x->>'floor_name', '')), '');
    v_position_x := case
      when x ? 'position_x' and nullif(x->>'position_x', '') is not null
        then (x->>'position_x')::numeric
      else null
    end;
    v_position_y := case
      when x ? 'position_y' and nullif(x->>'position_y', '') is not null
        then (x->>'position_y')::numeric
      else null
    end;
    v_shape := lower(trim(coalesce(nullif(x->>'shape', ''), 'rect')));
    v_sort_order := coalesce(nullif(x->>'sort_order', '')::integer, 0);

    if v_shape not in ('rect', 'round', 'square') then
      raise exception 'Invalid restaurant table shape %', v_shape;
    end if;

    if v_position_x is not null and (v_position_x < 0 or v_position_x > 100) then
      raise exception 'Table position_x must be between 0 and 100';
    end if;

    if v_position_y is not null and (v_position_y < 0 or v_position_y > 100) then
      raise exception 'Table position_y must be between 0 and 100';
    end if;

    update public.restaurant_tables
    set floor_name = v_floor_name,
        position_x = v_position_x,
        position_y = v_position_y,
        shape = v_shape,
        sort_order = v_sort_order,
        updated_at = now()
    where id = v_table_id
      and tenant_id = p_tenant_id
      and location_id = p_location_id;

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
      v_table_id,
      v_table_id,
      'state',
      'Layout updated | floor=' || coalesce(v_floor_name, '') ||
        ' | x=' || coalesce(v_position_x::text, '') ||
        ' | y=' || coalesce(v_position_y::text, '') ||
        ' | shape=' || v_shape ||
        ' | sort=' || v_sort_order,
      auth.uid()
    );

    perform private.thq_sync_bump_v480(
      p_tenant_id,
      'master',
      'restaurant_table',
      v_table_id::text,
      'layout_update'
    );

    v_count := v_count + 1;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_id', t.id,
        'table_code', t.table_code,
        'name', t.name,
        'floor_name', t.floor_name,
        'position_x', t.position_x,
        'position_y', t.position_y,
        'shape', t.shape,
        'sort_order', t.sort_order
      )
      order by coalesce(t.floor_name, ''), t.sort_order, t.table_code
    ),
    '[]'::jsonb
  )
  into v_rows
  from public.restaurant_tables t
  where t.tenant_id = p_tenant_id
    and t.location_id = p_location_id
    and t.id = any(v_seen);

  return jsonb_build_object(
    'success', true,
    'updated_count', v_count,
    'tables', v_rows,
    'position_scale', 'percent_0_100',
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_table_layout_batch_set_v610(
  uuid, uuid, uuid, jsonb
) from public, anon;

grant execute on function public.restaurant_table_layout_batch_set_v610(
  uuid, uuid, uuid, jsonb
) to authenticated, service_role;
