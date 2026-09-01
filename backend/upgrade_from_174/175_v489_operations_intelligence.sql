-- THQ ERP v4.8.9 — operational intelligence consolidation.
-- Makes the existing intelligence APIs aware of Purchasing V2, transfers,
-- offline sync, trace expiry and restaurant operations.
begin;

create or replace function public.supplier_payables_intelligence_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
)
returns table(
  supplier_id uuid,supplier_name text,phone text,total_outstanding numeric,current_amount numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,
  open_invoice_count bigint,oldest_due_date date,last_purchase_date date,status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with legacy_open as (
    select p.supplier_id,p.purchase_date,coalesce(p.due_date,p.purchase_date) due_date,
      greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
  ), v2_open as (
    select i.supplier_id,i.invoice_date as purchase_date,coalesce(i.due_date,i.invoice_date) due_date,
      greatest(i.balance_due,0)::numeric balance
    from public.purchase_invoices_v484 i
    where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and i.balance_due>0.005
      and (p_location_id is null or i.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
  ), open_docs as (
    select * from legacy_open
    union all
    select * from v2_open
  ), agg as (
    select op.supplier_id,sum(op.balance)::numeric outstanding,count(*)::bigint cnt,min(op.due_date) oldest,max(op.purchase_date) last_purchase,
      coalesce(sum(op.balance) filter(where op.due_date>=current_date),0)::numeric current_amt,
      coalesce(sum(op.balance) filter(where op.due_date<current_date and op.due_date>=current_date-30),0)::numeric a1,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-30 and op.due_date>=current_date-60),0)::numeric a2,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-60 and op.due_date>=current_date-90),0)::numeric a3,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-90),0)::numeric a4
    from open_docs op group by op.supplier_id
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

create or replace function public.operations_pipeline_v489(
  p_tenant_id uuid,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_pr bigint:=0;v_po bigint:=0;v_grn bigint:=0;v_invoice bigint:=0;
  v_transit bigint:=0;v_conflicts bigint:=0;v_batches bigint:=0;v_warranty bigint:=0;
  v_restaurant bigint:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) into v_pr from public.purchase_requests_v484 r
   where r.tenant_id=p_tenant_id and r.status='submitted'
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select count(*) into v_po from public.purchase_orders_v480 p
   where p.tenant_id=p_tenant_id and p.status='submitted'
     and (p_location_id is null or p.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');
  select count(*) into v_grn from public.goods_receipts_v484 g
   where g.tenant_id=p_tenant_id and g.status='draft'
     and (p_location_id is null or g.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,g.location_id,p_location_id,'view');
  select count(*) into v_invoice from public.purchase_invoices_v484 i
   where i.tenant_id=p_tenant_id and i.status='draft'
     and (p_location_id is null or i.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view');
  select count(*) into v_transit from public.stock_transfers t
   where t.tenant_id=p_tenant_id and t.status in('dispatched','in_transit')
     and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
     and (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,p_location_id,'view')
       or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,p_location_id,'view'));
  select count(*) into v_conflicts from public.pos_offline_sync_v486 q
   where q.tenant_id=p_tenant_id and q.status in('conflict','error')
     and (p_location_id is null or q.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,q.location_id,p_location_id,'view');
  select count(distinct b.id) into v_batches
    from public.inventory_batches_v483 b
    join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
   where b.tenant_id=p_tenant_id and b.status='active' and b.expiry_on between current_date and current_date+30
     and bb.quantity>0 and (p_location_id is null or bb.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,p_location_id,'view');
  select count(*) into v_warranty from public.product_warranties_v483 w
   where w.tenant_id=p_tenant_id and w.status='active' and w.warranty_expiry between current_date and current_date+30
     and exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=w.sale_id
       and (p_location_id is null or o.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view'));
  select count(*) into v_restaurant from public.restaurant_orders r
   where r.tenant_id=p_tenant_id and coalesce(r.status,'') not in('billed','cancelled','closed')
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  return jsonb_build_object(
    'purchase_requests_awaiting_approval',v_pr,
    'purchase_orders_awaiting_approval',v_po,
    'draft_grns',v_grn,
    'draft_purchase_invoices',v_invoice,
    'transfers_in_transit',v_transit,
    'offline_pos_conflicts',v_conflicts,
    'batches_expiring_30d',v_batches,
    'warranties_expiring_30d',v_warranty,
    'restaurant_open_orders',v_restaurant
  );
end $$;
grant execute on function public.operations_pipeline_v489(uuid,uuid) to authenticated;

create or replace function public.business_attention_summary_v480(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_low bigint:=0;v_out bigint:=0;v_dead bigint:=0;v_stock numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_overdue numeric:=0;v_pipeline jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) filter(where status='low_stock'),count(*) filter(where status='out_of_stock'),count(*) filter(where status='dead_stock'),coalesce(sum(stock_value),0)
    into v_low,v_out,v_dead,v_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,'',5000);
  select coalesce(sum(total_outstanding),0),coalesce(sum(days_1_30+days_31_60+days_61_90+days_90_plus),0)
    into v_recv,v_overdue from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into v_pay from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  v_pipeline:=public.operations_pipeline_v489(p_tenant_id,p_location_id);
  return jsonb_build_object('low_stock',v_low,'out_of_stock',v_out,'dead_stock',v_dead,'inventory_value',round(v_stock,2),
    'receivables',round(v_recv,2),'overdue_receivables',round(v_overdue,2),'payables',round(v_pay,2),'days',greatest(1,least(coalesce(p_days,30),365)))||v_pipeline;
end $$;
grant execute on function public.business_attention_summary_v480(uuid,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(175,'4.8.9','Stabilization & Operations','Unified legacy + Purchasing V2 supplier payables and cross-module operational attention pipeline.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 175 operations intelligence applied' as status;
