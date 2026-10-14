-- THQ ERP V7.1.5 — Customer Statement and On-Account Advance Receipt Integrity
-- 1. Full customer statement including Sales Invoices, Sales Returns (Credit Notes),
--    Customer Account Receipts, and direct POS/Sale Payments with opening balance & store scoping.
-- 2. Customer on-account advance receipts support (never blocks when invoice balance is 0 or payment exceeds balance).
-- 3. Supplier statement opening balance calculation parity when date-filtered.
begin;

-- ============================================================================
-- 1. CUSTOMERS GET STATEMENT V715
-- ============================================================================
create or replace function public.customers_get_statement_v715(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_from date default null,
  p_to date default null,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable security definer
set search_path = public, private, pg_temp
as $$
declare
  v_is_platform boolean := private.platform_v2_is_admin();
  v_name text;
  v_opening_balance numeric := 0;
  v_rows jsonb;
  v_debit numeric := 0;
  v_credit numeric := 0;
begin
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then
      raise exception 'Access denied';
    end if;
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'customers.view')
       and not private.erp_has_permission(p_tenant_id,'customers.manage')
       and not private.erp_has_permission(p_tenant_id,'sales.view')
       and not private.erp_has_permission(p_tenant_id,'sales.manage')
       and not private.erp_has_permission(p_tenant_id,'payments.receive') then
      raise exception 'Customer statement permission required';
    end if;
  end if;

  select name into v_name
  from public.customers
  where id=p_customer_id and tenant_id=p_tenant_id;

  if v_name is null then
    raise exception 'Customer not found';
  end if;

  with raw as (
    -- 1. Sales invoices (Debit)
    select
      coalesce(s.created_at, s.sale_date::timestamp) as ts,
      s.sale_date as entry_date,
      'sale'::text as entry_type,
      s.sale_number as reference,
      'Sales invoice'::text as description,
      s.grand_total::numeric as debit,
      0::numeric as credit,
      o.location_id
    from public.sales s
    left join public.document_origins o
      on o.entity_type='sale' and o.entity_id=s.id and o.tenant_id=s.tenant_id
    where s.tenant_id=p_tenant_id
      and s.customer_id=p_customer_id
      and coalesce(s.status,'') not in('void','cancelled')

    union all

    -- 2. Sales Returns / Credit Notes (Credit)
    select
      coalesce(sr.created_at, sr.return_date::timestamp) as ts,
      sr.return_date as entry_date,
      'sales_return'::text as entry_type,
      sr.return_number as reference,
      'Sales return / Credit note (' || coalesce(s.sale_number, 'Sale') || ')'::text as description,
      0::numeric as debit,
      sr.grand_total::numeric as credit,
      sr.location_id
    from public.sales_returns sr
    join public.sales s on s.id=sr.sale_id
    where sr.tenant_id=p_tenant_id
      and s.customer_id=p_customer_id
      and sr.refund_status <> 'waived'

    union all

    -- 3. Customer Account Receipts (Credit)
    select
      coalesce(r.created_at, r.receipt_date::timestamp) as ts,
      r.receipt_date as entry_date,
      'receipt'::text as entry_type,
      r.receipt_number as reference,
      'Customer account receipt (' || upper(r.payment_method) || ')' ||
        case when nullif(trim(coalesce(r.notes,'')),'') is not null then ' • ' || trim(r.notes) else '' end as description,
      0::numeric as debit,
      r.amount::numeric as credit,
      r.location_id
    from public.customer_receipts r
    where r.tenant_id=p_tenant_id
      and r.customer_id=p_customer_id
      and r.status='posted'

    union all

    -- 4. Direct Sale Payments (Credit, not from customer account receipts)
    select
      coalesce(sp.paid_at, sp.created_at) as ts,
      coalesce(sp.paid_at, sp.created_at)::date as entry_date,
      'payment'::text as entry_type,
      s.sale_number as reference,
      'Sale payment (' || upper(sp.payment_method) || ')' as description,
      0::numeric as debit,
      sp.amount::numeric as credit,
      o.location_id
    from public.sale_payments sp
    join public.sales s on s.id=sp.sale_id
    left join public.document_origins o
      on o.entity_type='sale' and o.entity_id=s.id and o.tenant_id=s.tenant_id
    where s.tenant_id=p_tenant_id
      and s.customer_id=p_customer_id
      and coalesce(s.status,'') not in('void','cancelled')
      and sp.id not in (
        select a.payment_id
        from public.customer_receipt_allocations a
        join public.customer_receipts r on r.id=a.receipt_id
        where a.payment_id is not null and r.status='posted'
      )
      and not exists (
        select 1
        from public.customer_receipts r
        where r.tenant_id=s.tenant_id
          and r.customer_id=s.customer_id
          and r.status='posted'
          and sp.notes like '%Receipt ' || r.receipt_number || '%'
      )
  ),
  scoped as (
    select * from raw
    where (v_is_platform or location_id is null or private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view'))
      and (p_location_id is null or location_id=p_location_id)
  ),
  opening as (
    select coalesce(sum(debit - credit), 0) as op_bal
    from scoped
    where p_from is not null and entry_date < p_from
  ),
  period_rows as (
    select s.*, op.op_bal
    from scoped s
    cross join opening op
    where (p_from is null or s.entry_date >= p_from)
      and (p_to is null or s.entry_date <= p_to)
  ),
  running as (
    select *,
      op_bal + sum(debit - credit) over(order by ts, entry_type, reference rows unbounded preceding) as balance
    from period_rows
  )
  select
    coalesce((select op_bal from opening), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'entry_date',entry_date,
      'entry_type',entry_type,
      'reference',reference,
      'description',description,
      'debit',debit,
      'credit',credit,
      'balance',balance
    ) order by ts,entry_type,reference),'[]'::jsonb),
    coalesce(sum(debit),0),
    coalesce(sum(credit),0)
  into v_opening_balance,v_rows,v_debit,v_credit
  from running;

  return jsonb_build_object(
    'party_id',p_customer_id,
    'party_name',v_name,
    'opening_balance',v_opening_balance,
    'total_debit',v_debit,
    'total_credit',v_credit,
    'closing_balance',v_opening_balance + v_debit - v_credit,
    'rows',v_rows
  );
