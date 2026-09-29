-- THQ ERP v6.2.6 Build 11 / Desktop v6.1.2 Build 5
-- Party Payments & Outstanding Settlement.
-- Source captured from the already-live Supabase migration
-- 20260929065106 / v626_build11_party_payments_settlement.
-- Applied statement MD5 in Supabase history: e375f402a0b1d2e1ff485e8b69ec1e73
-- DO NOT execute manually on the live project; migration 293 is already live.

begin;

create sequence if not exists public.party_settlement_number_seq_v626;

create table if not exists public.party_settlements_v626(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  party_type text not null check(party_type in('customer','supplier')),
  party_id uuid not null,
  settlement_number text not null,
  settlement_date date not null default current_date,
  adjustment_type text not null check(adjustment_type in('discount','write_off')),
  amount numeric not null check(amount>0),
  reason text,
  device_id uuid references public.business_devices(id) on delete set null,
  request_id text not null,
  status text not null default 'posted' check(status in('posted')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(tenant_id,settlement_number),
  unique(tenant_id,request_id)
);

create table if not exists public.party_settlement_allocations_v626(
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.party_settlements_v626(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  source_type text not null check(source_type in('sale','purchase','purchase_invoice')),
  source_id uuid not null,
  amount numeric not null check(amount>0),
  payment_id uuid,
  supplier_payment_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_party_settlement_allocations_v626_source
  on public.party_settlement_allocations_v626(tenant_id,source_type,source_id);
create index if not exists idx_party_settlements_v626_party
  on public.party_settlements_v626(tenant_id,party_type,party_id,created_at desc);

alter table public.party_settlements_v626 enable row level security;
alter table public.party_settlement_allocations_v626 enable row level security;
revoke all on public.party_settlements_v626,public.party_settlement_allocations_v626 from anon,authenticated;

create or replace function private.v626_ensure_settlement_accounts(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
begin
  if not exists(select 1 from public.tenants where id=p_tenant_id) then
    raise exception 'Tenant not found';
  end if;

  insert into public.accounting_accounts(
    tenant_id,code,name,account_type,system_key,is_system,description
  )
  select p_tenant_id,x.code,x.name,x.account_type,x.system_key,true,x.description
  from (values
    ('THQ-CDISC','Customer Settlement Discounts','expense','customer_settlement_discount','Financial settlement discounts granted to customers; does not change GST invoice value'),
    ('THQ-CWO','Customer Bad Debt Write-off','expense','customer_bad_debt_writeoff','Receivable balances written off as bad debt; does not change GST invoice value'),
    ('THQ-SDISC','Supplier Settlement Discounts','income','supplier_settlement_discount','Financial settlement discounts received from suppliers; does not change GST invoice value'),
    ('THQ-SWO','Supplier Balance Write-off Gain','income','supplier_balance_writeoff','Supplier payable balances waived/written off; does not change GST invoice value')
  ) x(code,name,account_type,system_key,description)
  where not exists(
    select 1 from public.accounting_accounts a
    where a.tenant_id=p_tenant_id and a.system_key=x.system_key
  )
  on conflict(tenant_id,code) do nothing;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,
    case a.system_key
      when 'customer_settlement_discount' then 'settlement.customer_discount'
      when 'customer_bad_debt_writeoff' then 'settlement.customer_writeoff'
      when 'supplier_settlement_discount' then 'settlement.supplier_discount'
      when 'supplier_balance_writeoff' then 'settlement.supplier_writeoff'
    end,
    a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id
    and a.system_key in(
      'customer_settlement_discount',
      'customer_bad_debt_writeoff',
      'supplier_settlement_discount',
      'supplier_balance_writeoff'
    )
  on conflict(tenant_id,mapping_key) do update
    set account_id=excluded.account_id,updated_at=now();
end;
$function$;
revoke all on function private.v626_ensure_settlement_accounts(uuid) from public;

create or replace function private.v626_tenant_settlement_accounts_after_insert()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
begin
  perform private.v626_ensure_settlement_accounts(new.id);
  return new;
end;
$function$;
revoke all on function private.v626_tenant_settlement_accounts_after_insert() from public;

drop trigger if exists trg_v626_tenant_settlement_accounts on public.tenants;
create trigger trg_v626_tenant_settlement_accounts
after insert on public.tenants
for each row execute function private.v626_tenant_settlement_accounts_after_insert();

do $block$
declare r record;
begin
  for r in select id from public.tenants loop
    perform private.v626_ensure_settlement_accounts(r.id);
  end loop;
end
$block$;

alter table public.sale_payments
  drop constraint if exists sale_payments_payment_method_check;
alter table public.sale_payments
  add constraint sale_payments_payment_method_check
  check(payment_method = any(array[
    'cash'::text,'bank'::text,'card'::text,'upi'::text,'cheque'::text,
    'wallet'::text,'other'::text,'discount'::text,'write_off'::text
  ]));

alter table public.purchase_payments
  drop constraint if exists purchase_payments_payment_method_check;
alter table public.purchase_payments
  add constraint purchase_payments_payment_method_check
  check(payment_method = any(array[
    'cash'::text,'bank'::text,'card'::text,'upi'::text,'cheque'::text,
    'other'::text,'discount'::text,'write_off'::text
  ]));

-- Normal payment triggers are unchanged. Settlement-only rows skip their
-- cash/bank auto-journal and receive a dedicated adjustment journal below.
drop trigger if exists trg_v4_sale_payment_after_insert on public.sale_payments;
create trigger trg_v4_sale_payment_after_insert
after insert on public.sale_payments
for each row
when (lower(coalesce(new.payment_method,'')) not in ('discount','write_off'))
execute function private.v4_sale_payment_after_insert();

drop trigger if exists trg_v4_purchase_payment_after_insert on public.purchase_payments;
create trigger trg_v4_purchase_payment_after_insert
after insert on public.purchase_payments
for each row
when (lower(coalesce(new.payment_method,'')) not in ('discount','write_off'))
execute function private.v4_purchase_payment_after_insert();

create or replace function public.supplier_payment_party_v626(
  p_tenant_id uuid,
  p_location_id uuid,
  p_supplier_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text default '',
  p_notes text default '',
  p_device_id uuid default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_existing jsonb;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_remaining numeric;
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
  v_credit numeric:=0;
  v_gross numeric:=0;
  v_net numeric:=0;
  v_doc record;
  v_alloc numeric;
  v_result jsonb;
  v_payment_id uuid;
  v_v2_amount numeric:=0;
  v_v2_allocations jsonb:='[]'::jsonb;
  v_v2_result jsonb;
  v_device_type text;
  v_device_location uuid;
  v_allowed text[];
  v_shift uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'supplier.payment.v626');
  if v_existing is not null then return v_existing; end if;

  if v_amount<=0 then raise exception 'Payment amount must be greater than zero';end if;
  if v_method not in('cash','upi','card','bank','cheque','other') then
    raise exception 'Invalid payment method';
  end if;
  if p_location_id is null then
    raise exception 'Select a specific store before recording a supplier payment';
  end if;

  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);

  if p_device_id is not null then
    select d.app_type,d.location_id,d.allowed_modules
      into v_device_type,v_device_location,v_allowed
    from public.business_devices d
    where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
    if v_device_type is null then raise exception 'Active payment system not found';end if;
    if v_device_location<>p_location_id then raise exception 'Payment system/location mismatch';end if;
    if v_device_type not in('client','pos') then raise exception 'Unsupported payment system type';end if;
    if not private.erp_user_app_allowed(p_tenant_id,v_device_type,auth.uid()) then
      raise exception 'Application access is disabled for this user';
    end if;
    if v_device_type='pos'
       and v_method='cash'
       and 'cashier_shifts'=any(coalesce(v_allowed,'{}'::text[])) then
      select s.id into v_shift
      from public.cashier_shifts s
      where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      order by s.opened_at desc limit 1;
      if v_shift is null then raise exception 'Open cashier shift before paying cash on this POS';end if;
    end if;
  end if;

  perform 1 from public.suppliers
   where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active'
   for update;
  if not found then raise exception 'Supplier not found';end if;

  select coalesce(sum(greatest(sp.amount-coalesce(a.allocated,0),0)),0)
    into v_credit
  from public.supplier_payments_v484 sp
  left join (
    select supplier_payment_id,sum(amount)::numeric allocated
    from public.supplier_payment_allocations_v484
    group by supplier_payment_id
  ) a on a.supplier_payment_id=sp.id
  where sp.tenant_id=p_tenant_id
    and sp.supplier_id=p_supplier_id
    and sp.location_id=p_location_id
    and sp.status='posted';

  with legacy as (
    select p.id source_id,'purchase'::text source_type,
      coalesce(p.due_date,p.purchase_date) due_date,p.created_at,
      greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id
      and p.status='posted' and o.location_id=p_location_id
      and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
  ), v2 as (
    select i.id source_id,'purchase_invoice'::text source_type,
      coalesce(i.due_date,i.invoice_date) due_date,i.created_at,i.balance_due::numeric balance
    from public.purchase_invoices_v484 i
    where i.tenant_id=p_tenant_id and i.supplier_id=p_supplier_id
      and i.location_id=p_location_id and i.status in('posted','part_paid') and i.balance_due>0.005
  )
  select coalesce(sum(x.balance),0) into v_gross
  from (select * from legacy union all select * from v2) x;

  v_net:=greatest(v_gross-v_credit,0);
  if v_net<=0.005 then raise exception 'Supplier has no net outstanding in this store';end if;
  if v_amount>v_net+0.005 then
    raise exception 'Payment % exceeds net outstanding %',v_amount,v_net;
  end if;

  v_remaining:=v_amount;

  for v_doc in
    with legacy as (
      select p.id source_id,'purchase'::text source_type,
        coalesce(p.due_date,p.purchase_date) due_date,p.created_at,
        greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
      from public.purchases p
      left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
      left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
      join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id
        and p.status='posted' and o.location_id=p_location_id
        and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
    ), v2 as (
      select i.id source_id,'purchase_invoice'::text source_type,
        coalesce(i.due_date,i.invoice_date) due_date,i.created_at,i.balance_due::numeric balance
      from public.purchase_invoices_v484 i
      where i.tenant_id=p_tenant_id and i.supplier_id=p_supplier_id
        and i.location_id=p_location_id and i.status in('posted','part_paid') and i.balance_due>0.005
    )
    select * from (select * from legacy union all select * from v2) x
    order by x.due_date,x.created_at
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_doc.balance);

    if v_doc.source_type='purchase' then
      v_result:=public.purchases_add_payment_v47(
        p_tenant_id,v_doc.source_id,v_alloc,v_method,
        nullif(trim(coalesce(p_reference_number,'')),''),
        nullif(trim(coalesce(p_notes,'')),''),
        p_request_id||':purchase:'||v_doc.source_id::text
      );
      begin v_payment_id:=nullif(v_result->>'payment_id','')::uuid;exception when others then v_payment_id:=null;end;
      if v_method='cash' and p_device_id is not null and v_shift is not null and v_payment_id is not null then
        insert into public.cash_drawer_movements(
          tenant_id,shift_id,movement_type,amount,reference_type,reference_id,
          reference_number,note,created_by
        )
        values(
          p_tenant_id,v_shift,'cash_out',-abs(v_alloc),'purchase_payment_v626',v_payment_id,
          nullif(trim(coalesce(p_reference_number,'')),''),
          'Supplier payment',auth.uid()
        )
        on conflict do nothing;
      end if;
    else
      v_v2_amount:=v_v2_amount+v_alloc;
      v_v2_allocations:=v_v2_allocations||jsonb_build_array(
        jsonb_build_object('purchase_invoice_id',v_doc.source_id,'amount',v_alloc)
      );
    end if;
    v_remaining:=v_remaining-v_alloc;
  end loop;

  if v_v2_amount>0.005 then
    v_v2_result:=public.supplier_payment_create_v490(
      p_tenant_id,p_location_id,p_supplier_id,current_date,v_v2_amount,v_method,
      v_v2_allocations,
      nullif(trim(coalesce(p_reference_number,'')),''),
      nullif(trim(coalesce(p_notes,'')),''),
      p_device_id
    );
  end if;

  if v_remaining>0.005 then
    raise exception 'Could not allocate full supplier payment. Remaining %',v_remaining;
  end if;

  v_result:=jsonb_build_object(
    'success',true,
    'amount',v_amount,
    'payment_method',v_method,
    'outstanding_before',v_net,
    'outstanding_after',greatest(v_net-v_amount,0),
    'v2_payment',coalesce(v_v2_result,'{}'::jsonb)
  );
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','supplier_payment',p_supplier_id::text,'post');
  return private.v47_request_complete(p_tenant_id,p_request_id,'supplier.payment.v626',v_result);
end;
$function$;
revoke all on function public.supplier_payment_party_v626(uuid,uuid,uuid,numeric,text,text,text,uuid,text) from public,anon;
grant execute on function public.supplier_payment_party_v626(uuid,uuid,uuid,numeric,text,text,text,uuid,text) to authenticated,service_role;

create or replace function public.party_outstanding_close_v626(
  p_tenant_id uuid,
  p_location_id uuid,
  p_party_type text,
  p_party_id uuid,
  p_adjustment_type text,
  p_amount numeric,
  p_reason text default '',
  p_device_id uuid default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_existing jsonb;
  v_kind text:=lower(trim(coalesce(p_party_type,'')));
  v_adj text:=lower(trim(coalesce(p_adjustment_type,'')));
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_remaining numeric;
  v_total numeric:=0;
  v_credit numeric:=0;
  v_gross numeric:=0;
  v_settlement uuid:=gen_random_uuid();
  v_no text;
  v_doc record;
  v_alloc numeric;
  v_payment uuid;
  v_supplier_payment uuid;
  v_v2_amount numeric:=0;
  v_v2_allocations jsonb:='[]'::jsonb;
  v_lines jsonb;
  v_adjustment_account uuid;
  v_device_type text;
  v_device_location uuid;
  v_response jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'party.settlement.v626');
  if v_existing is not null then return v_existing;end if;

  if v_kind not in('customer','supplier') then raise exception 'Party type must be customer or supplier';end if;
  if v_adj not in('discount','write_off') then raise exception 'Adjustment must be discount or write_off';end if;
  if v_amount<=0 then raise exception 'Adjustment amount must be greater than zero';end if;
  if p_location_id is null then raise exception 'Select a specific store before closing outstanding';end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then
    raise exception 'Location access denied';
  end if;

  if v_kind='customer' then
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'accounting.manage')
       and not private.erp_has_permission(p_tenant_id,'sales.manage') then
      raise exception 'Sales manage or accounting manage permission required';
    end if;
  else
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'accounting.manage')
       and not private.erp_has_permission(p_tenant_id,'purchases.manage') then
      raise exception 'Purchases manage or accounting manage permission required';
    end if;
  end if;

  if p_device_id is not null then
    select d.app_type,d.location_id into v_device_type,v_device_location
    from public.business_devices d
    where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
    if v_device_type is null then raise exception 'Active system not found';end if;
    if v_device_location<>p_location_id then raise exception 'System/location mismatch';end if;
    if v_device_type not in('client','pos') then raise exception 'Unsupported system type';end if;
    if not private.erp_user_app_allowed(p_tenant_id,v_device_type,auth.uid()) then
      raise exception 'Application access is disabled for this user';
    end if;
  end if;

  perform private.v626_ensure_settlement_accounts(p_tenant_id);

  if v_kind='customer' then
    perform 1 from public.customers
      where id=p_party_id and tenant_id=p_tenant_id and status='active'
      for update;
    if not found then raise exception 'Customer not found';end if;

    select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)),0)
      into v_total
    from public.sales s
    left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_party_id
      and coalesce(s.status,'') not in('void','cancelled')
      and o.location_id=p_location_id;

    if v_total<=0.005 then raise exception 'Customer has no sales outstanding in this store';end if;
    if v_amount>v_total+0.005 then raise exception 'Adjustment % exceeds sales outstanding %',v_amount,v_total;end if;

    v_no:='CSET-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.party_settlement_number_seq_v626')::text,6,'0');
    insert into public.party_settlements_v626(
      id,tenant_id,location_id,party_type,party_id,settlement_number,settlement_date,
      adjustment_type,amount,reason,device_id,request_id,created_by
    ) values(
      v_settlement,p_tenant_id,p_location_id,v_kind,p_party_id,v_no,current_date,
      v_adj,v_amount,nullif(trim(coalesce(p_reason,'')),''),p_device_id,p_request_id,auth.uid()
    );

    v_adjustment_account:=private.v4_account_id(
      p_tenant_id,
      case when v_adj='discount' then 'settlement.customer_discount' else 'settlement.customer_writeoff' end
    );
    v_remaining:=v_amount;

    for v_doc in
      select s.id source_id,s.sale_number reference,
        greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
      from public.sales s
      left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
      left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
      join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
      where s.tenant_id=p_tenant_id and s.customer_id=p_party_id
        and coalesce(s.status,'') not in('void','cancelled')
        and o.location_id=p_location_id
        and greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      order by coalesce(s.due_date,s.sale_date),s.created_at
      for update of s
    loop
      exit when v_remaining<=0.005;
      v_alloc:=least(v_remaining,v_doc.balance);
      insert into public.sale_payments(
        tenant_id,sale_id,amount,payment_method,reference_number,notes,paid_at,created_by
      ) values(
        p_tenant_id,v_doc.source_id,v_alloc,v_adj,v_no,
        concat(case when v_adj='discount' then 'Settlement discount' else 'Outstanding write-off' end,
          case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end),
        now(),auth.uid()
      ) returning id into v_payment;

      v_lines:=jsonb_build_array(
        jsonb_build_object(
          'account_id',v_adjustment_account,'debit',v_alloc,'credit',0,
          'party_type','customer','party_id',p_party_id,
          'description',case when v_adj='discount' then 'Customer settlement discount' else 'Customer bad debt write-off' end
        ),
        jsonb_build_object(
          'account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',v_alloc,
          'party_type','customer','party_id',p_party_id,'description','Receivable settlement'
        )
      );
      perform private.v4_journal_create(
        p_tenant_id,p_location_id,current_date,
        case when v_adj='discount' then 'Customer settlement discount • ' else 'Customer write-off • ' end||v_no,
        'sale_payment',v_payment,v_no,v_lines
      );

      insert into public.party_settlement_allocations_v626(
        settlement_id,tenant_id,source_type,source_id,amount,payment_id
      ) values(v_settlement,p_tenant_id,'sale',v_doc.source_id,v_alloc,v_payment);
      v_remaining:=v_remaining-v_alloc;
    end loop;

  else
    perform 1 from public.suppliers
      where id=p_party_id and tenant_id=p_tenant_id and coalesce(status,'active')='active'
      for update;
    if not found then raise exception 'Supplier not found';end if;

    select coalesce(sum(greatest(sp.amount-coalesce(a.allocated,0),0)),0)
      into v_credit
    from public.supplier_payments_v484 sp
    left join (
      select supplier_payment_id,sum(amount)::numeric allocated
      from public.supplier_payment_allocations_v484 group by supplier_payment_id
    ) a on a.supplier_payment_id=sp.id
    where sp.tenant_id=p_tenant_id and sp.supplier_id=p_party_id
      and sp.location_id=p_location_id and sp.status='posted';

    with legacy as (
      select greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
      from public.purchases p
      left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
      left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
      join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and p.status='posted'
        and o.location_id=p_location_id
        and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
    ), v2 as (
      select i.balance_due::numeric balance
      from public.purchase_invoices_v484 i
      where i.tenant_id=p_tenant_id and i.supplier_id=p_party_id and i.location_id=p_location_id
        and i.status in('posted','part_paid') and i.balance_due>0.005
    )
    select coalesce(sum(x.balance),0) into v_gross
    from (select * from legacy union all select * from v2) x;

    v_total:=greatest(v_gross-v_credit,0);
    if v_total<=0.005 then raise exception 'Supplier has no net outstanding in this store';end if;
    if v_amount>v_total+0.005 then raise exception 'Adjustment % exceeds net supplier outstanding %',v_amount,v_total;end if;

    v_no:='SSET-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.party_settlement_number_seq_v626')::text,6,'0');
    insert into public.party_settlements_v626(
      id,tenant_id,location_id,party_type,party_id,settlement_number,settlement_date,
      adjustment_type,amount,reason,device_id,request_id,created_by
    ) values(
      v_settlement,p_tenant_id,p_location_id,v_kind,p_party_id,v_no,current_date,
      v_adj,v_amount,nullif(trim(coalesce(p_reason,'')),''),p_device_id,p_request_id,auth.uid()
    );

    v_adjustment_account:=private.v4_account_id(
      p_tenant_id,
      case when v_adj='discount' then 'settlement.supplier_discount' else 'settlement.supplier_writeoff' end
    );
    v_remaining:=v_amount;

    for v_doc in
      with legacy as (
        select p.id source_id,'purchase'::text source_type,p.purchase_number reference,
          coalesce(p.due_date,p.purchase_date) due_date,p.created_at,
          greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)::numeric balance
        from public.purchases p
        left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
        left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
        join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
        where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and p.status='posted'
          and o.location_id=p_location_id
          and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      ), v2 as (
        select i.id source_id,'purchase_invoice'::text source_type,i.invoice_number reference,
          coalesce(i.due_date,i.invoice_date) due_date,i.created_at,i.balance_due::numeric balance
        from public.purchase_invoices_v484 i
        where i.tenant_id=p_tenant_id and i.supplier_id=p_party_id and i.location_id=p_location_id
          and i.status in('posted','part_paid') and i.balance_due>0.005
      )
      select * from (select * from legacy union all select * from v2) x
      order by x.due_date,x.created_at
    loop
      exit when v_remaining<=0.005;
      v_alloc:=least(v_remaining,v_doc.balance);

      if v_doc.source_type='purchase' then
        insert into public.purchase_payments(
          tenant_id,purchase_id,amount,payment_method,reference_number,notes,paid_at,created_by
        ) values(
          p_tenant_id,v_doc.source_id,v_alloc,v_adj,v_no,
          concat(case when v_adj='discount' then 'Settlement discount' else 'Outstanding write-off' end,
            case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end),
          now(),auth.uid()
        ) returning id into v_payment;

        v_lines:=jsonb_build_array(
          jsonb_build_object(
            'account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',v_alloc,'credit',0,
            'party_type','supplier','party_id',p_party_id,'description','Supplier payable settlement'
          ),
          jsonb_build_object(
            'account_id',v_adjustment_account,'debit',0,'credit',v_alloc,
            'party_type','supplier','party_id',p_party_id,
            'description',case when v_adj='discount' then 'Supplier settlement discount' else 'Supplier balance write-off gain' end
          )
        );
        perform private.v4_journal_create(
          p_tenant_id,p_location_id,current_date,
          case when v_adj='discount' then 'Supplier settlement discount • ' else 'Supplier write-off • ' end||v_no,
          'purchase_payment',v_payment,v_no,v_lines
        );

        insert into public.party_settlement_allocations_v626(
          settlement_id,tenant_id,source_type,source_id,amount,payment_id
        ) values(v_settlement,p_tenant_id,'purchase',v_doc.source_id,v_alloc,v_payment);
      else
        v_v2_amount:=v_v2_amount+v_alloc;
        v_v2_allocations:=v_v2_allocations||jsonb_build_array(
          jsonb_build_object('purchase_invoice_id',v_doc.source_id,'amount',v_alloc)
        );
        insert into public.party_settlement_allocations_v626(
          settlement_id,tenant_id,source_type,source_id,amount
        ) values(v_settlement,p_tenant_id,'purchase_invoice',v_doc.source_id,v_alloc);
      end if;
      v_remaining:=v_remaining-v_alloc;
    end loop;

    if v_v2_amount>0.005 then
      v_supplier_payment:=gen_random_uuid();
      insert into public.supplier_payments_v484(
        id,tenant_id,location_id,supplier_id,payment_number,payment_date,amount,
        payment_method,reference_number,notes,status,created_by
      ) values(
        v_supplier_payment,p_tenant_id,p_location_id,p_party_id,v_no,current_date,v_v2_amount,
        v_adj,v_no,
        concat(case when v_adj='discount' then 'Settlement discount' else 'Outstanding write-off' end,
          case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end),
        'posted',auth.uid()
      );

      for v_doc in
        select (x->>'purchase_invoice_id')::uuid invoice_id,(x->>'amount')::numeric amount
        from jsonb_array_elements(v_v2_allocations) x
      loop
        insert into public.supplier_payment_allocations_v484(
          supplier_payment_id,purchase_invoice_id,amount
        ) values(v_supplier_payment,v_doc.invoice_id,v_doc.amount);
        perform private.v484_refresh_invoice_payment_status(v_doc.invoice_id);
      end loop;

      insert into public.supplier_ledger_entries_v484(
        tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,
        reference_number,description,debit,credit,created_by
      ) values(
        p_tenant_id,p_party_id,p_location_id,current_date,
        case when v_adj='discount' then 'supplier_discount' else 'supplier_write_off' end,
        v_supplier_payment,v_no,
        case when v_adj='discount' then 'Supplier settlement discount' else 'Supplier outstanding write-off' end,
        0,v_v2_amount,auth.uid()
      );

      v_lines:=jsonb_build_array(
        jsonb_build_object(
          'account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',v_v2_amount,'credit',0,
          'party_type','supplier','party_id',p_party_id,'description','Supplier payable settlement'
        ),
        jsonb_build_object(
          'account_id',v_adjustment_account,'debit',0,'credit',v_v2_amount,
          'party_type','supplier','party_id',p_party_id,
          'description',case when v_adj='discount' then 'Supplier settlement discount' else 'Supplier balance write-off gain' end
        )
      );
      perform private.v4_journal_create(
        p_tenant_id,p_location_id,current_date,
        case when v_adj='discount' then 'Supplier settlement discount • ' else 'Supplier write-off • ' end||v_no,
        'supplier_payment_v484',v_supplier_payment,v_no,v_lines
      );

      update public.party_settlement_allocations_v626
      set supplier_payment_id=v_supplier_payment
      where settlement_id=v_settlement and source_type='purchase_invoice';
    end if;
  end if;

  if v_remaining>0.005 then
    raise exception 'Could not allocate full adjustment. Remaining %',v_remaining;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'party.outstanding.close',
    v_kind,
    p_party_id,
    v_no,
    null::jsonb,
    jsonb_build_object(
      'settlement_id',v_settlement,'adjustment_type',v_adj,'amount',v_amount,
      'location_id',p_location_id,'device_id',p_device_id,'reason',nullif(trim(coalesce(p_reason,'')),'')
    )
  );
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','party_settlement',v_settlement::text,'post');

  v_response:=jsonb_build_object(
    'success',true,'settlement_id',v_settlement,'settlement_number',v_no,
    'party_type',v_kind,'adjustment_type',v_adj,'amount',v_amount,
    'outstanding_before',v_total,'outstanding_after',greatest(v_total-v_amount,0),
    'gst_unchanged',true
  );
  return private.v47_request_complete(p_tenant_id,p_request_id,'party.settlement.v626',v_response);
