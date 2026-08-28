-- THQ ERP V4.8.2 — UPGRADE FROM MIGRATION 129 TO 134
-- Apply only to a database already at THQ ERP V4.8.1 / migration 129.

-- ============================================================================
-- 130_v482_pricing_engine.sql
-- ============================================================================

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

-- ============================================================================
-- 131_v482_product_identification.sql
-- ============================================================================

-- THQ ERP V4.8.2 — Product Identification
begin;

create table if not exists public.product_identifiers_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 variant_id uuid not null references public.product_variants(id) on delete cascade,
 identifier_type text not null check(identifier_type in('barcode','qr','manufacturer','supplier','internal','alternate_sku')),
 code text not null,supplier_id uuid references public.suppliers(id) on delete set null,label text,
 is_primary boolean not null default false,generated boolean not null default false,active boolean not null default true,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index if not exists ux_product_identifiers_v482_code on public.product_identifiers_v482(tenant_id,lower(trim(code))) where active;
create unique index if not exists ux_product_identifiers_v482_primary_barcode on public.product_identifiers_v482(tenant_id,variant_id,identifier_type) where active and is_primary and identifier_type in('barcode','qr','internal');
create index if not exists idx_product_identifiers_v482_variant on public.product_identifiers_v482(tenant_id,variant_id,active,identifier_type);
alter table public.product_identifiers_v482 enable row level security;
drop policy if exists product_identifiers_v482_read on public.product_identifiers_v482;
create policy product_identifiers_v482_read on public.product_identifiers_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.product_identifiers_v482 from authenticated; grant select on public.product_identifiers_v482 to authenticated;

create table if not exists public.product_identifier_sequences_v482(
 tenant_id uuid primary key references public.tenants(id) on delete cascade,next_barcode bigint not null default 1,next_qr bigint not null default 1,updated_at timestamptz not null default now());
alter table public.product_identifier_sequences_v482 enable row level security; revoke all on public.product_identifier_sequences_v482 from anon,authenticated;
insert into public.product_identifier_sequences_v482(tenant_id) select t.id from public.tenants t on conflict do nothing;

insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,label,is_primary,generated)
select pv.tenant_id,pv.id,'barcode',trim(pv.barcode),'Legacy Barcode',true,false from public.product_variants pv where nullif(trim(coalesce(pv.barcode,'')),'') is not null on conflict do nothing;
insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,label,is_primary,generated)
select pv.tenant_id,pv.id,'manufacturer',trim(pv.part_number),'Manufacturer / Part Code',true,false from public.product_variants pv where nullif(trim(coalesce(pv.part_number,'')),'') is not null on conflict do nothing;