end $$;

-- Backward compatible customers_get_statement wrapper
create or replace function public.customers_get_statement(p_tenant_id uuid, p_customer_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = public, private, pg_temp
as $$
begin
  return public.customers_get_statement_v715(p_tenant_id, p_customer_id, null, null, null);
end $$;

grant execute on function public.customers_get_statement_v715(uuid,uuid,date,date,uuid) to authenticated, service_role;
grant execute on function public.customers_get_statement(uuid,uuid) to authenticated, service_role;


-- ============================================================================
-- 2. SUPPLIERS GET STATEMENT OPENING BALANCE CORRECTION
-- ============================================================================
create or replace function public.suppliers_get_statement_v484(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_from date default null,
  p_to date default null,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_name text;
  v_opening_balance numeric := 0;
  v_rows jsonb;
  v_debit numeric := 0;
  v_credit numeric := 0;
begin
  perform private.purchasing_v484_permission(p_tenant_id,false);
  select name into v_name from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id;
  if v_name is null then raise exception 'Supplier not found'; end if;

  with raw as (
    select
      p.purchase_date::timestamp as ts,
      p.purchase_date as entry_date,
      'legacy_purchase'::text as entry_type,
      p.purchase_number as reference,
      'Legacy purchase bill'::text as description,
      p.grand_total::numeric as debit,
      0::numeric as credit,
      o.location_id
    from public.purchases p
    left join public.document_origins o
      on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id
    where p.tenant_id=p_tenant_id
      and p.supplier_id=p_supplier_id
      and coalesce(p.status,'') not in('cancelled','void')

    union all

    select
      coalesce(pp.paid_at,pp.created_at) as ts,
      coalesce(pp.paid_at,pp.created_at)::date as entry_date,
      'legacy_payment'::text as entry_type,
      p.purchase_number as reference,
      'Legacy supplier payment'::text as description,
      0::numeric as debit,
      pp.amount::numeric as credit,
      o.location_id
    from public.purchase_payments pp
    join public.purchases p on p.id=pp.purchase_id
    left join public.document_origins o
      on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id
    where p.tenant_id=p_tenant_id
      and p.supplier_id=p_supplier_id

    union all

    select
      e.created_at as ts,
      e.entry_date,
      e.entry_type,
      e.reference_number as reference,
      coalesce(e.description,'') as description,
      e.debit,
      e.credit,
      e.location_id
    from public.supplier_ledger_entries_v484 e
    where e.tenant_id=p_tenant_id
      and e.supplier_id=p_supplier_id
  ),
  scoped as (
    select * from raw
    where (p_location_id is null or location_id=p_location_id)
      and (location_id is null or private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view'))
  ),
  opening as (
    select coalesce(sum(debit - credit), 0) as op_bal
    from scoped
    where p_from is not null and entry_date < p_from
  ),
  period_rows as (
    select s.*, op.op_bal
    from scoped s
    cross join opening op
    where (p_from is null or s.entry_date >= p_from)
      and (p_to is null or s.entry_date <= p_to)
  ),
  running as (
    select *,
      op_bal + sum(debit - credit) over(order by ts, entry_type, reference rows unbounded preceding) as balance
    from period_rows
  )
  select
    coalesce((select op_bal from opening), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'entry_date',entry_date,
      'entry_type',entry_type,
      'reference',reference,
      'description',description,
      'debit',debit,
      'credit',credit,
      'balance',balance
    ) order by ts,entry_type,reference),'[]'::jsonb),
    coalesce(sum(debit),0),
    coalesce(sum(credit),0)
  into v_opening_balance,v_rows,v_debit,v_credit
  from running;

  return jsonb_build_object(
    'party_id',p_supplier_id,
    'party_name',v_name,
    'opening_balance',v_opening_balance,
    'total_debit',v_debit,
    'total_credit',v_credit,
    'closing_balance',v_opening_balance + v_debit - v_credit,
    'rows',v_rows
  );
end $$;

create or replace function public.suppliers_get_statement(p_tenant_id uuid, p_supplier_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
begin
  return public.suppliers_get_statement_v484(p_tenant_id, p_supplier_id, null, null, null);
end $$;

grant execute on function public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid) to authenticated, service_role;
grant execute on function public.suppliers_get_statement(uuid,uuid) to authenticated, service_role;


-- ============================================================================
-- 3. CUSTOMER RECEIVE PAYMENT WITH ON-ACCOUNT ADVANCE SUPPORT
-- ============================================================================
create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_sale_id uuid default null,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;
  v_receipt uuid := gen_random_uuid();
  v_receipt_no text;
  v_remaining numeric := round(coalesce(p_amount,0),2);
  v_total_outstanding numeric := 0;
  v_location uuid := p_location_id;
  v_sale record;
  v_alloc numeric;
  v_result jsonb;
  v_payment_id uuid;
  v_started timestamptz := clock_timestamp();
  v_lines jsonb;
  v_response jsonb;
  v_is_platform boolean := private.platform_v2_is_admin();
  v_device_type text;
  v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;
  v_existing := private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');
  if v_existing is not null then return v_existing; end if;

  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then
      raise exception 'Access denied';
    end if;
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'payments.receive')
       and not private.erp_has_permission(p_tenant_id,'sales.manage') then
      raise exception 'Receive payment permission required';
    end if;
  end if;

  if v_remaining <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers
  where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false)
  for update;

  if not found then
    raise exception 'Select an active non-walk-in customer';
  end if;

  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then
    raise exception 'Invalid payment method';
  end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found'; end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then
        raise exception 'Collecting POS/location mismatch';
      end if;
      v_location := v_device_location;
    else
      v_location := coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then
      perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');
    end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0)
  into v_total_outstanding
  from public.sales s
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));

  -- Location resolution for receipt recording
  if v_location is null then
    select o.location_id into v_location
    from public.sales s
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null then
    select id into v_location
    from public.business_locations
    where tenant_id=p_tenant_id and active
    order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then
    raise exception 'Could not determine collection location';
  end if;

  v_receipt_no := 'RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');

  insert into public.customer_receipts(
    id,tenant_id,customer_id,receipt_number,receipt_date,amount,
    payment_method,reference_number,notes,location_id,device_id,created_by
  )
  values(
    v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,round(coalesce(p_amount,0),2),
    lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),
    nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid()
  );

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric as balance,o.location_id
    from public.sales s
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0) > 0.005
      and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining <= 0.005;
    v_alloc := least(v_remaining, v_sale.balance);
    v_payment_id := null;
    if v_is_platform then
      v_payment_id := private.v471_platform_insert_sale_payment(
        v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,
        coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no
      );
    else
      v_result := public.sales_add_payment_v32(
        p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,
        coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no
      );
      begin
        v_payment_id := nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;
      exception when others then
        v_payment_id := null;
      end;
      if v_payment_id is null then
        select sp.id into v_payment_id
        from public.sale_payments sp
        where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds'
        order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;

    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);

    v_remaining := v_remaining - v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);

  -- Note: If v_remaining > 0.005, it represents unallocated on-account deposit / advance.
  -- Double-entry accounting: Debit Cash/Bank, Credit Accounts Receivable (Customer).
  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id',private.v4_payment_account(p_tenant_id,p_payment_method),
      'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,
      'description','Customer account receipt'
    ),
    jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),
      'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,
      'description','Receivable settlement' || case when v_remaining > 0.005 then ' (includes on-account advance)' else '' end
    )
  );
  perform private.v4_journal_create(
    p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,
    'customer_receipt',v_receipt,v_receipt_no,v_lines
  );

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s
    where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null::jsonb,
    jsonb_build_object(
      'receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),
      'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id,
      'unallocated_advance',round(v_remaining,2)
    )
  );

  v_response := jsonb_build_object(
    'success',true,
    'receipt_id',v_receipt,
    'receipt_number',v_receipt_no,
    'amount',p_amount,
    'allocated_amount',round(p_amount - v_remaining, 2),
    'unallocated_amount',round(v_remaining, 2),
    'outstanding_before',v_total_outstanding,
    'outstanding_after',greatest(v_total_outstanding - (p_amount - v_remaining), 0)
  );

  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;

grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated, service_role;


-- ============================================================================
-- 4. CUSTOMER ACCOUNT V471 REFRESH (WITH ADVANCE & ALLOCATED AMOUNTS)
-- ============================================================================
create or replace function public.customer_account_v471(
  p_tenant_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_customer jsonb;
  v_invoices jsonb;
  v_receipts jsonb;
  v_invoice_outstanding numeric := 0;
  v_unallocated_advance numeric := 0;
  v_platform boolean := private.platform_v2_is_admin();
begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not v_platform
     and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;

  select to_jsonb(c)
  into v_customer
  from public.customers c
  where c.id=p_customer_id and c.tenant_id=p_tenant_id;

  if v_customer is null then raise exception 'Customer not found'; end if;

  select
    coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id',s.id,
          'sale_number',s.sale_number,
          'sale_date',s.sale_date,
          'due_date',s.due_date,
          'grand_total',s.grand_total,
          'paid',coalesce(py.paid,0),
          'returned',coalesce(rt.returned,0),
          'balance',greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0),
          'location_id',o.location_id,
          'location_name',l.name
        )
        order by coalesce(s.due_date,s.sale_date),s.created_at
      ) filter(
        where greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
      ),
      '[]'::jsonb
    )
  into v_invoice_outstanding,v_invoices
  from public.sales s
  left join (
    select sale_id,sum(amount) paid
    from public.sale_payments
    group by sale_id
  ) py on py.sale_id=s.id
  left join (
    select sale_id,sum(grand_total) returned
    from public.sales_returns
    where refund_status<>'waived'
    group by sale_id
  ) rt on rt.sale_id=s.id
  left join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  where s.tenant_id=p_tenant_id
    and s.customer_id=p_customer_id
    and coalesce(s.status,'') not in('void','cancelled')
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'));

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'receipt_id',r.id,
        'receipt_number',r.receipt_number,
        'receipt_date',r.receipt_date,
        'amount',r.amount,
        'allocated_amount',coalesce(al.allocated,0),
        'unallocated_amount',greatest(r.amount - coalesce(al.allocated,0),0),
        'payment_method',r.payment_method,
        'reference_number',r.reference_number,
        'notes',r.notes,
        'status',r.status,
        'voided_at',r.voided_at,
        'void_reason',r.void_reason,
        'reversal_journal_id',r.reversal_journal_id,
        'location_id',r.location_id,
        'location_name',l.name,
        'device_id',r.device_id,
        'device_name',d.name,
        'created_at',r.created_at,
        'allocations',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'sale_id',a.sale_id,
              'sale_number',s.sale_number,
              'amount',a.amount
            )
          )
          from public.customer_receipt_allocations a
          join public.sales s on s.id=a.sale_id
          where a.receipt_id=r.id
        ),'[]'::jsonb)
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_receipts
  from public.customer_receipts r
  left join (
    select receipt_id, sum(amount) as allocated
    from public.customer_receipt_allocations
    group by receipt_id
  ) al on al.receipt_id = r.id
  left join public.business_locations l on l.id=r.location_id
  left join public.business_devices d on d.id=r.device_id
  where r.tenant_id=p_tenant_id
    and r.customer_id=p_customer_id
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'));

  -- Calculate unallocated advance balance across active posted receipts
  select coalesce(sum(r.amount - coalesce(al.allocated, 0)), 0)
  into v_unallocated_advance
  from public.customer_receipts r
  left join (
    select receipt_id, sum(amount) as allocated
    from public.customer_receipt_allocations
    group by receipt_id
  ) al on al.receipt_id = r.id
  where r.tenant_id=p_tenant_id
    and r.customer_id=p_customer_id
    and r.status='posted'
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'));

  return jsonb_build_object(
    'customer',v_customer,
    'outstanding',greatest(v_invoice_outstanding - v_unallocated_advance, 0),
    'gross_invoice_outstanding',v_invoice_outstanding,
    'unallocated_advance',v_unallocated_advance,
    'open_invoices',coalesce(v_invoices,'[]'::jsonb),
    'receipts',coalesce(v_receipts,'[]'::jsonb)
  );
