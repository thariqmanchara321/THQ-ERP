create or replace function public.restaurant_analytics_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_top_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_from timestamptz;
  v_to timestamptz;
  v_top_limit integer;
  v_sales jsonb;
  v_orders jsonb;
  v_kitchen jsonb;
  v_audit jsonb;
  v_order_types jsonb;
  v_tables jsonb;
  v_waiters jsonb;
  v_top_items jsonb;
  v_daily jsonb;
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
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant analytics permission denied';
  end if;

  v_from := coalesce(p_from, now() - interval '30 days');
  v_to := coalesce(p_to, now());
  v_top_limit := least(greatest(coalesce(p_top_limit, 10), 1), 50);

  if v_to <= v_from then
    raise exception 'Analytics end time must be after start time';
  end if;

  if v_to - v_from > interval '366 days' then
    raise exception 'Restaurant analytics range cannot exceed 366 days';
  end if;

  select jsonb_build_object(
    'bills', count(*),
    'sales', round(coalesce(sum(s.grand_total), 0), 2),
    'gross_profit', round(coalesce(sum(s.gross_profit), 0), 2),
    'avg_ticket', round(coalesce(avg(s.grand_total), 0), 2),
    'dine_in_guests', coalesce(sum(o.guest_count) filter (where o.order_type = 'dine_in'), 0),
    'sales_per_dine_in_guest', round(
      case
        when coalesce(sum(o.guest_count) filter (where o.order_type = 'dine_in'), 0) > 0
          then coalesce(sum(s.grand_total) filter (where o.order_type = 'dine_in'), 0)
             / sum(o.guest_count) filter (where o.order_type = 'dine_in')
        else 0
      end,
      2
    )
  )
  into v_sales
  from public.restaurant_orders o
  join public.sales s
    on s.id = o.sale_id
   and s.tenant_id = o.tenant_id
  where o.tenant_id = p_tenant_id
    and o.location_id = p_location_id
    and o.status = 'billed'
    and o.billed_at >= v_from
    and o.billed_at < v_to;

  select jsonb_build_object(
    'opened', count(*),
    'dine_in', count(*) filter (where order_type = 'dine_in'),
    'takeaway', count(*) filter (where order_type = 'takeaway'),
    'delivery', count(*) filter (where order_type = 'delivery'),
    'billed', count(*) filter (where status = 'billed'),
    'cancelled', count(*) filter (where status = 'cancelled' and merged_into_order_id is null),
    'merged', count(*) filter (where merged_into_order_id is not null),
    'avg_guests_dine_in', round(coalesce(avg(guest_count) filter (where order_type = 'dine_in'), 0), 2),
    'avg_order_cycle_minutes', round(coalesce(avg(
      extract(epoch from (billed_at - opened_at)) / 60.0
    ) filter (
      where billed_at is not null
        and billed_at >= opened_at
    ), 0), 1)
  )
  into v_orders
  from public.restaurant_orders
  where tenant_id = p_tenant_id
    and location_id = p_location_id
    and opened_at >= v_from
    and opened_at < v_to;

  select jsonb_build_object(
    'kots', count(*),
    'items_kots', count(*) filter (where k.kind = 'items'),
    'void_kots', count(*) filter (where k.kind = 'void'),
    'avg_queue_to_start_minutes', round(coalesce(avg(
      extract(epoch from (k.started_at - k.sent_at)) / 60.0
    ) filter (
      where k.started_at is not null
        and k.started_at >= k.sent_at
    ), 0), 1),
    'avg_send_to_ready_minutes', round(coalesce(avg(
      extract(epoch from (k.ready_at - k.sent_at)) / 60.0
    ) filter (
      where k.ready_at is not null
        and k.ready_at >= k.sent_at
    ), 0), 1),
    'avg_ready_to_served_minutes', round(coalesce(avg(
      extract(epoch from (k.served_at - k.ready_at)) / 60.0
    ) filter (
      where k.served_at is not null
        and k.ready_at is not null
        and k.served_at >= k.ready_at
    ), 0), 1),
    'ready_within_target_pct', round(
      case
        when count(*) filter (where k.kind = 'items' and k.ready_at is not null) > 0 then
          100.0 * count(*) filter (
            where k.kind = 'items'
              and k.ready_at is not null
              and k.ready_at <= k.sent_at + make_interval(mins => greatest(coalesce(o.preparation_minutes, 15), 0))
          ) / count(*) filter (where k.kind = 'items' and k.ready_at is not null)
        else 0
      end,
      1
    )
  )
  into v_kitchen
  from public.restaurant_kots k
  join public.restaurant_orders o
    on o.id = k.order_id
   and o.tenant_id = k.tenant_id
  where k.tenant_id = p_tenant_id
    and k.location_id = p_location_id
    and k.sent_at >= v_from
    and k.sent_at < v_to;

  select jsonb_build_object(
    'cancelled_orders', (
      select count(*)
      from public.restaurant_orders o
      where o.tenant_id = p_tenant_id
        and o.location_id = p_location_id
        and o.cancelled_at >= v_from
        and o.cancelled_at < v_to
        and o.merged_into_order_id is null
    ),
    'cancelled_item_lines', count(*) filter (where i.cancelled_quantity > 0),
    'cancelled_quantity', round(coalesce(sum(i.cancelled_quantity), 0), 3)
  )
  into v_audit
  from public.restaurant_order_items i
  join public.restaurant_orders o
    on o.id = i.order_id
   and o.tenant_id = i.tenant_id
  where i.tenant_id = p_tenant_id
    and o.location_id = p_location_id
    and i.cancelled_at >= v_from
    and i.cancelled_at < v_to;

  select coalesce(jsonb_agg(row_data order by sales desc, order_type), '[]'::jsonb)
  into v_order_types
  from (
    select
      o.order_type,
      sum(s.grand_total) as sales,
      jsonb_build_object(
        'order_type', o.order_type,
        'bills', count(*),
        'sales', round(coalesce(sum(s.grand_total), 0), 2),
        'gross_profit', round(coalesce(sum(s.gross_profit), 0), 2),
        'avg_ticket', round(coalesce(avg(s.grand_total), 0), 2),
        'guests', coalesce(sum(o.guest_count) filter (where o.order_type = 'dine_in'), 0)
      ) as row_data
    from public.restaurant_orders o
    join public.sales s
      on s.id = o.sale_id
     and s.tenant_id = o.tenant_id
    where o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
      and o.status = 'billed'
      and o.billed_at >= v_from
      and o.billed_at < v_to
    group by o.order_type
  ) q;

  select coalesce(jsonb_agg(row_data order by sales desc, table_name), '[]'::jsonb)
  into v_tables
  from (
    select
      coalesce(nullif(trim(t.name), ''), t.table_code, 'Unknown table') as table_name,
      sum(s.grand_total) as sales,
      jsonb_build_object(
        'table_id', o.table_id,
        'table_name', coalesce(nullif(trim(t.name), ''), t.table_code, 'Unknown table'),
        'floor_name', coalesce(nullif(trim(t.floor_name), ''), nullif(trim(t.area), '')),
        'bills', count(*),
        'guests', coalesce(sum(o.guest_count), 0),
        'sales', round(coalesce(sum(s.grand_total), 0), 2),
        'avg_ticket', round(coalesce(avg(s.grand_total), 0), 2),
        'avg_sales_per_guest', round(
          case when coalesce(sum(o.guest_count), 0) > 0
            then coalesce(sum(s.grand_total), 0) / sum(o.guest_count)
            else 0
          end,
          2
        ),
        'avg_cycle_minutes', round(coalesce(avg(
          extract(epoch from (o.billed_at - o.opened_at)) / 60.0
        ) filter (where o.billed_at >= o.opened_at), 0), 1)
      ) as row_data
    from public.restaurant_orders o
    join public.sales s
      on s.id = o.sale_id
     and s.tenant_id = o.tenant_id
    left join public.restaurant_tables t
      on t.id = o.table_id
     and t.tenant_id = o.tenant_id
    where o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
      and o.order_type = 'dine_in'
      and o.status = 'billed'
      and o.billed_at >= v_from
      and o.billed_at < v_to
    group by o.table_id, t.name, t.table_code, t.floor_name, t.area
    order by sum(s.grand_total) desc
    limit v_top_limit
  ) q;

  select coalesce(jsonb_agg(row_data order by sales desc, waiter_name), '[]'::jsonb)
  into v_waiters
  from (
    select
      coalesce(nullif(trim(p.display_name), ''), 'Unassigned') as waiter_name,
      sum(s.grand_total) as sales,
      jsonb_build_object(
        'waiter_user_id', o.waiter_user_id,
        'waiter_name', coalesce(nullif(trim(p.display_name), ''), 'Unassigned'),
        'bills', count(*),
        'guests', coalesce(sum(o.guest_count) filter (where o.order_type = 'dine_in'), 0),
        'sales', round(coalesce(sum(s.grand_total), 0), 2),
        'avg_ticket', round(coalesce(avg(s.grand_total), 0), 2),
        'avg_prep_minutes', round(coalesce(avg(
          extract(epoch from (o.ready_at - o.kitchen_sent_at)) / 60.0
        ) filter (
          where o.ready_at is not null
            and o.kitchen_sent_at is not null
            and o.ready_at >= o.kitchen_sent_at
        ), 0), 1)
      ) as row_data
    from public.restaurant_orders o
    join public.sales s
      on s.id = o.sale_id
     and s.tenant_id = o.tenant_id
    left join public.profiles p
      on p.id = o.waiter_user_id
    where o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
      and o.status = 'billed'
      and o.billed_at >= v_from
      and o.billed_at < v_to
    group by o.waiter_user_id, p.display_name
    order by sum(s.grand_total) desc
    limit v_top_limit
  ) q;

  select coalesce(jsonb_agg(row_data order by revenue desc, product_name), '[]'::jsonb)
  into v_top_items
  from (
    select
      coalesce(nullif(trim(si.product_name), ''), si.sku, 'Item') as product_name,
      sum(si.line_total) as revenue,
      jsonb_build_object(
        'variant_id', si.variant_id,
        'product_name', coalesce(nullif(trim(si.product_name), ''), si.sku, 'Item'),
        'sku', si.sku,
        'quantity', round(coalesce(sum(si.quantity), 0), 3),
        'revenue', round(coalesce(sum(si.line_total), 0), 2),
        'gross_profit', round(coalesce(sum(si.gross_profit), 0), 2)
      ) as row_data
    from public.restaurant_orders o
    join public.sale_items si
      on si.sale_id = o.sale_id
     and si.tenant_id = o.tenant_id
    where o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
      and o.status = 'billed'
      and o.billed_at >= v_from
      and o.billed_at < v_to
    group by si.variant_id, si.product_name, si.sku
    order by sum(si.line_total) desc
    limit v_top_limit
  ) q;

  select coalesce(jsonb_agg(row_data order by day), '[]'::jsonb)
  into v_daily
  from (
    select
      o.billed_at::date as day,
      jsonb_build_object(
        'date', o.billed_at::date,
        'bills', count(*),
        'sales', round(coalesce(sum(s.grand_total), 0), 2),
        'gross_profit', round(coalesce(sum(s.gross_profit), 0), 2),
        'guests', coalesce(sum(o.guest_count) filter (where o.order_type = 'dine_in'), 0),
        'avg_ticket', round(coalesce(avg(s.grand_total), 0), 2)
      ) as row_data
    from public.restaurant_orders o
    join public.sales s
      on s.id = o.sale_id
     and s.tenant_id = o.tenant_id
    where o.tenant_id = p_tenant_id
      and o.location_id = p_location_id
      and o.status = 'billed'
      and o.billed_at >= v_from
      and o.billed_at < v_to
    group by o.billed_at::date
  ) q;

  return jsonb_build_object(
    'range', jsonb_build_object(
      'from', v_from,
      'to', v_to
    ),
    'sales', coalesce(v_sales, '{}'::jsonb),
    'orders', coalesce(v_orders, '{}'::jsonb),
    'kitchen', coalesce(v_kitchen, '{}'::jsonb),
    'audit', coalesce(v_audit, '{}'::jsonb),
    'order_types', coalesce(v_order_types, '[]'::jsonb),
    'tables', coalesce(v_tables, '[]'::jsonb),
    'waiters', coalesce(v_waiters, '[]'::jsonb),
    'top_items', coalesce(v_top_items, '[]'::jsonb),
    'daily', coalesce(v_daily, '[]'::jsonb),
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_analytics_v610(
  uuid, uuid, uuid, timestamptz, timestamptz, integer
) from public, anon;

grant execute on function public.restaurant_analytics_v610(
  uuid, uuid, uuid, timestamptz, timestamptz, integer
) to authenticated, service_role;
