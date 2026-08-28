-- THQ ERP V4.7.1 — customer receivables, account receipts and invoice allocation.
begin;

create table if not exists public.customer_receipts(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  receipt_number text not null,
  receipt_date date not null default current_date,
  amount numeric not null check(amount>0),
  payment_method text not null,
  reference_number text,
  notes text,
  location_id uuid references public.business_locations(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(tenant_id,receipt_number)
);

create table if not exists public.customer_receipt_allocations(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  receipt_id uuid not null references public.customer_receipts(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  payment_id uuid,
  amount numeric not null check(amount>0),
  created_at timestamptz not null default now(),
  unique(receipt_id,sale_id)
);
create index if not exists idx_customer_receipts_customer_v471 on public.customer_receipts(tenant_id,customer_id,receipt_date desc,created_at desc);
create index if not exists idx_customer_receipt_allocations_sale_v471 on public.customer_receipt_allocations(tenant_id,sale_id);
alter table public.customer_receipts enable row level security;
alter table public.customer_receipt_allocations enable row level security;
revoke all on public.customer_receipts,public.customer_receipt_allocations from anon,authenticated;
create sequence if not exists public.customer_receipt_number_seq;

-- Customer receipts deliberately allocate into sale_payments so every existing report,
-- statement and outstanding calculation continues to use one source of truth.
-- The receipt flow sets a transaction-local marker; payment rows created under that
-- marker are accounted once at receipt level instead of once per allocation.
create or replace function private.v4_sale_payment_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant uuid;v_loc uuid;v_ref text;v_customer uuid;v_lines jsonb;v_receipt text;begin
  v_receipt:=current_setting('thq.customer_receipt_id',true);
  if nullif(v_receipt,'') is not null then return new;end if;
  select s.tenant_id,s.sale_number,s.customer_id,o.location_id into v_tenant,v_ref,v_customer,v_loc
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.id=new.sale_id;
  if v_tenant is null or v_loc is null then return new;end if;
  if exists(select 1 from public.journal_entries where tenant_id=v_tenant and source_type='sale_payment' and source_id=new.id) then return new;end if;
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(v_tenant,new.payment_method),'debit',new.amount,'credit',0,'party_type','customer','party_id',v_customer,'description','Customer receipt'),
    jsonb_build_object('account_id',private.v4_account_id(v_tenant,'accounts_receivable'),'debit',0,'credit',new.amount,'party_type','customer','party_id',v_customer,'description','Receivable settlement')
  );
  perform private.v4_journal_create(v_tenant,v_loc,coalesce(new.paid_at::date,current_date),'Customer receipt • '||v_ref,'sale_payment',new.id,v_ref,v_lines);
  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,'Customer cash receipt',auth.uid()
    from public.document_origins o join public.cashier_shifts sh on sh.tenant_id=v_tenant and sh.device_id=o.device_id and sh.status='open'
    where o.entity_type='sale' and o.entity_id=new.sale_id
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='sale_payment' and m.reference_id=new.id)
    limit 1;
  end if;
  return new;
end $$;

-- Dedicated cash-drawer type for payments of old customer balances. This avoids
-- incorrectly reporting a customer receipt as a new cash sale.
alter table public.cash_drawer_movements drop constraint if exists cash_drawer_movements_movement_type_check;
alter table public.cash_drawer_movements add constraint cash_drawer_movements_movement_type_check
  check(movement_type in('opening','sale','refund','cash_in','cash_out','expense','closing_adjustment','receipt'));

create or replace function public.cashier_shift_current_v4(p_tenant_id uuid,p_device_id uuid)
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
select coalesce((
  select to_jsonb(s) || jsonb_build_object(
    'cash_movement_total',coalesce(sum(m.amount),0),
    'expected_cash',coalesce(sum(m.amount),0),
    'cash_sales',coalesce(sum(case when m.movement_type='sale' then m.amount else 0 end),0),
    'customer_receipts',coalesce(sum(case when m.movement_type='receipt' then m.amount else 0 end),0),
    'cash_in',coalesce(sum(case when m.movement_type='cash_in' then m.amount else 0 end),0),
    'cash_out',abs(coalesce(sum(case when m.movement_type='cash_out' then m.amount else 0 end),0)),
    'cash_expenses',abs(coalesce(sum(case when m.movement_type='expense' then m.amount else 0 end),0)),
    'refunds',abs(coalesce(sum(case when m.movement_type='refund' then m.amount else 0 end),0))
  )
  from public.cashier_shifts s left join public.cash_drawer_movements m on m.shift_id=s.id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
  group by s.id limit 1
),'{}'::jsonb)
$$;
grant execute on function public.cashier_shift_current_v4(uuid,uuid) to authenticated;