end;
$$;

grant execute on function public.customer_account_v471(uuid,uuid) to authenticated, service_role;


-- ============================================================================
-- 5. CUSTOMER ACCOUNTS LIST V471 (ADVANCE AWARE)
-- ============================================================================
create or replace function public.customer_accounts_list_v471(
  p_tenant_id uuid,
  p_query text default null,
  p_limit integer default 500
)
returns table(
  customer_id uuid,
  public_id text,
  customer_name text,
  phone text,
  credit_limit numeric,
  outstanding numeric,
  open_invoice_count bigint,
  last_sale_date date
)
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_platform boolean := private.platform_v2_is_admin();
begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not v_platform and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;

  return query
  with visible_sales as (
    select
      s.id,
      s.customer_id,
      s.sale_date,
      s.grand_total,
      coalesce(py.paid,0)::numeric as paid,
      coalesce(rt.returned,0)::numeric as returned
    from public.sales s
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
      and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'))
  ),
  unallocated_receipts as (
    select
      r.customer_id,
      sum(r.amount - coalesce(al.allocated, 0)) as advance
    from public.customer_receipts r
    left join (
      select receipt_id, sum(amount) as allocated
      from public.customer_receipt_allocations
      group by receipt_id
    ) al on al.receipt_id = r.id
    where r.tenant_id=p_tenant_id and r.status='posted'
      and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'))
    group by r.customer_id
  )
  select
    c.id,
    coalesce(c.tracking_code,''),
    c.name,
    coalesce(c.phone,''),
    coalesce(c.credit_limit,0),
    greatest(coalesce(sum(greatest(vs.grand_total-vs.returned-vs.paid,0)),0) - coalesce(max(ur.advance),0), 0)::numeric as outstanding,
    count(vs.id) filter(where greatest(vs.grand_total-vs.returned-vs.paid,0)>0.005),
    max(vs.sale_date)
  from public.customers c
  left join visible_sales vs on vs.customer_id=c.id
  left join unallocated_receipts ur on ur.customer_id=c.id
  where c.tenant_id=p_tenant_id
    and coalesce(c.status,'active')='active'
    and not coalesce(c.is_walk_in,false)
    and (
      trim(coalesce(p_query,''))=''
      or lower(c.name) like '%'||lower(trim(p_query))||'%'
      or lower(coalesce(c.phone,'')) like '%'||lower(trim(p_query))||'%'
      or lower(coalesce(c.tracking_code,'')) like '%'||lower(trim(p_query))||'%'
    )
  group by c.id,c.tracking_code,c.name,c.phone,c.credit_limit
  order by 6 desc,c.name
  limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;

grant execute on function public.customer_accounts_list_v471(uuid,text,integer) to authenticated, service_role;


-- ============================================================================
-- 6. SCHEMA RELEASE REGISTRATION
-- ============================================================================
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  362,
  '7.1.5',
  'Customer Statement and On-Account Advance Receipt Integrity',
  'Upgrades customer statement to include sales returns and multi-invoice receipts with proper opening balance and scope filtering. Supports customer on-account advance receipts without blocking on 0 invoices or excess amount.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
