-- THQ ERP V4.8.2 — Pricing Engine
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values('pricing','Pricing','Price lists, customer pricing and quantity-based pricing','Commerce',false,18,true,false,true)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_active=true,is_beta=false,sort_order=excluded.sort_order;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select distinct tm.tenant_id,'pricing',true from public.tenant_modules tm
where tm.enabled and tm.module_key in('sales','inventory','customers')
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.business_template_modules(template_id,module_key)
select distinct btm.template_id,'pricing' from public.business_template_modules btm where btm.module_key in('sales','inventory') on conflict do nothing;
insert into public.subscription_plan_modules(plan_id,module_key)
select distinct spm.plan_id,'pricing' from public.subscription_plan_modules spm where spm.module_key in('sales','inventory') on conflict do nothing;

-- Add Pricing to Client navigation under an existing default root when available.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'client','pricing','module','pricing',p.id,'Pricing','sell',62
from public.app_menu_nodes_v45 p where p.tenant_id is null and p.app_key='client' and p.node_key='overview'
on conflict do nothing;
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select p.tenant_id,'client','pricing','module','pricing',p.id,'Pricing','sell',62
from public.app_menu_nodes_v45 p where p.tenant_id is not null and p.app_key='client' and p.node_key='overview'
and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p.tenant_id and tm.module_key='pricing' and tm.enabled)
on conflict do nothing;

create table if not exists public.price_lists_v482(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null,name text not null,description text,is_default boolean not null default false,system_list boolean not null default false,
 active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,code));
create unique index if not exists ux_price_lists_v482_default on public.price_lists_v482(tenant_id) where is_default and active;
create index if not exists idx_price_lists_v482_tenant on public.price_lists_v482(tenant_id,active,name);
alter table public.price_lists_v482 enable row level security;
drop policy if exists price_lists_v482_read on public.price_lists_v482;
create policy price_lists_v482_read on public.price_lists_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.price_lists_v482 from authenticated; grant select on public.price_lists_v482 to authenticated;

create table if not exists public.price_list_items_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 price_list_id uuid not null references public.price_lists_v482(id) on delete cascade,variant_id uuid not null references public.product_variants(id) on delete cascade,
 unit_id uuid not null references public.inventory_units_v481(id) on delete restrict,min_quantity numeric not null default 1 check(min_quantity>0),
 unit_price numeric not null check(unit_price>=0),active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,price_list_id,variant_id,unit_id,min_quantity));
create index if not exists idx_price_list_items_v482_lookup on public.price_list_items_v482(tenant_id,price_list_id,variant_id,unit_id,min_quantity desc) where active;
alter table public.price_list_items_v482 enable row level security;
drop policy if exists price_list_items_v482_read on public.price_list_items_v482;
create policy price_list_items_v482_read on public.price_list_items_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.price_list_items_v482 from authenticated; grant select on public.price_list_items_v482 to authenticated;

create table if not exists public.customer_pricing_profiles_v482(
 tenant_id uuid not null references public.tenants(id) on delete cascade,customer_id uuid not null references public.customers(id) on delete cascade,
 price_list_id uuid references public.price_lists_v482(id) on delete set null,active boolean not null default true,updated_at timestamptz not null default now(),updated_by uuid,
 primary key(tenant_id,customer_id));
alter table public.customer_pricing_profiles_v482 enable row level security;
drop policy if exists customer_pricing_profiles_v482_read on public.customer_pricing_profiles_v482;
create policy customer_pricing_profiles_v482_read on public.customer_pricing_profiles_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.customer_pricing_profiles_v482 from authenticated; grant select on public.customer_pricing_profiles_v482 to authenticated;

create table if not exists public.customer_prices_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,customer_id uuid not null references public.customers(id) on delete cascade,
 variant_id uuid not null references public.product_variants(id) on delete cascade,unit_id uuid not null references public.inventory_units_v481(id) on delete restrict,
 min_quantity numeric not null default 1 check(min_quantity>0),unit_price numeric not null check(unit_price>=0),active boolean not null default true,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,customer_id,variant_id,unit_id,min_quantity));
