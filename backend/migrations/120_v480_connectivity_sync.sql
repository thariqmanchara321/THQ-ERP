-- THQ ERP V4.8.0
-- Connectivity & synchronization foundation.
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values('operations_intelligence','Operations Intelligence','Stock, credit, payable and purchasing intelligence','Operations',false,14,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_active=true,is_beta=false,sort_order=excluded.sort_order;

-- Existing businesses that already use inventory/purchasing get the new read-only intelligence workspace.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select distinct tm.tenant_id,'operations_intelligence',true
from public.tenant_modules tm
where tm.enabled and tm.module_key in('inventory','purchases','reports')
on conflict(tenant_id,module_key) do update set enabled=true;

-- Carry the capability into templates/plans that already include Inventory or Reports.
insert into public.business_template_modules(template_id,module_key)
select distinct btm.template_id,'operations_intelligence'
from public.business_template_modules btm
where btm.module_key in('inventory','reports')
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct spm.plan_id,'operations_intelligence'
from public.subscription_plan_modules spm
where spm.module_key in('inventory','reports')
on conflict do nothing;

-- Add the module to the global Client menu without disturbing tenant-customized menus.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'client','operations_intelligence','module','operations_intelligence',p.id,'Operations Intelligence','intelligence',50
from public.app_menu_nodes_v45 p
where p.tenant_id is null and p.app_key='client' and p.node_key='overview'
on conflict do nothing;


-- Tenants with a customized Client menu must receive the node in their own tree as well.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select p.tenant_id,'client','operations_intelligence','module','operations_intelligence',p.id,'Operations Intelligence','intelligence',50
from public.app_menu_nodes_v45 p
where p.tenant_id is not null and p.app_key='client' and p.node_key='overview'
  and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p.tenant_id and tm.module_key='operations_intelligence' and tm.enabled)
on conflict do nothing;

