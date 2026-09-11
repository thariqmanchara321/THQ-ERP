create or replace function public.restaurant_order_move_items_v610(
  p_tenant_id uuid,
  p_source_order_id uuid,
  p_target_order_id uuid,
  p_device_id uuid,
  p_items jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_source public.restaurant_orders%rowtype;
  v_target public.restaurant_orders%rowtype;
  i public.restaurant_order_items%rowtype;
  x jsonb;
  v_item_id uuid;
  v_new_item_id uuid;
  v_move_qty numeric;
  v_active_before numeric;
  v_unsent_before numeric;
  v_moved_sent numeric;
  v_discount_move numeric;
  v_source_new_qty numeric;
  v_target_sent_total numeric := 0;
  v_moved_total numeric := 0;
  v_source_remaining numeric := 0;
  v_source_sent_remaining numeric := 0;
  v_rows integer := 0;
  v_note text;
  v_source_table_name text;
  v_target_table_name text;
  v_seen_item_ids uuid[] := array[]::uuid[];
  m record;
  v_target_modifier_qty numeric;
begin
  if p_source_order_id is null or p_target_order_id is null then
    raise exception 'Source and target restaurant orders are required';
  end if;

  if p_source_order_id = p_target_order_id then
    raise exception 'Source and target restaurant orders must be different';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Choose at least one restaurant item to move';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');

  perform 1
  from public.restaurant_orders
  where tenant_id = p_tenant_id
    and id in (p_source_order_id, p_target_order_id)
  order by id
  for update;

  select *
  into v_source
  from public.restaurant_orders
  where id = p_source_order_id
    and tenant_id = p_tenant_id;

  if not found then
    raise exception 'Source restaurant order not found';
  end if;

  select *
  into v_target
  from public.restaurant_orders
  where id = p_target_order_id
    and tenant_id = p_tenant_id;

  if not found then
    raise exception 'Target restaurant order not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    v_source.location_id,
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

  if v_source.location_id is distinct from v_target.location_id then
    raise exception 'Restaurant orders must belong to the same location';
  end if;

  if v_source.order_type <> 'dine_in' or v_target.order_type <> 'dine_in' then
    raise exception 'Items can only be moved between active dine-in orders';
  end if;

  if v_source.status in ('billed', 'cancelled') or v_source.sale_id is not null then
    raise exception 'Source restaurant order is closed';
  end if;

  if v_target.status in ('billed', 'cancelled') or v_target.sale_id is not null then
    raise exception 'Target restaurant order is closed';
  end if;

  if v_source.table_id is null or v_target.table_id is null then
    raise exception 'Both restaurant orders must be assigned to tables';
  end if;

  if v_source.table_id = v_target.table_id then
    raise exception 'Source and target orders must belong to different tables';
  end if;

  select coalesce(nullif(trim(t.name), ''), t.table_code)
  into v_source_table_name
  from public.restaurant_tables t
  where t.id = v_source.table_id
    and t.tenant_id = p_tenant_id;

  select coalesce(nullif(trim(t.name), ''), t.table_code)
  into v_target_table_name
  from public.restaurant_tables t
  where t.id = v_target.table_id
    and t.tenant_id = p_tenant_id;

  for x in
    select value
    from jsonb_array_elements(p_items)
  loop
    v_item_id := nullif(x->>'order_item_id', '')::uuid;
    v_move_qty := coalesce(nullif(x->>'quantity', '')::numeric, 0);

    if v_item_id is null or v_move_qty <= 0 then
      raise exception 'Each moved item requires an order_item_id and quantity greater than zero';
    end if;

    if v_item_id = any(v_seen_item_ids) then
      raise exception 'Restaurant order item % was supplied more than once', v_item_id;
    end if;
    v_seen_item_ids := array_append(v_seen_item_ids, v_item_id);

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
    if v_active_before <= 0 then
      raise exception 'Restaurant order item % has no active quantity to move', v_item_id;
    end if;

    if v_move_qty > v_active_before then
      raise exception 'Move quantity % exceeds active quantity % for item %',
        v_move_qty,
        v_active_before,
        v_item_id;
    end if;

    v_unsent_before := greatest(v_active_before - i.kot_sent_quantity, 0);
    v_moved_sent := greatest(v_move_qty - least(v_move_qty, v_unsent_before), 0);
    v_discount_move := case
      when i.quantity > 0 then i.discount_amount * v_move_qty / i.quantity
      else 0
    end;

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
      p_target_order_id,
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
        'move_items_from_order_id', p_source_order_id,
        'move_items_from_order_item_id', i.id,
        'move_items_at', now(),
        'engine', 'v6.1'
      ),
      v_moved_sent,
      0
    )
    returning id into v_new_item_id;

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
          v_new_item_id,
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

    v_source_new_qty := i.quantity - v_move_qty;

    if v_source_new_qty <= 0 then
      delete from public.restaurant_order_modifiers
      where tenant_id = p_tenant_id
        and order_item_id = i.id;

      delete from public.restaurant_order_items
      where id = i.id
        and tenant_id = p_tenant_id;
    else
      update public.restaurant_order_items
      set quantity = v_source_new_qty,
          discount_amount = greatest(discount_amount - v_discount_move, 0),
          kot_sent_quantity = greatest(kot_sent_quantity - v_moved_sent, 0)
      where id = i.id
        and tenant_id = p_tenant_id;
    end if;

    v_target_sent_total := v_target_sent_total + v_moved_sent;
    v_moved_total := v_moved_total + v_move_qty;
    v_rows := v_rows + 1;
  end loop;

  select
    coalesce(sum(greatest(quantity - cancelled_quantity, 0)), 0),
    coalesce(sum(greatest(kot_sent_quantity, 0)), 0)
  into v_source_remaining, v_source_sent_remaining
  from public.restaurant_order_items
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  if v_source_remaining <= 0 then
    raise exception 'Moving these items would empty the source order. Use Merge Tables / Orders instead.';
  end if;

  update public.restaurant_orders
  set status = case
        when status = 'open' and v_target_sent_total > 0 then 'sent_to_kitchen'
        else status
      end,
      kitchen_sent_at = case
        when status = 'open' and v_target_sent_total > 0
          then coalesce(kitchen_sent_at, v_source.kitchen_sent_at, now())
        else kitchen_sent_at
      end,
      updated_at = now()
  where id = p_target_order_id
    and tenant_id = p_tenant_id;

  update public.restaurant_orders
  set status = case
        when v_source_sent_remaining <= 0
         and status in ('sent_to_kitchen', 'preparing', 'ready', 'served')
          then 'open'
        else status
      end,
      kitchen_sent_at = case
        when v_source_sent_remaining <= 0 then null
        else kitchen_sent_at
      end,
      ready_at = case
        when v_source_sent_remaining <= 0 then null
        else ready_at
      end,
      served_at = case
        when v_source_sent_remaining <= 0 then null
        else served_at
      end,
      updated_at = now()
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
    v_source.table_id,
    v_target.table_id,
    'move_items',
    'Moved ' || v_rows || ' item line(s), quantity ' || v_moved_total ||
      ' from ' || v_source.order_number || ' to ' || v_target.order_number ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_source_order_id::text,
    'move_items_source'
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_target_order_id::text,
    'move_items_target'
  );

  return jsonb_build_object(
    'success', true,
    'source_order_id', p_source_order_id,
    'source_order_number', v_source.order_number,
    'source_table_id', v_source.table_id,
    'source_table_name', v_source_table_name,
    'source_remaining_quantity', v_source_remaining,
    'target_order_id', p_target_order_id,
    'target_order_number', v_target.order_number,
    'target_table_id', v_target.table_id,
    'target_table_name', v_target_table_name,
    'item_lines_moved', v_rows,
    'quantity_moved', v_moved_total,
    'already_sent_quantity_moved', v_target_sent_total,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_order_move_items_v610(
  uuid, uuid, uuid, uuid, jsonb, text
) from public, anon;

grant execute on function public.restaurant_order_move_items_v610(
  uuid, uuid, uuid, uuid, jsonb, text
) to authenticated, service_role;
