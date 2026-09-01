-- THQ ERP V4.8.7 — mobile sales/purchases/inventory/outstanding status contracts.
begin;

create or replace function public.mobile_sales_status_v487(p_tenant_id uuid,p_device_id uuid,p_location_id uuid default null,p_limit integer default 100)
returns table(id uuid,sale_number text,sale_date date,customer_name text,status text,grand_total numeric,paid_total numeric,balance_due numeric,location_name text)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_bound uuid;v_loc uuid;
begin
  v_bound:=private.v487_client_mobile_location(p_tenant_id,p_device_id);v_loc:=p_location_id;
  return query
  select s.id,s.sale_number,s.sale_date,c.name,coalesce(s.status,'posted'),s.grand_total,coalesce(py.paid,0)::numeric,
    greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric,l.name
  from public.sales s join public.customers c on c.id=s.customer_id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
  where s.tenant_id=p_tenant_id and (v_loc is null or o.location_id=v_loc) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,v_loc,'view')
  order by s.sale_date desc,s.created_at desc limit greatest(1,least(coalesce(p_limit,100),500));
end$$;
grant execute on function public.mobile_sales_status_v487(uuid,uuid,uuid,integer) to authenticated;

create or replace function public.mobile_purchases_status_v487(p_tenant_id uuid,p_device_id uuid,p_location_id uuid default null,p_limit integer default 100)
returns table(document_type text,id uuid,document_number text,document_date date,supplier_name text,status text,grand_total numeric,balance_due numeric,location_name text)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  return query
  select * from (
    select 'purchase_order'::text,o.id,o.order_number,o.order_date,s.name,o.status,o.grand_total,0::numeric,l.name
      from public.purchase_orders_v480 o join public.suppliers s on s.id=o.supplier_id join public.business_locations l on l.id=o.location_id
      where o.tenant_id=p_tenant_id and (p_location_id is null or o.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    union all
    select 'purchase_invoice'::text,i.id,i.invoice_number,i.invoice_date,s.name,i.status,i.grand_total,i.balance_due,l.name
      from public.purchase_invoices_v484 i join public.suppliers s on s.id=i.supplier_id join public.business_locations l on l.id=i.location_id
      where i.tenant_id=p_tenant_id and (p_location_id is null or i.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
    union all
    select 'legacy_purchase'::text,p.id,p.purchase_number,p.purchase_date,s.name,coalesce(p.status,'posted'),p.grand_total,
      greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric,l.name
      from public.purchases p join public.suppliers s on s.id=p.supplier_id
      left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      left join public.business_locations l on l.id=o.location_id
      left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
      left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
      where p.tenant_id=p_tenant_id and (p_location_id is null or o.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  ) q order by document_date desc limit greatest(1,least(coalesce(p_limit,100),500));
end$$;
grant execute on function public.mobile_purchases_status_v487(uuid,uuid,uuid,integer) to authenticated;

create or replace function public.mobile_inventory_status_v487(p_tenant_id uuid,p_device_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 250)
returns table(location_id uuid,location_name text,variant_id uuid,product_name text,sku text,available numeric,reorder_level numeric,stock_value numeric,status text)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  return query select x.location_id,x.location_name,x.variant_id,x.product_name,x.sku,x.available,x.reorder_level,x.stock_value,x.status
  from public.inventory_intelligence_v480(p_tenant_id,p_location_id,30,p_query,p_limit) x;
end$$;
grant execute on function public.mobile_inventory_status_v487(uuid,uuid,uuid,text,integer) to authenticated;

create or replace function public.mobile_customer_outstanding_v487(p_tenant_id uuid,p_device_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 250)
returns table(customer_id uuid,public_id text,customer_name text,phone text,total_outstanding numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,open_invoice_count bigint,oldest_due_date date,status text)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  return query select x.customer_id,x.public_id,x.customer_name,x.phone,x.total_outstanding,x.days_1_30,x.days_31_60,x.days_61_90,x.days_90_plus,x.open_invoice_count,x.oldest_due_date,x.status
  from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) x where x.total_outstanding>0.005;
end$$;
grant execute on function public.mobile_customer_outstanding_v487(uuid,uuid,uuid,text,integer) to authenticated;

create or replace function public.mobile_supplier_outstanding_v487(p_tenant_id uuid,p_device_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 250)
returns table(supplier_id uuid,supplier_name text,phone text,total_outstanding numeric,current_amount numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,open_invoice_count bigint,oldest_due_date date,status text)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  return query
  with legacy as (
    select p.supplier_id,coalesce(p.due_date,p.purchase_date) due_date,greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled') and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view') and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
  ), v2 as (
    select i.supplier_id,coalesce(i.due_date,i.invoice_date) due_date,i.balance_due::numeric balance
    from public.purchase_invoices_v484 i where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and i.balance_due>0.005
      and (p_location_id is null or i.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
  ), open_docs as (select * from legacy union all select * from v2), agg as (
    select d.supplier_id,sum(d.balance)::numeric outstanding,count(*)::bigint cnt,min(d.due_date) oldest,
      sum(d.balance) filter(where d.due_date>=current_date)::numeric current_amt,
      sum(d.balance) filter(where d.due_date<current_date and d.due_date>=current_date-30)::numeric a1,
      sum(d.balance) filter(where d.due_date<current_date-30 and d.due_date>=current_date-60)::numeric a2,
      sum(d.balance) filter(where d.due_date<current_date-60 and d.due_date>=current_date-90)::numeric a3,
      sum(d.balance) filter(where d.due_date<current_date-90)::numeric a4
    from open_docs d group by d.supplier_id
  )
  select s.id,s.name,coalesce(s.phone,''),coalesce(a.outstanding,0),coalesce(a.current_amt,0),coalesce(a.a1,0),coalesce(a.a2,0),coalesce(a.a3,0),coalesce(a.a4,0),coalesce(a.cnt,0),a.oldest,
    case when coalesce(a.a4,0)>0 then 'critical_overdue' when coalesce(a.a1,0)+coalesce(a.a2,0)+coalesce(a.a3,0)>0 then 'overdue' else 'current' end::text
  from public.suppliers s join agg a on a.supplier_id=s.id
  where s.tenant_id=p_tenant_id and (trim(coalesce(p_query,''))='' or lower(s.name) like q or lower(coalesce(s.phone,'')) like q)
  order by coalesce(a.a4,0) desc,coalesce(a.outstanding,0) desc,s.name limit greatest(1,least(coalesce(p_limit,250),2000));
end$$;
grant execute on function public.mobile_supplier_outstanding_v487(uuid,uuid,uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(162,'4.8.7','Client Mobile','Phone-oriented sales, purchasing, inventory, customer receivables and unified supplier payable status feeds.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.7 migration 162 mobile status feeds applied' as status;
