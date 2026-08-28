-- FLEXI ERP V3.1 - Restaurant tables, KOT, dine-in/takeaway/delivery workflow.

create table if not exists public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete cascade,
  tracking_code text,
  table_code text not null,
  name text not null,
  capacity integer not null default 4 check(capacity>0),
  area text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,location_id,table_code)
);
create unique index if not exists ux_restaurant_tables_tracking on public.restaurant_tables(tenant_id,tracking_code) where tracking_code is not null;
alter table public.restaurant_tables enable row level security;revoke all on public.restaurant_tables from anon,authenticated;

create table if not exists public.restaurant_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  tracking_code text,
  order_number text not null,
  order_type text not null check(order_type in ('dine_in','takeaway','delivery')),
  table_id uuid references public.restaurant_tables(id) on delete set null,
  customer_id uuid,
  status text not null default 'open' check(status in ('open','sent_to_kitchen','preparing','ready','served','billed','cancelled')),
  preparation_minutes integer not null default 15 check(preparation_minutes>=0),
  chef_note text,
  delivery_address text,
  opened_at timestamptz not null default now(),
  kitchen_sent_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  billed_at timestamptz,
  sale_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(tenant_id,order_number)
);
create unique index if not exists ux_restaurant_orders_tracking on public.restaurant_orders(tenant_id,tracking_code) where tracking_code is not null;
create index if not exists idx_restaurant_orders_live on public.restaurant_orders(tenant_id,location_id,status,opened_at desc);
alter table public.restaurant_orders enable row level security;revoke all on public.restaurant_orders from anon,authenticated;

create table if not exists public.restaurant_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null,
  quantity numeric(18,4) not null check(quantity>0),
  unit_price numeric(18,2) not null default 0,
  discount_amount numeric(18,2) not null default 0,
  tax_rate numeric(9,4) not null default 0,
  item_note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_restaurant_order_items_order on public.restaurant_order_items(order_id);
alter table public.restaurant_order_items enable row level security;revoke all on public.restaurant_order_items from anon,authenticated;

create table if not exists public.restaurant_kots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete set null,
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  tracking_code text,
  kot_number text not null,
  status text not null default 'queued' check(status in ('queued','preparing','ready','served','cancelled')),
  note text,
  sent_at timestamptz not null default now(),
  started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  unique(tenant_id,kot_number)
);
create unique index if not exists ux_restaurant_kots_tracking on public.restaurant_kots(tenant_id,tracking_code) where tracking_code is not null;
alter table public.restaurant_kots enable row level security;revoke all on public.restaurant_kots from anon,authenticated;

create or replace function private.restaurant_table_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'restaurant_tables','TBL'); end if;return new;end $$;
drop trigger if exists trg_restaurant_table_tracking on public.restaurant_tables;create trigger trg_restaurant_table_tracking before insert on public.restaurant_tables for each row execute function private.restaurant_table_tracking();

create or replace function private.restaurant_order_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'restaurant_orders','ORD'); end if;if new.order_number is null or trim(new.order_number)='' then new.order_number:='ORD-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(new.id::text,'-',''),1,5)); end if;return new;end $$;
drop trigger if exists trg_restaurant_order_tracking on public.restaurant_orders;create trigger trg_restaurant_order_tracking before insert on public.restaurant_orders for each row execute function private.restaurant_order_tracking();

create or replace function private.restaurant_kot_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'restaurant_kots','KOT'); end if;if new.kot_number is null or trim(new.kot_number)='' then new.kot_number:='KOT-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(new.id::text,'-',''),1,5)); end if;return new;end $$;
drop trigger if exists trg_restaurant_kot_tracking on public.restaurant_kots;create trigger trg_restaurant_kot_tracking before insert on public.restaurant_kots for each row execute function private.restaurant_kot_tracking();

create or replace function public.restaurant_tables_list(p_tenant_id uuid,p_location_id uuid default null)
returns setof public.restaurant_tables language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query select * from public.restaurant_tables where tenant_id=p_tenant_id and (p_location_id is null or location_id=p_location_id) order by area nulls first,table_code;
end $$;
grant execute on function public.restaurant_tables_list(uuid,uuid) to authenticated;