create or replace function private.v482_sync_legacy_identifiers(p_tenant_id uuid,p_variant_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_barcode text;v_part text;begin
 select i.code into v_barcode from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type='barcode' and i.active order by i.is_primary desc,i.updated_at desc limit 1;
 select i.code into v_part from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type='manufacturer' and i.active order by i.is_primary desc,i.updated_at desc limit 1;
 update public.product_variants set barcode=v_barcode,part_number=v_part,updated_at=now() where tenant_id=p_tenant_id and id=p_variant_id;
end$$;
revoke all on function private.v482_sync_legacy_identifiers(uuid,uuid) from public;

create or replace function private.v482_ean13_check_digit(p_digits12 text) returns text language plpgsql immutable set search_path=public,private,pg_temp as $$
declare i int;v_sum int:=0;v_digit int;begin
 if p_digits12 !~ '^[0-9]{12}$' then raise exception 'EAN seed must contain 12 digits';end if;
 for i in 1..12 loop v_digit:=substr(p_digits12,i,1)::int;v_sum:=v_sum+case when mod(i,2)=0 then v_digit*3 else v_digit end;end loop;
 return ((10-mod(v_sum,10))%10)::text;
end$$;
revoke all on function private.v482_ean13_check_digit(text) from public;
do $$declare r record;begin for r in select distinct i.tenant_id,i.variant_id from public.product_identifiers_v482 i loop perform private.v482_sync_legacy_identifiers(r.tenant_id,r.variant_id);end loop;end$$;

create or replace function public.product_identifiers_v482_list(p_tenant_id uuid,p_variant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select jsonb_build_object('identifier_id',i.id,'variant_id',i.variant_id,'identifier_type',i.identifier_type,'code',i.code,'supplier_id',i.supplier_id,'supplier_name',s.name,'label',i.label,'is_primary',i.is_primary,'generated',i.generated,'active',i.active,'created_at',i.created_at)
 from public.product_identifiers_v482 i left join public.suppliers s on s.id=i.supplier_id where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id order by i.active desc,i.is_primary desc,i.identifier_type,i.code;
end$$;
grant execute on function public.product_identifiers_v482_list(uuid,uuid) to authenticated;

create or replace function public.product_identifier_save_v482(p_tenant_id uuid,p_identifier_id uuid,p_variant_id uuid,p_identifier_type text,p_code text,p_supplier_id uuid,p_label text,p_is_primary boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_type text:=lower(trim(coalesce(p_identifier_type,'')));v_code text:=trim(coalesce(p_code,''));begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if v_type not in('barcode','qr','manufacturer','supplier','internal','alternate_sku') then raise exception 'Invalid identifier type';end if;
 if v_code='' then raise exception 'Identifier code is required';end if;
 if not exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id=p_variant_id) then raise exception 'Product variant not found';end if;
 if exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id<>p_variant_id and lower(trim(pv.sku))=lower(v_code)) then raise exception 'Code % is already used as another product SKU',v_code;end if;
 if p_supplier_id is not null and not exists(select 1 from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_supplier_id) then raise exception 'Supplier not found';end if;
 if p_is_primary then update public.product_identifiers_v482 set is_primary=false,updated_at=now() where tenant_id=p_tenant_id and variant_id=p_variant_id and identifier_type=v_type and active;end if;
 if p_identifier_id is null then
  insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,supplier_id,label,is_primary,active) values(p_tenant_id,p_variant_id,v_type,v_code,p_supplier_id,nullif(trim(coalesce(p_label,'')),''),p_is_primary,p_active) returning id into v_id;
 else
  update public.product_identifiers_v482 set identifier_type=v_type,code=v_code,supplier_id=p_supplier_id,label=nullif(trim(coalesce(p_label,'')),''),is_primary=p_is_primary,active=p_active,updated_at=now() where id=p_identifier_id and tenant_id=p_tenant_id and variant_id=p_variant_id returning id into v_id;
  if v_id is null then raise exception 'Identifier not found';end if;
 end if;
 perform private.v482_sync_legacy_identifiers(p_tenant_id,p_variant_id);
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','product_identifier',p_variant_id::text,'save');return v_id;
end$$;
grant execute on function public.product_identifier_save_v482(uuid,uuid,uuid,text,text,uuid,text,boolean,boolean) to authenticated;

create or replace function public.product_identifier_archive_v482(p_tenant_id uuid,p_identifier_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_variant uuid;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 update public.product_identifiers_v482 set active=false,is_primary=false,updated_at=now() where id=p_identifier_id and tenant_id=p_tenant_id returning variant_id into v_variant;
 if v_variant is null then raise exception 'Identifier not found';end if;
 perform private.v482_sync_legacy_identifiers(p_tenant_id,v_variant);
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','product_identifier',v_variant::text,'archive');
end$$;
grant execute on function public.product_identifier_archive_v482(uuid,uuid) to authenticated;

create or replace function public.product_identifier_generate_v482(p_tenant_id uuid,p_variant_id uuid,p_identifier_type text) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_type text:=lower(trim(coalesce(p_identifier_type,'')));v_seq bigint;v_seed text;v_code text;v_id uuid;v_short text;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if not exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id=p_variant_id) then raise exception 'Product variant not found';end if;
 insert into public.product_identifier_sequences_v482(tenant_id) values(p_tenant_id) on conflict do nothing;
 if v_type='barcode' then
  select s.next_barcode into v_seq from public.product_identifier_sequences_v482 s where s.tenant_id=p_tenant_id for update;
  update public.product_identifier_sequences_v482 set next_barcode=next_barcode+1,updated_at=now() where tenant_id=p_tenant_id;
  v_seed:='28'||lpad(v_seq::text,10,'0');v_code:=v_seed||private.v482_ean13_check_digit(v_seed);
 elsif v_type='qr' then
  select s.next_qr into v_seq from public.product_identifier_sequences_v482 s where s.tenant_id=p_tenant_id for update;
  update public.product_identifier_sequences_v482 set next_qr=next_qr+1,updated_at=now() where tenant_id=p_tenant_id;
  v_short:=replace(left(p_variant_id::text,8),'-','');v_code:='THQ:PRODUCT:'||v_short||':'||lpad(v_seq::text,8,'0');
 else raise exception 'Only barcode or QR identifiers can be generated automatically';end if;
 v_id:=public.product_identifier_save_v482(p_tenant_id,null,p_variant_id,v_type,v_code,null,'Generated by THQ',not exists(select 1 from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type=v_type and i.active and i.is_primary),true);
 update public.product_identifiers_v482 set generated=true where id=v_id;
 return jsonb_build_object('identifier_id',v_id,'identifier_type',v_type,'code',v_code);