create or replace function private.v471_platform_insert_sale_payment(
  p_sale_id uuid,p_amount numeric,p_method text,p_reference text,p_notes text
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;v_sql text;v_cols text:='sale_id,amount,payment_method';v_vals text:='$1,$2,$3';
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_payments' and column_name='reference_number') then
    v_cols:=v_cols||',reference_number';v_vals:=v_vals||',$4';
  end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_payments' and column_name='notes') then
    v_cols:=v_cols||',notes';
    v_vals:=v_vals||case when position('reference_number' in v_cols)>0 then ',$5' else ',$4' end;
  end if;
  v_sql:='insert into public.sale_payments('||v_cols||') values('||v_vals||') returning id';
  if position('reference_number' in v_cols)>0 and position('notes' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_reference,p_notes;
  elsif position('reference_number' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_reference;
  elsif position('notes' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_notes;
  else execute v_sql into v_id using p_sale_id,p_amount,p_method;end if;
  return v_id;
end $$;
revoke all on function private.v471_platform_insert_sale_payment(uuid,numeric,text,text,text) from public;

create or replace function public.customer_account_v471(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_customer jsonb;v_invoices jsonb;v_receipts jsonb;v_outstanding numeric:=0;v_platform boolean:=private.platform_v2_is_admin();
begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not v_platform and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;
  select to_jsonb(c) into v_customer from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id;
  if v_customer is null then raise exception 'Customer not found';end if;
  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0),
    coalesce(jsonb_agg(jsonb_build_object(
      'sale_id',s.id,'sale_number',s.sale_number,'sale_date',s.sale_date,'due_date',s.due_date,'grand_total',s.grand_total,
      'paid',coalesce(py.paid,0),'returned',coalesce(rt.returned,0),'balance',greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0),'location_id',o.location_id,'location_name',l.name
    ) order by coalesce(s.due_date,s.sale_date),s.created_at) filter(where greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005),'[]'::jsonb)
  into v_outstanding,v_invoices
  from public.sales s
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'));

  select coalesce(jsonb_agg(jsonb_build_object(
    'receipt_id',r.id,'receipt_number',r.receipt_number,'receipt_date',r.receipt_date,'amount',r.amount,
    'payment_method',r.payment_method,'reference_number',r.reference_number,'notes',r.notes,'location_id',r.location_id,
    'location_name',l.name,'device_id',r.device_id,'device_name',d.name,'created_at',r.created_at,
    'allocations',coalesce((select jsonb_agg(jsonb_build_object('sale_id',a.sale_id,'sale_number',s.sale_number,'amount',a.amount))
      from public.customer_receipt_allocations a join public.sales s on s.id=a.sale_id where a.receipt_id=r.id),'[]'::jsonb)
  ) order by r.created_at desc),'[]'::jsonb) into v_receipts
  from public.customer_receipts r left join public.business_locations l on l.id=r.location_id left join public.business_devices d on d.id=r.device_id
  where r.tenant_id=p_tenant_id and r.customer_id=p_customer_id
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'));

  return jsonb_build_object('customer',v_customer,'outstanding',v_outstanding,'open_invoices',coalesce(v_invoices,'[]'::jsonb),'receipts',coalesce(v_receipts,'[]'::jsonb));
end $$;
grant execute on function public.customer_account_v471(uuid,uuid) to authenticated;

create or replace function public.customer_accounts_list_v471(p_tenant_id uuid,p_query text default null,p_limit integer default 500)
returns table(customer_id uuid,public_id text,customer_name text,phone text,credit_limit numeric,outstanding numeric,open_invoice_count bigint,last_sale_date date)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v_platform boolean:=private.platform_v2_is_admin();begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
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
    select s.id,s.customer_id,s.sale_date,s.grand_total,coalesce(py.paid,0)::numeric as paid,coalesce(rt.returned,0)::numeric as returned
    from public.sales s
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
      and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'))
  )
  select c.id,coalesce(c.tracking_code,''),c.name,coalesce(c.phone,''),coalesce(c.credit_limit,0),
    coalesce(sum(greatest(vs.grand_total-vs.returned-vs.paid,0)),0)::numeric,
    count(vs.id) filter(where greatest(vs.grand_total-vs.returned-vs.paid,0)>0.005),max(vs.sale_date)
  from public.customers c
  left join visible_sales vs on vs.customer_id=c.id
  where c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active' and not coalesce(c.is_walk_in,false)
    and (trim(coalesce(p_query,''))='' or lower(c.name) like '%'||lower(trim(p_query))||'%' or lower(coalesce(c.phone,'')) like '%'||lower(trim(p_query))||'%' or lower(coalesce(c.tracking_code,'')) like '%'||lower(trim(p_query))||'%')
  group by c.id,c.tracking_code,c.name,c.phone,c.credit_limit
  order by 6 desc,c.name limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
grant execute on function public.customer_accounts_list_v471(uuid,text,integer) to authenticated;

create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,
  p_sale_id uuid default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;v_receipt uuid:=gen_random_uuid();v_receipt_no text;v_remaining numeric:=round(coalesce(p_amount,0),2);v_total_outstanding numeric:=0;
  v_location uuid:=p_location_id;v_sale record;v_alloc numeric;v_result jsonb;v_payment_id uuid;v_started timestamptz:=clock_timestamp();v_lines jsonb;v_response jsonb;
  v_is_platform boolean:=private.platform_v2_is_admin();v_device_type text;v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');if v_existing is not null then return v_existing;end if;
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'payments.receive') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Receive payment permission required';end if;
  end if;
  if v_remaining<=0 then raise exception 'Payment amount must be greater than zero';end if;
  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false) for update;
  if not found then raise exception 'Select an active non-walk-in customer';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then raise exception 'Invalid payment method';end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found';end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then raise exception 'Collecting POS/location mismatch';end if;
      v_location:=v_device_location;
    else
      v_location:=coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0) into v_total_outstanding
  from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));
  if v_total_outstanding<=0.005 then raise exception 'Customer has no outstanding balance in the permitted scope';end if;
  if v_remaining>v_total_outstanding+0.005 then raise exception 'Payment % exceeds outstanding balance %',v_remaining,v_total_outstanding;end if;

  if v_location is null then
    select o.location_id into v_location from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null and v_is_platform then
    select id into v_location from public.business_locations where tenant_id=p_tenant_id and active order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then raise exception 'Could not determine collection location';end if;
  v_receipt_no:='RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');
  insert into public.customer_receipts(id,tenant_id,customer_id,receipt_number,receipt_date,amount,payment_method,reference_number,notes,location_id,device_id,created_by)
  values(v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,v_remaining,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid());

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance,o.location_id
    from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005 and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_sale.balance);
    v_payment_id:=null;
    if v_is_platform then
      v_payment_id:=private.v471_platform_insert_sale_payment(v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
    else
      v_result:=public.sales_add_payment_v32(p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
      begin v_payment_id:=nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;exception when others then v_payment_id:=null;end;
      if v_payment_id is null then
        select sp.id into v_payment_id from public.sale_payments sp where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds' order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;
    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);
    v_remaining:=v_remaining-v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);
  if v_remaining>0.005 then raise exception 'Could not allocate full receipt. Remaining %',v_remaining;end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,'description','Customer account receipt'),
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,'description','Receivable settlement')
  );
  perform private.v4_journal_create(p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,'customer_receipt',v_receipt,v_receipt_no,v_lines);

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write(p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null,
    jsonb_build_object('receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id));
  v_response:=jsonb_build_object('success',true,'receipt_id',v_receipt,'receipt_number',v_receipt_no,'amount',p_amount,'outstanding_before',v_total_outstanding,'outstanding_after',greatest(v_total_outstanding-p_amount,0));
  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;
grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(112,'4.7.1','Operational Stabilization Patch','Customer receivable accounts and partial/account-level receipt allocation with accounting and POS cash-drawer support.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.7.1 migration 112 customer receivables ready' as status;
