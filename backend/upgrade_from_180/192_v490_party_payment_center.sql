-- THQ ERP v4.9.0 Build 21 — Party-centric Pending Payments / Receivables & Payables.
begin;

create or replace function public.payments_party_summary_v491(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_query text default '',
  p_limit integer default 500
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_receivables jsonb;
  v_payables jsonb;
  v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
  v_limit int:=greatest(1,least(coalesce(p_limit,500),2000));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'purchases.manage')
     and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Permission denied';
  end if;

  with sale_paid as (
    select sale_id,sum(amount)::numeric paid from public.sale_payments group by sale_id
  ), sale_returned as (
    select sale_id,sum(grand_total)::numeric returned
    from public.sales_returns where refund_status<>'waived' group by sale_id
  ), sale_docs as (
    select s.customer_id party_id,'sale'::text source_type,s.id source_id,
      coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,
      s.sale_date doc_date,s.due_date,
      s.grand_total::numeric total,coalesce(sp.paid,0)::numeric paid,
      greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)::numeric balance,
      o.location_id,l.name location_name
    from public.sales s
    left join sale_paid sp on sp.sale_id=s.id
    left join sale_returned sr on sr.sale_id=s.id
    left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
    left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('cancelled','void')
      and greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  ), loan_docs as (
    select l.client_id party_id,'loan'::text source_type,l.id source_id,l.loan_number reference,
      coalesce(l.disbursement_date,l.created_at::date) doc_date,
      coalesce((select min(s.due_date) from public.loan_schedule_v490 s
        where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
          and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005),l.maturity_date) due_date,
      (l.principal_amount+l.interest_outstanding+l.penalty_outstanding)::numeric total,
      l.total_paid::numeric paid,
      (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)::numeric balance,
      l.location_id,bl.name location_name
    from public.loan_accounts_v490 l
    join public.business_locations bl on bl.id=l.location_id
    where l.tenant_id=p_tenant_id and l.status in('active','defaulted')
      and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), customer_docs as (
    select * from sale_docs union all select * from loan_docs
  ), customer_rows as (
    select c.id party_id,'customer'::text party_type,c.name party_name,
      coalesce(c.tracking_code,'') tracking_code,coalesce(c.phone,'') phone,coalesce(c.email,'') email,
      round(sum(d.balance),2) balance,
      round(sum(case when d.source_type='sale' then d.balance else 0 end),2) sales_outstanding,
      round(sum(case when d.source_type='loan' then d.balance else 0 end),2) loan_outstanding,
      round(sum(case when d.due_date is not null and d.due_date<current_date then d.balance else 0 end),2) overdue,
      count(*)::int document_count,min(d.due_date) filter(where d.due_date>=current_date) next_due_date,
      max(d.doc_date) last_activity_date
    from customer_docs d join public.customers c on c.id=d.party_id and c.tenant_id=p_tenant_id
    where trim(coalesce(p_query,''))='' or lower(c.name) like v_q or lower(coalesce(c.tracking_code,'')) like v_q
      or lower(coalesce(c.phone,'')) like v_q or lower(coalesce(c.email,'')) like v_q
    group by c.id,c.name,c.tracking_code,c.phone,c.email
    order by sum(d.balance) desc,c.name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.balance desc,r.party_name),'[]'::jsonb)
  into v_receivables from customer_rows r;

  with purchase_paid as (
    select purchase_id,sum(amount)::numeric paid from public.purchase_payments group by purchase_id
  ), purchase_returned as (
    select purchase_id,sum(grand_total)::numeric returned
    from public.purchase_returns where credit_status<>'waived' group by purchase_id
  ), legacy_docs as (
    select p.supplier_id party_id,'purchase'::text source_type,p.id source_id,
      coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,
      p.purchase_date doc_date,p.due_date,p.grand_total::numeric total,coalesce(pp.paid,0)::numeric paid,
      greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)::numeric balance,
      o.location_id,l.name location_name
    from public.purchases p
    left join purchase_paid pp on pp.purchase_id=p.id
    left join purchase_returned pr on pr.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
    left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('cancelled','void')
      and greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  ), v2_docs as (
    select i.supplier_id party_id,'purchase_invoice'::text source_type,i.id source_id,
      i.invoice_number reference,i.invoice_date doc_date,i.due_date,i.grand_total::numeric total,
      i.paid_total::numeric paid,i.balance_due::numeric balance,i.location_id,l.name location_name
    from public.purchase_invoices_v484 i join public.business_locations l on l.id=i.location_id
    where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and i.balance_due>0.005
      and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
  ), supplier_docs as (
    select * from legacy_docs union all select * from v2_docs
  ), supplier_credits as (
    select p.supplier_id,
      round(sum(greatest(p.amount-coalesce(a.allocated,0),0)),2)::numeric credit_balance
    from public.supplier_payments_v484 p
    left join (
      select supplier_payment_id,sum(amount)::numeric allocated
      from public.supplier_payment_allocations_v484 group by supplier_payment_id
    ) a on a.supplier_payment_id=p.id
    where p.tenant_id=p_tenant_id and p.status='posted'
      and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')
    group by p.supplier_id
  ), supplier_rows as (
    select s.id party_id,'supplier'::text party_type,s.name party_name,
      coalesce(s.tracking_code,'') tracking_code,coalesce(s.phone,'') phone,coalesce(s.email,'') email,
      round(greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0),2) balance,
      round(sum(case when d.source_type='purchase' then d.balance else 0 end),2) purchase_outstanding,
      round(sum(case when d.source_type='purchase_invoice' then d.balance else 0 end),2) invoice_outstanding,
      round(coalesce(sc.credit_balance,0),2) credit_balance,
      round(sum(case when d.due_date is not null and d.due_date<current_date then d.balance else 0 end),2) overdue,
      count(*)::int document_count,min(d.due_date) filter(where d.due_date>=current_date) next_due_date,
      max(d.doc_date) last_activity_date
    from supplier_docs d join public.suppliers s on s.id=d.party_id and s.tenant_id=p_tenant_id
    left join supplier_credits sc on sc.supplier_id=s.id
    where trim(coalesce(p_query,''))='' or lower(s.name) like v_q or lower(coalesce(s.tracking_code,'')) like v_q
      or lower(coalesce(s.phone,'')) like v_q or lower(coalesce(s.email,'')) like v_q
    group by s.id,s.name,s.tracking_code,s.phone,s.email,sc.credit_balance
    having greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0)>0.005 or coalesce(sc.credit_balance,0)>0.005
    order by greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0) desc,s.name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.balance desc,r.party_name),'[]'::jsonb)
  into v_payables from supplier_rows r;

  return jsonb_build_object(
    'receivables',v_receivables,
    'payables',v_payables,
    'totals',jsonb_build_object(
      'receivable',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_receivables) x),0),
      'payable',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_payables) x),0),
      'customer_count',jsonb_array_length(v_receivables),
      'supplier_count',jsonb_array_length(v_payables)
    )
  );
