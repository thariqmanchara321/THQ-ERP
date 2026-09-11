create or replace function public.restaurant_order_split_safe_v610(
  p_tenant_id uuid,
  p_source_order_id uuid,
  p_device_id uuid,
  p_to_table_id uuid,
  p_items jsonb,
  p_guest_count integer default 1,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  t public.restaurant_tables%rowtype;
  v_moving_guests integer;
  v_result jsonb;
  v_target_order_id uuid;
begin
  v_moving_guests := greatest(1, least(coalesce(p_guest_count, 1), 999));

  select *
  into o
  from public.restaurant_orders
  where id = p_source_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Source restaurant order not found';
  end if;

  if o.guest_count <= 1 then
    raise exception 'Source order must have at least 2 guests before splitting to another table';
  end if;

  if v_moving_guests >= o.guest_count then
    raise exception 'Guests moved must be less than source guest count';
  end if;

  select *
  into t
  from public.restaurant_tables
  where id = p_to_table_id
    and tenant_id = p_tenant_id
    and location_id = o.location_id
    and active = true
  for update;

  if not found then
    raise exception 'Destination restaurant table not found';
  end if;

  if t.capacity < v_moving_guests then
    raise exception 'Destination table capacity is smaller than guests being moved';
  end if;

  v_result := public.restaurant_order_split_v610(
    p_tenant_id,
    p_source_order_id,
    p_device_id,
    p_to_table_id,
    p_items,
    v_moving_guests,
    p_note
  );

  v_target_order_id := nullif(v_result->>'target_order_id', '')::uuid;
  if v_target_order_id is null then
    raise exception 'Split target order was not created';
  end if;

  update public.restaurant_orders
  set guest_count = guest_count - v_moving_guests,
      updated_at = now()
  where id = p_source_order_id
    and tenant_id = p_tenant_id;

  return v_result || jsonb_build_object(
    'source_guest_count', o.guest_count - v_moving_guests,
    'target_guest_count', v_moving_guests,
    'guest_integrity', true
  );
end;
$$;

revoke all on function public.restaurant_order_split_safe_v610(
  uuid,uuid,uuid,uuid,jsonb,integer,text
) from public, anon;

grant execute on function public.restaurant_order_split_safe_v610(
  uuid,uuid,uuid,uuid,jsonb,integer,text
) to authenticated, service_role;

revoke execute on function public.restaurant_order_split_v610(
  uuid,uuid,uuid,uuid,jsonb,integer,text
) from authenticated;
