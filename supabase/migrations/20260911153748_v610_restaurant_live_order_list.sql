create or replace function public.restaurant_orders_list_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_live_only boolean default true,
  p_limit integer default 200
)
returns table(
  id uuid,
  tracking_code text,
  order_number text,
  order_type text,
  table_id uuid,
  table_name text,
  customer_id uuid,
  customer_name text,
  status text,
  preparation_minutes integer,
  chef_note text,
  delivery_address text,
  opened_at timestamptz,
  kitchen_sent_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  sale_id uuid,
  total numeric,
  guest_count integer,
  waiter_user_id uuid,
  waiter_name text,
  order_note text,
  bill_requested_at timestamptz,
  cancelled_at timestamptz,
  cancelled_reason text,
  merged_into_order_id uuid,
  merged_at timestamptz
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
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
    raise exception 'Permission denied';
  end if;

  return query
  select
    o.id,
    o.tracking_code,
    o.order_number,
    o.order_type,
    o.table_id,
    coalesce(nullif(trim(t.name), ''), t.table_code) as table_name,
    o.customer_id,
    c.name as customer_name,
    o.status,
    o.preparation_minutes,
    o.chef_note,
    o.delivery_address,
    o.opened_at,
    o.kitchen_sent_at,
    o.ready_at,
    o.served_at,
    o.sale_id,
    coalesce((
      select sum(
        greatest(
          greatest(i.quantity - coalesce(i.cancelled_quantity, 0), 0) * i.unit_price
          - case
              when i.quantity > 0 then
                i.discount_amount
                * greatest(i.quantity - coalesce(i.cancelled_quantity, 0), 0)
                / i.quantity
              else 0
            end,
          0
        ) * (1 + i.tax_rate / 100)
      )
      from public.restaurant_order_items i
      where i.tenant_id = p_tenant_id
        and i.order_id = o.id
        and greatest(i.quantity - coalesce(i.cancelled_quantity, 0), 0) > 0
    ), 0)::numeric as total,
    o.guest_count,
    o.waiter_user_id,
    p.display_name as waiter_name,
    o.order_note,
    o.bill_requested_at,
    o.cancelled_at,
    o.cancelled_reason,
    o.merged_into_order_id,
    o.merged_at
  from public.restaurant_orders o
  left join public.restaurant_tables t
    on t.id = o.table_id
   and t.tenant_id = o.tenant_id
  left join public.customers c
    on c.id = o.customer_id
   and c.tenant_id = o.tenant_id
  left join public.profiles p
    on p.id = o.waiter_user_id
  where o.tenant_id = p_tenant_id
    and private.erp_document_scope_allowed(
      p_tenant_id,
      o.location_id,
      p_location_id,
      'view'
    )
    and (not p_live_only or o.status not in ('billed','cancelled'))
  order by o.opened_at desc
  limit greatest(1, least(coalesce(p_limit,200),1000));
end;
$$;

revoke all on function public.restaurant_orders_list_v610(
  uuid, uuid, uuid, boolean, integer
) from public, anon;

grant execute on function public.restaurant_orders_list_v610(
  uuid, uuid, uuid, boolean, integer
) to authenticated, service_role;
