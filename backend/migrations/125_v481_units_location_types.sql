-- THQ ERP V4.8.1 — units, conversions and generalized location types.
begin;

create table if not exists public.inventory_units_v481(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  unit_group text not null default 'count',
  decimal_places integer not null default 0 check(decimal_places between 0 and 6),
  allow_fractional boolean not null default false,
  system_unit boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code)
);
create index if not exists idx_inventory_units_v481_tenant on public.inventory_units_v481(tenant_id,active,unit_group,name);
alter table public.inventory_units_v481 enable row level security;
drop policy if exists inventory_units_v481_read on public.inventory_units_v481;
create policy inventory_units_v481_read on public.inventory_units_v481 for select to authenticated
using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.inventory_units_v481 from authenticated;
grant select on public.inventory_units_v481 to authenticated;

create table if not exists public.product_units_v481(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  unit_id uuid not null references public.inventory_units_v481(id) on delete restrict,
  is_base boolean not null default false,
  allow_purchase boolean not null default false,
  allow_sale boolean not null default true,
  is_default_purchase boolean not null default false,
  is_default_sale boolean not null default false,
  conversion_to_base numeric not null default 1 check(conversion_to_base>0),
  quantity_step numeric not null default 1 check(quantity_step>0),
  sale_price numeric,
  purchase_cost numeric,
  cutting_allowed boolean not null default false,
  cutting_charge numeric not null default 0 check(cutting_charge>=0),
  active boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,variant_id,unit_id)
);
create unique index if not exists ux_product_units_v481_base on public.product_units_v481(tenant_id,variant_id) where is_base and active;
create unique index if not exists ux_product_units_v481_default_sale on public.product_units_v481(tenant_id,variant_id) where is_default_sale and active;
create unique index if not exists ux_product_units_v481_default_purchase on public.product_units_v481(tenant_id,variant_id) where is_default_purchase and active;
create index if not exists idx_product_units_v481_variant on public.product_units_v481(tenant_id,variant_id,active);
alter table public.product_units_v481 enable row level security;
drop policy if exists product_units_v481_read on public.product_units_v481;
create policy product_units_v481_read on public.product_units_v481 for select to authenticated
using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.product_units_v481 from authenticated;
grant select on public.product_units_v481 to authenticated;

create or replace function private.v481_seed_units(p_tenant_id uuid) returns void
language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.inventory_units_v481(tenant_id,code,name,unit_group,decimal_places,allow_fractional,system_unit)
  values
   (p_tenant_id,'PCS','Piece','count',0,false,true),(p_tenant_id,'SET','Set','count',0,false,true),
   (p_tenant_id,'PAIR','Pair','count',0,false,true),(p_tenant_id,'DOZ','Dozen','count',0,false,true),
   (p_tenant_id,'BOX','Box','pack',0,false,true),(p_tenant_id,'CTN','Carton','pack',0,false,true),
   (p_tenant_id,'COIL','Coil','pack',0,false,true),(p_tenant_id,'ROLL','Roll','pack',0,false,true),
   (p_tenant_id,'BDL','Bundle','pack',0,false,true),(p_tenant_id,'M','Meter','length',3,true,true),
   (p_tenant_id,'CM','Centimeter','length',2,true,true),(p_tenant_id,'MM','Millimeter','length',2,true,true),
   (p_tenant_id,'KG','Kilogram','weight',3,true,true),(p_tenant_id,'G','Gram','weight',2,true,true),
   (p_tenant_id,'L','Liter','volume',3,true,true),(p_tenant_id,'ML','Milliliter','volume',2,true,true),
   (p_tenant_id,'HR','Hour','time',2,true,true),(p_tenant_id,'MIN','Minute','time',2,true,true)
  on conflict(tenant_id,code) do nothing;
end $$;
revoke all on function private.v481_seed_units(uuid) from public;

do $$ declare r record; begin for r in select id from public.tenants loop perform private.v481_seed_units(r.id); end loop; end $$;

create or replace function private.v481_seed_units_trigger() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin perform private.v481_seed_units(new.id); return new; end $$;
drop trigger if exists trg_v481_seed_units on public.tenants;
create trigger trg_v481_seed_units after insert on public.tenants for each row execute function private.v481_seed_units_trigger();

