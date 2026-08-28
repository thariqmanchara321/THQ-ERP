-- THQ ERP v4.8.0 — Upgrade from migration 119
-- Apply only when the current THQ backend is already at migration 119.
-- This file concatenates migrations 120 through 124 in the required order.


-- ============================================================================
-- 120_v480_connectivity_sync.sql
-- ============================================================================

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


-- ============================================================================
-- 121_v480_operational_intelligence.sql
-- ============================================================================

-- THQ ERP V4.8.0
-- Operational Intelligence: stock/reorder, customer credit, supplier payables.
begin;

create or replace function public.inventory_intelligence_v480(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days integer default 30,
  p_query text default '',
  p_limit integer default 1000
)
returns table(
  location_id uuid,location_code text,location_name text,variant_id uuid,product_name text,sku text,
  quantity numeric,available numeric,reorder_level numeric,max_stock numeric,average_cost numeric,stock_value numeric,
  net_sold_qty numeric,avg_daily_sales numeric,days_cover numeric,suggested_reorder numeric,last_sale_date date,last_purchase_date date,status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_days integer:=greatest(1,least(coalesce(p_days,30),365));
  v_from date:=current_date-(greatest(1,least(coalesce(p_days,30),365))-1);
  q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'view') then raise exception 'Location access denied';end if;

  return query
  with sold as (
    select o.location_id,si.variant_id,
      sum(greatest(si.quantity-coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id=ri.sales_return_id
        where ri.sale_item_id=si.id and r.refund_status<>'waived' and r.return_date<=current_date
      ),0),0))::numeric qty
    from public.sale_items si join public.sales s on s.id=si.sale_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between v_from and current_date
      and coalesce(s.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,si.variant_id
  ), last_sold as (
    select o.location_id,si.variant_id,max(s.sale_date) last_sale
    from public.sale_items si join public.sales s on s.id=si.sale_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,si.variant_id
  ), purchased as (
    select o.location_id,pi.variant_id,max(p.purchase_date) last_purchase
    from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,pi.variant_id
  ), base as (
    select l.id location_id,l.location_code,l.name location_name,pv.id variant_id,p.name product_name,pv.sku,
      coalesce(b.quantity,0)::numeric quantity,
      (coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0))::numeric available,
      coalesce(s.reorder_level,pv.reorder_level,0)::numeric reorder_level,coalesce(s.max_stock,0)::numeric max_stock,
      coalesce(b.average_cost,pv.cost_price,0)::numeric average_cost,
      coalesce(so.qty,0)::numeric net_sold_qty,
      ls.last_sale,pu.last_purchase
    from public.location_product_settings s
    join public.business_locations l on l.id=s.location_id and l.tenant_id=s.tenant_id and l.active
    join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
    join public.products p on p.id=pv.product_id and p.tenant_id=s.tenant_id
    left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
    left join sold so on so.location_id=s.location_id and so.variant_id=s.variant_id
    left join last_sold ls on ls.location_id=s.location_id and ls.variant_id=s.variant_id
    left join purchased pu on pu.location_id=s.location_id and pu.variant_id=s.variant_id
    where s.tenant_id=p_tenant_id and s.active
      and (p_location_id is null or s.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view')
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(coalesce(pv.sku,'')) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q)
  )
  select b.location_id,b.location_code,b.location_name,b.variant_id,b.product_name,b.sku,b.quantity,b.available,b.reorder_level,b.max_stock,b.average_cost,
    round(b.quantity*b.average_cost,2)::numeric,
    b.net_sold_qty,round(b.net_sold_qty/v_days,4)::numeric,
    case when b.net_sold_qty<=0 then null else round(b.available/(b.net_sold_qty/v_days),1) end::numeric,
    greatest(
      case
        when b.max_stock>0 and b.available<=b.reorder_level then b.max_stock-b.available
        when b.reorder_level>0 and b.available<=b.reorder_level then greatest(b.reorder_level*2-b.available,0)
        else 0
      end,0
    )::numeric,
    b.last_sale,b.last_purchase,
    (case
      when b.available<=0 then 'out_of_stock'
      when b.reorder_level>0 and b.available<=b.reorder_level then 'low_stock'
      when b.max_stock>0 and b.available>b.max_stock then 'overstock'
      when b.net_sold_qty=0 and b.available>0 and coalesce(b.last_sale,date '1900-01-01')<current_date-interval '90 days' then 'dead_stock'
      else 'healthy' end)::text
  from base b
  order by
    case when b.available<=0 then 0 when b.reorder_level>0 and b.available<=b.reorder_level then 1 when b.net_sold_qty=0 and b.available>0 then 2 else 3 end,
    b.product_name,b.location_name
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.inventory_intelligence_v480(uuid,uuid,integer,text,integer) to authenticated;

