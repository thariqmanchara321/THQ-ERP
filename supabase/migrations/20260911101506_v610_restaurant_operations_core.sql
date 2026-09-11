-- THQ ERP v6.1 Restaurant Operations Core
-- Recovered/mirrored from migration-test database truth for repository alignment.
-- This migration is intentionally idempotent so a fresh database can replay it safely.

alter table public.restaurant_orders
  add column if not exists guest_count integer not null default 1,
  add column if not exists waiter_user_id uuid null,
  add column if not exists order_note text null,
  add column if not exists bill_requested_at timestamptz null,
  add column if not exists cancelled_at timestamptz null,
  add column if not exists cancelled_reason text null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_orders'::regclass
      and conname='restaurant_orders_guest_count_check'
  ) then
    alter table public.restaurant_orders
      add constraint restaurant_orders_guest_count_check
      check (guest_count between 1 and 999);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_orders'::regclass
      and conname='restaurant_orders_waiter_user_id_fkey'
  ) then
    alter table public.restaurant_orders
      add constraint restaurant_orders_waiter_user_id_fkey
      foreign key (waiter_user_id)
      references auth.users(id)
      on delete set null;
  end if;
end
$$;

alter table public.restaurant_order_items
  add column if not exists kot_sent_quantity numeric not null default 0,
  add column if not exists cancelled_quantity numeric not null default 0,
  add column if not exists cancel_reason text null,
  add column if not exists cancelled_at timestamptz null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_order_items'::regclass
      and conname='restaurant_order_items_kot_sent_quantity_check'
  ) then
    alter table public.restaurant_order_items
      add constraint restaurant_order_items_kot_sent_quantity_check
      check (kot_sent_quantity >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_order_items'::regclass
      and conname='restaurant_order_items_cancelled_quantity_check'
  ) then
    alter table public.restaurant_order_items
      add constraint restaurant_order_items_cancelled_quantity_check
      check (cancelled_quantity >= 0 and cancelled_quantity <= quantity);
  end if;
end
$$;

