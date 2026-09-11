create or replace function public.restaurant_kot_status_set_v610(
  p_tenant_id uuid,
  p_kot_id uuid,
  p_device_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  k public.restaurant_kots%rowtype;
  o public.restaurant_orders%rowtype;
  v_status text;
  v_order_status text;
begin
  v_status := lower(trim(coalesce(p_status, '')));
  if v_status not in ('queued', 'preparing', 'ready', 'served', 'cancelled') then
    raise exception 'Invalid KOT status';
  end if;

  select *
  into k
  from public.restaurant_kots
  where id = p_kot_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Kitchen order not found';
  end if;

  select *
  into o
  from public.restaurant_orders
  where id = k.order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Restaurant order not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    k.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.kot')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant kitchen permission denied';
  end if;

  if o.status in ('billed', 'cancelled') and v_status not in ('served', 'cancelled') then
    raise exception 'Restaurant order is closed';
  end if;

  if k.status <> v_status then
    if k.status = 'queued' and v_status not in ('preparing', 'cancelled') then
      raise exception 'KOT must move from queued to preparing before %', v_status;
    elsif k.status = 'preparing' and v_status not in ('ready', 'cancelled') then
      raise exception 'KOT must move from preparing to ready before %', v_status;
    elsif k.status = 'ready' and v_status not in ('served', 'cancelled') then
      raise exception 'KOT must move from ready to served before %', v_status;
    elsif k.status = 'served' then
      raise exception 'Served KOT cannot be moved to %', v_status;
    elsif k.status = 'cancelled' then
      raise exception 'Cancelled KOT cannot be moved to %', v_status;
    end if;
  end if;

  update public.restaurant_kots
  set status = v_status,
      started_at = case
        when v_status in ('preparing', 'ready', 'served') then coalesce(started_at, now())
        else started_at
      end,
      ready_at = case
        when v_status in ('ready', 'served') then coalesce(ready_at, now())
        else ready_at
      end,
      served_at = case
        when v_status = 'served' then coalesce(served_at, now())
        else served_at
      end
  where id = p_kot_id
    and tenant_id = p_tenant_id;

  if k.kind = 'items' and o.status not in ('billed', 'cancelled') then
    if v_status = 'queued' then
      if o.status = 'open' then
        update public.restaurant_orders
        set status = 'sent_to_kitchen',
            kitchen_sent_at = coalesce(kitchen_sent_at, now()),
            updated_at = now()
        where id = o.id and tenant_id = p_tenant_id;
      end if;
    elsif v_status = 'preparing' then
      update public.restaurant_orders
      set status = 'preparing',
          kitchen_sent_at = coalesce(kitchen_sent_at, now()),
          updated_at = now()
      where id = o.id and tenant_id = p_tenant_id;
    elsif v_status = 'ready' then
      if not exists (
        select 1
        from public.restaurant_kots x
        where x.tenant_id = p_tenant_id
          and x.order_id = o.id
          and x.kind = 'items'
          and x.status not in ('ready', 'served', 'cancelled')
      ) then
        update public.restaurant_orders
        set status = 'ready',
            ready_at = coalesce(ready_at, now()),
            updated_at = now()
        where id = o.id and tenant_id = p_tenant_id;
      end if;
    elsif v_status = 'served' then
      if not exists (
        select 1
        from public.restaurant_kots x
        where x.tenant_id = p_tenant_id
          and x.order_id = o.id
          and x.kind = 'items'
          and x.status not in ('served', 'cancelled')
      ) then
        update public.restaurant_orders
        set status = 'served',
            ready_at = coalesce(ready_at, now()),
            served_at = coalesce(served_at, now()),
            updated_at = now()
        where id = o.id and tenant_id = p_tenant_id;
      end if;
    end if;
  end if;

  select status
  into v_order_status
  from public.restaurant_orders
  where id = o.id
    and tenant_id = p_tenant_id;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_kot',
    p_kot_id::text,
    'status_' || v_status
  );

  return jsonb_build_object(
    'success', true,
    'kot_id', p_kot_id,
    'kot_number', k.kot_number,
    'kind', k.kind,
    'previous_status', k.status,
    'status', v_status,
    'order_id', o.id,
    'order_number', o.order_number,
    'order_status', v_order_status,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_kot_status_set_v610(
  uuid, uuid, uuid, text
) from public, anon;

grant execute on function public.restaurant_kot_status_set_v610(
  uuid, uuid, uuid, text
) to authenticated, service_role;
