do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_order_modifiers_order_item_id_fkey'
      and conrelid='public.restaurant_order_modifiers'::regclass
  ) then
    alter table public.restaurant_order_modifiers
      add constraint restaurant_order_modifiers_order_item_id_fkey
      foreign key (order_item_id)
      references public.restaurant_order_items(id)
      on delete cascade
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_waiter_assignments_order_id_fkey'
      and conrelid='public.restaurant_waiter_assignments'::regclass
  ) then
    alter table public.restaurant_waiter_assignments
      add constraint restaurant_waiter_assignments_order_id_fkey
      foreign key (order_id)
      references public.restaurant_orders(id)
      on delete cascade
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_table_events_order_id_fkey'
      and conrelid='public.restaurant_table_events'::regclass
  ) then
    alter table public.restaurant_table_events
      add constraint restaurant_table_events_order_id_fkey
      foreign key (order_id)
      references public.restaurant_orders(id)
      on delete set null
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_table_events_from_table_id_fkey'
      and conrelid='public.restaurant_table_events'::regclass
  ) then
    alter table public.restaurant_table_events
      add constraint restaurant_table_events_from_table_id_fkey
      foreign key (from_table_id)
      references public.restaurant_tables(id)
      on delete set null
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_table_events_to_table_id_fkey'
      and conrelid='public.restaurant_table_events'::regclass
  ) then
    alter table public.restaurant_table_events
      add constraint restaurant_table_events_to_table_id_fkey
      foreign key (to_table_id)
      references public.restaurant_tables(id)
      on delete set null
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='restaurant_order_items_variant_id_tenant_id_fkey'
      and conrelid='public.restaurant_order_items'::regclass
  ) then
    alter table public.restaurant_order_items
      add constraint restaurant_order_items_variant_id_tenant_id_fkey
      foreign key (variant_id, tenant_id)
      references public.product_variants(id, tenant_id)
      deferrable initially deferred
      not valid;
  end if;
end
$$;

alter table public.restaurant_order_modifiers
  validate constraint restaurant_order_modifiers_order_item_id_fkey;

alter table public.restaurant_waiter_assignments
  validate constraint restaurant_waiter_assignments_order_id_fkey;

alter table public.restaurant_table_events
  validate constraint restaurant_table_events_order_id_fkey;

alter table public.restaurant_table_events
  validate constraint restaurant_table_events_from_table_id_fkey;

alter table public.restaurant_table_events
  validate constraint restaurant_table_events_to_table_id_fkey;

alter table public.restaurant_order_items
  validate constraint restaurant_order_items_variant_id_tenant_id_fkey;

create index if not exists idx_restaurant_order_modifiers_order_item
  on public.restaurant_order_modifiers(tenant_id, order_item_id);

create index if not exists idx_restaurant_order_items_tenant_order
  on public.restaurant_order_items(tenant_id, order_id);

create index if not exists idx_restaurant_table_events_order
  on public.restaurant_table_events(tenant_id, order_id, created_at desc)
  where order_id is not null;

create index if not exists idx_restaurant_table_events_from_table
  on public.restaurant_table_events(tenant_id, from_table_id, created_at desc)
  where from_table_id is not null;

create index if not exists idx_restaurant_table_events_to_table
  on public.restaurant_table_events(tenant_id, to_table_id, created_at desc)
  where to_table_id is not null;

create index if not exists idx_restaurant_orders_billed_analytics
  on public.restaurant_orders(tenant_id, location_id, billed_at desc)
  where status='billed' and billed_at is not null;

create index if not exists idx_restaurant_kots_history
  on public.restaurant_kots(tenant_id, location_id, sent_at desc);

create index if not exists idx_restaurant_tables_floor_layout
  on public.restaurant_tables(tenant_id, location_id, floor_name, sort_order, table_code)
  where active=true;
