-- THQ ERP v4.9.0 Build 19 — fast transaction entry + detail workspaces.
-- Keeps schema_version on the 4.9.0 compatibility line so existing Build 18
-- clients remain valid while Build 19 introduces forward-compatible checks.
begin;

-- -----------------------------------------------------------------------------
-- Module catalogue: keep the stable sales/purchases keys but present them as
-- fast entry modules, then add separate management/detail modules.
-- -----------------------------------------------------------------------------
update public.modules
set name='New Sale',
    description='Fast sales invoice entry'
where key='sales';

update public.modules
set name='New Purchase',
    description='Fast direct purchase entry'
where key='purchases';

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values
  ('sales_details','Sales Details','Sales history and invoice detail workspace','Operations',false,31,true,false,false),
  ('purchase_details','Purchase Details','Purchase requests, orders, GRN, supplier invoices, ledger, price history and purchase history','Operations',false,41,true,false,false)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  is_beta=false;

insert into public.module_dependencies(module_key,depends_on_module_key)
values
  ('sales_details','sales'),
  ('purchase_details','purchases')
on conflict do nothing;

-- Existing tenants that can transact automatically receive the matching detail
-- workspace. This is additive; no existing base module is renamed or removed.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tenant_id,'sales_details',true
from public.tenant_modules
where module_key='sales' and enabled
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select tenant_id,'purchase_details',true
from public.tenant_modules
where module_key='purchases' and enabled
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.business_template_modules(template_id,module_key)
select distinct template_id,'sales_details'
from public.business_template_modules
where module_key='sales'
on conflict do nothing;

insert into public.business_template_modules(template_id,module_key)
select distinct template_id,'purchase_details'
from public.business_template_modules
where module_key='purchases'
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'sales_details'
from public.subscription_plan_modules
where module_key='sales'
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'purchase_details'
from public.subscription_plan_modules
where module_key='purchases'
on conflict do nothing;

-- Keep the companion detail workspaces automatically entitled on all future
-- plan edits/creates. The existing procedure name/signature is preserved for
-- older Admin builds.
create or replace function public.platform_subscription_plan_upsert(
  p_id uuid,p_key text,p_name text,p_description text,p_monthly_price numeric,p_yearly_price numeric,p_currency_code text,p_is_active boolean,p_sort_order integer,p_module_keys text[],p_limits jsonb
)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.platform_v2_has_role('billing_admin') then raise exception 'Billing admin access required'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Plan key and name are required'; end if;
  if coalesce(p_monthly_price,0)<0 or coalesce(p_yearly_price,0)<0 then raise exception 'Prices cannot be negative'; end if;
  if p_id is null then
    insert into public.subscription_plans(key,name,description,monthly_price,yearly_price,currency_code,is_active,sort_order,limits)
    values(trim(p_key),trim(p_name),nullif(trim(p_description),''),coalesce(p_monthly_price,0),coalesce(p_yearly_price,0),upper(coalesce(nullif(trim(p_currency_code),''),'INR')),coalesce(p_is_active,true),coalesce(p_sort_order,100),coalesce(p_limits,'{}'::jsonb))
    on conflict(key) do update set name=excluded.name,description=excluded.description,monthly_price=excluded.monthly_price,yearly_price=excluded.yearly_price,currency_code=excluded.currency_code,is_active=excluded.is_active,sort_order=excluded.sort_order,limits=excluded.limits,updated_at=now()
    returning id into v_id;
  else
    update public.subscription_plans set name=trim(p_name),description=nullif(trim(p_description),''),monthly_price=coalesce(p_monthly_price,0),yearly_price=coalesce(p_yearly_price,0),currency_code=upper(coalesce(nullif(trim(p_currency_code),''),'INR')),is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,100),limits=coalesce(p_limits,limits),updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Plan not found'; end if;
  end if;

  delete from public.subscription_plan_modules where plan_id=v_id;
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,x
  from unnest(coalesce(p_module_keys,array[]::text[])) x
  where exists(select 1 from public.modules m where m.key=x and m.is_active)
  on conflict do nothing;

  -- Required base dependencies when a detail module is selected directly.
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,md.depends_on_module_key
  from public.subscription_plan_modules chosen
  join public.module_dependencies md on md.module_key=chosen.module_key
  join public.modules dependency on dependency.key=md.depends_on_module_key and dependency.is_active
  where chosen.plan_id=v_id
  on conflict do nothing;

  -- Companion workspaces always follow the fast transaction module.
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,'sales_details'
  where exists(select 1 from public.subscription_plan_modules where plan_id=v_id and module_key='sales')
    and exists(select 1 from public.modules where key='sales_details' and is_active)
  on conflict do nothing;

  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,'purchase_details'
  where exists(select 1 from public.subscription_plan_modules where plan_id=v_id and module_key='purchases')
    and exists(select 1 from public.modules where key='purchase_details' and is_active)
  on conflict do nothing;

  insert into public.subscription_plan_modules(plan_id,module_key) values(v_id,'dashboard') on conflict do nothing;
  perform private.platform_audit_write('subscription_plan.upsert','subscription_plan',v_id::text,null,jsonb_build_object('key',p_key));
  return v_id;