end$$;
grant execute on function public.product_identifier_generate_v482(uuid,uuid,text) to authenticated;

create or replace function public.inventory_list_products_v482(p_tenant_id uuid,p_location_id uuid default null) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_variant uuid;v_ids jsonb;v_codes text;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 for r in select * from public.inventory_list_products_v481(p_tenant_id,p_location_id) loop
  begin v_variant:=(r->>'variant_id')::uuid;exception when others then v_variant:=null;end;
  if v_variant is not null then
   select coalesce(jsonb_agg(jsonb_build_object('identifier_id',i.id,'type',i.identifier_type,'code',i.code,'label',i.label,'is_primary',i.is_primary,'supplier_id',i.supplier_id) order by i.is_primary desc,i.identifier_type,i.code),'[]'::jsonb),string_agg(i.code,' ' order by i.code)
   into v_ids,v_codes from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=v_variant and i.active;
  else v_ids:='[]'::jsonb;v_codes:='';end if;
  return next r||jsonb_build_object('identifiers',coalesce(v_ids,'[]'::jsonb),'search_codes',coalesce(v_codes,''));
 end loop;return;
end$$;
grant execute on function public.inventory_list_products_v482(uuid,uuid) to authenticated;

create or replace function public.inventory_product_lookup_v482(p_tenant_id uuid,p_code text,p_location_id uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_variant uuid;v_code text:=lower(trim(coalesce(p_code,'')));v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if v_code='' then return '{}'::jsonb;end if;
 select pv.id into v_variant from public.product_variants pv where pv.tenant_id=p_tenant_id and lower(trim(pv.sku))=v_code limit 1;
 if v_variant is null then select i.variant_id into v_variant from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.active and lower(trim(i.code))=v_code limit 1;end if;
 -- Compatibility fallback for historical installations where a legacy barcode/part number
 -- has not yet been promoted to the identifier table. SKU always has first priority.
 if v_variant is null then select pv.id into v_variant from public.product_variants pv where pv.tenant_id=p_tenant_id and (lower(trim(coalesce(pv.barcode,'')))=v_code or lower(trim(coalesce(pv.part_number,'')))=v_code) order by case when lower(trim(coalesce(pv.barcode,'')))=v_code then 0 else 1 end limit 1;end if;
 if v_variant is null then return '{}'::jsonb;end if;
 select r into v from public.inventory_list_products_v482(p_tenant_id,p_location_id) r where (r->>'variant_id')::uuid=v_variant limit 1;
 return coalesce(v,'{}'::jsonb);
end$$;
grant execute on function public.inventory_product_lookup_v482(uuid,text,uuid) to authenticated;

-- Prevent future SKU edits from colliding with an identifier owned by another product.
create or replace function private.v482_product_sku_guard() returns trigger language plpgsql set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.product_identifiers_v482 i where i.tenant_id=new.tenant_id and i.variant_id<>new.id and i.active and lower(trim(i.code))=lower(trim(new.sku))) then raise exception 'SKU % is already used as another product identifier',new.sku;end if;
 return new;
