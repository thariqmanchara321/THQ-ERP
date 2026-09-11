create or replace function public.restaurant_operations_summary_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_tables bigint := 0;
  v_available bigint := 0;
  v_occupied bigint := 0;
  v_reserved bigint := 0;
  v_cleaning bigint := 0;
  v_out_of_service bigint := 0;
  v_open_orders bigint := 0;
  v_dine_in bigint := 0;
  v_takeaway bigint := 0;
  v_delivery bigint := 0;
  v_live_guests bigint := 0;
  v_kot_queued bigint := 0;
  v_kot_preparing bigint := 0;
  v_kot_ready bigint := 0;
  v_kot_void bigint := 0;
  v_kot_overdue bigint := 0;
  v_waiting bigint := 0;
  v_notified bigint := 0;
  v_waiting_guests bigint := 0;
  v_upcoming_reservations bigint := 0;
  v_bills_today bigint := 0;
  v_sales_today numeric := 0;
  v_avg_ticket numeric := 0;
  v_cancelled_qty_today numeric := 0;
  v_avg_prep_minutes numeric := 0;
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
    or private.erp_has_permission(p_tenant_id,'restaurant.view')
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.kot')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant dashboard permission denied';
  end if;

  select
    count(*),
    count(*) filter (
      where t.operational_status='available'
        and not exists (
          select 1
          from public.restaurant_orders o
          where o.tenant_id=p_tenant_id
            and o.location_id=p_location_id
            and o.table_id=t.id
            and o.status not in ('billed','cancelled')
        )
    ),
    count(*) filter (
      where exists (
        select 1
        from public.restaurant_orders o
        where o.tenant_id=p_tenant_id
          and o.location_id=p_location_id
          and o.table_id=t.id
          and o.status not in ('billed','cancelled')
      )
    ),
    count(*) filter (where t.operational_status='reserved'),
    count(*) filter (where t.operational_status='cleaning'),
    count(*) filter (where t.operational_status='out_of_service')
  into
    v_tables,
    v_available,
    v_occupied,
    v_reserved,
    v_cleaning,
    v_out_of_service
  from public.restaurant_tables t
  where t.tenant_id=p_tenant_id
    and t.location_id=p_location_id
    and t.active=true;

  select
    count(*),
    count(*) filter (where o.order_type='dine_in'),
    count(*) filter (where o.order_type='takeaway'),
    count(*) filter (where o.order_type='delivery'),
    coalesce(sum(o.guest_count) filter (where o.order_type='dine_in'),0)
  into
    v_open_orders,
    v_dine_in,
    v_takeaway,
    v_delivery,
    v_live_guests
  from public.restaurant_orders o
  where o.tenant_id=p_tenant_id
    and o.location_id=p_location_id
    and o.status not in ('billed','cancelled');

  select
    count(*) filter (where k.status='queued'),
    count(*) filter (where k.status='preparing'),
    count(*) filter (where k.status='ready'),
    count(*) filter (where k.kind='void' and k.status not in ('served','cancelled')),
    count(*) filter (
      where k.status in ('queued','preparing')
        and now() > k.sent_at + make_interval(mins => greatest(coalesce(o.preparation_minutes,15),0))
    )
  into
    v_kot_queued,
    v_kot_preparing,
    v_kot_ready,
    v_kot_void,
    v_kot_overdue
  from public.restaurant_kots k
  join public.restaurant_orders o
    on o.id=k.order_id
   and o.tenant_id=k.tenant_id
  where k.tenant_id=p_tenant_id
    and k.location_id=p_location_id
    and k.status not in ('served','cancelled');

  select
    count(*) filter (where w.status='waiting'),
    count(*) filter (where w.status='notified'),
    coalesce(sum(w.guest_count) filter (where w.status in ('waiting','notified')),0)
  into
    v_waiting,
    v_notified,
    v_waiting_guests
  from public.restaurant_waitlist w
  where w.tenant_id=p_tenant_id
    and w.location_id=p_location_id
    and w.status in ('waiting','notified');

  select count(*)
  into v_upcoming_reservations
  from public.restaurant_tables t
  where t.tenant_id=p_tenant_id
    and t.location_id=p_location_id
    and t.active=true
    and t.reservation_at is not null
    and t.reservation_at >= now()
    and t.reservation_at < now() + interval '24 hours';

  select
    count(*),
    coalesce(sum(s.grand_total),0)
  into
    v_bills_today,
    v_sales_today
  from public.restaurant_orders o
  join public.sales s
    on s.id=o.sale_id
   and s.tenant_id=o.tenant_id
  where o.tenant_id=p_tenant_id
    and o.location_id=p_location_id
    and o.status='billed'
    and s.sale_date=current_date;

  if v_bills_today > 0 then
    v_avg_ticket := v_sales_today / v_bills_today;
  end if;

  select coalesce(sum(i.cancelled_quantity),0)
  into v_cancelled_qty_today
  from public.restaurant_order_items i
  join public.restaurant_orders o
    on o.id=i.order_id
   and o.tenant_id=i.tenant_id
  where i.tenant_id=p_tenant_id
    and o.location_id=p_location_id
    and i.cancelled_at is not null
    and i.cancelled_at::date=current_date;

  select coalesce(
    avg(extract(epoch from (o.ready_at-o.kitchen_sent_at))/60.0)
      filter (
        where o.ready_at is not null
          and o.kitchen_sent_at is not null
          and o.ready_at >= o.kitchen_sent_at
      ),
    0
  )
  into v_avg_prep_minutes
  from public.restaurant_orders o
  where o.tenant_id=p_tenant_id
    and o.location_id=p_location_id
    and o.opened_at::date=current_date;

  return jsonb_build_object(
    'tables', jsonb_build_object(
      'total', v_tables,
      'available', v_available,
      'occupied', v_occupied,
      'reserved', v_reserved,
      'cleaning', v_cleaning,
      'out_of_service', v_out_of_service
    ),
    'orders', jsonb_build_object(
      'live', v_open_orders,
      'dine_in', v_dine_in,
      'takeaway', v_takeaway,
      'delivery', v_delivery,
      'live_guests', v_live_guests
    ),
    'kitchen', jsonb_build_object(
      'queued', v_kot_queued,
      'preparing', v_kot_preparing,
      'ready', v_kot_ready,
      'void_live', v_kot_void,
      'overdue', v_kot_overdue,
      'avg_prep_minutes_today', round(v_avg_prep_minutes,1)
    ),
    'waitlist', jsonb_build_object(
      'waiting', v_waiting,
      'notified', v_notified,
      'waiting_guests', v_waiting_guests
    ),
    'reservations', jsonb_build_object(
      'next_24h', v_upcoming_reservations
    ),
    'sales', jsonb_build_object(
      'bills_today', v_bills_today,
      'sales_today', round(v_sales_today,2),
      'avg_ticket_today', round(v_avg_ticket,2)
    ),
    'audit', jsonb_build_object(
      'cancelled_quantity_today', round(v_cancelled_qty_today,3)
    ),
    'restaurant_engine','v6.1'
  );
end;
$$;

revoke all on function public.restaurant_operations_summary_v610(uuid,uuid,uuid) from public, anon;
grant execute on function public.restaurant_operations_summary_v610(uuid,uuid,uuid) to authenticated, service_role;
