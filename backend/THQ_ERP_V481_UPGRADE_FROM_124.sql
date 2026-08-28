-- THQ ERP V4.8.1 — Inventory & Unit Engine
-- Upgrade bundle for databases already at migration 124 / THQ ERP 4.8.0.
-- BACK UP THE DATABASE FIRST. Run this file once, in order.

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

-- THQ ERP V4.8.1 — universal inventory movement ledger enrichment.
begin;

alter table public.location_stock_movements
  add column if not exists base_quantity_delta numeric,
  add column if not exists display_quantity numeric,
  add column if not exists unit_id uuid references public.inventory_units_v481(id) on delete set null,
  add column if not exists unit_code text,
  add column if not exists conversion_to_base numeric,
  add column if not exists balance_before numeric,
  add column if not exists balance_after numeric,
  add column if not exists source_line_id uuid,
  add column if not exists movement_group text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.location_stock_movements m set base_quantity_delta=coalesce(base_quantity_delta,quantity_delta),display_quantity=coalesce(display_quantity,quantity_delta),conversion_to_base=coalesce(conversion_to_base,1),movement_group=coalesce(movement_group,case when movement_type like 'transfer_%' then 'transfer' when movement_type like 'production_%' then 'production' else movement_type end) where base_quantity_delta is null or display_quantity is null or conversion_to_base is null or movement_group is null;

-- Expand movement vocabulary for industrial use now so inventory won't need redesign later.
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.location_stock_movements'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%movement_type%' loop
    execute format('alter table public.location_stock_movements drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.location_stock_movements add constraint location_stock_movements_type_v481_check check(movement_type in(
 'opening','purchase','sale','sale_return','sales_return','purchase_return','adjustment','stock_adjustment','adjustment_in','adjustment_out','transfer_in','transfer_out','stock_count',
 'damage','damage_restore','quarantine_in','quarantine_out','production_in','production_out','production_consumption','production_output',
 'wastage','scrap','scrap_sale','rework_in','rework_out','reservation','reservation_release','grn','delivery'
));
create index if not exists idx_location_stock_movements_source_v481 on public.location_stock_movements(tenant_id,reference_type,reference_id,variant_id);
create index if not exists idx_location_stock_movements_time_v481 on public.location_stock_movements(tenant_id,created_at desc,movement_type);

create or replace function private.v4_location_stock_apply(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_delta numeric,
  p_movement_type text,p_reference_type text default null,p_reference_id uuid default null,
  p_reference_number text default null,p_note text default null,p_device_id uuid default null,
  p_allow_negative boolean default false
) returns numeric language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_before numeric:=0;v_after numeric;v_cost numeric:=0;v_reserved numeric:=0;v_damaged numeric:=0;v_quarantine numeric:=0;v_available numeric:=0;v_unit uuid;v_unit_code text;
begin
  insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,0,0,now()) on conflict(tenant_id,location_id,variant_id) do nothing;
  select b.quantity,b.reserved_quantity,b.damaged_quantity,b.quarantine_quantity into v_before,v_reserved,v_damaged,v_quarantine
  from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.location_id=p_location_id and b.variant_id=p_variant_id for update;
  v_before:=coalesce(v_before,0);v_reserved:=coalesce(v_reserved,0);v_damaged:=coalesce(v_damaged,0);v_quarantine:=coalesce(v_quarantine,0);
  v_available:=v_before-v_reserved-v_damaged-v_quarantine;v_after:=v_before+coalesce(p_delta,0);
  if not p_allow_negative and coalesce(p_delta,0)<0 and v_available+coalesce(p_delta,0)<-0.000001 then raise exception 'Insufficient available stock at selected location. Available: %, requested: %',v_available,abs(p_delta);end if;
  if not p_allow_negative and v_after<0 then raise exception 'Insufficient physical stock at selected location';end if;
  select coalesce(pv.cost_price,0) into v_cost from public.product_variants pv where pv.id=p_variant_id and pv.tenant_id=p_tenant_id;
  select pu.unit_id,u.code into v_unit,v_unit_code from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.is_base and pu.active limit 1;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active) values(p_tenant_id,p_location_id,p_variant_id,true) on conflict(tenant_id,location_id,variant_id) do nothing;
  update public.location_stock_balances set quantity=v_after,average_cost=case when v_cost<>0 then v_cost else average_cost end,updated_at=now() where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
  insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,base_quantity_delta,display_quantity,unit_id,unit_code,conversion_to_base,balance_before,balance_after,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id,movement_group)
  values(p_tenant_id,p_location_id,p_variant_id,p_movement_type,p_delta,p_delta,p_delta,v_unit,v_unit_code,1,v_before,v_after,v_cost,p_reference_type,p_reference_id,p_reference_number,nullif(trim(coalesce(p_note,'')),''),auth.uid(),p_device_id,case when p_movement_type like 'transfer_%' then 'transfer' when p_movement_type like 'production_%' then 'production' else p_movement_type end);
  return v_after;
