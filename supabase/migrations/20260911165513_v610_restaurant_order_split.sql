create or replace function public.restaurant_order_split_v610(
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
  i public.restaurant_order_items%rowtype;
  x jsonb;
  v_target_order_id uuid := gen_random_uuid();
  v_target_order_number text;
  v_target_tracking_code text;
  v_item_id uuid;
  v_move_qty numeric;
  v_active_before numeric;
  v_unsent_before numeric;
  v_moved_unsent numeric;
  v_moved_sent numeric;
  v_discount_move numeric;
  v_target_sent_total numeric := 0;
  v_moved_total numeric := 0;
  v_source_remaining numeric := 0;
  v_note text;
  v_target_status text := 'open';
  v_rows integer := 0;
  m record;
  v_target_modifier_qty numeric;
begin
  if p_to_table_id is null then
    raise exception 'Destination table is required';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Choose at least one restaurant item to split';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');

  select *
  into o
  from public.restaurant_orders
  where id = p_source_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Source restaurant order not found';
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

  if o.status in ('billed', 'cancelled') or o.sale_id is not null then
    raise exception 'Source restaurant order is closed';
  end if;

  if o.order_type <> 'dine_in' then
    raise exception 'Only dine-in orders can be split to another table';
  end if;

  if o.table_id is null then
    raise exception 'Source restaurant order has no table';
  end if;

  if o.table_id = p_to_table_id then
    raise exception 'Choose a different destination table';
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

  if t.operational_status <> 'available' then
    raise exception 'Destination table is not available';
  end if;

  if exists (
    select 1
    from public.restaurant_orders other_o
    where other_o.tenant_id = p_tenant_id
      and other_o.location_id = o.location_id
      and other_o.table_id = p_to_table_id
      and other_o.status not in ('billed', 'cancelled')
  ) then
    raise exception 'Destination table already has an active order';
  end if;

  insert into public.restaurant_orders(
    id,
    tenant_id,
    location_id,
    device_id,
    order_number,
    order_type,
    table_id,
    customer_id,
    status,
    preparation_minutes,
    chef_note,
    delivery_address,
    created_by,
    guest_count,
    waiter_user_id,
    order_note,
    kitchen_sent_at,
    ready_at,
    served_at
  )
  values (
    v_target_order_id,
    p_tenant_id,
    o.location_id,
    p_device_id,
    '',
    'dine_in',
    p_to_table_id,
    o.customer_id,
    'open',
    o.preparation_minutes,
    o.chef_note,
    null,
    auth.uid(),
    greatest(1, least(coalesce(p_guest_count, 1), 999)),
    o.waiter_user_id,
    o.order_note,
    null,
    null,
    null
  )
  returning order_number, tracking_code
  into v_target_order_number, v_target_tracking_code;

  insert into public.document_origins(
    tenant_id,
    entity_type,
    entity_id,
    location_id,
    device_id,
    created_by
  )
  values (
    p_tenant_id,
    'restaurant_order',
    v_target_order_id,
    o.location_id,
    p_device_id,
    auth.uid()
  )
  on conflict do nothing;

  if o.waiter_user_id is not null then
    insert into public.restaurant_waiter_assignments(
      tenant_id,
      order_id,
      user_id,
      assigned_at
    )
    values (
      p_tenant_id,
      v_target_order_id,
      o.waiter_user_id,
      now()
    )
    on conflict (tenant_id, order_id)
    do update set
      user_id = excluded.user_id,
      assigned_at = excluded.assigned_at;
  end if;

  for x in
    select value
    from jsonb_array_elements(p_items)
  loop
    v_item_id := nullif(x->>'order_item_id', '')::uuid;
    v_move_qty := coalesce(nullif(x->>'quantity', '')::numeric, 0);

    if v_item_id is null or v_move_qty <= 0 then
      raise exception 'Each split item requires an order_item_id and quantity greater than zero';
    end if;

    select *
    into i
    from public.restaurant_order_items
    where id = v_item_id
      and tenant_id = p_tenant_id
      and order_id = p_source_order_id
    for update;

    if not found then
      raise exception 'Restaurant order item % was not found on the source order', v_item_id;
    end if;

    v_active_before := greatest(i.quantity - i.cancelled_quantity, 0);
    if v_move_qty > v_active_before then
      raise exception 'Split quantity % exceeds active quantity % for item %',
        v_move_qty,
        v_active_before,
        v_item_id;
    end if;

    v_unsent_before := greatest(v_active_before - i.kot_sent_quantity, 0);
    v_moved_unsent := least(v_move_qty, v_unsent_before);
    v_moved_sent := greatest(v_move_qty - v_moved_unsent, 0);
    v_discount_move := case
      when i.quantity > 0 then i.discount_amount * v_move_qty / i.quantity
      else 0
    end;

    if v_move_qty = i.quantity and i.cancelled_quantity = 0 then
      update public.restaurant_order_items
      set order_id = v_target_order_id
      where id = i.id
        and tenant_id = p_tenant_id;
    else
      insert into public.restaurant_order_items(
        order_id,
        tenant_id,
        variant_id,
        quantity,
        unit_id,
        conversion_to_base,
        unit_price,
        discount_amount,
        tax_rate,
        item_note,
        pricing_source,
        price_list_id,
        pricing_metadata,
        kot_sent_quantity,
        cancelled_quantity
      )
      values (
        v_target_order_id,
        p_tenant_id,
        i.variant_id,
        v_move_qty,
        i.unit_id,
        i.conversion_to_base,
        i.unit_price,
        v_discount_move,
        i.tax_rate,
        i.item_note,
        i.pricing_source,
        i.price_list_id,
        i.pricing_metadata || jsonb_build_object(
          'split_from_order_id', p_source_order_id,
          'split_from_order_item_id', i.id,
          'split_at', now(),
          'engine', 'v6.1'
        ),
        v_moved_sent,
        0
      )
      returning id into v_item_id;

      for m in
        select *
        from public.restaurant_order_modifiers rm
        where rm.tenant_id = p_tenant_id
          and rm.order_item_id = i.id
      loop
        v_target_modifier_qty := case
          when i.quantity > 0 then m.quantity * v_move_qty / i.quantity
          else 0
        end;

        if v_target_modifier_qty > 0 then
          insert into public.restaurant_order_modifiers(
            tenant_id,
            order_item_id,
            modifier_name,
            price_delta,
            quantity
          )
          values (
            p_tenant_id,
            v_item_id,
            m.modifier_name,
            m.price_delta,
            v_target_modifier_qty
          );

          update public.restaurant_order_modifiers
          set quantity = greatest(quantity - v_target_modifier_qty, 0)
          where id = m.id;
        end if;
      end loop;

      delete from public.restaurant_order_modifiers
      where tenant_id = p_tenant_id
        and order_item_id = i.id
        and quantity <= 0;

      update public.restaurant_order_items
      set quantity = quantity - v_move_qty,
          discount_amount = greatest(discount_amount - v_discount_move, 0),
          kot_sent_quantity = greatest(kot_sent_quantity - v_moved_sent, 0)
      where id = i.id
        and tenant_id = p_tenant_id;
    end if;

    v_target_sent_total := v_target_sent_total + v_moved_sent;
    v_moved_total := v_moved_total + v_move_qty;
    v_rows := v_rows + 1;
  end loop;

  select coalesce(sum(greatest(quantity - cancelled_quantity, 0)), 0)
  into v_source_remaining
  from public.restaurant_order_items
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  if v_source_remaining <= 0 then
    raise exception 'A split must leave at least one active item on the source order. Use table transfer instead.';
  end if;

  if v_target_sent_total > 0 then
    v_target_status := case
      when o.status in ('preparing', 'ready', 'served') then o.status
      else 'sent_to_kitchen'
    end;
  else
    v_target_status := 'open';
  end if;

  update public.restaurant_orders
  set status = v_target_status,
      kitchen_sent_at = case when v_target_sent_total > 0 then o.kitchen_sent_at else null end,
      ready_at = case when v_target_status in ('ready','served') then o.ready_at else null end,
      served_at = case when v_target_status = 'served' then o.served_at else null end,
      updated_at = now()
  where id = v_target_order_id
    and tenant_id = p_tenant_id;

  update public.restaurant_orders
  set updated_at = now()
  where id = p_source_order_id
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
    p_source_order_id,
    o.table_id,
    p_to_table_id,
    'split',
    'Split ' || v_rows || ' item line(s), quantity ' || v_moved_total ||
      ' to ' || v_target_order_number ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_source_order_id::text,
    'split_source'
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    v_target_order_id::text,
    'split_target'
  );

  return jsonb_build_object(
    'success', true,
    'source_order_id', p_source_order_id,
    'source_order_number', o.order_number,
    'source_table_id', o.table_id,
    'source_remaining_quantity', v_source_remaining,
    'target_order_id', v_target_order_id,
    'target_order_number', v_target_order_number,
    'target_tracking_code', v_target_tracking_code,
    'target_table_id', p_to_table_id,
    'target_table_name', coalesce(nullif(trim(t.name), ''), t.table_code),
    'target_status', v_target_status,
    'item_lines_moved', v_rows,
    'quantity_moved', v_moved_total,
    'already_sent_quantity_moved', v_target_sent_total,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_order_split_v610(
  uuid, uuid, uuid, uuid, jsonb, integer, text
) from public, anon;

grant execute on function public.restaurant_order_split_v610(
  uuid, uuid, uuid, uuid, jsonb, integer, text
) to authenticated, service_role;
