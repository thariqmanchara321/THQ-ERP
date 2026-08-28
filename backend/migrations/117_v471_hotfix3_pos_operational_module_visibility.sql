-- THQ ERP V4.7.1 Hotfix 3
-- Align POS operational-module visibility with device enforcement.
-- Existing databases at migration 116 can apply this migration directly.
begin;

-- Ensure the POS operational modules exist and remain active.
insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values
  ('cashier_shifts','Cashier Shifts','Opening/closing cash and drawer reconciliation','POS',false,36,true,false,true),
  ('terminal_day','Terminal Daily','Daily terminal invoices, payment totals, cashier shift and day close','POS',false,37,true,false,false)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  requires_configuration=excluded.requires_configuration;

insert into public.module_dependencies(module_key,depends_on_module_key)
values
  ('cashier_shifts','pos'),
  ('terminal_day','pos')
on conflict do nothing;

-- A plan that includes POS also includes its operational controls. This is the
-- missing entitlement that allowed billing enforcement to require a shift
-- while the POS navigation hid the Cashier Shift screen.
insert into public.subscription_plan_modules(plan_id,module_key)
select distinct spm.plan_id, child.module_key
from public.subscription_plan_modules spm
cross join (values ('cashier_shifts'),('terminal_day')) as child(module_key)
where spm.module_key='pos'
on conflict do nothing;

-- Keep tenant-level availability aligned for every POS-enabled business.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select distinct tm.tenant_id, child.module_key, true
from public.tenant_modules tm
cross join (values ('cashier_shifts'),('terminal_day')) as child(module_key)
where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do update set enabled=true;

-- Keep future business template/application of POS consistent too.
insert into public.business_template_modules(template_id,module_key)
select distinct btm.template_id, child.module_key
from public.business_template_modules btm
cross join (values ('cashier_shifts'),('terminal_day')) as child(module_key)
where btm.module_key='pos'
on conflict do nothing;

-- Report Hotfix 3 through the common backend contract.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch — Hotfix 3'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  117,
  '4.7.1',
  'Operational Stabilization Patch — Hotfix 3',
  'Aligns cashier shift and terminal daily subscription/tenant visibility with POS device enforcement so enabled operational modules are visible in POS.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

-- Release guard: every plan with POS must expose both operational modules.
do $$
begin
  if exists(
    select 1
    from public.subscription_plan_modules pos
    where pos.module_key='pos'
      and not exists(
        select 1 from public.subscription_plan_modules c
        where c.plan_id=pos.plan_id and c.module_key='cashier_shifts'
      )
  ) then
    raise exception 'Cashier Shift entitlement backfill incomplete';
  end if;

  if exists(
    select 1
    from public.subscription_plan_modules pos
    where pos.module_key='pos'
      and not exists(
        select 1 from public.subscription_plan_modules c
        where c.plan_id=pos.plan_id and c.module_key='terminal_day'
      )
  ) then
    raise exception 'Terminal Daily entitlement backfill incomplete';
  end if;

  if exists(
    select 1
    from public.tenant_modules pos
    where pos.module_key='pos' and pos.enabled
      and not exists(
        select 1 from public.tenant_modules c
        where c.tenant_id=pos.tenant_id and c.module_key='cashier_shifts' and c.enabled
      )
  ) then
    raise exception 'Cashier Shift tenant-module backfill incomplete';
  end if;
end $$;

commit;
select 'THQ ERP V4.7.1 Hotfix 3 migration 117 applied' as status;