-- Generalize physical locations without breaking existing legacy types.
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.business_locations'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%location_type%' loop
    execute format('alter table public.business_locations drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.business_locations add constraint business_locations_location_type_v481_check
check(location_type in('head_office','branch','store','warehouse','production','office','scrap','restaurant','kitchen','service_base'));

-- Use hierarchy_role=operational for production/office/scrap while preserving MAIN/store/warehouse behavior.
create or replace function private.v481_normalize_location_type() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if new.location_type='warehouse' then new.hierarchy_role:='warehouse';
  elsif new.location_type in('production','office','scrap') and coalesce(new.hierarchy_role,'')<>'main_store' then new.hierarchy_role:='operational';
  elsif new.location_type in('store','branch') and coalesce(new.hierarchy_role,'') not in('main_store','child_store') then new.hierarchy_role:='child_store';
  end if;
  return new;
end $$;
drop trigger if exists trg_v481_normalize_location_type on public.business_locations;
create trigger trg_v481_normalize_location_type before insert or update of location_type,hierarchy_role on public.business_locations
for each row execute function private.v481_normalize_location_type();

-- Backfill one base unit for every existing variant. Legacy invoice unit_code wins when it matches a known unit.
do $$ declare r record; v_unit uuid; v_code text; begin
  for r in select pv.tenant_id,pv.id variant_id,p.item_type from public.product_variants pv join public.products p on p.id=pv.product_id loop
    perform private.v481_seed_units(r.tenant_id);
    select upper(trim(a.unit_code)) into v_code from public.product_invoice_attributes_v45 a where a.tenant_id=r.tenant_id and a.variant_id=r.variant_id;
    if coalesce(v_code,'')='' then v_code:=case when r.item_type='service' then 'HR' else 'PCS' end; end if;
    select id into v_unit from public.inventory_units_v481 where tenant_id=r.tenant_id and code=v_code and active limit 1;
    if v_unit is null then select id into v_unit from public.inventory_units_v481 where tenant_id=r.tenant_id and code=case when r.item_type='service' then 'HR' else 'PCS' end limit 1; end if;
    insert into public.product_units_v481(tenant_id,variant_id,unit_id,is_base,allow_purchase,allow_sale,is_default_purchase,is_default_sale,conversion_to_base,quantity_step)
    values(r.tenant_id,r.variant_id,v_unit,true,r.item_type<>'service',true,r.item_type<>'service',true,1,case when r.item_type='service' then 0.25 else 1 end)
    on conflict(tenant_id,variant_id,unit_id) do update set is_base=true,is_default_sale=true,conversion_to_base=1,active=true;
  end loop;
end $$;

create or replace function public.inventory_units_list_v481(p_tenant_id uuid,p_active_only boolean default true)
returns table(unit_id uuid,code text,name text,unit_group text,decimal_places integer,allow_fractional boolean,system_unit boolean,active boolean)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select u.id,u.code,u.name,u.unit_group,u.decimal_places,u.allow_fractional,u.system_unit,u.active
  from public.inventory_units_v481 u where u.tenant_id=p_tenant_id and (not p_active_only or u.active) order by u.unit_group,u.name;
end $$;
grant execute on function public.inventory_units_list_v481(uuid,boolean) to authenticated;

create or replace function public.inventory_unit_save_v481(p_tenant_id uuid,p_unit_id uuid,p_code text,p_name text,p_group text,p_decimal_places integer,p_allow_fractional boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
  if trim(coalesce(p_code,''))='' or trim(coalesce(p_name,''))='' then raise exception 'Unit code and name are required';end if;
  if p_unit_id is not null and exists(select 1 from public.inventory_units_v481 u where u.id=p_unit_id and u.tenant_id=p_tenant_id and u.system_unit) then
    raise exception 'System unit definitions cannot be edited. Create a custom unit instead.';
  end if;
  if p_unit_id is null then
    insert into public.inventory_units_v481(tenant_id,code,name,unit_group,decimal_places,allow_fractional,active)
    values(p_tenant_id,upper(trim(p_code)),trim(p_name),coalesce(nullif(trim(p_group),''),'custom'),greatest(0,least(coalesce(p_decimal_places,0),6)),coalesce(p_allow_fractional,false),coalesce(p_active,true)) returning id into v_id;
  else
    update public.inventory_units_v481 set code=upper(trim(p_code)),name=trim(p_name),unit_group=coalesce(nullif(trim(p_group),''),'custom'),decimal_places=greatest(0,least(coalesce(p_decimal_places,0),6)),allow_fractional=coalesce(p_allow_fractional,false),active=coalesce(p_active,true),updated_at=now()
    where id=p_unit_id and tenant_id=p_tenant_id returning id into v_id;
    if v_id is null then raise exception 'Unit not found';end if;
  end if; return v_id;
end $$;
grant execute on function public.inventory_unit_save_v481(uuid,uuid,text,text,text,integer,boolean,boolean) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(125,'4.8.1','Inventory & Unit Engine','Standard/custom units, product conversion model and generalized Store/Warehouse/Production/Office/Scrap location types.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 125 units and location types applied' as status;
