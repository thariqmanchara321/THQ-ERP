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