end$$;
drop trigger if exists trg_v482_product_sku_guard on public.product_variants;
create trigger trg_v482_product_sku_guard before insert or update of sku on public.product_variants for each row execute function private.v482_product_sku_guard();

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(131,'4.8.2','Pricing & Product Identification','Multiple product identifiers, generated internal barcodes/QR codes and unified SKU/code lookup.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 131 product identification applied' as status;

-- ============================================================================
-- 132_v482_label_printing.sql
-- ============================================================================

-- THQ ERP V4.8.2 — Barcode/QR label templates.
begin;
create table if not exists public.label_templates_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,code text not null,name text not null,
 paper_mode text not null default 'thermal' check(paper_mode in('thermal','a4')),width_mm numeric not null default 50 check(width_mm>0),height_mm numeric not null default 30 check(height_mm>0),
 columns integer not null default 1 check(columns between 1 and 6),show_business boolean not null default true,show_product boolean not null default true,show_price boolean not null default true,
 show_sku boolean not null default true,show_code_text boolean not null default true,code_mode text not null default 'barcode' check(code_mode in('barcode','qr')),
 is_default boolean not null default false,system_template boolean not null default false,active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,code));
create unique index if not exists ux_label_templates_v482_default on public.label_templates_v482(tenant_id) where is_default and active;
alter table public.label_templates_v482 enable row level security;
drop policy if exists label_templates_v482_read on public.label_templates_v482;
create policy label_templates_v482_read on public.label_templates_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.label_templates_v482 from authenticated;grant select on public.label_templates_v482 to authenticated;

