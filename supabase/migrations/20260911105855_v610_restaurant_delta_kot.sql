-- THQ ERP v6.1 Restaurant delta-KOT / re-KOT safety
-- Applied to migration-test as Supabase migration:
-- 20260911105855_v610_restaurant_delta_kot
-- Keeps existing GST billing untouched. New KOTs include only quantities not already sent.

with last_kot as (
  select tenant_id, order_id, max(sent_at) as last_sent_at
  from public.restaurant_kots
  where kind = 'items'
  group by tenant_id, order_id
)
update public.restaurant_order_items i
set kot_sent_quantity = greatest(i.quantity - i.cancelled_quantity, 0)
from last_kot k
where i.tenant_id = k.tenant_id
  and i.order_id = k.order_id
  and coalesce(i.kot_sent_quantity, 0) = 0
  and i.created_at <= k.last_sent_at;

create or replace function public.restaurant_kot_send_delta_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  v_kot_id uuid := gen_random_uuid();
  v_kot_number text;
  v_tracking_code text;
  v_items jsonb := '[]'::jsonb;
  v_items_count integer := 0;
  v_quantity_total numeric := 0;
begin
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
    or private.erp_has_permission(p_tenant_id, 'restaurant.kot')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant KOT permission denied';
  end if;

  if o.status in ('billed', 'cancelled') then
    raise exception 'Order is closed';
  end if;

  select count(*),
         coalesce(sum(greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0)), 0)
  into v_items_count, v_quantity_total
  from public.restaurant_order_items i
  where i.tenant_id = p_tenant_id
    and i.order_id = p_order_id
    and greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0) > 0;

  if v_items_count = 0 then
    return jsonb_build_object(
      'success', true,
      'kot_created', false,
      'order_id', p_order_id,
      'items_count', 0,
      'quantity_total', 0,
      'items', '[]'::jsonb,
      'restaurant_engine', 'v6.1'
    );
  end if;

  insert into public.restaurant_kots(
    id,
    tenant_id,
    location_id,
    order_id,
    kot_number,
    status,
    note,
    kind
  )
  values (
    v_kot_id,
    p_tenant_id,
    o.location_id,
    p_order_id,
    '',
    'queued',
    coalesce(nullif(trim(coalesce(p_note, '')), ''), o.chef_note),
    'items'
  )
  returning kot_number, tracking_code
  into v_kot_number, v_tracking_code;

  insert into public.restaurant_kot_items(
    tenant_id,
    kot_id,
    order_id,
    order_item_id,
    variant_id,
    quantity,
    item_note,
    modifiers
  )
  select
    i.tenant_id,
    v_kot_id,
    i.order_id,
    i.id,
    i.variant_id,
    greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0),
    i.item_note,
    coalesce(
      (
        select jsonb_agg(
          jsonb_strip_nulls(
            jsonb_build_object(
              'name', m.modifier_name,
              'price_delta', m.price_delta,
              'quantity', m.quantity
            )
          )
          order by m.modifier_name
        )
        from public.restaurant_order_modifiers m
        where m.tenant_id = i.tenant_id
          and m.order_item_id = i.id
      ),
      '[]'::jsonb
    )
  from public.restaurant_order_items i
  where i.tenant_id = p_tenant_id
    and i.order_id = p_order_id
    and greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0) > 0;

  update public.restaurant_order_items i
  set kot_sent_quantity = i.kot_sent_quantity
      + greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0)
  where i.tenant_id = p_tenant_id
    and i.order_id = p_order_id
    and greatest(i.quantity - i.cancelled_quantity - i.kot_sent_quantity, 0) > 0;

  update public.restaurant_orders
  set status = case
        when status in ('open', 'ready', 'served') then 'sent_to_kitchen'
        else status
      end,
      kitchen_sent_at = coalesce(kitchen_sent_at, now()),
      ready_at = case when status in ('ready', 'served') then null else ready_at end,
      served_at = case when status = 'served' then null else served_at end,
      updated_at = now()
  where id = p_order_id
    and tenant_id = p_tenant_id;

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'kot_item_id', ki.id,
          'order_item_id', ki.order_item_id,
          'variant_id', ki.variant_id,
          'product_name', coalesce(nullif(trim(p.name), ''), nullif(trim(pv.name), ''), pv.sku),
          'variant_name', nullif(trim(pv.name), ''),
          'sku', pv.sku,
          'quantity', ki.quantity,
          'item_note', ki.item_note,
          'modifiers', ki.modifiers
        )
      )
      order by ki.created_at, ki.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.restaurant_kot_items ki
  join public.product_variants pv
    on pv.id = ki.variant_id
   and pv.tenant_id = ki.tenant_id
  left join public.products p
    on p.id = pv.product_id
   and p.tenant_id = pv.tenant_id
  where ki.tenant_id = p_tenant_id
    and ki.kot_id = v_kot_id;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_kot',
    v_kot_id::text,
    'delta_send'
  );

  return jsonb_build_object(
    'success', true,
    'kot_created', true,
    'kot_id', v_kot_id,
    'kot_number', v_kot_number,
    'tracking_code', v_tracking_code,
    'order_id', p_order_id,
    'items_count', v_items_count,
    'quantity_total', v_quantity_total,
    'items', v_items,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_kot_send_delta_v610(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.restaurant_kot_send_delta_v610(uuid, uuid, uuid, text) to authenticated, service_role;

create or replace function public.restaurant_kot_send_v32(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  return public.restaurant_kot_send_delta_v610(
    p_tenant_id,
    p_order_id,
    p_device_id,
    p_note
  );
end;
$$;

revoke all on function public.restaurant_kot_send_v32(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.restaurant_kot_send_v32(uuid, uuid, uuid, text) to authenticated, service_role;
