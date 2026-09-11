alter table public.restaurant_orders
  add column if not exists merged_into_order_id uuid null,
  add column if not exists merged_at timestamptz null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.restaurant_orders'::regclass
      and conname = 'restaurant_orders_merged_into_order_id_fkey'
  ) then
    alter table public.restaurant_orders
      add constraint restaurant_orders_merged_into_order_id_fkey
      foreign key (merged_into_order_id)
      references public.restaurant_orders(id)
      on delete set null;
  end if;
end
$$;

create index if not exists idx_restaurant_orders_merged_into
  on public.restaurant_orders(tenant_id, merged_into_order_id)
  where merged_into_order_id is not null;

create or replace function public.restaurant_orders_merge_v610(
  p_tenant_id uuid,
  p_target_order_id uuid,
  p_source_order_id uuid,
  p_device_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_target public.restaurant_orders%rowtype;
  v_source public.restaurant_orders%rowtype;
  v_source_table_id uuid;
  v_target_table_id uuid;
  v_source_order_number text;
  v_target_order_number text;
  v_source_item_count integer := 0;
  v_source_kot_count integer := 0;
  v_note text;
begin
  if p_target_order_id is null or p_source_order_id is null then
    raise exception 'Target and source restaurant orders are required';
  end if;

  if p_target_order_id = p_source_order_id then
    raise exception 'Cannot merge a restaurant order into itself';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');

  perform 1
  from public.restaurant_orders
  where tenant_id = p_tenant_id
    and id in (p_target_order_id, p_source_order_id)
  order by id
  for update;

  select *
  into v_target
  from public.restaurant_orders
  where id = p_target_order_id
    and tenant_id = p_tenant_id;

  if not found then
    raise exception 'Target restaurant order not found';
  end if;

  select *
  into v_source
  from public.restaurant_orders
  where id = p_source_order_id
    and tenant_id = p_tenant_id;

  if not found then
    raise exception 'Source restaurant order not found';
  end if;

  if v_source.merged_into_order_id = p_target_order_id then
    return jsonb_build_object(
      'success', true,
      'idempotent', true,
      'target_order_id', p_target_order_id,
      'source_order_id', p_source_order_id,
      'restaurant_engine', 'v6.1'
    );
  end if;

  if v_source.merged_into_order_id is not null then
    raise exception 'Source order was already merged into another restaurant order';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    v_target.location_id,
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

  if v_target.location_id is distinct from v_source.location_id then
    raise exception 'Restaurant orders must belong to the same location';
  end if;

  if v_target.order_type <> 'dine_in' or v_source.order_type <> 'dine_in' then
    raise exception 'Only dine-in orders can be merged';
  end if;

  if v_target.status in ('billed', 'cancelled') or v_target.sale_id is not null then
    raise exception 'Target restaurant order is closed';
  end if;

  if v_source.status in ('billed', 'cancelled') or v_source.sale_id is not null then
    raise exception 'Source restaurant order is closed';
  end if;

  if v_target.table_id is null or v_source.table_id is null then
    raise exception 'Both restaurant orders must have tables before merge';
  end if;

  v_source_table_id := v_source.table_id;
  v_target_table_id := v_target.table_id;
  v_source_order_number := v_source.order_number;
  v_target_order_number := v_target.order_number;

  select count(*)
  into v_source_item_count
  from public.restaurant_order_items
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  select count(*)
  into v_source_kot_count
  from public.restaurant_kots
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  update public.restaurant_order_items
  set order_id = p_target_order_id
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  update public.restaurant_kots
  set order_id = p_target_order_id
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  update public.restaurant_kot_items
  set order_id = p_target_order_id
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  delete from public.restaurant_waiter_assignments
  where tenant_id = p_tenant_id
    and order_id = p_source_order_id;

  update public.restaurant_orders
  set guest_count = least(999, greatest(1, guest_count + v_source.guest_count)),
      status = case
        when status = 'open' and v_source.status <> 'open' then 'sent_to_kitchen'
        else status
      end,
      kitchen_sent_at = case
        when kitchen_sent_at is null then v_source.kitchen_sent_at
        when v_source.kitchen_sent_at is null then kitchen_sent_at
        else least(kitchen_sent_at, v_source.kitchen_sent_at)
      end,
      updated_at = now()
  where id = p_target_order_id
    and tenant_id = p_tenant_id;

  update public.restaurant_orders
  set status = 'cancelled',
      table_id = null,
      cancelled_at = now(),
      cancelled_reason = 'Merged into ' || v_target_order_number ||
        case when v_note is null then '' else ' | ' || v_note end,
      merged_into_order_id = p_target_order_id,
      merged_at = now(),
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
    p_target_order_id,
    v_source_table_id,
    v_target_table_id,
    'merge',
    'Merged ' || v_source_order_number || ' into ' || v_target_order_number ||
      case when v_note is null then '' else ' | ' || v_note end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_target_order_id::text,
    'merge_target'
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_source_order_id::text,
    'merge_source'
  );

  return jsonb_build_object(
    'success', true,
    'target_order_id', p_target_order_id,
    'target_order_number', v_target_order_number,
    'target_table_id', v_target_table_id,
    'source_order_id', p_source_order_id,
    'source_order_number', v_source_order_number,
    'source_table_id', v_source_table_id,
    'items_moved', v_source_item_count,
    'kots_moved', v_source_kot_count,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

revoke all on function public.restaurant_orders_merge_v610(
  uuid, uuid, uuid, uuid, text
) from public, anon;

grant execute on function public.restaurant_orders_merge_v610(
  uuid, uuid, uuid, uuid, text
) to authenticated, service_role;
