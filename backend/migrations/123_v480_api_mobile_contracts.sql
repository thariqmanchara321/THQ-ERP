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