create or replace function public.customer_credit_intelligence_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
)
returns table(
  customer_id uuid,public_id text,customer_name text,phone text,credit_limit numeric,total_outstanding numeric,available_credit numeric,utilization_pct numeric,
  current_amount numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,open_invoice_count bigint,oldest_due_date date,status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with open_sales as (
    select s.id,s.customer_id,coalesce(s.due_date,s.sale_date) due_date,
      greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance
    from public.sales s
    left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
  ), agg as (
    select os.customer_id,sum(os.balance)::numeric outstanding,count(*)::bigint cnt,min(os.due_date) oldest,
      sum(os.balance) filter(where os.due_date>=current_date)::numeric current_amt,
      sum(os.balance) filter(where os.due_date<current_date and os.due_date>=current_date-30)::numeric a1,
      sum(os.balance) filter(where os.due_date<current_date-30 and os.due_date>=current_date-60)::numeric a2,
      sum(os.balance) filter(where os.due_date<current_date-60 and os.due_date>=current_date-90)::numeric a3,
      sum(os.balance) filter(where os.due_date<current_date-90)::numeric a4
    from open_sales os group by os.customer_id
  )
  select c.id,coalesce(c.tracking_code,''),c.name,coalesce(c.phone,''),coalesce(c.credit_limit,0)::numeric,coalesce(a.outstanding,0)::numeric,
    greatest(coalesce(c.credit_limit,0)-coalesce(a.outstanding,0),0)::numeric,
    case when coalesce(c.credit_limit,0)>0 then round(coalesce(a.outstanding,0)*100/coalesce(c.credit_limit,1),1) else null end::numeric,
    coalesce(a.current_amt,0)::numeric,coalesce(a.a1,0)::numeric,coalesce(a.a2,0)::numeric,coalesce(a.a3,0)::numeric,coalesce(a.a4,0)::numeric,
    coalesce(a.cnt,0),a.oldest,
    (case when coalesce(a.outstanding,0)<=0.005 then 'clear'
      when coalesce(c.credit_limit,0)>0 and coalesce(a.outstanding,0)>c.credit_limit then 'over_limit'
      when coalesce(a.a4,0)>0 then 'critical_overdue'
      when coalesce(a.a1,0)+coalesce(a.a2,0)+coalesce(a.a3,0)>0 then 'overdue'
      else 'current' end)::text
  from public.customers c left join agg a on a.customer_id=c.id
  where c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active' and not coalesce(c.is_walk_in,false)
    and (trim(coalesce(p_query,''))='' or lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
  order by coalesce(a.a4,0) desc,coalesce(a.outstanding,0) desc,c.name
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.customer_credit_intelligence_v480(uuid,uuid,text,integer) to authenticated;

create or replace function public.supplier_payables_intelligence_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
)
returns table(
  supplier_id uuid,supplier_name text,phone text,total_outstanding numeric,current_amount numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,
  open_invoice_count bigint,oldest_due_date date,last_purchase_date date,status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with open_purchases as (
    select p.id,p.supplier_id,p.purchase_date,coalesce(p.due_date,p.purchase_date) due_date,
      greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
  ), agg as (
    select op.supplier_id,sum(op.balance)::numeric outstanding,count(*)::bigint cnt,min(op.due_date) oldest,max(op.purchase_date) last_purchase,
      sum(op.balance) filter(where op.due_date>=current_date)::numeric current_amt,
      sum(op.balance) filter(where op.due_date<current_date and op.due_date>=current_date-30)::numeric a1,
      sum(op.balance) filter(where op.due_date<current_date-30 and op.due_date>=current_date-60)::numeric a2,
      sum(op.balance) filter(where op.due_date<current_date-60 and op.due_date>=current_date-90)::numeric a3,
      sum(op.balance) filter(where op.due_date<current_date-90)::numeric a4
    from open_purchases op group by op.supplier_id
  )
  select s.id,s.name,coalesce(s.phone,''),coalesce(a.outstanding,0)::numeric,coalesce(a.current_amt,0)::numeric,coalesce(a.a1,0)::numeric,
    coalesce(a.a2,0)::numeric,coalesce(a.a3,0)::numeric,coalesce(a.a4,0)::numeric,coalesce(a.cnt,0),a.oldest,a.last_purchase,
    (case when coalesce(a.outstanding,0)<=0.005 then 'clear' when coalesce(a.a4,0)>0 then 'critical_overdue'
      when coalesce(a.a1,0)+coalesce(a.a2,0)+coalesce(a.a3,0)>0 then 'overdue' else 'current' end)::text
  from public.suppliers s left join agg a on a.supplier_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active'
    and (trim(coalesce(p_query,''))='' or lower(s.name) like q or lower(coalesce(s.phone,'')) like q)
  order by coalesce(a.a4,0) desc,coalesce(a.outstanding,0) desc,s.name
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.supplier_payables_intelligence_v480(uuid,uuid,text,integer) to authenticated;

create or replace function public.business_attention_summary_v480(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_low bigint:=0;v_out bigint:=0;v_dead bigint:=0;v_stock numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_overdue numeric:=0;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) filter(where status='low_stock'),count(*) filter(where status='out_of_stock'),count(*) filter(where status='dead_stock'),coalesce(sum(stock_value),0)
    into v_low,v_out,v_dead,v_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,'',5000);
  select coalesce(sum(total_outstanding),0),coalesce(sum(days_1_30+days_31_60+days_61_90+days_90_plus),0)
    into v_recv,v_overdue from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into v_pay from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  return jsonb_build_object('low_stock',v_low,'out_of_stock',v_out,'dead_stock',v_dead,'inventory_value',round(v_stock,2),
    'receivables',round(v_recv,2),'overdue_receivables',round(v_overdue,2),'payables',round(v_pay,2),'days',greatest(1,least(coalesce(p_days,30),365)));
end $$;
grant execute on function public.business_attention_summary_v480(uuid,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(121,'4.8.0','Operational Intelligence & Connectivity','Inventory/reorder intelligence plus return-aware customer credit ageing and supplier payable ageing.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 121 operational intelligence ready' as status;


-- ============================================================================
-- 122_v480_purchase_planning.sql
-- ============================================================================

-- THQ ERP V4.8.0
-- Purchase planning and non-posting Purchase Orders.
begin;

create sequence if not exists public.purchase_order_number_seq;

create table if not exists public.purchase_orders_v480(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  order_number text not null,
  order_date date not null default current_date,
  expected_date date,
  status text not null default 'draft' check(status in('draft','submitted','approved','ordered','cancelled')),
  notes text,
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  grand_total numeric not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  ordered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,order_number)
);
create index if not exists idx_purchase_orders_v480_lookup on public.purchase_orders_v480(tenant_id,location_id,status,order_date desc);
alter table public.purchase_orders_v480 enable row level security;
revoke all on public.purchase_orders_v480 from anon,authenticated;

create table if not exists public.purchase_order_items_v480(
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders_v480(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tax_rate numeric not null default 0,
  line_subtotal numeric not null default 0,
  tax_amount numeric not null default 0,
  line_total numeric not null default 0,
  note text,
  unique(purchase_order_id,variant_id)
);
create index if not exists idx_purchase_order_items_v480_variant on public.purchase_order_items_v480(variant_id,purchase_order_id);
alter table public.purchase_order_items_v480 enable row level security;
revoke all on public.purchase_order_items_v480 from anon,authenticated;

create table if not exists public.purchase_order_status_history_v480(
  id bigint generated always as identity primary key,
  purchase_order_id uuid not null references public.purchase_orders_v480(id) on delete cascade,
  from_status text,
  to_status text not null,
  reason text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists idx_po_status_history_v480 on public.purchase_order_status_history_v480(purchase_order_id,id);
alter table public.purchase_order_status_history_v480 enable row level security;
revoke all on public.purchase_order_status_history_v480 from anon,authenticated;

create or replace function private.purchase_planning_access_v480(p_tenant_id uuid,p_location_id uuid,p_manage boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,case when p_manage then 'operate' else 'view' end) then raise exception 'Location access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) then
    if p_manage and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase management permission required';end if;
    if not p_manage and not private.erp_has_permission(p_tenant_id,'purchases.view') and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase permission required';end if;
  end if;
end $$;
revoke all on function private.purchase_planning_access_v480(uuid,uuid,boolean) from public;

create or replace function public.purchase_reorder_suggestions_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30,p_query text default '',p_limit integer default 1000
)
returns table(
  location_id uuid,location_code text,location_name text,variant_id uuid,product_name text,sku text,current_stock numeric,reorder_level numeric,max_stock numeric,
  avg_daily_sales numeric,days_cover numeric,suggested_quantity numeric,last_supplier_id uuid,last_supplier_name text,last_unit_cost numeric,tax_rate numeric,last_purchase_date date
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with intel as (
    select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,p_query,p_limit)
    where suggested_reorder>0
  ), last_buy as (
    select distinct on(o.location_id,pi.variant_id) o.location_id,pi.variant_id,p.supplier_id,s.name supplier_name,pi.unit_cost,p.purchase_date
    from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id
    join public.suppliers s on s.id=p.supplier_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    order by o.location_id,pi.variant_id,p.purchase_date desc,p.created_at desc
  )
  select i.location_id,i.location_code,i.location_name,i.variant_id,i.product_name,i.sku,i.available,i.reorder_level,i.max_stock,
    i.avg_daily_sales,i.days_cover,i.suggested_reorder,lb.supplier_id,lb.supplier_name,coalesce(lb.unit_cost,i.average_cost,0),coalesce(pv.tax_rate,0),lb.purchase_date
  from intel i join public.product_variants pv on pv.id=i.variant_id left join last_buy lb on lb.location_id=i.location_id and lb.variant_id=i.variant_id
  order by i.location_name,i.status,i.product_name;
end $$;
grant execute on function public.purchase_reorder_suggestions_v480(uuid,uuid,integer,text,integer) to authenticated;

create or replace function public.purchase_order_create_v480(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_items jsonb,p_expected_date date default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_sub numeric:=0;v_tax numeric:=0;v_total numeric:=0;x jsonb;v_variant uuid;v_qty numeric;v_cost numeric;v_rate numeric;v_line numeric;v_line_tax numeric;begin
  perform private.purchase_planning_access_v480(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active') then raise exception 'Active supplier not found';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required';end if;
  v_no:='PO-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.purchase_order_number_seq')::text,6,'0');
  insert into public.purchase_orders_v480(id,tenant_id,location_id,supplier_id,order_number,expected_date,notes,created_by)
  values(v_id,p_tenant_id,p_location_id,p_supplier_id,v_no,p_expected_date,nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(p_items)
  loop
    v_variant:=nullif(x->>'variant_id','')::uuid;v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=greatest(coalesce(nullif(x->>'unit_cost','')::numeric,0),0);v_rate:=greatest(coalesce(nullif(x->>'tax_rate','')::numeric,0),0);
    if v_variant is null or v_qty<=0 then raise exception 'Invalid purchase order item';end if;
    if not exists(select 1 from public.product_variants where id=v_variant and tenant_id=p_tenant_id) then raise exception 'Product variant not found';end if;
    v_line:=round(v_qty*v_cost,2);v_line_tax:=round(v_line*v_rate/100.0,2);
    insert into public.purchase_order_items_v480(purchase_order_id,variant_id,quantity,unit_cost,tax_rate,line_subtotal,tax_amount,line_total,note)
    values(v_id,v_variant,v_qty,v_cost,v_rate,v_line,v_line_tax,v_line+v_line_tax,nullif(trim(coalesce(x->>'note','')),''))
    on conflict(purchase_order_id,variant_id) do update set quantity=public.purchase_order_items_v480.quantity+excluded.quantity,
      unit_cost=excluded.unit_cost,tax_rate=excluded.tax_rate,
      line_subtotal=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost,2),
      tax_amount=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost*excluded.tax_rate/100.0,2),
      line_total=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost*(1+excluded.tax_rate/100.0),2);
  end loop;
  select coalesce(sum(line_subtotal),0),coalesce(sum(tax_amount),0),coalesce(sum(line_total),0) into v_sub,v_tax,v_total from public.purchase_order_items_v480 where purchase_order_id=v_id;
  update public.purchase_orders_v480 set subtotal=v_sub,tax_total=v_tax,grand_total=v_total,updated_at=now() where id=v_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,to_status,reason,changed_by) values(v_id,'draft','Purchase order created',auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',v_id::text,'create');
  return jsonb_build_object('success',true,'purchase_order_id',v_id,'order_number',v_no,'status','draft','grand_total',v_total);
end $$;
grant execute on function public.purchase_order_create_v480(uuid,uuid,uuid,jsonb,date,text) to authenticated;

create or replace function public.purchase_order_list_v480(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,order_number text,order_date date,expected_date date,status text,location_id uuid,location_name text,supplier_id uuid,supplier_name text,grand_total numeric,item_count bigint,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select po.id,po.order_number,po.order_date,po.expected_date,po.status,po.location_id,l.name,po.supplier_id,s.name,po.grand_total,count(i.id),po.created_at
  from public.purchase_orders_v480 po join public.business_locations l on l.id=po.location_id join public.suppliers s on s.id=po.supplier_id
  left join public.purchase_order_items_v480 i on i.purchase_order_id=po.id
  where po.tenant_id=p_tenant_id and (p_location_id is null or po.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,po.location_id,p_location_id,'view')
    and (nullif(trim(coalesce(p_status,'')),'') is null or po.status=p_status)
    and (trim(coalesce(p_query,''))='' or lower(po.order_number) like q or lower(s.name) like q)
  group by po.id,l.name,s.name order by po.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
grant execute on function public.purchase_order_list_v480(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.purchase_order_detail_v480(p_tenant_id uuid,p_purchase_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_location uuid;begin
  select location_id into v_location from public.purchase_orders_v480 where id=p_purchase_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Purchase order not found';end if;perform private.purchase_planning_access_v480(p_tenant_id,v_location,false);
  select jsonb_build_object(
    'order',to_jsonb(po)||jsonb_build_object('location_name',l.name,'supplier_name',s.name),
    'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku) order by p.name) from public.purchase_order_items_v480 i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.purchase_order_id=po.id),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from public.purchase_order_status_history_v480 h where h.purchase_order_id=po.id),'[]'::jsonb)
  ) into v
  from public.purchase_orders_v480 po join public.business_locations l on l.id=po.location_id join public.suppliers s on s.id=po.supplier_id
  where po.id=p_purchase_order_id and po.tenant_id=p_tenant_id;
  return v;
end $$;
grant execute on function public.purchase_order_detail_v480(uuid,uuid) to authenticated;

create or replace function public.purchase_order_status_v480(p_tenant_id uuid,p_purchase_order_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_old text;v_loc uuid;v_allowed boolean:=false;begin
  select status,location_id into v_old,v_loc from public.purchase_orders_v480 where id=p_purchase_order_id and tenant_id=p_tenant_id for update;
  if v_old is null then raise exception 'Purchase order not found';end if;perform private.purchase_planning_access_v480(p_tenant_id,v_loc,true);
  if p_status=v_old then return jsonb_build_object('success',true,'status',v_old);end if;
  v_allowed:=case v_old when 'draft' then p_status in('submitted','cancelled') when 'submitted' then p_status in('approved','draft','cancelled') when 'approved' then p_status in('ordered','cancelled') when 'ordered' then p_status='cancelled' else false end;
  if not v_allowed then raise exception 'Invalid purchase order transition: % -> %',v_old,p_status;end if;
  if p_status='cancelled' and trim(coalesce(p_reason,''))='' then raise exception 'Cancellation reason is required';end if;
  update public.purchase_orders_v480 set status=p_status,updated_at=now(),
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then now() else approved_at end,
    ordered_at=case when p_status='ordered' then now() else ordered_at end,
    cancelled_at=case when p_status='cancelled' then now() else cancelled_at end
  where id=p_purchase_order_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
  values(p_purchase_order_id,v_old,p_status,nullif(trim(coalesce(p_reason,'')),''),auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',p_purchase_order_id::text,'status.'||p_status);
  return jsonb_build_object('success',true,'purchase_order_id',p_purchase_order_id,'from_status',v_old,'status',p_status);
end $$;
grant execute on function public.purchase_order_status_v480(uuid,uuid,text,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(122,'4.8.0','Operational Intelligence & Connectivity','Store-specific reorder suggestions and non-posting Purchase Orders with controlled workflow/history.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 122 purchase planning ready' as status;


-- ============================================================================
-- 123_v480_api_mobile_contracts.sql
-- ============================================================================

-- THQ ERP V4.8.0
-- THQ API v1 read contracts and mobile-ready summaries.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array('sync','attention','inventory-intelligence','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'),
    'core_financial_posting','direct_hardened_rpc','mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

create or replace function public.mobile_store_status_v480(p_tenant_id uuid,p_day date default current_date)
returns table(
  location_id uuid,location_code text,location_name text,sales_total numeric,returns_total numeric,net_sales numeric,gross_profit numeric,invoice_count bigint,
  inventory_value numeric,low_stock_count bigint,out_of_stock_count bigint,receivables numeric,payables numeric
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with sale as (
    select o.location_id,sum(s.grand_total)::numeric total,sum(coalesce(s.gross_profit,0))::numeric profit,count(*)::bigint cnt
    from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date=coalesce(p_day,current_date) and coalesce(s.status,'') not in('void','cancelled')
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') group by o.location_id
  ), ret as (
    select r.location_id,sum(r.grand_total)::numeric total,
      sum(coalesce(si.cost_total,0)*(ri.quantity/nullif(si.quantity,0)))::numeric returned_cost
    from public.sales_returns r join public.sales_return_items ri on ri.sales_return_id=r.id join public.sale_items si on si.id=ri.sale_item_id
    where r.tenant_id=p_tenant_id and r.return_date=coalesce(p_day,current_date) and r.refund_status<>'waived'
      and private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view') group by r.location_id
  ), stock as (
    select ii.location_id,sum(ii.stock_value)::numeric val,count(*) filter(where ii.status='low_stock')::bigint low,count(*) filter(where ii.status='out_of_stock')::bigint out
    from public.inventory_intelligence_v480(p_tenant_id,null,30,'',5000) ii group by ii.location_id
  ), recv as (
    select o.location_id,sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0))::numeric amount
    from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') group by o.location_id
  ), pay as (
    select o.location_id,sum(greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0))::numeric amount
    from public.purchases p join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') group by o.location_id
  )
  select l.id,l.location_code,l.name,coalesce(sale.total,0),coalesce(ret.total,0),greatest(coalesce(sale.total,0)-coalesce(ret.total,0),0),
    coalesce(sale.profit,0)-coalesce(ret.total-coalesce(ret.returned_cost,0),0),coalesce(sale.cnt,0),coalesce(stock.val,0),coalesce(stock.low,0),coalesce(stock.out,0),coalesce(recv.amount,0),coalesce(pay.amount,0)
  from public.business_locations l
  left join sale on sale.location_id=l.id left join ret on ret.location_id=l.id left join stock on stock.location_id=l.id left join recv on recv.location_id=l.id left join pay on pay.location_id=l.id
  where l.tenant_id=p_tenant_id and l.active and private.erp_document_scope_allowed(p_tenant_id,l.id,null,'view')
  order by l.name;
end $$;
grant execute on function public.mobile_store_status_v480(uuid,date) to authenticated;

create or replace function public.mobile_business_summary_v480(p_tenant_id uuid,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_attention jsonb;v_stores jsonb;v_sales numeric:=0;v_returns numeric:=0;v_profit numeric:=0;v_invoices bigint:=0;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_attention:=public.business_attention_summary_v480(p_tenant_id,null,30);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.location_name),'[]'::jsonb),coalesce(sum(x.sales_total),0),coalesce(sum(x.returns_total),0),coalesce(sum(x.gross_profit),0),coalesce(sum(x.invoice_count),0)
    into v_stores,v_sales,v_returns,v_profit,v_invoices
  from public.mobile_store_status_v480(p_tenant_id,p_day) x;
  return jsonb_build_object('day',coalesce(p_day,current_date),'sales',v_sales,'returns',v_returns,'net_sales',greatest(v_sales-v_returns,0),'gross_profit',v_profit,'invoice_count',v_invoices,
    'attention',v_attention,'stores',coalesce(v_stores,'[]'::jsonb),'sync',public.thq_sync_versions_v480(p_tenant_id));
end $$;
grant execute on function public.mobile_business_summary_v480(uuid,date) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(123,'4.8.0','Operational Intelligence & Connectivity','THQ API v1 contract plus authenticated mobile-ready business/store summary endpoints.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 123 API/mobile contracts ready' as status;


-- ============================================================================
-- 124_v480_release_contract.sql
-- ============================================================================

-- THQ ERP V4.8.0
-- Release hardening and final contract.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.8.0',
    'release','Operational Intelligence & Connectivity',
    'api_version','v1'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v480_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_missing text[]:='{}'::text[];begin
  if to_regclass('public.thq_sync_state_v480') is null then v_missing:=array_append(v_missing,'thq_sync_state_v480');end if;
  if to_regclass('public.purchase_orders_v480') is null then v_missing:=array_append(v_missing,'purchase_orders_v480');end if;
  if to_regprocedure('public.thq_sync_versions_v480(uuid)') is null then v_missing:=array_append(v_missing,'thq_sync_versions_v480');end if;
  if to_regprocedure('public.inventory_intelligence_v480(uuid,uuid,integer,text,integer)') is null then v_missing:=array_append(v_missing,'inventory_intelligence_v480');end if;
  if to_regprocedure('public.customer_credit_intelligence_v480(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'customer_credit_intelligence_v480');end if;
  if to_regprocedure('public.supplier_payables_intelligence_v480(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'supplier_payables_intelligence_v480');end if;
  if to_regprocedure('public.purchase_reorder_suggestions_v480(uuid,uuid,integer,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_reorder_suggestions_v480');end if;
  if to_regprocedure('public.purchase_order_create_v480(uuid,uuid,uuid,jsonb,date,text)') is null then v_missing:=array_append(v_missing,'purchase_order_create_v480');end if;
  if to_regprocedure('public.mobile_business_summary_v480(uuid,date)') is null then v_missing:=array_append(v_missing,'mobile_business_summary_v480');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.0','migration_no',124,'api_version','v1');
end $$;
grant execute on function public.thq_v480_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(124,'4.8.0','Operational Intelligence & Connectivity','Final V4.8.0 release contract: THQ API v1, synchronization, operational intelligence, purchase planning and mobile-ready read contracts.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 124 release contract applied' as status;

