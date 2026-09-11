create index if not exists idx_restaurant_kots_kitchen_v610
  on public.restaurant_kots(tenant_id, location_id, status, sent_at desc);

create or replace function public.restaurant_kitchen_queue_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_status text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_status text;
  v_limit integer;
  v_rows jsonb;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'restaurant',
    'view'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.view')
    or private.erp_has_permission(p_tenant_id, 'restaurant.kot')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant kitchen permission denied';
  end if;

  v_status := nullif(lower(trim(coalesce(p_status, ''))), '');
  if v_status is not null and v_status not in (
    'queued', 'preparing', 'ready', 'served', 'cancelled', 'live'
  ) then
    raise exception 'Invalid kitchen status filter';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 100), 1), 500);

  select coalesce(
    jsonb_agg(row_data order by sent_at, kot_number),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      k.sent_at,
      k.kot_number,
      jsonb_build_object(
        'kot_id', k.id,
        'kot_number', k.kot_number,
        'tracking_code', k.tracking_code,
        'kind', k.kind,
        'status', k.status,
        'note', k.note,
        'sent_at', k.sent_at,
        'started_at', k.started_at,
        'ready_at', k.ready_at,
        'served_at', k.served_at,
        'elapsed_minutes', greatest(0, floor(extract(epoch from (now() - k.sent_at)) / 60))::integer,
        'order_id', o.id,
        'order_number', o.order_number,
        'order_type', o.order_type,
        'order_status', o.status,
        'guest_count', o.guest_count,
        'table_id', o.table_id,
        'table_name', coalesce(nullif(trim(t.name), ''), t.table_code),
        'chef_note', o.chef_note,
        'order_note', o.order_note,
        'items', coalesce((
          select jsonb_agg(
            jsonb_strip_nulls(
              jsonb_build_object(
                'kot_item_id', ki.id,
                'order_item_id', ki.order_item_id,
                'variant_id', ki.variant_id,
                'product_name', coalesce(nullif(trim(p.name), ''), nullif(trim(pv.name), ''), pv.sku, 'Item'),
                'variant_name', nullif(trim(pv.name), ''),
                'sku', pv.sku,
                'quantity', ki.quantity,
                'item_note', ki.item_note,
                'modifiers', ki.modifiers
              )
            )
            order by ki.created_at, ki.id
          )
          from public.restaurant_kot_items ki
          left join public.product_variants pv
            on pv.id = ki.variant_id
           and pv.tenant_id = p_tenant_id
          left join public.products p
            on p.id = pv.product_id
           and p.tenant_id = pv.tenant_id
          where ki.tenant_id = p_tenant_id
            and ki.kot_id = k.id
        ), '[]'::jsonb)
      ) as row_data
    from public.restaurant_kots k
    join public.restaurant_orders o
      on o.id = k.order_id
     and o.tenant_id = k.tenant_id
    left join public.restaurant_tables t
      on t.id = o.table_id
     and t.tenant_id = o.tenant_id
    where k.tenant_id = p_tenant_id
      and k.location_id = p_location_id
      and (
        v_status is null and k.status in ('queued', 'preparing', 'ready')
        or v_status = 'live' and k.status in ('queued', 'preparing', 'ready')
        or v_status in ('queued', 'preparing', 'ready', 'served', 'cancelled') and k.status = v_status
      )
    order by k.sent_at, k.kot_number
    limit v_limit
  ) q;

  return jsonb_build_object(
    'success', true,
    'location_id', p_location_id,
    'status_filter', coalesce(v_status, 'live'),
    'count', jsonb_array_length(v_rows),
    'kots', v_rows,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

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

  update public.restaurant_kots
  set status = v_status,
      started_at = case
        when v_status in ('preparing', 'ready', 'served') then coalesce(started_at, now())
        else started_at
      end,
      ready_at = case
        when v_status in ('ready', 'served') then coalesce(ready_at, now())
        when v_status in ('queued', 'preparing') then null
        else ready_at
      end,
      served_at = case
        when v_status = 'served' then coalesce(served_at, now())
        when v_status in ('queued', 'preparing', 'ready') then null
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
            ready_at = null,
            served_at = null,
            updated_at = now()
        where id = o.id and tenant_id = p_tenant_id;
      end if;
    elsif v_status = 'preparing' then
      update public.restaurant_orders
      set status = 'preparing',
          kitchen_sent_at = coalesce(kitchen_sent_at, now()),
          ready_at = null,
          served_at = null,
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
            served_at = null,
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

  select status into v_order_status
  from public.restaurant_orders
  where id = o.id and tenant_id = p_tenant_id;

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
    'status', v_status,
    'order_id', o.id,
    'order_number', o.order_number,
    'order_status', v_order_status,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_kitchen_queue_v610(
  uuid, uuid, uuid, text, integer
) from public, anon;

revoke all on function public.restaurant_kot_status_set_v610(
  uuid, uuid, uuid, text
) from public, anon;

grant execute on function public.restaurant_kitchen_queue_v610(
  uuid, uuid, uuid, text, integer
) to authenticated, service_role;

grant execute on function public.restaurant_kot_status_set_v610(
  uuid, uuid, uuid, text
) to authenticated, service_role;
