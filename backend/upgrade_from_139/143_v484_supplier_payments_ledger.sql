-- THQ ERP V4.8.4 — Supplier payments, allocations and supplier ledger.
begin;

create sequence if not exists public.supplier_payment_number_seq_v484;

create table if not exists public.supplier_payments_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  payment_number text not null,
  payment_date date not null default current_date,
  amount numeric not null check(amount>0),
  payment_method text not null,
  reference_number text,
  notes text,
  status text not null default 'posted' check(status in('posted','void')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  voided_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  unique(tenant_id,payment_number)
);
create index if not exists idx_supplier_payments_v484_supplier on public.supplier_payments_v484(tenant_id,supplier_id,payment_date desc);
alter table public.supplier_payments_v484 enable row level security;
revoke all on public.supplier_payments_v484 from anon,authenticated;

create table if not exists public.supplier_payment_allocations_v484(
  id uuid primary key default gen_random_uuid(),
  supplier_payment_id uuid not null references public.supplier_payments_v484(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices_v484(id) on delete restrict,
  amount numeric not null check(amount>0),
  created_at timestamptz not null default now(),
  unique(supplier_payment_id,purchase_invoice_id)
);
create index if not exists idx_supplier_payment_allocations_v484_invoice on public.supplier_payment_allocations_v484(purchase_invoice_id,supplier_payment_id);
alter table public.supplier_payment_allocations_v484 enable row level security;
revoke all on public.supplier_payment_allocations_v484 from anon,authenticated;

create table if not exists public.supplier_ledger_entries_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  location_id uuid references public.business_locations(id) on delete set null,
  entry_date date not null,
  entry_type text not null check(entry_type in('purchase_invoice','supplier_payment','adjustment','void')),
  source_id uuid not null,
  reference_number text,
  description text,
  debit numeric not null default 0 check(debit>=0),
  credit numeric not null default 0 check(credit>=0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(tenant_id,entry_type,source_id)
);
create index if not exists idx_supplier_ledger_entries_v484_supplier on public.supplier_ledger_entries_v484(tenant_id,supplier_id,entry_date,created_at);
alter table public.supplier_ledger_entries_v484 enable row level security;
revoke all on public.supplier_ledger_entries_v484 from anon,authenticated;

create or replace function private.v484_invoice_ledger_after_status()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if new.status in('posted','part_paid','paid') and old.status='draft' then
    insert into public.supplier_ledger_entries_v484(tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by)
    values(new.tenant_id,new.supplier_id,new.location_id,new.invoice_date,'purchase_invoice',new.id,new.invoice_number,'Purchase Invoice '||coalesce(new.supplier_invoice_number,new.invoice_number),new.grand_total,0,new.posted_by)
    on conflict(tenant_id,entry_type,source_id) do nothing;
  end if;
  return new;
end$$;
drop trigger if exists trg_v484_invoice_ledger_after_status on public.purchase_invoices_v484;
create trigger trg_v484_invoice_ledger_after_status after update of status on public.purchase_invoices_v484 for each row execute function private.v484_invoice_ledger_after_status();

create or replace function private.v484_refresh_invoice_payment_status(p_invoice_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_paid numeric;v_total numeric;v_status text;begin
 select grand_total,status into v_total,v_status from public.purchase_invoices_v484 where id=p_invoice_id for update;if not found or v_status='void' then return;end if;
 select coalesce(sum(a.amount),0) into v_paid from public.supplier_payment_allocations_v484 a join public.supplier_payments_v484 p on p.id=a.supplier_payment_id where a.purchase_invoice_id=p_invoice_id and p.status='posted';
 update public.purchase_invoices_v484 set paid_total=v_paid,balance_due=greatest(v_total-v_paid,0),status=case when v_paid>=v_total-0.005 then 'paid' when v_paid>0 then 'part_paid' else 'posted' end,updated_at=now() where id=p_invoice_id;
end$$;
revoke all on function private.v484_refresh_invoice_payment_status(uuid) from public;

create or replace function public.supplier_payment_create_v484(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,
  p_allocations jsonb default '[]'::jsonb,p_reference_number text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_sum numeric:=0;x jsonb;v_invoice uuid;v_alloc numeric;i public.purchase_invoices_v484%rowtype;v_lines jsonb;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id and coalesce(status,'active')='active') then raise exception 'Supplier not found';end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Payment amount must be positive';end if;if trim(coalesce(p_payment_method,''))='' then raise exception 'Payment method is required';end if;
  if jsonb_typeof(coalesce(p_allocations,'[]'::jsonb))<>'array' then raise exception 'Allocations must be an array';end if;
  for x in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_invoice:=nullif(x->>'purchase_invoice_id','')::uuid;v_alloc:=coalesce(nullif(x->>'amount','')::numeric,0);if v_invoice is null or v_alloc<=0 then raise exception 'Each allocation requires an invoice and positive amount';end if;
    select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=v_invoice and supplier_id=p_supplier_id for update;if not found then raise exception 'Supplier invoice not found';end if;if i.status not in('posted','part_paid') then raise exception 'Invoice % is not open for payment',i.invoice_number;end if;if v_alloc-i.balance_due>0.005 then raise exception 'Allocation exceeds balance on invoice %',i.invoice_number;end if;v_sum:=v_sum+v_alloc;
  end loop;
  if v_sum-p_amount>0.005 then raise exception 'Allocated amount cannot exceed payment amount';end if;
  v_no:='SPAY-'||to_char(coalesce(p_payment_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.supplier_payment_number_seq_v484')::text,6,'0');
  insert into public.supplier_payments_v484(id,tenant_id,location_id,supplier_id,payment_number,payment_date,amount,payment_method,reference_number,notes,created_by)
  values(v_id,p_tenant_id,p_location_id,p_supplier_id,v_no,coalesce(p_payment_date,current_date),p_amount,lower(trim(p_payment_method)),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_invoice:=(x->>'purchase_invoice_id')::uuid;v_alloc:=(x->>'amount')::numeric;
    insert into public.supplier_payment_allocations_v484(supplier_payment_id,purchase_invoice_id,amount) values(v_id,v_invoice,v_alloc);
    perform private.v484_refresh_invoice_payment_status(v_invoice);
  end loop;
  insert into public.supplier_ledger_entries_v484(tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by)
  values(p_tenant_id,p_supplier_id,p_location_id,coalesce(p_payment_date,current_date),'supplier_payment',v_id,v_no,'Supplier payment'||case when v_sum<p_amount-0.005 then ' (includes unallocated credit)' else '' end,0,p_amount,auth.uid());
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',p_amount,'credit',0,'party_type','supplier','party_id',p_supplier_id,'description','Supplier payable settlement'),
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,lower(trim(p_payment_method))),'debit',0,'credit',p_amount,'party_type','supplier','party_id',p_supplier_id,'description','Supplier payment')
  );
  perform private.v4_journal_create(p_tenant_id,p_location_id,coalesce(p_payment_date,current_date),'Supplier Payment '||v_no,'supplier_payment_v484',v_id,v_no,v_lines);
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','supplier_payment',v_id::text,'post');
  return jsonb_build_object('success',true,'supplier_payment_id',v_id,'payment_number',v_no,'amount',p_amount,'allocated_amount',v_sum,'unallocated_amount',greatest(p_amount-v_sum,0));
end$$;
grant execute on function public.supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text) to authenticated;

create or replace function public.supplier_payment_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_supplier_id uuid default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,payment_number text,payment_date date,supplier_id uuid,supplier_name text,location_id uuid,location_name text,amount numeric,allocated_amount numeric,unallocated_amount numeric,payment_method text,reference_number text,status text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query select p.id,p.payment_number,p.payment_date,p.supplier_id,s.name,p.location_id,l.name,p.amount,coalesce(sum(a.amount),0),greatest(p.amount-coalesce(sum(a.amount),0),0),p.payment_method,p.reference_number,p.status,p.created_at
 from public.supplier_payments_v484 p join public.suppliers s on s.id=p.supplier_id join public.business_locations l on l.id=p.location_id left join public.supplier_payment_allocations_v484 a on a.supplier_payment_id=p.id
 where p.tenant_id=p_tenant_id and (p_location_id is null or p.location_id=p_location_id) and (p_supplier_id is null or p.supplier_id=p_supplier_id) and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')
 and (trim(coalesce(p_query,''))='' or lower(p.payment_number) like q or lower(s.name) like q or lower(coalesce(p.reference_number,'')) like q)
 group by p.id,s.name,l.name order by p.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.supplier_payment_list_v484(uuid,uuid,uuid,text,integer) to authenticated;

-- Complete supplier statement: legacy purchases/payments + Purchasing V2 invoices/payments.
create or replace function public.suppliers_get_statement_v484(p_tenant_id uuid,p_supplier_id uuid,p_from date default null,p_to date default null,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_name text;v_rows jsonb;v_debit numeric;v_credit numeric;begin
 perform private.purchasing_v484_permission(p_tenant_id,false);select name into v_name from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id;if v_name is null then raise exception 'Supplier not found';end if;
 with raw as (
   select p.purchase_date::timestamp as ts,p.purchase_date entry_date,'legacy_purchase'::text entry_type,p.purchase_number reference,'Legacy purchase bill'::text description,p.grand_total::numeric debit,0::numeric credit,o.location_id
   from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id and coalesce(p.status,'') not in('cancelled','void')
   union all
   select coalesce(pp.paid_at,pp.created_at),coalesce(pp.paid_at,pp.created_at)::date,'legacy_payment',p.purchase_number,'Legacy supplier payment',0::numeric,pp.amount::numeric,o.location_id
   from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id
   union all
   select e.created_at,e.entry_date,e.entry_type,e.reference_number,coalesce(e.description,''),e.debit,e.credit,e.location_id from public.supplier_ledger_entries_v484 e where e.tenant_id=p_tenant_id and e.supplier_id=p_supplier_id
 ), filtered as (
   select * from raw where (p_from is null or entry_date>=p_from) and (p_to is null or entry_date<=p_to) and (p_location_id is null or location_id=p_location_id) and (location_id is null or private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view'))
 ), running as (
   select *,sum(debit-credit) over(order by ts,entry_type,reference rows unbounded preceding) balance from filtered
 )
 select coalesce(jsonb_agg(jsonb_build_object('entry_date',entry_date,'entry_type',entry_type,'reference',reference,'description',description,'debit',debit,'credit',credit,'balance',balance) order by ts,entry_type,reference),'[]'::jsonb),coalesce(sum(debit),0),coalesce(sum(credit),0) into v_rows,v_debit,v_credit from running;
 return jsonb_build_object('party_id',p_supplier_id,'party_name',v_name,'opening_balance',0,'total_debit',v_debit,'total_credit',v_credit,'closing_balance',v_debit-v_credit,'rows',v_rows);
end$$;
grant execute on function public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(143,'4.8.4','Purchasing V2','Supplier payments with invoice allocation, Accounts Payable journals and unified legacy + V2 supplier ledger.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 143 supplier payments and ledger applied' as status;
