create or replace function public.restaurant_order_cancel_item_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_order_item_id uuid,
  p_device_id uuid,
  p_cancel_quantity numeric,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  i public.restaurant_order_items%rowtype;
  v_active_before numeric;
  v_unsent_before numeric;
  v_void_quantity numeric;
  v_remaining_total numeric;
  v_reason text;
  v_void_kot_id uuid;
  v_void_kot_number text;
  v_void_tracking_code text;
  v_modifiers jsonb := '[]'::jsonb;
  v_product_name text;
  v_variant_name text;
  v_sku text;
begin
  if p_cancel_quantity is null or p_cancel_quantity <= 0 then
    raise exception 'Cancel quantity must be greater than zero';
  end if;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'Cancellation reason is required';
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

  select *
  into i
  from public.restaurant_order_items
  where id = p_order_item_id
    and order_id = p_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Restaurant order item not found';
  end if;

  v_active_before := greatest(i.quantity - i.cancelled_quantity, 0);

  if p_cancel_quantity > v_active_before then
    raise exception 'Cancel quantity % exceeds remaining item quantity %',
      p_cancel_quantity,
      v_active_before;
  end if;

  v_unsent_before := greatest(v_active_before - i.kot_sent_quantity, 0);
  v_void_quantity := greatest(
    p_cancel_quantity - least(p_cancel_quantity, v_unsent_before),
    0
  );

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'name', m.modifier_name,
          'price_delta', m.price_delta,
          'quantity', m.quantity
        )
      )
      order by m.modifier_name
    ),
    '[]'::jsonb
  )
  into v_modifiers
  from public.restaurant_order_modifiers m
  where m.tenant_id = p_tenant_id
    and m.order_item_id = p_order_item_id;

  select
    coalesce(
      nullif(trim(p.name), ''),
      nullif(trim(pv.name), ''),
      pv.sku
    ),
    nullif(trim(pv.name), ''),
    pv.sku
  into v_product_name, v_variant_name, v_sku
  from public.product_variants pv
  left join public.products p
    on p.id = pv.product_id
   and p.tenant_id = pv.tenant_id
  where pv.id = i.variant_id
    and pv.tenant_id = p_tenant_id;

  update public.restaurant_order_items
  set cancelled_quantity = cancelled_quantity + p_cancel_quantity,
      cancel_reason = case
        when nullif(trim(coalesce(cancel_reason, '')), '') is null then v_reason
        else cancel_reason || ' | ' || v_reason
      end,
      cancelled_at = now()
  where id = p_order_item_id
    and tenant_id = p_tenant_id;

  if v_void_quantity > 0 then
    v_void_kot_id := gen_random_uuid();

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
      v_void_kot_id,
      p_tenant_id,
      o.location_id,
      p_order_id,
      '',
      'queued',
      'VOID: ' || v_reason,
      'void'
    )
    returning kot_number, tracking_code
    into v_void_kot_number, v_void_tracking_code;

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
    values (
      p_tenant_id,
      v_void_kot_id,
      p_order_id,
      p_order_item_id,
      i.variant_id,
      v_void_quantity,
      'VOID: ' || v_reason,
      v_modifiers
    );
  end if;

  select coalesce(
    sum(greatest(quantity - cancelled_quantity, 0)),
    0
  )
  into v_remaining_total
  from public.restaurant_order_items
  where tenant_id = p_tenant_id
    and order_id = p_order_id;

  if v_remaining_total <= 0 then
    update public.restaurant_orders
    set status = 'cancelled',
        cancelled_at = now(),
        cancelled_reason = v_reason,
        updated_at = now()
    where id = p_order_id
      and tenant_id = p_tenant_id;
  else
    update public.restaurant_orders
    set updated_at = now()
    where id = p_order_id
      and tenant_id = p_tenant_id;
  end if;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_order_id::text,
    'item_cancel'
  );

  return jsonb_strip_nulls(
    jsonb_build_object(
      'success', true,
      'order_id', p_order_id,
      'order_item_id', p_order_item_id,
      'cancelled_quantity', p_cancel_quantity,
      'remaining_item_quantity', v_active_before - p_cancel_quantity,
      'order_remaining_quantity', v_remaining_total,
      'order_cancelled', v_remaining_total <= 0,
      'reason', v_reason,
      'void_kot_created', v_void_quantity > 0,
      'void_quantity', v_void_quantity,
      'void_kot_id', v_void_kot_id,
      'void_kot_number', v_void_kot_number,
      'void_tracking_code', v_void_tracking_code,
      'void_items', case
        when v_void_quantity > 0 then jsonb_build_array(
          jsonb_strip_nulls(
            jsonb_build_object(
              'order_item_id', p_order_item_id,
              'variant_id', i.variant_id,
              'product_name', v_product_name,
              'variant_name', v_variant_name,
              'sku', v_sku,
              'quantity', v_void_quantity,
              'item_note', 'VOID: ' || v_reason,
              'modifiers', v_modifiers
            )
          )
        )
        else '[]'::jsonb
      end,
      'restaurant_engine', 'v6.1'
    )
  );
end;
$$;

revoke all on function public.restaurant_order_cancel_item_v610(
  uuid, uuid, uuid, uuid, numeric, text
) from public, anon;

grant execute on function public.restaurant_order_cancel_item_v610(
  uuid, uuid, uuid, uuid, numeric, text
) to authenticated, service_role;