end;
$function$;
revoke all on function public.party_outstanding_close_v626(uuid,uuid,text,uuid,text,numeric,text,uuid,text) from public,anon;
grant execute on function public.party_outstanding_close_v626(uuid,uuid,text,uuid,text,numeric,text,uuid,text) to authenticated,service_role;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','windows','6.1.2',5,'stable',false,false,
  'THQ ERP v6.1.2 Build 5 — Party Payments & Settlement. Adds customer/supplier outstanding closure with financial discount or write-off accounting in Windows Client. GST invoice values remain unchanged.',
  null,now()
),
(
  gen_random_uuid(),'pos','windows','6.1.2',5,'stable',false,false,
  'THQ ERP v6.1.2 Build 5 — Party Payments & Settlement. Adds customer/supplier outstanding closure and supplier payment actions in Windows POS Payment Center. GST invoice values remain unchanged.',
  null,now()
),
(
  gen_random_uuid(),'client','android','6.2.6',11,'stable',false,false,
  'THQ ERP v6.2.6 Build 11 — Party Payments & Settlement. Adds supplier payments and customer/supplier outstanding closure with Discount or Write-off in Client Mobile. GST invoice values remain unchanged.',
  null,now()
),
(
  gen_random_uuid(),'pos','android','6.2.6',11,'stable',false,false,
  'THQ ERP v6.2.6 Build 11 — Party Payments & Settlement. Adds mobile Party Payments with supplier payment and customer/supplier outstanding closure. Existing authoritative v5.2 sale/GST sync remains unchanged.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,status=excluded.status,
    minimum_supported=excluded.minimum_supported,mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  293,'6.2.6-build11',
  'v6.2.6 Build 11 Party Payments & Settlement',
  'Adds supplier payment allocation across legacy and Purchasing V2 documents plus audited financial-only customer/supplier Discount/Write-off settlement. No GST snapshot, invoice-value or authoritative sale writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
