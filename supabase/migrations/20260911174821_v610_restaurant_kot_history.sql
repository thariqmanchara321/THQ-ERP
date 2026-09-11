create or replace function public.restaurant_kot_history_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_order_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_from timestamptz := coalesce(p_from, now() - interval '30 days');
  v_to timestamptz := coalesce(p_to, now());
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
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
    raise exception 'Restaurant KOT history permission denied';
  end if;

  if v_to <= v_from then
    raise exception 'KOT history end time must be after start time';
  end if;

  if v_to - v_from > interval '366 days' then
    raise exception 'KOT history range cannot exceed 366 days';
  end if;

  if p_order_id is not null and not exists (
    select 1
    from public.restaurant_orders o
    where o.id = p_order_id
      and o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
  ) then
    raise exception 'Restaurant order not found in this location';
  end if;

  select coalesce(
    jsonb_agg(row_data order by sent_at desc, kot_number desc),
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
        'order_id', o.id,
        'order_number', o.order_number,
        'order_type', o.order_type,
        'order_status', o.status,
        'table_id', o.table_id,
        'table_name', coalesce(nullif(trim(t.name), ''), t.table_code),
        'guest_count', o.guest_count,
        'waiter_user_id', o.waiter_user_id,
        'waiter_name', coalesce(nullif(trim(p.display_name), ''), 'Unassigned'),
        'preparation_minutes', o.preparation_minutes,
        'chef_note', o.chef_note,
        'order_note', o.order_note,
        'items', coalesce((
          select jsonb_agg(
            jsonb_strip_nulls(
              jsonb_build_object(
                'kot_item_id', ki.id,
                'order_item_id', ki.order_item_id,
                'variant_id', ki.variant_id,
                'product_name', coalesce(nullif(trim(pr.name), ''), nullif(trim(pv.name), ''), pv.sku, 'Item'),
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
          left join public.products pr
            on pr.id = pv.product_id
           and pr.tenant_id = pv.tenant_id
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
    left join public.profiles p
      on p.id = o.waiter_user_id
    where k.tenant_id = p_tenant_id
      and k.location_id = p_location_id
      and k.sent_at >= v_from
      and k.sent_at < v_to
      and (p_order_id is null or k.order_id = p_order_id)
    order by k.sent_at desc, k.kot_number desc
    limit v_limit
  ) q;

  return jsonb_build_object(
    'success', true,
    'location_id', p_location_id,
    'order_id', p_order_id,
    'from', v_from,
    'to', v_to,
    'count', jsonb_array_length(v_rows),
    'kots', v_rows,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_kot_history_v610(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer
) from public, anon;

grant execute on function public.restaurant_kot_history_v610(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer
) to authenticated, service_role;