create index if not exists idx_customer_prices_v482_lookup on public.customer_prices_v482(tenant_id,customer_id,variant_id,unit_id,min_quantity desc) where active;
alter table public.customer_prices_v482 enable row level security;
drop policy if exists customer_prices_v482_read on public.customer_prices_v482;
create policy customer_prices_v482_read on public.customer_prices_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.customer_prices_v482 from authenticated; grant select on public.customer_prices_v482 to authenticated;

create or replace function private.v482_seed_price_lists(p_tenant_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 insert into public.price_lists_v482(tenant_id,code,name,description,is_default,system_list) values
 (p_tenant_id,'RETAIL','Retail','Default counter/retail selling price',true,true),
 (p_tenant_id,'WHOLESALE','Wholesale','Wholesale customer pricing',false,true),
 (p_tenant_id,'DEALER','Dealer','Dealer pricing',false,true),
 (p_tenant_id,'CONTRACTOR','Contractor','Contractor/project pricing',false,true)
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description,system_list=true;
 if not exists(select 1 from public.price_lists_v482 pl where pl.tenant_id=p_tenant_id and pl.active and pl.is_default) then
   update public.price_lists_v482 set is_default=true where tenant_id=p_tenant_id and code='RETAIL';
 end if;
end$$;
revoke all on function private.v482_seed_price_lists(uuid) from public;
do $$declare r record;begin for r in select t.id from public.tenants t loop perform private.v482_seed_price_lists(r.id);end loop;end$$;
create or replace function private.v482_seed_price_lists_trigger() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$begin perform private.v482_seed_price_lists(new.id);return new;end$$;
drop trigger if exists trg_v482_seed_price_lists on public.tenants;
create trigger trg_v482_seed_price_lists after insert on public.tenants for each row execute function private.v482_seed_price_lists_trigger();

create or replace function private.v482_pricing_manage_allowed(p_tenant_id uuid) returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
 select private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'inventory.manage') or private.erp_has_permission(p_tenant_id,'sales.manage')
$$;
revoke all on function private.v482_pricing_manage_allowed(uuid) from public;