end $$;
grant execute on function public.platform_subscription_plan_upsert(uuid,text,text,text,numeric,numeric,text,boolean,integer,text[],jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Client navigation. Add to both the global/default menu and any tenant menu
-- that has already been cloned/customized. Existing New Sale/New Purchase nodes
-- are retained, so older Client builds keep resolving the same module keys.
-- -----------------------------------------------------------------------------
insert into public.app_menu_nodes_v45(
  tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata
)
select p.tenant_id,'client','sales_details','module','sales_details',p.id,
       'Sales Details','sales',25,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p
where p.app_key='client' and p.node_key='operations' and p.node_type='group'
on conflict do nothing;

insert into public.app_menu_nodes_v45(
  tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata
)
select p.tenant_id,'client','purchase_details','module','purchase_details',p.id,
       'Purchase Details','purchases',35,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p
where p.app_key='client' and p.node_key='operations' and p.node_type='group'
on conflict do nothing;

-- Keep default labels explicit without changing tenant-customized labels.
update public.app_menu_nodes_v45
set label='New Sale', sort_order=20, updated_at=now()
where tenant_id is null and app_key='client' and node_key='sales' and module_key='sales';

update public.app_menu_nodes_v45
set label='New Purchase', sort_order=30, updated_at=now()
where tenant_id is null and app_key='client' and node_key='purchases' and module_key='purchases';

-- -----------------------------------------------------------------------------
-- Compatibility contract.
-- schema_version stays 4.9.0 intentionally. Build 18's exact-version startup
-- check therefore continues to work after migration 186. Build 19 and later use
-- minimum_app_version instead of exact schema equality, allowing future additive
-- backend migrations without forcing a Client EXE replacement.
-- -----------------------------------------------------------------------------
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Transaction Workspaces',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build19_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
begin
  if not exists(select 1 from public.modules where key='sales' and is_active) then
    v_missing:=array_append(v_missing,'module.sales');
  end if;
  if not exists(select 1 from public.modules where key='sales_details' and is_active) then
    v_missing:=array_append(v_missing,'module.sales_details');
  end if;
  if not exists(select 1 from public.modules where key='purchases' and is_active) then
    v_missing:=array_append(v_missing,'module.purchases');
  end if;
  if not exists(select 1 from public.modules where key='purchase_details' and is_active) then
    v_missing:=array_append(v_missing,'module.purchase_details');
  end if;
  if not exists(select 1 from public.module_dependencies where module_key='sales_details' and depends_on_module_key='sales') then
    v_missing:=array_append(v_missing,'dependency.sales_details.sales');
  end if;
  if not exists(select 1 from public.module_dependencies where module_key='purchase_details' and depends_on_module_key='purchases') then
    v_missing:=array_append(v_missing,'dependency.purchase_details.purchases');
  end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='sales_details' and module_key='sales_details') then
    v_missing:=array_append(v_missing,'navigation.client.sales_details');
  end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='purchase_details' and module_key='purchase_details') then
    v_missing:=array_append(v_missing,'navigation.client.purchase_details');
  end if;
  if to_regprocedure('public.purchases_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,uuid,uuid,text)') is null then
    v_missing:=array_append(v_missing,'purchases_create_v489');
  end if;
  if to_regprocedure('public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then
    v_missing:=array_append(v_missing,'sales_create_v489');
  end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',186,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'new_purchase_fast_entry',true,
    'purchase_details_workspace',true,
    'new_sale_fast_entry',true,
    'sales_details_workspace',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build19_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  186,
  '4.9.0',
  'Transaction Workspaces',
  'Build 19 separates fast New Purchase/New Sale entry from Purchase Details/Sales Details and introduces forward-compatible Client/backend version checks.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 19 migration 186 transaction workspaces applied' as status;