end $$;
revoke all on function private.v4_location_stock_apply(uuid,uuid,uuid,numeric,text,text,uuid,text,text,uuid,boolean) from public;

create or replace function public.inventory_movement_history_v481(p_tenant_id uuid,p_variant_id uuid default null,p_location_id uuid default null,p_movement_type text default null,p_from timestamptz default null,p_to timestamptz default null,p_limit integer default 500)
returns table(movement_id uuid,location_id uuid,location_name text,variant_id uuid,product_name text,sku text,movement_type text,movement_group text,display_quantity numeric,unit_code text,base_quantity_delta numeric,balance_before numeric,balance_after numeric,unit_cost numeric,reference_type text,reference_number text,note text,occurred_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select m.id,m.location_id,l.name,m.variant_id,p.name,pv.sku,m.movement_type,m.movement_group,coalesce(m.display_quantity,m.quantity_delta),m.unit_code,coalesce(m.base_quantity_delta,m.quantity_delta),m.balance_before,m.balance_after,m.unit_cost,m.reference_type,m.reference_number,m.note,m.created_at
  from public.location_stock_movements m join public.business_locations l on l.id=m.location_id join public.product_variants pv on pv.id=m.variant_id join public.products p on p.id=pv.product_id
  where m.tenant_id=p_tenant_id and (p_variant_id is null or m.variant_id=p_variant_id) and (p_location_id is null or m.location_id=p_location_id) and (p_movement_type is null or m.movement_type=p_movement_type) and (p_from is null or m.created_at>=p_from) and (p_to is null or m.created_at<p_to)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,m.location_id,'view'))
  order by m.created_at desc limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.inventory_movement_history_v481(uuid,uuid,uuid,text,timestamptz,timestamptz,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(126,'4.8.1','Inventory & Unit Engine','Universal movement ledger enriched with unit/display/base quantities, before/after balances, source metadata and future production/wastage/scrap movement types.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 126 movement ledger applied' as status;

-- THQ ERP V4.8.1 — product/unit configuration and enriched inventory APIs.
begin;

create or replace function public.inventory_product_units_v481(p_tenant_id uuid,p_variant_id uuid)
returns table(unit_id uuid,code text,name text,unit_group text,decimal_places integer,allow_fractional boolean,is_base boolean,allow_purchase boolean,allow_sale boolean,is_default_purchase boolean,is_default_sale boolean,conversion_to_base numeric,quantity_step numeric,sale_price numeric,purchase_cost numeric,cutting_allowed boolean,cutting_charge numeric,active boolean)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select u.id,u.code,u.name,u.unit_group,u.decimal_places,u.allow_fractional,pu.is_base,pu.allow_purchase,pu.allow_sale,pu.is_default_purchase,pu.is_default_sale,pu.conversion_to_base,pu.quantity_step,pu.sale_price,pu.purchase_cost,pu.cutting_allowed,pu.cutting_charge,pu.active
  from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id
  where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id order by pu.is_base desc,pu.is_default_sale desc,u.name;
end $$;
grant execute on function public.inventory_product_units_v481(uuid,uuid) to authenticated;

create or replace function public.inventory_product_units_save_v481(p_tenant_id uuid,p_variant_id uuid,p_base_unit_code text,p_units jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_unit uuid;v_base uuid;v_old_base uuid;v_code text;v_count int:=0;v_default_sale int:=0;v_default_purchase int:=0;v_requested_sale int:=0;v_requested_purchase int:=0;v_has_history boolean:=false;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
  if not exists(select 1 from public.product_variants pv where pv.id=p_variant_id and pv.tenant_id=p_tenant_id) then raise exception 'Product variant not found';end if;
  perform private.v481_seed_units(p_tenant_id);
  v_code:=upper(trim(coalesce(p_base_unit_code,'PCS')));
  select u.id into v_base from public.inventory_units_v481 u where u.tenant_id=p_tenant_id and u.code=v_code and u.active;
  if v_base is null then raise exception 'Base unit % not found',v_code;end if;
  select pu.unit_id into v_old_base from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.is_base and pu.active limit 1;
  if v_old_base is not null and v_old_base<>v_base then
    select exists(select 1 from public.location_stock_movements m where m.tenant_id=p_tenant_id and m.variant_id=p_variant_id)
        or exists(select 1 from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and abs(coalesce(b.quantity,0))>0.000001)
      into v_has_history;
    if v_has_history then raise exception 'Base inventory unit cannot be changed after stock/history exists. Add a conversion unit instead.';end if;
  end if;
  select count(*) filter(where coalesce((value->>'is_default_sale')::boolean,false) and coalesce((value->>'allow_sale')::boolean,true)),
         count(*) filter(where coalesce((value->>'is_default_purchase')::boolean,false) and coalesce((value->>'allow_purchase')::boolean,false))
    into v_requested_sale,v_requested_purchase
  from jsonb_array_elements(coalesce(p_units,'[]'::jsonb));
  if v_requested_sale>1 then raise exception 'Only one default sale unit is allowed';end if;
  if v_requested_purchase>1 then raise exception 'Only one default purchase unit is allowed';end if;

  -- Clear flags first; rows are preserved so historical IDs remain stable.
  update public.product_units_v481 set is_base=false,is_default_sale=false,is_default_purchase=false,active=false,updated_at=now() where tenant_id=p_tenant_id and variant_id=p_variant_id;
  insert into public.product_units_v481(tenant_id,variant_id,unit_id,is_base,allow_purchase,allow_sale,is_default_purchase,is_default_sale,conversion_to_base,quantity_step,active)
  values(p_tenant_id,p_variant_id,v_base,true,true,true,v_requested_purchase=0,v_requested_sale=0,1,coalesce((select case when allow_fractional then power(10::numeric,-least(decimal_places,3)) else 1 end from public.inventory_units_v481 where id=v_base),1),true)
  on conflict(tenant_id,variant_id,unit_id) do update set is_base=true,allow_purchase=true,allow_sale=true,is_default_purchase=(v_requested_purchase=0),is_default_sale=(v_requested_sale=0),conversion_to_base=1,quantity_step=case when excluded.quantity_step<=0 then 1 else excluded.quantity_step end,active=true,updated_at=now();

  for x in select value from jsonb_array_elements(coalesce(p_units,'[]'::jsonb)) loop
    v_unit:=null;
    if nullif(x->>'unit_id','') is not null then begin v_unit:=(x->>'unit_id')::uuid; exception when others then v_unit:=null; end; end if;
    if v_unit is null and nullif(trim(coalesce(x->>'code','')),'') is not null then select u.id into v_unit from public.inventory_units_v481 u where u.tenant_id=p_tenant_id and u.code=upper(trim(x->>'code')) and u.active;end if;
    if v_unit is null then raise exception 'Unknown unit in product conversion';end if;
    if v_unit=v_base then
      update public.product_units_v481 set
        quantity_step=coalesce(nullif(x->>'quantity_step','')::numeric,quantity_step),
        cutting_allowed=coalesce((x->>'cutting_allowed')::boolean,cutting_allowed),
        cutting_charge=coalesce(nullif(x->>'cutting_charge','')::numeric,cutting_charge),
        sale_price=nullif(x->>'sale_price','')::numeric,
        purchase_cost=nullif(x->>'purchase_cost','')::numeric,
        updated_at=now()
      where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;
      continue;
    end if;
    insert into public.product_units_v481(tenant_id,variant_id,unit_id,is_base,allow_purchase,allow_sale,is_default_purchase,is_default_sale,conversion_to_base,quantity_step,sale_price,purchase_cost,cutting_allowed,cutting_charge,active,settings)
    values(p_tenant_id,p_variant_id,v_unit,false,coalesce((x->>'allow_purchase')::boolean,false),coalesce((x->>'allow_sale')::boolean,true),coalesce((x->>'is_default_purchase')::boolean,false) and coalesce((x->>'allow_purchase')::boolean,false),coalesce((x->>'is_default_sale')::boolean,false) and coalesce((x->>'allow_sale')::boolean,true),coalesce(nullif(x->>'conversion_to_base','')::numeric,1),coalesce(nullif(x->>'quantity_step','')::numeric,1),nullif(x->>'sale_price','')::numeric,nullif(x->>'purchase_cost','')::numeric,coalesce((x->>'cutting_allowed')::boolean,false),coalesce(nullif(x->>'cutting_charge','')::numeric,0),coalesce((x->>'active')::boolean,true),coalesce(x->'settings','{}'::jsonb))
    on conflict(tenant_id,variant_id,unit_id) do update set allow_purchase=excluded.allow_purchase,allow_sale=excluded.allow_sale,is_default_purchase=excluded.is_default_purchase,is_default_sale=excluded.is_default_sale,conversion_to_base=excluded.conversion_to_base,quantity_step=excluded.quantity_step,sale_price=excluded.sale_price,purchase_cost=excluded.purchase_cost,cutting_allowed=excluded.cutting_allowed,cutting_charge=excluded.cutting_charge,active=excluded.active,settings=excluded.settings,updated_at=now();
  end loop;

  -- Guarantee one default sale/purchase among active allowed units; base is the fallback.
  select count(*) into v_default_sale from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active and allow_sale and is_default_sale;
  if v_default_sale=0 then update public.product_units_v481 set is_default_sale=true where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;end if;
  if v_default_sale>1 then raise exception 'Only one default sale unit is allowed';end if;
  select count(*) into v_default_purchase from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active and allow_purchase and is_default_purchase;
  if v_default_purchase=0 then update public.product_units_v481 set is_default_purchase=true where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;end if;
  if v_default_purchase>1 then raise exception 'Only one default purchase unit is allowed';end if;

  insert into public.product_invoice_attributes_v45(tenant_id,variant_id,unit_code,updated_at,updated_by)
  values(p_tenant_id,p_variant_id,v_code,now(),auth.uid()) on conflict(tenant_id,variant_id) do update set unit_code=excluded.unit_code,updated_at=now(),updated_by=auth.uid();
  select count(*) into v_count from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active;
  return jsonb_build_object('variant_id',p_variant_id,'base_unit_code',v_code,'active_units',v_count);
end $$;
grant execute on function public.inventory_product_units_save_v481(uuid,uuid,text,jsonb) to authenticated;

create or replace function public.inventory_create_product_v481(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_name text,p_sku text,p_item_type text,p_description text,
  p_category_name text,p_brand_name text,p_barcode text,p_part_number text,p_cost_price numeric,p_selling_price numeric,
  p_list_price numeric,p_tax_rate numeric,p_reorder_level numeric,p_opening_stock numeric,p_base_unit_code text default 'PCS',p_units jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_variant uuid;v_base_unit uuid;v_base_code text;begin
  v:=public.inventory_create_product_v4(p_tenant_id,p_location_id,p_device_id,p_name,p_sku,p_item_type,p_description,p_category_name,p_brand_name,p_barcode,p_part_number,p_cost_price,p_selling_price,p_list_price,p_tax_rate,p_reorder_level,p_opening_stock);
  v_variant:=nullif(v->>'variant_id','')::uuid;
  perform public.inventory_product_units_save_v481(p_tenant_id,v_variant,coalesce(nullif(trim(p_base_unit_code),''),case when p_item_type='service' then 'HR' else 'PCS' end),coalesce(p_units,'[]'::jsonb));
  select pu.unit_id,u.code into v_base_unit,v_base_code from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.is_base and pu.active limit 1;
  update public.location_stock_movements m set unit_id=v_base_unit,unit_code=v_base_code,conversion_to_base=1,display_quantity=m.base_quantity_delta
  where m.tenant_id=p_tenant_id and m.variant_id=v_variant and m.reference_type='product' and m.reference_id=v_variant and m.movement_type='opening' and m.unit_id is null;
  return v||jsonb_build_object('base_unit_code',upper(coalesce(nullif(trim(p_base_unit_code),''),case when p_item_type='service' then 'HR' else 'PCS' end)));
end $$;
grant execute on function public.inventory_create_product_v481(uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;

create or replace function public.inventory_list_products_v481(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_variant uuid;v_units jsonb;v_purchase_units jsonb;v_base jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select * from public.inventory_list_products_v4(p_tenant_id,p_location_id) loop
    begin v_variant:=nullif(r->>'variant_id','')::uuid; exception when others then v_variant:=null;end;
    if v_variant is null then return next r;continue;end if;
    select to_jsonb(x) into v_base from (select u.id unit_id,u.code,u.name,u.decimal_places,u.allow_fractional,pu.quantity_step,pu.cutting_allowed,pu.cutting_charge from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.is_base and pu.active limit 1) x;
    select coalesce(jsonb_agg(jsonb_build_object('unit_id',u.id,'code',u.code,'name',u.name,'decimal_places',u.decimal_places,'allow_fractional',u.allow_fractional,'conversion_to_base',pu.conversion_to_base,'quantity_step',pu.quantity_step,'sale_price',pu.sale_price,'purchase_cost',pu.purchase_cost,'cutting_allowed',pu.cutting_allowed,'cutting_charge',pu.cutting_charge,'is_default_sale',pu.is_default_sale,'is_default_purchase',pu.is_default_purchase,'allow_sale',pu.allow_sale,'allow_purchase',pu.allow_purchase,'is_base',pu.is_base,'active',pu.active) order by pu.is_default_sale desc,pu.is_base desc,u.name),'[]'::jsonb) into v_units
    from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.allow_sale;
    select coalesce(jsonb_agg(jsonb_build_object('unit_id',u.id,'code',u.code,'name',u.name,'decimal_places',u.decimal_places,'allow_fractional',u.allow_fractional,'conversion_to_base',pu.conversion_to_base,'quantity_step',pu.quantity_step,'sale_price',pu.sale_price,'purchase_cost',pu.purchase_cost,'cutting_allowed',pu.cutting_allowed,'cutting_charge',pu.cutting_charge,'is_default_sale',pu.is_default_sale,'is_default_purchase',pu.is_default_purchase,'allow_sale',pu.allow_sale,'allow_purchase',pu.allow_purchase,'is_base',pu.is_base,'active',pu.active) order by pu.is_default_purchase desc,pu.is_base desc,u.name),'[]'::jsonb) into v_purchase_units
    from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.allow_purchase;
    return next r||jsonb_build_object('base_unit',coalesce(v_base,'{}'::jsonb),'sale_units',coalesce(v_units,'[]'::jsonb),'purchase_units',coalesce(v_purchase_units,'[]'::jsonb),'base_unit_code',coalesce(v_base->>'code',r->>'unit_code','PCS'),'unit_code',coalesce(v_base->>'code',r->>'unit_code','PCS'));
  end loop;return;
end $$;
grant execute on function public.inventory_list_products_v481(uuid,uuid) to authenticated;

create or replace function public.inventory_location_movements_v481(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select jsonb_build_object('movement_id',m.id,'movement_type',m.movement_type,'movement_group',m.movement_group,'quantity_delta',coalesce(m.display_quantity,m.quantity_delta),'base_quantity_delta',coalesce(m.base_quantity_delta,m.quantity_delta),'unit_code',m.unit_code,'conversion_to_base',coalesce(m.conversion_to_base,1),'balance_before',m.balance_before,'balance_after',m.balance_after,'unit_cost',m.unit_cost,'location_id',m.location_id,'location_name',l.name,'reference_type',m.reference_type,'reference_number',m.reference_number,'note',m.note,'occurred_at',m.created_at,'created_at',m.created_at)
  from public.location_stock_movements m join public.business_locations l on l.id=m.location_id
  where m.tenant_id=p_tenant_id and m.variant_id=p_variant_id and (p_location_id is null or m.location_id=p_location_id)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,m.location_id,'view'))
  order by m.created_at desc limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.inventory_location_movements_v481(uuid,uuid,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(127,'4.8.1','Inventory & Unit Engine','Product unit configuration, conversion API, unit-aware product creation/listing and enriched stock movement history.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 127 product unit API applied' as status;

-- THQ ERP V4.8.1 — unit-aware sale/purchase transaction wrappers. Existing quantity columns remain BASE quantity.
begin;

alter table public.sale_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric,
 add column if not exists entered_unit_price numeric;
alter table public.purchase_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric,
 add column if not exists entered_unit_cost numeric;

alter table public.sales_return_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric;
alter table public.purchase_return_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric;

create or replace function private.v481_normalize_line(p_tenant_id uuid,p_item jsonb,p_mode text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_variant uuid;v_unit uuid;v_factor numeric:=1;v_qty numeric;v_price numeric;v_code text;v_step numeric:=1;v_fractional boolean:=false;begin
  v_variant:=nullif(p_item->>'variant_id','')::uuid;v_qty:=coalesce(nullif(p_item->>'quantity','')::numeric,0);
  if v_qty<=0 then raise exception 'Quantity must be greater than zero';end if;
  if nullif(p_item->>'unit_id','') is not null then v_unit:=(p_item->>'unit_id')::uuid;end if;
  if v_unit is null then select pu.unit_id into v_unit from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and ((p_mode='sale' and pu.is_default_sale) or (p_mode='purchase' and pu.is_default_purchase)) limit 1;end if;
  if v_unit is null then select pu.unit_id into v_unit from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.is_base limit 1;end if;
  select pu.conversion_to_base,u.code,pu.quantity_step,u.allow_fractional into v_factor,v_code,v_step,v_fractional
  from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id
  where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.unit_id=v_unit and pu.active
    and ((p_mode='sale' and pu.allow_sale) or (p_mode='purchase' and pu.allow_purchase));
  if v_factor is null then raise exception 'Selected unit is not enabled for this product';end if;
  v_step:=greatest(coalesce(v_step,1),0.000001);
  if not coalesce(v_fractional,false) and v_qty<>trunc(v_qty) then raise exception 'Unit % only allows whole quantities',v_code;end if;
  if abs((v_qty/v_step)-round(v_qty/v_step))>0.000001 then raise exception 'Quantity for unit % must use increments of %',v_code,v_step;end if;
  v_price:=coalesce(nullif(p_item->>case when p_mode='sale' then 'unit_price' else 'unit_cost' end,'')::numeric,0);
  if p_mode='sale' then
    return p_item||jsonb_build_object('quantity',v_qty*v_factor,'unit_price',case when v_factor=0 then v_price else v_price/v_factor end,'_entered_quantity',v_qty,'_entered_unit_id',v_unit,'_entered_unit_code',v_code,'_conversion_to_base',v_factor,'_entered_unit_price',v_price);
  end if;
  return p_item||jsonb_build_object('quantity',v_qty*v_factor,'unit_cost',case when v_factor=0 then v_price else v_price/v_factor end,'_entered_quantity',v_qty,'_entered_unit_id',v_unit,'_entered_unit_code',v_code,'_conversion_to_base',v_factor,'_entered_unit_cost',v_price);
end $$;
revoke all on function private.v481_normalize_line(uuid,jsonb,text) from public;

create or replace function private.v481_normalize_items(p_tenant_id uuid,p_items jsonb,p_mode text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v jsonb:='[]'::jsonb;v_total int;v_distinct int;begin
  select count(*),count(distinct value->>'variant_id') into v_total,v_distinct from jsonb_array_elements(coalesce(p_items,'[]'::jsonb));
  if v_total<>v_distinct then raise exception 'A product variant can appear only once per unit-aware transaction';end if;
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop v:=v||jsonb_build_array(private.v481_normalize_line(p_tenant_id,x,p_mode));end loop;
  return v;
end $$;
revoke all on function private.v481_normalize_items(uuid,jsonb,text) from public;

create or replace function public.sales_create_v481(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_items jsonb;v jsonb;v_sale uuid;x jsonb;v_variant uuid;begin
  v_items:=private.v481_normalize_items(p_tenant_id,p_items,'sale');
  v:=public.sales_create_v47(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
  v_sale:=nullif(v->>'sale_id','')::uuid;
  if v_sale is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      v_variant:=(x->>'variant_id')::uuid;
      update public.sale_items si set entered_unit_id=nullif(x->>'_entered_unit_id','')::uuid,entered_unit_code=x->>'_entered_unit_code',entered_quantity=(x->>'_entered_quantity')::numeric,conversion_to_base=(x->>'_conversion_to_base')::numeric,entered_unit_price=(x->>'_entered_unit_price')::numeric
      where si.sale_id=v_sale and si.variant_id=v_variant;
      update public.location_stock_movements m set unit_id=nullif(x->>'_entered_unit_id','')::uuid,unit_code=x->>'_entered_unit_code',display_quantity=-abs((x->>'_entered_quantity')::numeric),conversion_to_base=(x->>'_conversion_to_base')::numeric,metadata=m.metadata||jsonb_build_object('entered_unit_price',(x->>'_entered_unit_price')::numeric)
      where m.tenant_id=p_tenant_id and m.reference_type='sale' and m.reference_id=v_sale and m.variant_id=v_variant and m.movement_type='sale';
    end loop;
  end if;return v;
end $$;
grant execute on function public.sales_create_v481(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.purchases_create_v481(
 p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_items jsonb;v jsonb;v_purchase uuid;x jsonb;v_variant uuid;begin
  v_items:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
  v:=public.purchases_create_v47(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,v_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
  v_purchase:=nullif(v->>'purchase_id','')::uuid;
  if v_purchase is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      v_variant:=(x->>'variant_id')::uuid;
      update public.purchase_items pi set entered_unit_id=nullif(x->>'_entered_unit_id','')::uuid,entered_unit_code=x->>'_entered_unit_code',entered_quantity=(x->>'_entered_quantity')::numeric,conversion_to_base=(x->>'_conversion_to_base')::numeric,entered_unit_cost=(x->>'_entered_unit_cost')::numeric where pi.purchase_id=v_purchase and pi.variant_id=v_variant;
      update public.location_stock_movements m set unit_id=nullif(x->>'_entered_unit_id','')::uuid,unit_code=x->>'_entered_unit_code',display_quantity=abs((x->>'_entered_quantity')::numeric),conversion_to_base=(x->>'_conversion_to_base')::numeric,metadata=m.metadata||jsonb_build_object('entered_unit_cost',(x->>'_entered_unit_cost')::numeric)
      where m.tenant_id=p_tenant_id and m.reference_type='purchase' and m.reference_id=v_purchase and m.variant_id=v_variant and m.movement_type='purchase';
    end loop;
  end if;return v;
end $$;
grant execute on function public.purchases_create_v481(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

-- Prefer the actual transaction unit on invoice/detail APIs while base quantity remains the accounting/inventory truth.
create or replace function public.sales_get_detail_v32(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;v_items jsonb;begin
  select o.location_id into v_loc from public.document_origins o where o.entity_type='sale' and o.entity_id=p_sale_id and o.tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.sales_get_detail(p_tenant_id,p_sale_id);
  select coalesce(jsonb_agg(i.value||jsonb_build_object(
    'hsn_sac',a.hsn_sac,
    'unit_code',coalesce(si.entered_unit_code,nullif(i.value->>'unit_code',''),a.unit_code),
    'quantity',coalesce(si.entered_quantity,(i.value->>'quantity')::numeric),
    'base_quantity',coalesce(si.quantity,(i.value->>'quantity')::numeric),
    'unit_price',coalesce(si.entered_unit_price,(i.value->>'unit_price')::numeric),
    'conversion_to_base',coalesce(si.conversion_to_base,1),
    'preferred_supplier_name',a.preferred_supplier_name
  )),'[]'::jsonb) into v_items
  from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value)
  left join public.sale_items si on si.sale_id=p_sale_id and si.variant_id=nullif(i.value->>'variant_id','')::uuid
  left join public.product_invoice_attributes_v45 a on a.tenant_id=p_tenant_id and a.variant_id=nullif(i.value->>'variant_id','')::uuid;
  return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end $$;
grant execute on function public.sales_get_detail_v32(uuid,uuid) to authenticated;

create or replace function public.purchases_get_detail_v32(p_tenant_id uuid,p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;v_items jsonb;begin
  select o.location_id into v_loc from public.document_origins o where o.entity_type='purchase' and o.entity_id=p_purchase_id and o.tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.purchases_get_detail(p_tenant_id,p_purchase_id);
  select coalesce(jsonb_agg(i.value||jsonb_build_object(
    'unit_code',coalesce(pi.entered_unit_code,nullif(i.value->>'unit_code','')),
    'quantity',coalesce(pi.entered_quantity,(i.value->>'quantity')::numeric),
    'base_quantity',coalesce(pi.quantity,(i.value->>'quantity')::numeric),
    'unit_cost',coalesce(pi.entered_unit_cost,(i.value->>'unit_cost')::numeric),
    'conversion_to_base',coalesce(pi.conversion_to_base,1)
  )),'[]'::jsonb) into v_items
  from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value)
  left join public.purchase_items pi on pi.purchase_id=p_purchase_id and pi.variant_id=nullif(i.value->>'variant_id','')::uuid;
  return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end $$;
grant execute on function public.purchases_get_detail_v32(uuid,uuid) to authenticated;

-- Unit-aware return wrappers accept the quantity in the unit shown on the original document,
-- convert it back to base quantity for the proven return engine, then preserve entered-unit metadata.
create or replace function public.sales_return_create_v481(
  p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_items jsonb:='[]'::jsonb;v_si public.sale_items%rowtype;v_entered numeric;v_factor numeric;v_step numeric:=1;v_fractional boolean:=false;v jsonb;v_return uuid;begin
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select si.* into v_si from public.sale_items si where si.id=(x->>'sale_item_id')::uuid and si.sale_id=p_sale_id;
    if not found then raise exception 'Sale item not found';end if;
    v_entered:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_entered<=0 then raise exception 'Return quantity must be positive';end if;
    v_factor:=coalesce(nullif(v_si.conversion_to_base,0),1);
    if v_si.entered_unit_id is not null then
      select pu.quantity_step,u.allow_fractional into v_step,v_fractional from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_si.variant_id and pu.unit_id=v_si.entered_unit_id;
      v_step:=greatest(coalesce(v_step,1),0.000001);
      if not coalesce(v_fractional,false) and v_entered<>trunc(v_entered) then raise exception 'Return unit % only allows whole quantities',coalesce(v_si.entered_unit_code,'');end if;
      if abs((v_entered/v_step)-round(v_entered/v_step))>0.000001 then raise exception 'Return quantity for unit % must use increments of %',coalesce(v_si.entered_unit_code,''),v_step;end if;
    end if;
    v_items:=v_items||jsonb_build_array(x||jsonb_build_object('quantity',v_entered*v_factor,'_entered_quantity',v_entered,'_unit_id',v_si.entered_unit_id,'_unit_code',coalesce(v_si.entered_unit_code,''),'_conversion_to_base',v_factor));
  end loop;
  v:=public.sales_return_create_v47(p_tenant_id,p_sale_id,v_items,p_reason,p_device_id,p_request_id);
  v_return:=nullif(v->>'return_id','')::uuid;
  if v_return is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      update public.sales_return_items ri set
        entered_unit_id=nullif(x->>'_unit_id','')::uuid,
        entered_unit_code=nullif(x->>'_unit_code',''),
        entered_quantity=(x->>'_entered_quantity')::numeric,
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where ri.sales_return_id=v_return and ri.sale_item_id=(x->>'sale_item_id')::uuid;
      update public.location_stock_movements m set
        unit_id=nullif(x->>'_unit_id','')::uuid,
        unit_code=nullif(x->>'_unit_code',''),
        display_quantity=abs((x->>'_entered_quantity')::numeric),
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where m.tenant_id=p_tenant_id and m.reference_type='sales_return' and m.reference_id=v_return
        and m.variant_id=(select si.variant_id from public.sale_items si where si.id=(x->>'sale_item_id')::uuid)
        and m.movement_type in('sale_return','sales_return');
    end loop;
  end if;
  return v;
end $$;
grant execute on function public.sales_return_create_v481(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v481(
  p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_items jsonb:='[]'::jsonb;v_pi public.purchase_items%rowtype;v_entered numeric;v_factor numeric;v_step numeric:=1;v_fractional boolean:=false;v jsonb;v_return uuid;begin
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select pi.* into v_pi from public.purchase_items pi where pi.id=(x->>'purchase_item_id')::uuid and pi.purchase_id=p_purchase_id;
    if not found then raise exception 'Purchase item not found';end if;
    v_entered:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_entered<=0 then raise exception 'Return quantity must be positive';end if;
    v_factor:=coalesce(nullif(v_pi.conversion_to_base,0),1);
    if v_pi.entered_unit_id is not null then
      select pu.quantity_step,u.allow_fractional into v_step,v_fractional from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_pi.variant_id and pu.unit_id=v_pi.entered_unit_id;
      v_step:=greatest(coalesce(v_step,1),0.000001);
      if not coalesce(v_fractional,false) and v_entered<>trunc(v_entered) then raise exception 'Return unit % only allows whole quantities',coalesce(v_pi.entered_unit_code,'');end if;
      if abs((v_entered/v_step)-round(v_entered/v_step))>0.000001 then raise exception 'Return quantity for unit % must use increments of %',coalesce(v_pi.entered_unit_code,''),v_step;end if;
    end if;
    v_items:=v_items||jsonb_build_array(x||jsonb_build_object('quantity',v_entered*v_factor,'_entered_quantity',v_entered,'_unit_id',v_pi.entered_unit_id,'_unit_code',coalesce(v_pi.entered_unit_code,''),'_conversion_to_base',v_factor));
  end loop;
  v:=public.purchase_return_create_v47(p_tenant_id,p_purchase_id,v_items,p_reason,p_device_id,p_request_id);
  v_return:=nullif(v->>'return_id','')::uuid;
  if v_return is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      update public.purchase_return_items ri set
        entered_unit_id=nullif(x->>'_unit_id','')::uuid,
        entered_unit_code=nullif(x->>'_unit_code',''),
        entered_quantity=(x->>'_entered_quantity')::numeric,
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where ri.purchase_return_id=v_return and ri.purchase_item_id=(x->>'purchase_item_id')::uuid;
      update public.location_stock_movements m set
        unit_id=nullif(x->>'_unit_id','')::uuid,
        unit_code=nullif(x->>'_unit_code',''),
        display_quantity=-abs((x->>'_entered_quantity')::numeric),
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where m.tenant_id=p_tenant_id and m.reference_type='purchase_return' and m.reference_id=v_return
        and m.variant_id=(select pi.variant_id from public.purchase_items pi where pi.id=(x->>'purchase_item_id')::uuid)
        and m.movement_type='purchase_return';
    end loop;
  end if;
  return v;
end $$;
grant execute on function public.purchase_return_create_v481(uuid,uuid,jsonb,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(128,'4.8.1','Inventory & Unit Engine','Unit-aware sales and purchases preserve entered units/quantities while existing quantity columns remain canonical base quantities for stock, returns and accounting.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 128 unit transactions applied' as status;

-- THQ ERP V4.8.1 — release contract, sync hooks and verification.
begin;

-- Unit and location metadata are master-data changes and should refresh Client/POS catalog/config.
do $$ declare r record;v_name text;begin
  for r in select * from (values ('inventory_units_v481','catalogue'),('product_units_v481','catalogue')) x(table_name,domain) loop
    v_name:='trg_v481_sync_'||r.table_name;
    execute format('drop trigger if exists %I on public.%I',v_name,r.table_name);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.thq_sync_row_trigger_v480(%L)',v_name,r.table_name,r.domain);
  end loop;
end $$;


-- Extend THQ API v1 contract with the inventory/unit resources introduced in V4.8.1.
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','inventory-intelligence','inventory-movements','units','product-units',
      'customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'
    ),
    'core_financial_posting','direct_hardened_rpc','mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.1','release','Inventory & Unit Engine','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v481_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
  if to_regclass('public.inventory_units_v481') is null then v_missing:=array_append(v_missing,'inventory_units_v481');end if;
  if to_regclass('public.product_units_v481') is null then v_missing:=array_append(v_missing,'product_units_v481');end if;
  if to_regclass('public.location_stock_movements') is null then v_missing:=array_append(v_missing,'location_stock_movements');end if;
  if to_regprocedure('public.inventory_units_list_v481(uuid,boolean)') is null then v_missing:=array_append(v_missing,'inventory_units_list_v481');end if;
  if to_regprocedure('public.inventory_product_units_v481(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_product_units_v481');end if;
  if to_regprocedure('public.inventory_product_units_save_v481(uuid,uuid,text,jsonb)') is null then v_missing:=array_append(v_missing,'inventory_product_units_save_v481');end if;
  if to_regprocedure('public.inventory_list_products_v481(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_list_products_v481');end if;
  if to_regprocedure('public.inventory_movement_history_v481(uuid,uuid,uuid,text,timestamptz,timestamptz,integer)') is null then v_missing:=array_append(v_missing,'inventory_movement_history_v481');end if;
  if to_regprocedure('public.sales_create_v481(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v481');end if;
  if to_regprocedure('public.purchases_create_v481(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v481');end if;
  if to_regprocedure('public.sales_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_return_create_v481');end if;
  if to_regprocedure('public.purchase_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'purchase_return_create_v481');end if;
  if to_regprocedure('public.inventory_unit_save_v481(uuid,uuid,text,text,text,integer,boolean,boolean)') is null then v_missing:=array_append(v_missing,'inventory_unit_save_v481');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='location_stock_movements' and column_name='base_quantity_delta') then v_missing:=array_append(v_missing,'location_stock_movements.base_quantity_delta');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='location_stock_movements' and column_name='balance_after') then v_missing:=array_append(v_missing,'location_stock_movements.balance_after');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='entered_unit_id') then v_missing:=array_append(v_missing,'sale_items.entered_unit_id');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchase_items' and column_name='entered_unit_id') then v_missing:=array_append(v_missing,'purchase_items.entered_unit_id');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.1','migration_no',129,'api_version','v1','inventory_model','base-unit movement ledger');
end $$;
grant execute on function public.thq_v481_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(129,'4.8.1','Inventory & Unit Engine','Universal movement ledger, multi-unit conversion, decimal/cutting-ready sale quantities and generalized operational location types.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 129 release contract applied' as status;