create or replace function public.pricing_lists_v482(p_tenant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select jsonb_build_object('price_list_id',pl.id,'code',pl.code,'name',pl.name,'description',pl.description,'is_default',pl.is_default,'system_list',pl.system_list,'active',pl.active)
 from public.price_lists_v482 pl where pl.tenant_id=p_tenant_id order by pl.is_default desc,pl.name;
end$$;
grant execute on function public.pricing_lists_v482(uuid) to authenticated;

create or replace function public.pricing_list_save_v482(p_tenant_id uuid,p_price_list_id uuid,p_code text,p_name text,p_description text,p_is_default boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_id uuid;begin
 if not private.v482_pricing_manage_allowed(p_tenant_id) then raise exception 'Pricing manage permission required';end if;
 if trim(coalesce(p_code,''))='' or trim(coalesce(p_name,''))='' then raise exception 'Code and name are required';end if;
 if p_is_default then update public.price_lists_v482 set is_default=false,updated_at=now() where tenant_id=p_tenant_id;end if;
 if p_price_list_id is null then
   insert into public.price_lists_v482(tenant_id,code,name,description,is_default,active) values(p_tenant_id,upper(trim(p_code)),trim(p_name),nullif(trim(coalesce(p_description,'')),''),p_is_default,p_active) returning id into v_id;
 else
   update public.price_lists_v482 set code=upper(trim(p_code)),name=trim(p_name),description=nullif(trim(coalesce(p_description,'')),''),is_default=p_is_default,active=p_active,updated_at=now() where id=p_price_list_id and tenant_id=p_tenant_id returning id into v_id;
   if v_id is null then raise exception 'Price list not found';end if;
 end if;
 if not exists(select 1 from public.price_lists_v482 pl where pl.tenant_id=p_tenant_id and pl.active and pl.is_default) then update public.price_lists_v482 set is_default=true where id=v_id;end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','price_list',v_id::text,'save'); return v_id;
end$$;
grant execute on function public.pricing_list_save_v482(uuid,uuid,text,text,text,boolean,boolean) to authenticated;

create or replace function public.pricing_rules_v482(p_tenant_id uuid,p_price_list_id uuid,p_variant_id uuid default null) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select jsonb_build_object('rule_id',r.id,'price_list_id',r.price_list_id,'price_list_name',pl.name,'variant_id',r.variant_id,'product_name',p.name,'sku',pv.sku,'unit_id',r.unit_id,'unit_code',u.code,'unit_name',u.name,'min_quantity',r.min_quantity,'unit_price',r.unit_price,'active',r.active)
 from public.price_list_items_v482 r join public.price_lists_v482 pl on pl.id=r.price_list_id join public.product_variants pv on pv.id=r.variant_id join public.products p on p.id=pv.product_id join public.inventory_units_v481 u on u.id=r.unit_id
 where r.tenant_id=p_tenant_id and r.price_list_id=p_price_list_id and (p_variant_id is null or r.variant_id=p_variant_id) order by p.name,u.name,r.min_quantity;
end$$;
grant execute on function public.pricing_rules_v482(uuid,uuid,uuid) to authenticated;

create or replace function public.pricing_rule_save_v482(p_tenant_id uuid,p_rule_id uuid,p_price_list_id uuid,p_variant_id uuid,p_unit_id uuid,p_min_quantity numeric,p_unit_price numeric,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_id uuid;begin
 if not private.v482_pricing_manage_allowed(p_tenant_id) then raise exception 'Pricing manage permission required';end if;
 if coalesce(p_min_quantity,0)<=0 then raise exception 'Minimum quantity must be greater than zero';end if;
 if coalesce(p_unit_price,-1)<0 then raise exception 'Price cannot be negative';end if;
 if not exists(select 1 from public.price_lists_v482 pl where pl.id=p_price_list_id and pl.tenant_id=p_tenant_id and pl.active) then raise exception 'Price list not found';end if;
 if not exists(select 1 from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=p_unit_id and pu.active and pu.allow_sale) then raise exception 'Unit is not enabled for sale on this product';end if;
 if p_rule_id is null then
  insert into public.price_list_items_v482(tenant_id,price_list_id,variant_id,unit_id,min_quantity,unit_price,active) values(p_tenant_id,p_price_list_id,p_variant_id,p_unit_id,p_min_quantity,p_unit_price,p_active)
  on conflict(tenant_id,price_list_id,variant_id,unit_id,min_quantity) do update set unit_price=excluded.unit_price,active=excluded.active,updated_at=now() returning id into v_id;
 else
  update public.price_list_items_v482 set price_list_id=p_price_list_id,variant_id=p_variant_id,unit_id=p_unit_id,min_quantity=p_min_quantity,unit_price=p_unit_price,active=p_active,updated_at=now() where id=p_rule_id and tenant_id=p_tenant_id returning id into v_id;
  if v_id is null then raise exception 'Pricing rule not found';end if;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','price_rule',v_id::text,'save');return v_id;
end$$;
grant execute on function public.pricing_rule_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean) to authenticated;

create or replace function public.customer_pricing_profile_set_v482(p_tenant_id uuid,p_customer_id uuid,p_price_list_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if not private.v482_pricing_manage_allowed(p_tenant_id) then raise exception 'Pricing manage permission required';end if;
 if not exists(select 1 from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id) then raise exception 'Customer not found';end if;
 if p_price_list_id is not null and not exists(select 1 from public.price_lists_v482 pl where pl.id=p_price_list_id and pl.tenant_id=p_tenant_id and pl.active) then raise exception 'Price list not found';end if;
 insert into public.customer_pricing_profiles_v482(tenant_id,customer_id,price_list_id,active,updated_at,updated_by) values(p_tenant_id,p_customer_id,p_price_list_id,true,now(),auth.uid())
 on conflict(tenant_id,customer_id) do update set price_list_id=excluded.price_list_id,active=true,updated_at=now(),updated_by=auth.uid();
 perform private.thq_sync_bump_v480(p_tenant_id,'parties','customer_pricing',p_customer_id::text,'save');
end$$;
grant execute on function public.customer_pricing_profile_set_v482(uuid,uuid,uuid) to authenticated;

create or replace function public.customer_price_save_v482(p_tenant_id uuid,p_rule_id uuid,p_customer_id uuid,p_variant_id uuid,p_unit_id uuid,p_min_quantity numeric,p_unit_price numeric,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_id uuid;begin
 if not private.v482_pricing_manage_allowed(p_tenant_id) then raise exception 'Pricing manage permission required';end if;
 if coalesce(p_min_quantity,0)<=0 or coalesce(p_unit_price,-1)<0 then raise exception 'Valid quantity and price are required';end if;
 if not exists(select 1 from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id) then raise exception 'Customer not found';end if;
 if not exists(select 1 from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=p_unit_id and pu.active and pu.allow_sale) then raise exception 'Unit is not enabled for sale on this product';end if;
 if p_rule_id is null then
  insert into public.customer_prices_v482(tenant_id,customer_id,variant_id,unit_id,min_quantity,unit_price,active) values(p_tenant_id,p_customer_id,p_variant_id,p_unit_id,p_min_quantity,p_unit_price,p_active)
  on conflict(tenant_id,customer_id,variant_id,unit_id,min_quantity) do update set unit_price=excluded.unit_price,active=excluded.active,updated_at=now() returning id into v_id;
 else
  update public.customer_prices_v482 set customer_id=p_customer_id,variant_id=p_variant_id,unit_id=p_unit_id,min_quantity=p_min_quantity,unit_price=p_unit_price,active=p_active,updated_at=now() where id=p_rule_id and tenant_id=p_tenant_id returning id into v_id;
  if v_id is null then raise exception 'Customer price rule not found';end if;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'parties','customer_price',p_customer_id::text,'save');return v_id;
end$$;
grant execute on function public.customer_price_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean) to authenticated;

create or replace function public.customer_prices_v482(p_tenant_id uuid,p_customer_id uuid,p_variant_id uuid default null) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select jsonb_build_object('rule_id',r.id,'customer_id',r.customer_id,'variant_id',r.variant_id,'product_name',p.name,'sku',pv.sku,'unit_id',r.unit_id,'unit_code',u.code,'unit_name',u.name,'min_quantity',r.min_quantity,'unit_price',r.unit_price,'active',r.active)
 from public.customer_prices_v482 r join public.product_variants pv on pv.id=r.variant_id join public.products p on p.id=pv.product_id join public.inventory_units_v481 u on u.id=r.unit_id
 where r.tenant_id=p_tenant_id and r.customer_id=p_customer_id and (p_variant_id is null or r.variant_id=p_variant_id) order by p.name,u.name,r.min_quantity;
end$$;
grant execute on function public.customer_prices_v482(uuid,uuid,uuid) to authenticated;

create or replace function private.pricing_resolve_v482_internal(p_tenant_id uuid,p_variant_id uuid,p_customer_id uuid,p_unit_id uuid,p_quantity numeric,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_price numeric;v_source text;v_list uuid;v_list_name text;v_factor numeric:=1;v_qty numeric:=greatest(coalesce(p_quantity,1),0.000001);v_unit_id uuid:=p_unit_id;begin
 if v_unit_id is null then select pu.unit_id into v_unit_id from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.active and pu.is_default_sale limit 1;end if;
 if v_unit_id is null then select pu.unit_id into v_unit_id from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.active and pu.is_base limit 1;end if;
 select pu.conversion_to_base into v_factor from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=v_unit_id and pu.active and pu.allow_sale;
 if v_factor is null then raise exception 'Sale unit is not enabled for this product';end if;
 if p_customer_id is not null then
  select cp.unit_price into v_price from public.customer_prices_v482 cp where cp.tenant_id=p_tenant_id and cp.customer_id=p_customer_id and cp.variant_id=p_variant_id and cp.unit_id=v_unit_id and cp.active and cp.min_quantity<=v_qty order by cp.min_quantity desc limit 1;
  if v_price is not null then v_source:='customer';end if;
 end if;
 if v_price is null then
  if p_customer_id is not null then select cpp.price_list_id into v_list from public.customer_pricing_profiles_v482 cpp where cpp.tenant_id=p_tenant_id and cpp.customer_id=p_customer_id and cpp.active;end if;
  if v_list is null then select pl.id into v_list from public.price_lists_v482 pl where pl.tenant_id=p_tenant_id and pl.active and pl.is_default limit 1;end if;
  if v_list is not null then
   select pli.unit_price,pl.name into v_price,v_list_name from public.price_list_items_v482 pli join public.price_lists_v482 pl on pl.id=pli.price_list_id
   where pli.tenant_id=p_tenant_id and pli.price_list_id=v_list and pli.variant_id=p_variant_id and pli.unit_id=v_unit_id and pli.active and pl.active and pli.min_quantity<=v_qty order by pli.min_quantity desc limit 1;
   if v_price is not null then v_source:='price_list';end if;
  end if;
 end if;
 if v_price is null then
  select coalesce(pu.sale_price,coalesce(lps.selling_price,pv.selling_price)*pu.conversion_to_base),case when pu.sale_price is not null then 'unit_price' when lps.selling_price is not null then 'location_price' else 'product_price' end
  into v_price,v_source from public.product_units_v481 pu join public.product_variants pv on pv.id=pu.variant_id
  left join public.location_product_settings lps on lps.tenant_id=p_tenant_id and lps.variant_id=p_variant_id and lps.location_id=p_location_id and lps.active
  where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=v_unit_id and pu.active limit 1;
 end if;
 return jsonb_build_object('variant_id',p_variant_id,'customer_id',p_customer_id,'unit_id',v_unit_id,'quantity',v_qty,'unit_price',coalesce(v_price,0),'source',coalesce(v_source,'product_price'),'price_list_id',v_list,'price_list_name',v_list_name);
end$$;
revoke all on function private.pricing_resolve_v482_internal(uuid,uuid,uuid,uuid,numeric,uuid) from public;

create or replace function public.pricing_resolve_v482(p_tenant_id uuid,p_variant_id uuid,p_customer_id uuid,p_unit_id uuid,p_quantity numeric,p_location_id uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return private.pricing_resolve_v482_internal(p_tenant_id,p_variant_id,p_customer_id,p_unit_id,p_quantity,p_location_id);
end$$;
grant execute on function public.pricing_resolve_v482(uuid,uuid,uuid,uuid,numeric,uuid) to authenticated;

create or replace function public.customers_list_v482(p_tenant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_id uuid;v_list uuid;v_name text;begin
 for r in select * from public.customers_list_v32(p_tenant_id) loop
  begin v_id:=coalesce(nullif(r->>'customer_id',''),nullif(r->>'id',''))::uuid;exception when others then v_id:=null;end;
  v_list:=null;v_name:=null;
  if v_id is not null then select cpp.price_list_id,pl.name into v_list,v_name from public.customer_pricing_profiles_v482 cpp left join public.price_lists_v482 pl on pl.id=cpp.price_list_id where cpp.tenant_id=p_tenant_id and cpp.customer_id=v_id and cpp.active;end if;
  return next r||jsonb_build_object('price_list_id',v_list,'price_list_name',v_name);
 end loop;return;
end$$;
grant execute on function public.customers_list_v482(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(130,'4.8.2','Pricing & Product Identification','Price lists, customer-specific pricing, quantity breaks and authoritative price resolution.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 130 pricing engine applied' as status;