end $$;
grant execute on function public.payments_party_summary_v491(uuid,uuid,text,integer) to authenticated;

create or replace function public.payments_party_detail_v491(
  p_tenant_id uuid,
  p_party_type text,
  p_party_id uuid,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_party jsonb;
  v_documents jsonb:='[]'::jsonb;
  v_payments jsonb:='[]'::jsonb;
  v_credit numeric:=0;
  v_kind text:=lower(trim(coalesce(p_party_type,'')));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'purchases.manage')
     and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Permission denied';end if;

  if v_kind='customer' then
    select jsonb_build_object(
      'party_id',c.id,'party_type','customer','party_name',c.name,'tracking_code',coalesce(c.tracking_code,''),
      'phone',coalesce(c.phone,''),'email',coalesce(c.email,''),'tax_number',coalesce(c.tax_number,'')
    ) into v_party from public.customers c where c.tenant_id=p_tenant_id and c.id=p_party_id;
    if v_party is null then raise exception 'Customer not found';end if;

    with sale_paid as (
      select sale_id,sum(amount)::numeric paid from public.sale_payments group by sale_id
    ), sale_returned as (
      select sale_id,sum(grand_total)::numeric returned from public.sales_returns where refund_status<>'waived' group by sale_id
    ), docs as (
      select 'sale'::text source_type,s.id source_id,
        coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,s.sale_date doc_date,s.due_date,
        s.grand_total::numeric total,coalesce(sp.paid,0)::numeric paid,
        greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)::numeric balance,
        coalesce(s.status,'') status,o.location_id,l.name location_name,
        jsonb_build_object('returned',coalesce(sr.returned,0),'sale_number',s.sale_number) extra
      from public.sales s
      left join sale_paid sp on sp.sale_id=s.id left join sale_returned sr on sr.sale_id=s.id
      left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where s.tenant_id=p_tenant_id and s.customer_id=p_party_id and coalesce(s.status,'') not in('cancelled','void')
        and greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select 'loan'::text,l.id,l.loan_number,coalesce(l.disbursement_date,l.created_at::date),
        coalesce((select min(sc.due_date) from public.loan_schedule_v490 sc where sc.tenant_id=l.tenant_id and sc.loan_id=l.id and sc.status<>'waived'
          and (sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid)>0.005),l.maturity_date),
        (l.principal_amount+l.interest_outstanding+l.penalty_outstanding)::numeric,l.total_paid::numeric,
        (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)::numeric,l.status,l.location_id,bl.name,
        jsonb_build_object(
          'principal_outstanding',l.principal_outstanding,'interest_outstanding',l.interest_outstanding,
          'penalty_outstanding',l.penalty_outstanding,'interest_rate',l.interest_rate,'rate_type',l.rate_type,
          'maturity_date',l.maturity_date,'repayment_frequency',l.repayment_frequency,'repayment_term_count',l.repayment_term_count
        )
      from public.loan_accounts_v490 l join public.business_locations bl on bl.id=l.location_id
      where l.tenant_id=p_tenant_id and l.client_id=p_party_id and l.status in('active','defaulted')
        and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_type',source_type,'source_id',source_id,'reference',reference,'date',doc_date,'due_date',due_date,
      'total',total,'paid',paid,'balance',balance,'status',status,'location_id',location_id,'location_name',location_name,
      'overdue',due_date is not null and due_date<current_date,'extra',extra
    ) order by coalesce(due_date,doc_date),doc_date),'[]'::jsonb) into v_documents from docs;

    with payments as (
      select coalesce(sp.paid_at,sp.created_at) ts,'sale_payment'::text payment_type,sp.id,
        coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,sp.amount::numeric amount,sp.payment_method,
        null::text payment_number,o.location_id,l.name location_name
      from public.sale_payments sp join public.sales s on s.id=sp.sale_id
      left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where s.tenant_id=p_tenant_id and s.customer_id=p_party_id
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select lp.created_at,'loan_payment',lp.id,la.loan_number,lp.amount,lp.payment_method,lp.payment_number,lp.location_id,bl.name
      from public.loan_payments_v490 lp join public.loan_accounts_v490 la on la.id=lp.loan_id
      join public.business_locations bl on bl.id=lp.location_id
      where lp.tenant_id=p_tenant_id and la.client_id=p_party_id and lp.status='posted'
        and private.erp_document_scope_allowed(p_tenant_id,lp.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_type',payment_type,'payment_id',id,'reference',reference,'payment_number',payment_number,
      'date',ts::date,'amount',amount,'payment_method',payment_method,'location_id',location_id,'location_name',location_name
    ) order by ts desc),'[]'::jsonb) into v_payments from (select * from payments order by ts desc limit 100) p;

  elsif v_kind='supplier' then
    select jsonb_build_object(
      'party_id',s.id,'party_type','supplier','party_name',s.name,'tracking_code',coalesce(s.tracking_code,''),
      'phone',coalesce(s.phone,''),'email',coalesce(s.email,''),'tax_number',coalesce(s.tax_number,'')
    ) into v_party from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_party_id;
    if v_party is null then raise exception 'Supplier not found';end if;

    with purchase_paid as (
      select purchase_id,sum(amount)::numeric paid from public.purchase_payments group by purchase_id
    ), purchase_returned as (
      select purchase_id,sum(grand_total)::numeric returned from public.purchase_returns where credit_status<>'waived' group by purchase_id
    ), docs as (
      select 'purchase'::text source_type,p.id source_id,
        coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,p.purchase_date doc_date,p.due_date,
        p.grand_total::numeric total,coalesce(pp.paid,0)::numeric paid,
        greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)::numeric balance,
        coalesce(p.status,'') status,o.location_id,l.name location_name,
        jsonb_build_object('returned',coalesce(pr.returned,0),'purchase_number',p.purchase_number) extra
      from public.purchases p
      left join purchase_paid pp on pp.purchase_id=p.id left join purchase_returned pr on pr.purchase_id=p.id
      left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and coalesce(p.status,'') not in('cancelled','void')
        and greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select 'purchase_invoice'::text,i.id,i.invoice_number,i.invoice_date,i.due_date,i.grand_total,i.paid_total,i.balance_due,
        i.status,i.location_id,bl.name,
        jsonb_build_object('supplier_invoice_number',coalesce(i.supplier_invoice_number,''),'purchase_order_id',i.purchase_order_id)
      from public.purchase_invoices_v484 i join public.business_locations bl on bl.id=i.location_id
      where i.tenant_id=p_tenant_id and i.supplier_id=p_party_id and i.status in('posted','part_paid') and i.balance_due>0.005
        and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_type',source_type,'source_id',source_id,'reference',reference,'date',doc_date,'due_date',due_date,
      'total',total,'paid',paid,'balance',balance,'status',status,'location_id',location_id,'location_name',location_name,
      'overdue',due_date is not null and due_date<current_date,'extra',extra
    ) order by coalesce(due_date,doc_date),doc_date),'[]'::jsonb) into v_documents from docs;

    select coalesce(sum(greatest(p.amount-coalesce(a.allocated,0),0)),0) into v_credit
    from public.supplier_payments_v484 p
    left join (
      select supplier_payment_id,sum(amount)::numeric allocated from public.supplier_payment_allocations_v484 group by supplier_payment_id
    ) a on a.supplier_payment_id=p.id
    where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and p.status='posted'
      and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');

    with payments as (
      select coalesce(pp.paid_at,pp.created_at) ts,'purchase_payment'::text payment_type,pp.id,
        coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,pp.amount::numeric amount,pp.payment_method,
        null::text payment_number,o.location_id,l.name location_name
      from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id
      left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select sp.created_at,'supplier_payment',sp.id,sp.reference_number,sp.amount,sp.payment_method,sp.payment_number,sp.location_id,bl.name
      from public.supplier_payments_v484 sp join public.business_locations bl on bl.id=sp.location_id
      where sp.tenant_id=p_tenant_id and sp.supplier_id=p_party_id and sp.status='posted'
        and private.erp_document_scope_allowed(p_tenant_id,sp.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_type',payment_type,'payment_id',id,'reference',coalesce(reference,''),'payment_number',payment_number,
      'date',ts::date,'amount',amount,'payment_method',payment_method,'location_id',location_id,'location_name',location_name
    ) order by ts desc),'[]'::jsonb) into v_payments from (select * from payments order by ts desc limit 100) p;
  else
    raise exception 'Party type must be customer or supplier';
  end if;

  return jsonb_build_object(
    'party',v_party,
    'documents',v_documents,
    'recent_payments',v_payments,
    'gross_outstanding',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x),0),
    'credit_balance',round(coalesce(v_credit,0),2),
    'net_outstanding',greatest(coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x),0)-coalesce(v_credit,0),0),
    'overdue',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x where coalesce((x->>'overdue')::boolean,false)),0)
  );
end $$;
grant execute on function public.payments_party_detail_v491(uuid,text,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(192,'4.9.0','Party Payment Center','Pending Payments is grouped by customer/supplier with sales, loans, legacy purchases, Purchasing V2 invoices, credits and payment drill-down.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 21 migration 192 party payment center applied' as status;