alter table public.restaurant_tables
  add column if not exists operational_status text not null default 'available',
  add column if not exists floor_name text null,
  add column if not exists position_x numeric null,
  add column if not exists position_y numeric null,
  add column if not exists shape text not null default 'rect',
  add column if not exists sort_order integer not null default 0,
  add column if not exists reservation_name text null,
  add column if not exists reservation_phone text null,
  add column if not exists reservation_at timestamptz null,
  add column if not exists reservation_note text null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_tables'::regclass
      and conname='restaurant_tables_operational_status_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_operational_status_check
      check (operational_status in ('available','reserved','cleaning','out_of_service'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_tables'::regclass
      and conname='restaurant_tables_shape_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_shape_check
      check (shape in ('rect','round','square'));
  end if;
end
$$;

create index if not exists idx_restaurant_tables_layout
  on public.restaurant_tables(
    tenant_id,
    location_id,
    area,
    sort_order,
    table_code
  );

create table if not exists public.restaurant_waiter_assignments (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_id uuid not null,
  user_id uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  primary key (tenant_id, order_id)
);

alter table public.restaurant_waiter_assignments enable row level security;
revoke all on table public.restaurant_waiter_assignments from public, anon, authenticated;
grant select, insert, update, delete on table public.restaurant_waiter_assignments to service_role;

create table if not exists public.restaurant_table_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_id uuid null,
  from_table_id uuid null,
  to_table_id uuid null,
  event_type text not null
    check (event_type in ('transfer','merge','split','move_items','state','bill_request','clear')),
  note text null,
  created_by uuid null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.restaurant_table_events enable row level security;
revoke all on table public.restaurant_table_events from public, anon, authenticated;
grant select, insert, update, delete on table public.restaurant_table_events to service_role;

create or replace function public.restaurant_waiters_list_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid
)
returns table(user_id uuid, display_name text)
language plpgsql
security definer
set search_path to public, private, pg_temp
as $function$
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
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Permission denied';
  end if;

  return query
  select
    m.user_id,
    coalesce(nullif(trim(p.display_name),''),m.user_id::text)
  from public.tenant_memberships m
  left join public.profiles p on p.id=m.user_id
  where m.tenant_id=p_tenant_id
    and m.status='active'
  order by 2;
end
$function$;

create or replace function public.restaurant_order_create_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_order_type text,
  p_table_id uuid,
  p_customer_id uuid,
  p_preparation_minutes integer,
  p_chef_note text,
  p_delivery_address text,
  p_items jsonb,
  p_guest_count integer default 1,
  p_waiter_user_id uuid default null,
  p_order_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to public, private, pg_temp
as $function$
declare
  v jsonb;
  v_order_id uuid;
begin
  v:=public.restaurant_order_create_v32(
    p_tenant_id,
    p_location_id,
    p_device_id,
    p_order_type,
    p_table_id,
    p_customer_id,
    p_preparation_minutes,
    p_chef_note,
    p_delivery_address,
    p_items
  );

  v_order_id:=nullif(v->>'order_id','')::uuid;
  if v_order_id is null then
    raise exception 'Restaurant order was not created';
  end if;

  if p_waiter_user_id is not null
     and not exists(
       select 1
       from public.tenant_memberships m
       where m.tenant_id=p_tenant_id
         and m.user_id=p_waiter_user_id
         and m.status='active'
     ) then
    raise exception 'Selected waiter is not an active business user';
  end if;

  update public.restaurant_orders
  set guest_count=greatest(coalesce(p_guest_count,1),1),
      waiter_user_id=p_waiter_user_id,
      order_note=nullif(trim(coalesce(p_order_note,'')),''),
      updated_at=now()
  where id=v_order_id
    and tenant_id=p_tenant_id;

  if p_waiter_user_id is not null then
    insert into public.restaurant_waiter_assignments(
      tenant_id,
      order_id,
      user_id,
      assigned_at
    )
    values(
      p_tenant_id,
      v_order_id,
      p_waiter_user_id,
      now()
    )
    on conflict(tenant_id,order_id)
    do update set
      user_id=excluded.user_id,
      assigned_at=excluded.assigned_at;
  end if;

  return v || jsonb_build_object(
    'guest_count',greatest(coalesce(p_guest_count,1),1),
    'waiter_user_id',p_waiter_user_id,
    'restaurant_engine','v6.1'
  );
end
$function$;

create or replace function public.restaurant_order_update_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_table_id uuid default null,
  p_customer_id uuid default null,
  p_guest_count integer default null,
  p_waiter_user_id uuid default null,
  p_order_note text default null,
  p_chef_note text default null,
  p_delivery_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to public, private, pg_temp
as $function$
declare
  o public.restaurant_orders%rowtype;
begin
  select *
  into o
  from public.restaurant_orders
  where id=p_order_id
    and tenant_id=p_tenant_id
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
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant order permission denied';
  end if;

  if o.status in ('billed','cancelled') then
    raise exception 'Order is closed';
  end if;

  if p_table_id is not null
     and not exists(
       select 1
       from public.restaurant_tables t
       where t.id=p_table_id
         and t.tenant_id=p_tenant_id
         and t.location_id=o.location_id
         and t.active
     ) then
    raise exception 'Choose a table from this store';
  end if;

  if p_customer_id is not null
     and not exists(
       select 1
       from public.customers c
       where c.id=p_customer_id
         and c.tenant_id=p_tenant_id
         and coalesce(c.status,'active')='active'
     ) then
    raise exception 'Customer is not available';
  end if;

  if p_waiter_user_id is not null
     and not exists(
       select 1
       from public.tenant_memberships m
       where m.tenant_id=p_tenant_id
         and m.user_id=p_waiter_user_id
         and m.status='active'
     ) then
    raise exception 'Selected waiter is not an active business user';
  end if;

  update public.restaurant_orders
  set table_id=coalesce(p_table_id,table_id),
      customer_id=coalesce(p_customer_id,customer_id),
      guest_count=coalesce(greatest(p_guest_count,1),guest_count),
      waiter_user_id=p_waiter_user_id,
      order_note=case
        when p_order_note is null then order_note
        else nullif(trim(p_order_note),'')
      end,
      chef_note=case
        when p_chef_note is null then chef_note
        else nullif(trim(p_chef_note),'')
      end,
      delivery_address=case
        when p_delivery_address is null then delivery_address
        else nullif(trim(p_delivery_address),'')
      end,
      updated_at=now()
  where id=p_order_id
    and tenant_id=p_tenant_id;

  delete from public.restaurant_waiter_assignments
  where tenant_id=p_tenant_id
    and order_id=p_order_id;

  if p_waiter_user_id is not null then
    insert into public.restaurant_waiter_assignments(
      tenant_id,
      order_id,
      user_id,
      assigned_at
    )
    values(
      p_tenant_id,
      p_order_id,
      p_waiter_user_id,
      now()
    );
  end if;

  return public.restaurant_order_detail_v32(
    p_tenant_id,
    p_order_id,
    p_device_id
  );
end
$function$;

create or replace function public.restaurant_order_add_items_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to public, private, pg_temp
as $function$
declare
  o public.restaurant_orders%rowtype;
  x jsonb;
  v_priced jsonb;
  v_norm jsonb;
  v_variant uuid;
  v_unit uuid;
  v_qty numeric;
  v_factor numeric;
  v_unit_price numeric;
  v_tax numeric;
  v_discount numeric;
  v_source text;
  v_price_list uuid;
  v_price_name text;
  v_count integer:=0;
begin
  select *
  into o
  from public.restaurant_orders
  where id=p_order_id
    and tenant_id=p_tenant_id
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
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant order permission denied';
  end if;

  if o.status in ('billed','cancelled') then
    raise exception 'Order is closed';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Add at least one item';
  end if;

  v_priced:=private.v482_price_sale_items(
    p_tenant_id,
    o.customer_id,
    p_items,
    o.location_id
  );

  for x in
    select value
    from jsonb_array_elements(v_priced)
  loop
    v_norm:=private.v481_normalize_line(p_tenant_id,x,'sale');
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_unit:=nullif(v_norm->>'_entered_unit_id','')::uuid;
    v_qty:=coalesce(nullif(v_norm->>'_entered_quantity','')::numeric,0);
    v_factor:=coalesce(nullif(v_norm->>'_conversion_to_base','')::numeric,1);
    v_unit_price:=coalesce(nullif(v_norm->>'_entered_unit_price','')::numeric,0);
    v_discount:=greatest(coalesce(nullif(x->>'discount_amount','')::numeric,0),0);
    v_source:=nullif(x->>'_pricing_source','');
    v_price_list:=nullif(x->>'_price_list_id','')::uuid;
    v_price_name:=nullif(x->>'_price_list_name','');

    select coalesce(p.tax_rate,0)
    into v_tax
    from public.product_variants pv
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
    where pv.id=v_variant
      and pv.tenant_id=p_tenant_id;

    if not found then
      raise exception 'Product is not available for this business';
    end if;

    if v_qty<=0 then
      raise exception 'Restaurant item quantity must be greater than zero';
    end if;

    if v_discount>v_qty*v_unit_price then
      raise exception 'Restaurant item discount exceeds line value';
    end if;

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
    values(
      p_order_id,
      p_tenant_id,
      v_variant,
      v_qty,
      v_unit,
      v_factor,
      v_unit_price,
      v_discount,
      v_tax,
      nullif(trim(x->>'item_note'),''),
      coalesce(v_source,'product_price'),
      v_price_list,
      jsonb_strip_nulls(
        jsonb_build_object(
          'price_list_name',v_price_name,
          'resolved_at',now(),
          'engine','v6.1'
        )
      ),
      0,
      0
    );

    v_count:=v_count+1;
  end loop;

  update public.restaurant_orders
  set updated_at=now()
  where id=p_order_id
    and tenant_id=p_tenant_id;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    p_order_id::text,
    'add_items'
  );

  return jsonb_build_object(
    'success',true,
    'order_id',p_order_id,
    'items_added',v_count
  );
end
$function$;

revoke all on function public.restaurant_waiters_list_v610(uuid,uuid,uuid) from public, anon;
revoke all on function public.restaurant_order_create_v610(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb,integer,uuid,text) from public, anon;
revoke all on function public.restaurant_order_update_v610(uuid,uuid,uuid,uuid,uuid,integer,uuid,text,text,text) from public, anon;
revoke all on function public.restaurant_order_add_items_v610(uuid,uuid,uuid,jsonb) from public, anon;

grant execute on function public.restaurant_waiters_list_v610(uuid,uuid,uuid) to authenticated, service_role;
grant execute on function public.restaurant_order_create_v610(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb,integer,uuid,text) to authenticated, service_role;
grant execute on function public.restaurant_order_update_v610(uuid,uuid,uuid,uuid,uuid,integer,uuid,text,text,text) to authenticated, service_role;
grant execute on function public.restaurant_order_add_items_v610(uuid,uuid,uuid,jsonb) to authenticated, service_role;
