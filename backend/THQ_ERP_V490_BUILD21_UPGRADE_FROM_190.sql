-- THQ ERP v4.9.0 Build 21 incremental database upgrade: migration 190 -> 193
-- Apply only if the database is already at migration 190.


-- ============================================================================
-- MIGRATION 191: 191_v490_loan_payment_hardening.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 21 — Loan collection hardening and readable runtime errors.
begin;

-- Repair financial mappings before accepting loan collections. This is additive
-- and safe for tenants created before the v4.7 accounting provisioning trigger.
do $$
declare r record;
begin
  for r in select id from public.tenants loop
    perform private.v47_ensure_accounting_for_tenant(r.id);
  end loop;
end $$;

insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
select t.id,x.code,x.name,x.account_type,x.system_key,true,x.description
from public.tenants t
cross join (values
  ('1110','Loan Receivable','asset','loan_receivable','Outstanding principal advanced to customers/clients'),
  ('4020','Loan Interest Income','income','loan_interest_income','Interest earned on customer/client loans'),
  ('4030','Loan Penalty Income','income','loan_penalty_income','Late-payment and overdue loan charges')
) as x(code,name,account_type,system_key,description)
on conflict(tenant_id,code) do nothing;

insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,a.system_key,a.id
from public.accounting_accounts a
where a.system_key in('loan_receivable','loan_interest_income','loan_penalty_income')
on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();

create or replace function public.loan_payment_create_v490(
  p_tenant_id uuid,p_loan_id uuid,p_amount numeric,p_payment_date date default current_date,p_payment_method text default 'cash',
  p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;
  v_payment uuid:=gen_random_uuid();
  v_no text;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_remaining numeric:=round(coalesce(p_amount,0),2);
  v_method text:=lower(coalesce(nullif(trim(p_payment_method),''),'cash'));
  v_device_id uuid:=p_device_id;
  v_device_app text;
  v_device_location uuid;
  r record;
  v_pen numeric;v_int numeric;v_prin numeric;v_take numeric;
  v_total_pen numeric:=0;v_total_int numeric:=0;v_total_prin numeric:=0;
  v_lines jsonb:='[]'::jsonb;
  v_shift uuid;
begin
  if v_remaining<=0 then raise exception 'Payment amount must be positive';end if;
  if v_method not in('cash','upi','card','credit_card','debit_card','bank','bank_transfer') then
    raise exception 'Unsupported loan payment method %',v_method;
  end if;

  select * into v from public.loan_accounts_v490
  where tenant_id=p_tenant_id and id=p_loan_id for update;
  if not found then raise exception 'Loan not found';end if;

  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.collect','operate');

  -- Client workstations can have a registered Client device. It must not be
  -- treated as a POS cash drawer. Only an active POS device is retained for
  -- cash-shift posting; Client/non-POS device IDs are intentionally ignored.
  if v_device_id is not null then
    select d.app_type,d.location_id into v_device_app,v_device_location
    from public.business_devices d
    where d.id=v_device_id and d.tenant_id=p_tenant_id and d.status='active';
    if not found then
      v_device_id:=null;
      v_device_app:=null;
      v_device_location:=null;
    elsif v_device_app='pos' and v_device_location<>v.location_id then
      raise exception 'POS device belongs to a different loan location';
    elsif v_device_app<>'pos' then
      v_device_id:=null;
    end if;
  end if;

  if v.status not in('active','defaulted') then
    raise exception 'Payments are allowed only for Active/Defaulted loans';
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  select * into v from public.loan_accounts_v490
  where tenant_id=p_tenant_id and id=p_loan_id for update;

  if v_remaining>v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding+0.005 then
    raise exception 'Payment % exceeds loan outstanding %',v_remaining,
      round(v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding,2);
  end if;

  -- Re-check/repair accounting immediately before the journal is created.
  perform private.v47_ensure_accounting_for_tenant(p_tenant_id);
  if private.v4_account_id(p_tenant_id,'loan_receivable') is null then
    raise exception 'Loan receivable accounting mapping is not configured';
  end if;
  if private.v4_account_id(p_tenant_id,'loan_interest_income') is null then
    raise exception 'Loan interest income accounting mapping is not configured';
  end if;
  if private.v4_account_id(p_tenant_id,'loan_penalty_income') is null then
    raise exception 'Loan penalty income accounting mapping is not configured';
  end if;
  if private.v4_payment_account(p_tenant_id,v_method) is null then
    raise exception 'Payment account mapping is not configured for %',v_method;
  end if;

  v_no:='LPAY-'||lpad(nextval('public.loan_payment_number_seq_v490')::text,9,'0');
  insert into public.loan_payments_v490(
    id,tenant_id,loan_id,location_id,payment_number,payment_date,amount,payment_method,
    reference_number,notes,device_id,created_by
  ) values(
    v_payment,p_tenant_id,p_loan_id,v.location_id,v_no,coalesce(p_payment_date,current_date),v_amount,v_method,
    nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_device_id,auth.uid()
  );

  -- Apply penalty -> interest -> principal, oldest installment first. Future
  -- scheduled installments are valid for early/pre-payments as well.
  for r in
    select * from public.loan_schedule_v490
    where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived'
      and (principal_due+interest_due+penalty_due)-(principal_paid+interest_paid+penalty_paid)>0.005
    order by due_date,installment_no
    for update
  loop
    exit when v_remaining<=0.005;
    v_pen:=greatest(r.penalty_due-r.penalty_paid,0);
    v_int:=greatest(r.interest_due-r.interest_paid,0);
    v_prin:=greatest(r.principal_due-r.principal_paid,0);

    v_take:=least(v_remaining,v_pen);v_pen:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_int);v_int:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_prin);v_prin:=v_take;v_remaining:=v_remaining-v_take;

    if v_pen+v_int+v_prin>0 then
      update public.loan_schedule_v490
      set penalty_paid=penalty_paid+v_pen,
          interest_paid=interest_paid+v_int,
          principal_paid=principal_paid+v_prin,
          updated_at=now()
      where id=r.id;
      insert into public.loan_payment_allocations_v490(
        tenant_id,payment_id,schedule_id,principal_amount,interest_amount,penalty_amount
      ) values(p_tenant_id,v_payment,r.id,v_prin,v_int,v_pen);
      v_total_pen:=v_total_pen+v_pen;
      v_total_int:=v_total_int+v_int;
      v_total_prin:=v_total_prin+v_prin;
    end if;
  end loop;

  if v_remaining>0.005 then
    raise exception 'Payment could not be fully allocated. Remaining %',round(v_remaining,2);
  end if;

  update public.loan_payments_v490
  set principal_amount=round(v_total_prin,2),
      interest_amount=round(v_total_int,2),
      penalty_amount=round(v_total_pen,2)
  where id=v_payment;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
    'account_id',private.v4_payment_account(p_tenant_id,v_method),
    'debit',v_amount,'credit',0,'party_type','customer','party_id',v.client_id,
    'description','Loan repayment received'
  ));
  if v_total_prin>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),
      'debit',0,'credit',v_total_prin,'party_type','customer','party_id',v.client_id,
      'description','Loan principal repaid'
    ));
  end if;
  if v_total_int>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_interest_income'),
      'debit',0,'credit',v_total_int,'party_type','customer','party_id',v.client_id,
      'description','Loan interest income'
    ));
  end if;
  if v_total_pen>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_penalty_income'),
      'debit',0,'credit',v_total_pen,'party_type','customer','party_id',v.client_id,
      'description','Loan penalty income'
    ));
  end if;

  begin
    perform private.v4_journal_create(
      p_tenant_id,v.location_id,coalesce(p_payment_date,current_date),
      'Loan payment '||v_no,'loan_payment_v490',v_payment,v_no,v_lines
    );
  exception when others then
    raise exception 'Loan payment accounting post failed: %',SQLERRM;
  end;

  if v_device_id is not null and v_device_app='pos' and v_method='cash' then
    select id into v_shift from public.cashier_shifts
    where tenant_id=p_tenant_id and device_id=v_device_id and status='open'
    order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(
        tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by
      ) values(
        p_tenant_id,v_shift,'cash_in',abs(v_amount),'loan_payment_v490',v_payment,v_no,'Loan repayment',auth.uid()
      );
    end if;
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(
    p_tenant_id,p_loan_id,'payment','Loan payment received',
    jsonb_build_object(
      'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,
      'principal',round(v_total_prin,2),'interest',round(v_total_int,2),'penalty',round(v_total_pen,2),
      'payment_method',v_method
    )
  );
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v_payment::text,'create');

  return jsonb_build_object(
    'success',true,'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,
    'principal_amount',round(v_total_prin,2),'interest_amount',round(v_total_int,2),'penalty_amount',round(v_total_pen,2),
    'remaining_outstanding',greatest(round(v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding-v_amount,2),0)
  );