create or replace function private.v482_seed_label_templates(p_tenant_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 insert into public.label_templates_v482(tenant_id,code,name,paper_mode,width_mm,height_mm,columns,code_mode,is_default,system_template) values
 (p_tenant_id,'THERMAL_50X30','Thermal 50 × 30 mm','thermal',50,30,1,'barcode',true,true),
 (p_tenant_id,'THERMAL_38X25','Thermal 38 × 25 mm','thermal',38,25,1,'barcode',false,true),
 (p_tenant_id,'A4_3COL','A4 • 3 Columns','a4',63,35,3,'barcode',false,true),
 (p_tenant_id,'QR_50X30','QR 50 × 30 mm','thermal',50,30,1,'qr',false,true)
 on conflict(tenant_id,code) do update set name=excluded.name,system_template=true;
end$$;
revoke all on function private.v482_seed_label_templates(uuid) from public;
do $$declare r record;begin for r in select t.id from public.tenants t loop perform private.v482_seed_label_templates(r.id);end loop;end$$;
create or replace function private.v482_seed_label_templates_trigger() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$begin perform private.v482_seed_label_templates(new.id);return new;end$$;
drop trigger if exists trg_v482_seed_label_templates on public.tenants;
create trigger trg_v482_seed_label_templates after insert on public.tenants for each row execute function private.v482_seed_label_templates_trigger();

create or replace function public.label_templates_v482(p_tenant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select to_jsonb(t) from public.label_templates_v482 t where t.tenant_id=p_tenant_id and t.active order by t.is_default desc,t.name;
end$$;
grant execute on function public.label_templates_v482(uuid) to authenticated;

create or replace function public.label_template_save_v482(p_tenant_id uuid,p_template_id uuid,p_code text,p_name text,p_paper_mode text,p_width_mm numeric,p_height_mm numeric,p_columns integer,p_show_business boolean,p_show_product boolean,p_show_price boolean,p_show_sku boolean,p_show_code_text boolean,p_code_mode text,p_is_default boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_id uuid;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if p_is_default then update public.label_templates_v482 set is_default=false,updated_at=now() where tenant_id=p_tenant_id;end if;
 if p_template_id is null then
  insert into public.label_templates_v482(tenant_id,code,name,paper_mode,width_mm,height_mm,columns,show_business,show_product,show_price,show_sku,show_code_text,code_mode,is_default,active)
  values(p_tenant_id,upper(trim(p_code)),trim(p_name),p_paper_mode,p_width_mm,p_height_mm,p_columns,p_show_business,p_show_product,p_show_price,p_show_sku,p_show_code_text,p_code_mode,p_is_default,p_active) returning id into v_id;
 else
  update public.label_templates_v482 set code=upper(trim(p_code)),name=trim(p_name),paper_mode=p_paper_mode,width_mm=p_width_mm,height_mm=p_height_mm,columns=p_columns,show_business=p_show_business,show_product=p_show_product,show_price=p_show_price,show_sku=p_show_sku,show_code_text=p_show_code_text,code_mode=p_code_mode,is_default=p_is_default,active=p_active,updated_at=now() where id=p_template_id and tenant_id=p_tenant_id returning id into v_id;
  if v_id is null then raise exception 'Label template not found';end if;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','label_template',v_id::text,'save');return v_id;
end$$;
grant execute on function public.label_template_save_v482(uuid,uuid,text,text,text,numeric,numeric,integer,boolean,boolean,boolean,boolean,boolean,text,boolean,boolean) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(132,'4.8.2','Pricing & Product Identification','Reusable thermal/A4 barcode and QR label templates.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 132 label printing applied' as status;

-- ============================================================================
-- 133_v482_authoritative_sale_pricing.sql
-- ============================================================================

-- THQ ERP V4.8.2 — authoritative sale pricing.
begin;
alter table public.sale_items add column if not exists pricing_source text,add column if not exists price_list_id uuid references public.price_lists_v482(id) on delete set null,add column if not exists pricing_metadata jsonb not null default '{}'::jsonb;
create or replace function private.v482_price_sale_items(p_tenant_id uuid,p_customer_id uuid,p_items jsonb,p_location_id uuid) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_out jsonb:='[]'::jsonb;v_variant uuid;v_unit uuid;v_qty numeric;v_price jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=nullif(x->>'variant_id','')::uuid;v_unit:=nullif(x->>'unit_id','')::uuid;v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
  if v_variant is null or v_qty<=0 then raise exception 'Valid product and quantity are required';end if;
  v_price:=private.pricing_resolve_v482_internal(p_tenant_id,v_variant,p_customer_id,v_unit,v_qty,p_location_id);
  v_out:=v_out||jsonb_build_array(x||jsonb_build_object('unit_id',v_price->>'unit_id','unit_price',(v_price->>'unit_price')::numeric,'_pricing_source',v_price->>'source','_price_list_id',v_price->>'price_list_id','_price_list_name',v_price->>'price_list_name'));
 end loop;return v_out;
end$$;
revoke all on function private.v482_price_sale_items(uuid,uuid,jsonb,uuid) from public;
create or replace function public.sales_create_v482(p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_priced jsonb;v_result jsonb;v_sale uuid;x jsonb;v_variant uuid;begin
 v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);
 v_result:=public.sales_create_v481(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_priced,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
 v_sale:=nullif(v_result->>'sale_id','')::uuid;
 if v_sale is not null then
  for x in select value from jsonb_array_elements(v_priced) loop
   v_variant:=(x->>'variant_id')::uuid;
   update public.sale_items si set pricing_source=nullif(x->>'_pricing_source',''),price_list_id=nullif(x->>'_price_list_id','')::uuid,pricing_metadata=jsonb_strip_nulls(jsonb_build_object('price_list_name',nullif(x->>'_price_list_name',''),'resolved_at',now()))
   where si.sale_id=v_sale and si.variant_id=v_variant and si.entered_unit_id=nullif(x->>'unit_id','')::uuid;
  end loop;
 end if;
 return v_result||jsonb_build_object('pricing_engine','v4.8.2');
end$$;
grant execute on function public.sales_create_v482(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;
create or replace function public.sales_get_detail_v482(p_tenant_id uuid,p_sale_id uuid) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare v jsonb;v_items jsonb;begin
 v:=public.sales_get_detail_v32(p_tenant_id,p_sale_id);
 select coalesce(jsonb_agg(i.value||jsonb_build_object('pricing_source',si.pricing_source,'price_list_id',si.price_list_id,'pricing_metadata',si.pricing_metadata)),'[]'::jsonb) into v_items
 from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value) left join public.sale_items si on si.sale_id=p_sale_id and si.variant_id=nullif(i.value->>'variant_id','')::uuid and (si.entered_unit_code is null or si.entered_unit_code=coalesce(i.value->>'unit_code',si.entered_unit_code));
 return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end$$;
grant execute on function public.sales_get_detail_v482(uuid,uuid) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(133,'4.8.2','Pricing & Product Identification','Authoritative database price resolution for sales with pricing provenance on sale lines.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 133 authoritative pricing applied' as status;

-- ============================================================================
-- 134_v482_release_contract.sql
-- ============================================================================

-- THQ ERP V4.8.2 — release contract.
begin;
create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json','resources',jsonb_build_array('sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'),'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','mobile_ready',true)
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.2','release','Pricing & Product Identification','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v482_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.price_lists_v482') is null then v_missing:=array_append(v_missing,'price_lists_v482');end if;
 if to_regclass('public.price_list_items_v482') is null then v_missing:=array_append(v_missing,'price_list_items_v482');end if;
 if to_regclass('public.customer_prices_v482') is null then v_missing:=array_append(v_missing,'customer_prices_v482');end if;
 if to_regclass('public.product_identifiers_v482') is null then v_missing:=array_append(v_missing,'product_identifiers_v482');end if;
 if to_regclass('public.label_templates_v482') is null then v_missing:=array_append(v_missing,'label_templates_v482');end if;
 if to_regprocedure('public.pricing_resolve_v482(uuid,uuid,uuid,uuid,numeric,uuid)') is null then v_missing:=array_append(v_missing,'pricing_resolve_v482');end if;
 if to_regprocedure('public.product_identifier_save_v482(uuid,uuid,uuid,text,text,uuid,text,boolean,boolean)') is null then v_missing:=array_append(v_missing,'product_identifier_save_v482');end if;
 if to_regprocedure('public.inventory_product_lookup_v482(uuid,text,uuid)') is null then v_missing:=array_append(v_missing,'inventory_product_lookup_v482');end if;
 if to_regprocedure('public.label_templates_v482(uuid)') is null then v_missing:=array_append(v_missing,'label_templates_v482');end if;
 if to_regprocedure('public.sales_create_v482(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v482');end if;
 if to_regprocedure('public.sales_get_detail_v482(uuid,uuid)') is null then v_missing:=array_append(v_missing,'sales_get_detail_v482');end if;
 if to_regprocedure('public.pricing_lists_v482(uuid)') is null then v_missing:=array_append(v_missing,'pricing_lists_v482');end if;
 if to_regprocedure('public.pricing_rule_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean)') is null then v_missing:=array_append(v_missing,'pricing_rule_save_v482');end if;
 if to_regprocedure('public.customer_price_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean)') is null then v_missing:=array_append(v_missing,'customer_price_save_v482');end if;
 if to_regprocedure('public.product_identifier_generate_v482(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'product_identifier_generate_v482');end if;
 if to_regprocedure('public.product_identifier_archive_v482(uuid,uuid)') is null then v_missing:=array_append(v_missing,'product_identifier_archive_v482');end if;
 if to_regprocedure('public.label_template_save_v482(uuid,uuid,text,text,text,numeric,numeric,integer,boolean,boolean,boolean,boolean,boolean,text,boolean,boolean)') is null then v_missing:=array_append(v_missing,'label_template_save_v482');end if;
 if to_regprocedure('private.v482_sync_legacy_identifiers(uuid,uuid)') is null then v_missing:=array_append(v_missing,'v482_sync_legacy_identifiers');end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='pricing_source') then v_missing:=array_append(v_missing,'sale_items.pricing_source');end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='pricing_metadata') then v_missing:=array_append(v_missing,'sale_items.pricing_metadata');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.2','migration_no',134,'api_version','v1','label_printing',true);
end$$;
grant execute on function public.thq_v482_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(134,'4.8.2','Pricing & Product Identification','Retail/wholesale/dealer/contractor pricing, customer and quantity pricing, multiple product identifiers, QR/barcode generation and label printing.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 134 release contract applied' as status;
