-- THQ ERP — Aggregate / Material Yard foundation.
-- Live backend schema release number: 303.
--
-- Safety contract:
-- * Additive only.
-- * Does not enable Aggregate Yard for existing tenants.
-- * Does not replace or modify authoritative Sales/Purchase/GST/accounting writers.
-- * Adds a tenant-gated Client module, system template, navigation entry and
--   aggregate-oriented UOM defaults that seed only when the module is enabled.

begin;

insert into public.modules(
  key,name,description,category,is_core,sort_order,
  is_active,is_beta,requires_configuration
)
values(
  'aggregate_yard',
  'Material Yard',
  'Aggregate, M-Sand and bulk-material yard workspace built on THQ Sales, Purchase, Inventory and Vehicle Logistics',
  'Operations',
  false,
  18,
  true,
  false,
  true
)
on conflict(key) do update
set name=excluded.name,
    description=excluded.description,
    category=excluded.category,
    is_core=excluded.is_core,
    sort_order=excluded.sort_order,
    is_active=true,
    requires_configuration=true;

insert into public.module_dependencies(module_key,depends_on_module_key)
values
  ('aggregate_yard','inventory'),
  ('aggregate_yard','sales'),
  ('aggregate_yard','purchases'),
  ('aggregate_yard','customers'),
  ('aggregate_yard','suppliers')
on conflict do nothing;

insert into public.module_business_types(module_key,business_type)
values('aggregate_yard','Building Materials / Aggregate Yard')
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct s.plan_id,'aggregate_yard'
from public.subscription_plan_modules s
join public.subscription_plan_modules p
  on p.plan_id=s.plan_id and p.module_key='purchases'
where s.module_key='sales'
on conflict do nothing;

insert into public.business_templates(
  key,name,business_type,description,is_system,sort_order,settings
)
values(
  'aggregate_yard',
  'Building Materials / Aggregate Yard',
  'Building Materials / Aggregate Yard',
  'M-Sand, metal and bulk-material trading with yard inventory and truck-linked operations',
  true,
  45,
  '{
    "aggregate.default_uom":"CFT",
    "aggregate.capacity_warning":true,
    "aggregate.direct_delivery":true,
    "inventory.allow_negative_stock":false
  }'::jsonb
)
on conflict(key) do update
set name=excluded.name,
    business_type=excluded.business_type,
    description=excluded.description,
    is_system=true,
    sort_order=excluded.sort_order,
    settings=excluded.settings;

delete from public.business_template_modules btm
using public.business_templates bt
where bt.id=btm.template_id
  and bt.key='aggregate_yard';

insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key
from public.business_templates bt
join (values
  ('dashboard'),
  ('aggregate_yard'),
  ('inventory'),
  ('sales'),
  ('purchases'),
  ('customers'),
  ('suppliers'),
  ('expenses'),
  ('accounting'),
  ('reports'),
  ('stock_transfers'),
  ('vehicle_logistics'),
  ('settings')
) x(module_key) on true
where bt.key='aggregate_yard'
  and exists(select 1 from public.modules m where m.key=x.module_key)
on conflict do nothing;

insert into public.app_menu_nodes_v45(
  tenant_id,app_key,node_key,node_type,module_key,parent_id,label,
  icon_key,sort_order,enabled,collapsed_by_default,metadata
)
select
  null,'client','aggregate_yard','module','aggregate_yard',
  p.id,'Material Yard','aggregate_yard',5,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p
where p.tenant_id is null
  and p.app_key='client'
  and p.node_key='operations'
on conflict do nothing;

create or replace function private.aggregate_yard_seed_units_v617(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if p_tenant_id is null then
    raise exception 'Tenant is required';
  end if;

  insert into public.inventory_units_v481(
    tenant_id,code,name,unit_group,decimal_places,
    allow_fractional,system_unit,active
  )
  values
    (p_tenant_id,'CFT','Cubic Foot','volume',3,true,true,true),
    (p_tenant_id,'CBM','Cubic Metre','volume',3,true,true,true),
    (p_tenant_id,'TON','Tonne','weight',3,true,true,true),
    (p_tenant_id,'LOAD','Load','count',3,true,true,true),
    (p_tenant_id,'BRASS','Brass','volume',3,true,true,true)
  on conflict(tenant_id,code) do update
  set active=true,
      updated_at=now();
end
$$;

revoke all on function private.aggregate_yard_seed_units_v617(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_module_seed_v617()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.module_key='aggregate_yard' and new.enabled then
    perform private.aggregate_yard_seed_units_v617(new.tenant_id);
  end if;
  return new;
end
$$;

revoke all on function private.aggregate_yard_module_seed_v617()
from public,anon,authenticated;

drop trigger if exists trg_aggregate_yard_module_seed_v617
on public.tenant_modules;

create trigger trg_aggregate_yard_module_seed_v617
after insert or update of enabled,module_key
on public.tenant_modules
for each row
execute function private.aggregate_yard_module_seed_v617();

do $$
declare r record;
begin
  for r in
    select tenant_id
    from public.tenant_modules
    where module_key='aggregate_yard'
      and enabled
  loop
    perform private.aggregate_yard_seed_units_v617(r.tenant_id);
  end loop;
end
$$;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  303,
  '6.1.7-aggregate-foundation',
  'Aggregate / Material Yard Foundation',
  'Tenant-gated Material Yard module, reusable business template, Client navigation entry and CFT/CBM/TON/LOAD/BRASS unit seeding. Existing tenants remain disabled. No Sales, Purchase, GST, accounting or stock writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