end $$;
grant execute on function public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(191,'4.9.0','Loan Collection Hardening','Repairs accounting mappings, separates Client devices from POS cash drawer behavior and hardens loan payment posting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 21 migration 191 loan collection hardening applied' as status;


-- ============================================================================
-- MIGRATION 192: 192_v490_party_payment_center.sql
-- ============================================================================

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


-- ============================================================================
-- MIGRATION 193: 193_v490_build21_release.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 21 — Loan collections, contrast and Party Payment Center release.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','purchase-cycle',
      'loans','loan-dashboard','loan-warnings','customer-loans','payment-center',
      'finance-operations-health','transaction-bulk-import',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'loan_engine','v4.9.0','loan_accounting','double_entry','loan_warnings',true,
    'purchase_cycle_engine','v4.9.0','transaction_bulk_import','v4.9.0','purchase_reversals','v4.9.0',
    'party_payment_center','v4.9.0','loan_collection_hardening','v4.9.0',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Payments & Collections Hardening',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build21_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'loan_payment_create_v490','loan_detail_v490','loan_dashboard_v490','loan_warnings_v490',
    'payments_party_summary_v491','payments_party_detail_v491',
    'purchase_request_create_v484','purchase_order_create_v484','goods_receipt_create_v484','purchase_invoice_create_v489',
    'supplier_payment_create_v490','transaction_bulk_import_v490','thq_api_contract_v480'
  ];
begin
  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.purchase_invoices_v484') is null then v_missing:=array_append(v_missing,'purchase_invoices_v484');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.permissions where key='payments.view') then v_missing:=array_append(v_missing,'permission.payments.view');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='payment.cash') then v_missing:=array_append(v_missing,'mapping.payment.cash');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',193,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'loan_collection_hardened',true,
    'client_device_cash_drawer_isolation',true,
    'party_grouped_receivables_payables',true,
    'sales_and_loan_customer_breakdown',true,
    'legacy_and_v2_supplier_breakdown',true,
    'supplier_unallocated_credit_awareness',true,
    'readable_edge_errors',true,
    'light_surface_text_contrast',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build21_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  193,
  '4.9.0',
  'Payments & Collections Hardening',
  'Build 21 hardens loan collection, separates Client devices from POS cash drawers, improves light-theme text contrast, and redesigns Pending Payments around customer/supplier balances with drill-down.'
)
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 21 migration 193 release applied' as status;

