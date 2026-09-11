create index if not exists idx_restaurant_orders_table_live
  on public.restaurant_orders(tenant_id, location_id, table_id, status)
  where table_id is not null;

create or replace function public.restaurant_order_transfer_table_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_to_table_id uuid,
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
  v_from_table_id uuid;
  v_from_name text;
  v_to_name text;
begin
  if p_to_table_id is null then
    raise exception 'Destination table is required';
  end if;

  select *
  into o
  from public.restaurant_orders
  where id = p_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Restaurant order not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    o.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant order permission denied';
  end if;

  if o.status in ('billed', 'cancelled') then
    raise exception 'Order is closed';
  end if;

  if o.order_type <> 'dine_in' then
    raise exception 'Only dine-in orders can be transferred between tables';
  end if;

  v_from_table_id := o.table_id;
  if v_from_table_id is null then
    raise exception 'Restaurant order has no current table';
  end if;

  if v_from_table_id = p_to_table_id then
    raise exception 'Order is already assigned to this table';
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
    raise exception 'Destination table not found in this restaurant location';
  end if;

  if t.operational_status <> 'available' then
    raise exception 'Destination table is not available';
  end if;

  if exists (
    select 1
    from public.restaurant_orders x
    where x.tenant_id = p_tenant_id
      and x.location_id = o.location_id
      and x.table_id = p_to_table_id
      and x.id <> p_order_id
      and x.status not in ('billed', 'cancelled')
  ) then
    raise exception 'Destination table already has an active order';
  end if;

  select coalesce(nullif(trim(name), ''), table_code)
  into v_from_name
  from public.restaurant_tables
  where id = v_from_table_id
    and tenant_id = p_tenant_id;

  v_to_name := coalesce(nullif(trim(t.name), ''), t.table_code);

  update public.restaurant_orders
  set table_id = p_to_table_id,
      updated_at = now()
  where id = p_order_id
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
    p_order_id,
    v_from_table_id,
    p_to_table_id,
    'transfer',
    nullif(trim(coalesce(p_note, '')), ''),
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_order_id::text,
    'table_transfer'
  );

  return jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'from_table_id', v_from_table_id,
    'from_table_name', v_from_name,
    'to_table_id', p_to_table_id,
    'to_table_name', v_to_name,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_order_transfer_table_v610(
  uuid, uuid, uuid, uuid, text
) from public, anon;

grant execute on function public.restaurant_order_transfer_table_v610(
  uuid, uuid, uuid, uuid, text
) to authenticated, service_role;