create table if not exists public.thq_sync_state_v480(
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  configuration_version bigint not null default 1,
  catalogue_version bigint not null default 1,
  parties_version bigint not null default 1,
  transactions_version bigint not null default 1,
  inventory_version bigint not null default 1,
  finance_version bigint not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.thq_sync_state_v480 enable row level security;
revoke all on public.thq_sync_state_v480 from anon,authenticated;

create table if not exists public.thq_sync_events_v480(
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  domain text not null check(domain in('configuration','catalogue','parties','transactions','inventory','finance')),
  entity_type text,
  entity_id text,
  action text not null default 'change',
  created_at timestamptz not null default now()
);
create index if not exists idx_thq_sync_events_v480_tenant on public.thq_sync_events_v480(tenant_id,id desc);
alter table public.thq_sync_events_v480 enable row level security;
revoke all on public.thq_sync_events_v480 from anon,authenticated;

insert into public.thq_sync_state_v480(tenant_id)
select id from public.tenants
on conflict(tenant_id) do nothing;

create or replace function private.thq_sync_bump_v480(
  p_tenant_id uuid,
  p_domain text,
  p_entity_type text default null,
  p_entity_id text default null,
  p_action text default 'change'
) returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if p_tenant_id is null then return; end if;
  insert into public.thq_sync_state_v480(tenant_id) values(p_tenant_id)
  on conflict(tenant_id) do nothing;

  update public.thq_sync_state_v480 set
    configuration_version=configuration_version+case when p_domain='configuration' then 1 else 0 end,
    catalogue_version=catalogue_version+case when p_domain='catalogue' then 1 else 0 end,
    parties_version=parties_version+case when p_domain='parties' then 1 else 0 end,
    transactions_version=transactions_version+case when p_domain='transactions' then 1 else 0 end,
    inventory_version=inventory_version+case when p_domain='inventory' then 1 else 0 end,
    finance_version=finance_version+case when p_domain='finance' then 1 else 0 end,
    updated_at=now()
  where tenant_id=p_tenant_id;

  insert into public.thq_sync_events_v480(tenant_id,domain,entity_type,entity_id,action)
  values(p_tenant_id,p_domain,nullif(trim(coalesce(p_entity_type,'')),''),nullif(trim(coalesce(p_entity_id,'')),''),coalesce(nullif(trim(p_action),''),'change'));

  -- Keep metadata events bounded. Versions are authoritative; events are diagnostic hints.
  delete from public.thq_sync_events_v480 e
  where e.tenant_id=p_tenant_id and e.id < (
    select coalesce(max(x.id)-2000,0) from public.thq_sync_events_v480 x where x.tenant_id=p_tenant_id
  );
end $$;
revoke all on function private.thq_sync_bump_v480(uuid,text,text,text,text) from public;

create or replace function private.thq_sync_row_trigger_v480()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_tenant uuid;
begin
  if TG_OP='DELETE' then
    v_tenant:=old.tenant_id;
    perform private.thq_sync_bump_v480(v_tenant,TG_ARGV[0],TG_TABLE_NAME,null,lower(TG_OP));
    return old;
  end if;
  v_tenant:=new.tenant_id;
  perform private.thq_sync_bump_v480(v_tenant,TG_ARGV[0],TG_TABLE_NAME,null,lower(TG_OP));
  return new;
end $$;
revoke all on function private.thq_sync_row_trigger_v480() from public;

-- Helper to create triggers only when the table exists. Every listed table carries tenant_id.
do $$
declare r record;v_name text;
begin
  for r in select * from (values
    ('tenant_modules','configuration'),('business_locations','configuration'),('business_devices','configuration'),
    ('products','catalogue'),('product_variants','catalogue'),('location_product_settings','catalogue'),
    ('customers','parties'),('suppliers','parties'),
    ('sales','transactions'),('purchases','transactions'),('expenses','transactions'),('sales_returns','transactions'),('purchase_returns','transactions'),
    ('location_stock_balances','inventory'),
    ('journal_entries','finance'),('customer_receipts','finance')
  ) x(table_name,domain)
  loop
    if to_regclass('public.'||r.table_name) is not null then
      v_name:='trg_v480_sync_'||r.table_name;
      execute format('drop trigger if exists %I on public.%I',v_name,r.table_name);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.thq_sync_row_trigger_v480(%L)',v_name,r.table_name,r.domain);
    end if;
  end loop;
end $$;

create or replace function public.thq_sync_versions_v480(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v public.thq_sync_state_v480%rowtype;begin
  if not private.platform_v2_is_admin() and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select * into v from public.thq_sync_state_v480 where tenant_id=p_tenant_id;
  if not found then
    return jsonb_build_object('tenant_id',p_tenant_id,'configuration',1,'catalogue',1,'parties',1,'transactions',1,'inventory',1,'finance',1,'updated_at',now());
  end if;
  return jsonb_build_object(
    'tenant_id',v.tenant_id,'configuration',v.configuration_version,'catalogue',v.catalogue_version,'parties',v.parties_version,
    'transactions',v.transactions_version,'inventory',v.inventory_version,'finance',v.finance_version,'updated_at',v.updated_at
  );
end $$;
grant execute on function public.thq_sync_versions_v480(uuid) to authenticated;

create or replace function public.thq_sync_events_v480_list(p_tenant_id uuid,p_after_id bigint default 0,p_limit integer default 100)
returns table(id bigint,domain text,entity_type text,entity_id text,action text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select e.id,e.domain,e.entity_type,e.entity_id,e.action,e.created_at
  from public.thq_sync_events_v480 e where e.tenant_id=p_tenant_id and e.id>coalesce(p_after_id,0)
  order by e.id limit greatest(1,least(coalesce(p_limit,100),500));
end $$;
grant execute on function public.thq_sync_events_v480_list(uuid,bigint,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(120,'4.8.0','Operational Intelligence & Connectivity','THQ API/synchronization foundation, version state/events and Operations Intelligence module registration.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 120 connectivity/sync ready' as status;