create or replace function public.restaurant_table_save(p_tenant_id uuid,p_table_id uuid,p_location_id uuid,p_table_code text,p_name text,p_capacity integer,p_area text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;if not private.erp_has_permission(p_tenant_id,'restaurant.manage') then raise exception 'Permission denied'; end if;
  if p_table_id is null then insert into public.restaurant_tables(tenant_id,location_id,table_code,name,capacity,area,active) values(p_tenant_id,p_location_id,upper(trim(p_table_code)),trim(p_name),greatest(coalesce(p_capacity,4),1),nullif(trim(p_area),''),coalesce(p_active,true)) returning id into v_id;
  else update public.restaurant_tables set location_id=p_location_id,table_code=upper(trim(p_table_code)),name=trim(p_name),capacity=greatest(coalesce(p_capacity,4),1),area=nullif(trim(p_area),''),active=coalesce(p_active,true),updated_at=now() where id=p_table_id and tenant_id=p_tenant_id returning id into v_id;end if;
  if v_id is null then raise exception 'Table not found';end if;return v_id;
end $$;
grant execute on function public.restaurant_table_save(uuid,uuid,uuid,text,text,integer,text,boolean) to authenticated;

create or replace function public.restaurant_orders_list(p_tenant_id uuid,p_location_id uuid default null,p_live_only boolean default true,p_limit integer default 200)
returns table(id uuid,tracking_code text,order_number text,order_type text,table_id uuid,table_name text,customer_id uuid,customer_name text,status text,preparation_minutes integer,chef_note text,delivery_address text,opened_at timestamptz,kitchen_sent_at timestamptz,ready_at timestamptz,sale_id uuid,total numeric)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query select o.id,o.tracking_code,o.order_number,o.order_type,o.table_id,t.name,o.customer_id,c.name,o.status,o.preparation_minutes,o.chef_note,o.delivery_address,o.opened_at,o.kitchen_sent_at,o.ready_at,o.sale_id,
    coalesce((select sum(greatest(i.quantity*i.unit_price-i.discount_amount,0)*(1+i.tax_rate/100)) from public.restaurant_order_items i where i.order_id=o.id),0)::numeric
  from public.restaurant_orders o left join public.restaurant_tables t on t.id=o.table_id left join public.customers c on c.id=o.customer_id
  where o.tenant_id=p_tenant_id and (p_location_id is null or o.location_id=p_location_id) and (not p_live_only or o.status not in ('billed','cancelled'))
  order by o.opened_at desc limit greatest(1,least(coalesce(p_limit,200),1000));
end $$;
grant execute on function public.restaurant_orders_list(uuid,uuid,boolean,integer) to authenticated;

create or replace function public.restaurant_order_detail(p_tenant_id uuid,p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select jsonb_build_object(
    'order',to_jsonb(o),
    'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at) from public.restaurant_order_items i where i.order_id=o.id),'[]'::jsonb),
    'kots',coalesce((select jsonb_agg(to_jsonb(k) order by k.sent_at) from public.restaurant_kots k where k.order_id=o.id),'[]'::jsonb)
  ) into v from public.restaurant_orders o where o.id=p_order_id and o.tenant_id=p_tenant_id;
  if v is null then raise exception 'Order not found';end if;return v;
end $$;
grant execute on function public.restaurant_order_detail(uuid,uuid) to authenticated;

create or replace function public.restaurant_order_create(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_order_type text,p_table_id uuid,p_customer_id uuid,p_preparation_minutes integer,p_chef_note text,p_delivery_address text,p_items jsonb
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid:=gen_random_uuid();v_order text;v_track text;x jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'restaurant.order') and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then raise exception 'Permission denied';end if;
  if p_order_type not in ('dine_in','takeaway','delivery') then raise exception 'Invalid order type';end if;
  if p_order_type='dine_in' and p_table_id is null then raise exception 'Choose a table';end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one item';end if;
  insert into public.restaurant_orders(id,tenant_id,location_id,device_id,order_number,order_type,table_id,customer_id,preparation_minutes,chef_note,delivery_address,created_by)
  values(v_id,p_tenant_id,p_location_id,p_device_id,'',p_order_type,p_table_id,p_customer_id,greatest(coalesce(p_preparation_minutes,15),0),nullif(trim(p_chef_note),''),nullif(trim(p_delivery_address),''),auth.uid()) returning order_number,tracking_code into v_order,v_track;
  for x in select * from jsonb_array_elements(p_items) loop
    insert into public.restaurant_order_items(order_id,tenant_id,variant_id,quantity,unit_price,discount_amount,tax_rate,item_note)
    values(v_id,p_tenant_id,(x->>'variant_id')::uuid,(x->>'quantity')::numeric,coalesce(nullif(x->>'unit_price','')::numeric,0),coalesce(nullif(x->>'discount_amount','')::numeric,0),coalesce(nullif(x->>'tax_rate','')::numeric,0),nullif(trim(x->>'item_note'),''));
  end loop;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by) values(p_tenant_id,'restaurant_order',v_id,p_location_id,p_device_id,auth.uid()) on conflict do nothing;
  return jsonb_build_object('order_id',v_id,'order_number',v_order,'tracking_code',v_track);
end $$;
grant execute on function public.restaurant_order_create(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb) to authenticated;

create or replace function public.restaurant_kot_send(p_tenant_id uuid,p_order_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_order public.restaurant_orders%rowtype;v_id uuid:=gen_random_uuid();v_no text;v_track text;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if not private.erp_has_permission(p_tenant_id,'restaurant.kot') and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then raise exception 'Permission denied';end if;
  select * into v_order from public.restaurant_orders where id=p_order_id and tenant_id=p_tenant_id for update;if v_order.id is null then raise exception 'Order not found';end if;if v_order.status in ('billed','cancelled') then raise exception 'Order is closed';end if;
  insert into public.restaurant_kots(id,tenant_id,location_id,order_id,kot_number,note) values(v_id,p_tenant_id,v_order.location_id,p_order_id,'',coalesce(nullif(trim(p_note),''),v_order.chef_note)) returning kot_number,tracking_code into v_no,v_track;
  update public.restaurant_orders set status='sent_to_kitchen',kitchen_sent_at=coalesce(kitchen_sent_at,now()),updated_at=now() where id=p_order_id;
  return jsonb_build_object('kot_id',v_id,'kot_number',v_no,'tracking_code',v_track);
end $$;
grant execute on function public.restaurant_kot_send(uuid,uuid,text) to authenticated;

create or replace function public.restaurant_order_set_status(p_tenant_id uuid,p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if not private.erp_has_permission(p_tenant_id,'restaurant.kot') and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then raise exception 'Permission denied';end if;
  if p_status not in ('preparing','ready','served','cancelled') then raise exception 'Invalid status';end if;
  update public.restaurant_orders set status=p_status,ready_at=case when p_status='ready' then now() else ready_at end,served_at=case when p_status='served' then now() else served_at end,updated_at=now() where id=p_order_id and tenant_id=p_tenant_id and status not in ('billed','cancelled');
  if not found then raise exception 'Order not found or closed';end if;
  update public.restaurant_kots set status=case when p_status='preparing' then 'preparing' when p_status='ready' then 'ready' when p_status='served' then 'served' when p_status='cancelled' then 'cancelled' else status end,started_at=case when p_status='preparing' then coalesce(started_at,now()) else started_at end,ready_at=case when p_status='ready' then coalesce(ready_at,now()) else ready_at end,served_at=case when p_status='served' then coalesce(served_at,now()) else served_at end where order_id=p_order_id and status not in ('served','cancelled');
end $$;
grant execute on function public.restaurant_order_set_status(uuid,uuid,text) to authenticated;

create or replace function public.restaurant_order_mark_billed(p_tenant_id uuid,p_order_id uuid,p_sale_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if not private.erp_has_permission(p_tenant_id,'restaurant.order') and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then raise exception 'Permission denied';end if;
  if not exists(select 1 from public.sales where id=p_sale_id and tenant_id=p_tenant_id) then raise exception 'Sale not found';end if;
  update public.restaurant_orders set status='billed',sale_id=p_sale_id,billed_at=now(),updated_at=now() where id=p_order_id and tenant_id=p_tenant_id and status<>'cancelled';
  if not found then raise exception 'Order not found';end if;
end $$;
grant execute on function public.restaurant_order_mark_billed(uuid,uuid,uuid) to authenticated;

select 'V3.1 restaurant workflow ready' as status;

create or replace function public.restaurant_order_mark_billed_by_reference(p_tenant_id uuid,p_order_id uuid,p_sale_number text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_sale_id uuid;begin
  select id into v_sale_id from public.sales where tenant_id=p_tenant_id and sale_number=p_sale_number;
  if v_sale_id is null then raise exception 'Sale not found';end if;
  perform public.restaurant_order_mark_billed(p_tenant_id,p_order_id,v_sale_id);
end $$;
grant execute on function public.restaurant_order_mark_billed_by_reference(uuid,uuid,text) to authenticated;
