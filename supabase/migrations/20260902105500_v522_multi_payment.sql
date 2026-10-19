-- THQ ERP v5.2.2 Build 30
-- Repository filename: backend/migrations/260_v522_multi_payment.sql
-- Additive cutover: v5.2.0 RPCs remain unchanged; apps explicitly switch to v5.2.2.

create table if not exists public.payment_methods_v522 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  display_name text not null,
  ledger_account_id uuid null references public.accounting_accounts(id),
  active boolean not null default true,
  allow_over_tender boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  constraint payment_methods_v522_code_ck check (code in ('cash','upi','card','bank','cheque','wallet','credit','other'))
);

create table if not exists public.sale_payment_allocations_v522 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sale_id uuid not null,
  payment_method_id uuid not null references public.payment_methods_v522(id),
  method_code text not null,
  tendered_amount numeric(18,2) not null,
  allocated_amount numeric(18,2) not null,
  settlement_amount numeric(18,2) not null default 0,
  change_amount numeric(18,2) not null default 0,
  reference_number text null,
  sale_payment_id uuid null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint sale_payment_allocations_v522_sale_fk foreign key (sale_id,tenant_id)
    references public.sales(id,tenant_id) on delete cascade deferrable initially deferred,
  constraint sale_payment_allocations_v522_method_ck check (method_code in ('cash','upi','card','bank','cheque','wallet','credit','other')),
  constraint sale_payment_allocations_v522_amount_ck check (
    tendered_amount >= 0 and allocated_amount >= 0 and settlement_amount >= 0 and change_amount >= 0
  )
);

create index if not exists sale_payment_allocations_v522_sale_idx
  on public.sale_payment_allocations_v522(tenant_id,sale_id,created_at);

alter table public.sale_payments
  drop constraint if exists sale_payments_payment_method_check;
alter table public.sale_payments
  add constraint sale_payments_payment_method_check
  check (payment_method = any (array['cash'::text,'bank'::text,'card'::text,'upi'::text,'cheque'::text,'wallet'::text,'other'::text]));
alter table public.sale_payments
  add column if not exists payment_method_id uuid null references public.payment_methods_v522(id),
  add column if not exists payment_allocation_id uuid null references public.sale_payment_allocations_v522(id),
  add column if not exists ledger_account_id uuid null references public.accounting_accounts(id);
alter table public.sale_payment_allocations_v522
  add constraint sale_payment_allocations_v522_payment_fk foreign key (sale_payment_id)
  references public.sale_payments(id) on delete set null;

insert into public.payment_methods_v522(tenant_id,code,display_name,active,allow_over_tender,sort_order)
select t.id,x.code,x.name,true,x.over_tender,x.sort_order
from public.tenants t
cross join (values
 ('cash','Cash',true,10),('upi','UPI',false,20),('card','Card',false,30),('bank','Bank',false,40),
 ('cheque','Cheque',false,50),('wallet','Wallet',false,60),('credit','Credit',false,70),('other','Other',false,80)
) x(code,name,over_tender,sort_order)
on conflict (tenant_id,code) do nothing;

-- Preserve current working mappings, but give every settlement method its own key.
update public.payment_methods_v522 pm
set ledger_account_id=m.account_id,updated_at=now()
from public.accounting_account_mappings m
where m.tenant_id=pm.tenant_id and m.mapping_key='payment.'||pm.code and pm.code<>'credit';

insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id,updated_at)
select pm.tenant_id,'payment.'||pm.code,b.account_id,now()
from public.payment_methods_v522 pm
join public.accounting_account_mappings b on b.tenant_id=pm.tenant_id and b.mapping_key='payment.bank'
where pm.code in ('cheque','wallet','other')
on conflict (tenant_id,mapping_key) do nothing;

update public.payment_methods_v522 pm
set ledger_account_id=m.account_id,updated_at=now()
from public.accounting_account_mappings m
where m.tenant_id=pm.tenant_id and m.mapping_key='payment.'||pm.code and pm.code<>'credit' and pm.ledger_account_id is null;

alter table public.payment_methods_v522 enable row level security;
alter table public.sale_payment_allocations_v522 enable row level security;
revoke all on public.payment_methods_v522 from anon,authenticated;
revoke all on public.sale_payment_allocations_v522 from anon,authenticated;

create or replace function public.payment_methods_list_v522(p_tenant_id uuid)
returns table(id uuid,code text,display_name text,ledger_account_id uuid,ledger_code text,ledger_name text,active boolean,allow_over_tender boolean,sort_order integer)
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query
  select pm.id,pm.code,pm.display_name,pm.ledger_account_id,a.code,a.name,pm.active,pm.allow_over_tender,pm.sort_order
  from public.payment_methods_v522 pm
  left join public.accounting_accounts a on a.id=pm.ledger_account_id and a.tenant_id=pm.tenant_id
  where pm.tenant_id=p_tenant_id
  order by pm.sort_order,pm.display_name;
end;
$$;

create or replace function public.payment_method_save_v522(
  p_tenant_id uuid,p_code text,p_display_name text,p_ledger_account_id uuid,p_active boolean,p_sort_order integer default 0
) returns jsonb
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare v_code text:=lower(trim(coalesce(p_code,'')));v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'settings.manage') or private.erp_has_permission(p_tenant_id,'business.settings')) then
    raise exception 'Owner/Admin permission required';
  end if;
  if v_code not in ('cash','upi','card','bank','cheque','wallet','credit','other') then raise exception 'Unsupported payment method %',p_code; end if;
  if v_code<>'credit' and coalesce(p_active,true) and p_ledger_account_id is null then raise exception 'Active settlement method requires a ledger mapping'; end if;
  if p_ledger_account_id is not null and not exists(select 1 from public.accounting_accounts a where a.id=p_ledger_account_id and a.tenant_id=p_tenant_id and a.active) then
    raise exception 'Ledger account is invalid or inactive';
  end if;
  insert into public.payment_methods_v522(tenant_id,code,display_name,ledger_account_id,active,allow_over_tender,sort_order)
  values(p_tenant_id,v_code,coalesce(nullif(trim(p_display_name),''),initcap(v_code)),case when v_code='credit' then null else p_ledger_account_id end,
         coalesce(p_active,true),v_code='cash',coalesce(p_sort_order,0))
  on conflict(tenant_id,code) do update set display_name=excluded.display_name,ledger_account_id=excluded.ledger_account_id,
    active=excluded.active,allow_over_tender=excluded.allow_over_tender,sort_order=excluded.sort_order,updated_at=now()
  returning id into v_id;
  if v_code<>'credit' and p_ledger_account_id is not null then
    insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id,updated_at)
    values(p_tenant_id,'payment.'||v_code,p_ledger_account_id,now())
    on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();
  end if;
  return jsonb_build_object('success',true,'id',v_id,'code',v_code);
end;
$$;

create or replace function private.gst_payment_gl_line_v522(
  p_tenant_id uuid,p_method text,p_amount numeric,p_description text,p_party_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare v_amount numeric:=round(coalesce(p_amount,0),2);v_acc uuid;v_code text:=lower(trim(coalesce(p_method,'')));
begin
  if v_amount<=0 then return null; end if;
  select ledger_account_id into v_acc from public.payment_methods_v522
  where tenant_id=p_tenant_id and code=v_code and active;
  if v_acc is null then raise exception 'Payment method % has no active ledger mapping in Business Settings',v_code; end if;
  if not exists(select 1 from public.accounting_accounts where id=v_acc and tenant_id=p_tenant_id and active) then
    raise exception 'Payment ledger for % is missing or inactive',v_code;
  end if;
  return jsonb_build_object('account_id',v_acc,'mapping_key','payment.'||v_code,'debit',v_amount,'credit',0,
    'party_type','customer','party_id',p_party_id,'description',p_description);
end;
$$;

create or replace function private.sale_payment_allocations_create_v522(
  p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_total numeric,p_allocations jsonb
) returns jsonb
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare
  x jsonb;v_code text;v_tender numeric;v_alloc numeric;v_change numeric;v_remaining numeric:=round(coalesce(p_total,0),2);
  v_settled numeric:=0;v_credit numeric:=0;v_change_total numeric:=0;v_pm public.payment_methods_v522%rowtype;
  v_customer public.customers%rowtype;v_payment uuid;v_allocation uuid;v_ref text;
begin
  if jsonb_typeof(coalesce(p_allocations,'null'::jsonb))<>'array' then raise exception 'Payment allocations must be an array'; end if;
  select * into v_customer from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active';
  if not found then raise exception 'Active customer not found'; end if;
  for x in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_code:=lower(trim(coalesce(x->>'method_code',x->>'payment_method','')));
    v_tender:=round(coalesce(nullif(x->>'tendered_amount','')::numeric,nullif(x->>'amount','')::numeric,0),2);
    v_ref:=nullif(trim(coalesce(x->>'reference_number',x->>'reference','')),'');
    if v_tender<=0 then continue; end if;
    select * into v_pm from public.payment_methods_v522 where tenant_id=p_tenant_id and code=v_code and active;
    if not found then raise exception 'Payment method % is disabled or unavailable',v_code; end if;
    if v_remaining<=0 then
      if v_code='cash' and v_pm.allow_over_tender then raise exception 'Cash tender was provided after invoice was already fully allocated'; end if;
      raise exception 'Payment allocations exceed invoice total';
    end if;
    if v_code='credit' then
      if v_customer.is_walk_in or nullif(trim(v_customer.name),'') is null then raise exception 'Credit requires a named customer'; end if;
      if v_tender>v_remaining+0.005 then raise exception 'Credit allocation exceeds remaining invoice balance'; end if;
      v_alloc:=least(v_tender,v_remaining);v_change:=0;v_payment:=null;v_credit:=v_credit+v_alloc;
    else
      if v_pm.ledger_account_id is null then raise exception 'Payment method % has no ledger mapping in Business Settings',v_code; end if;
      if v_tender>v_remaining+0.005 and (v_code<>'cash' or not v_pm.allow_over_tender) then
        raise exception 'Overpayment is not supported for %',v_code;
      end if;
      v_alloc:=least(v_tender,v_remaining);v_change:=case when v_code='cash' then round(v_tender-v_alloc,2) else 0 end;
      insert into public.sale_payments(tenant_id,sale_id,amount,payment_method,reference_number,notes,paid_at,created_by,payment_method_id,ledger_account_id)
      values(p_tenant_id,p_sale_id,v_alloc,v_code,v_ref,'v5.2.2 invoice allocation',now(),auth.uid(),v_pm.id,v_pm.ledger_account_id)
      returning id into v_payment;
      v_settled:=round(v_settled+v_alloc,2);v_change_total:=round(v_change_total+v_change,2);
    end if;
    insert into public.sale_payment_allocations_v522(tenant_id,sale_id,payment_method_id,method_code,tendered_amount,allocated_amount,settlement_amount,change_amount,reference_number,sale_payment_id,created_by)
    values(p_tenant_id,p_sale_id,v_pm.id,v_code,v_tender,v_alloc,case when v_code='credit' then 0 else v_alloc end,v_change,v_ref,v_payment,auth.uid())
    returning id into v_allocation;
    if v_payment is not null then update public.sale_payments set payment_allocation_id=v_allocation where id=v_payment; end if;
    v_remaining:=round(v_remaining-v_alloc,2);
  end loop;
  if abs(v_remaining)>0.005 then raise exception 'Payment allocations must cover the invoice total. Remaining %',v_remaining; end if;
  return jsonb_build_object('settled_amount',v_settled,'credit_amount',v_credit,'change_amount',v_change_total,'accounts_receivable',round(p_total-v_settled,2));
end;
$$;

create or replace function private.gst_snapshot_sale_journal_lines_v522(p_tenant_id uuid,p_snapshot_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare s public.gst_document_snapshots_v520%rowtype;v_lines jsonb:='[]'::jsonb;v_tax jsonb;v_party uuid;v_paid numeric:=0;v_balance numeric;v_cost numeric:=0;v_delta numeric;r record;x jsonb;
begin
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found or s.source_type<>'sale' then raise exception 'v5.2.2 Sale snapshot not found'; end if;
  if abs(coalesce(s.additional_charges,0))>0.0001 then raise exception 'Unclassified Additional Charges are not permitted'; end if;
  select customer_id into v_party from public.sales where id=s.source_id and tenant_id=p_tenant_id and status='posted';
  if v_party is null then raise exception 'Posted Sale source not found'; end if;
  for r in
    select a.method_code,sum(a.settlement_amount)::numeric amount
    from public.sale_payment_allocations_v522 a
    where a.tenant_id=p_tenant_id and a.sale_id=s.source_id and a.settlement_amount>0
    group by a.method_code
  loop
    x:=private.gst_payment_gl_line_v522(p_tenant_id,r.method_code,r.amount,'Sale receipt - '||r.method_code,v_party);
    if x is not null then v_lines:=v_lines||jsonb_build_array(x); end if;
    v_paid:=v_paid+r.amount;
  end loop;
  v_paid:=least(round(v_paid,2),round(s.grand_total,2));v_balance:=round(s.grand_total-v_paid,2);
  v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_receivable',v_balance,'debit','Customer receivable','customer',v_party));
  v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'sales_revenue',round(s.taxable_total,2),'credit','Sales revenue','customer',v_party));
  v_tax:=private.gst_snapshot_tax_journal_lines_v520(p_tenant_id,p_snapshot_id);v_lines:=v_lines||v_tax;
  v_delta:=round(coalesce(s.calculation_rounding,0)+coalesce(s.round_off,0),2);
  v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'sale','GST sale calculation/document round off'));
  select round(coalesce(sum(coalesce(si.cost_total,0)) filter(where p.item_type='stock'),0),2) into v_cost
  from public.sale_items si join public.product_variants pv on pv.id=si.variant_id and pv.tenant_id=si.tenant_id
  join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  where si.tenant_id=p_tenant_id and si.sale_id=s.source_id;
  v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'cogs',v_cost,'debit','Cost of goods sold'));
  v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_cost,'credit','Inventory issued'));
  return v_lines;
end;
$$;

create or replace function private.gst_authoritative_sale_journal_post_v522(p_tenant_id uuid,p_snapshot_id uuid)
returns uuid
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare s public.gst_document_snapshots_v520%rowtype;v_lines jsonb;v_dr numeric;v_cr numeric;v_existing uuid;v_created uuid;
begin
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found or s.source_type<>'sale' then raise exception 'Authoritative v5.2.2 Sale snapshot not found'; end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type='sale' and m.source_id=s.source_id) then
    raise exception 'Legacy-unverified GST evidence cannot be posted as v5.2.2 authoritative accounting';
  end if;
  v_lines:=private.gst_snapshot_sale_journal_lines_v522(p_tenant_id,p_snapshot_id);
  select round(coalesce(sum((x->>'debit')::numeric),0),2),round(coalesce(sum((x->>'credit')::numeric),0),2) into v_dr,v_cr from jsonb_array_elements(v_lines)x;
  if v_dr<=0 or v_cr<=0 or v_dr<>v_cr then raise exception 'v5.2.2 Sale journal is not balanced. Debit %, Credit %',v_dr,v_cr; end if;
  select id into v_existing from public.journal_entries where tenant_id=p_tenant_id and source_type='sale' and source_id=s.source_id and status='posted' order by created_at limit 1;
  if v_existing is not null then
    if private.gst_journal_matches_expected_v520(p_tenant_id,v_existing,v_lines) then return v_existing; end if;
    raise exception 'Posted Sale journal does not match v5.2.2 authoritative payment allocation';
  end if;
  v_created:=private.v4_journal_create(p_tenant_id,s.location_id,s.document_date,'GST Sale '||s.source_number,'sale',s.source_id,s.source_number,v_lines);
  if v_created is null or not private.gst_journal_matches_expected_v520(p_tenant_id,v_created,v_lines) then raise exception 'v5.2.2 Sale journal verification failed'; end if;
  return v_created;
end;
$$;

create or replace function public.gst_sale_create_v522(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,
  p_notes text default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null,
  p_supply_type text default null,p_place_of_supply_code text default null
) returns jsonb
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare
  v_req_payload jsonb;v_req_state jsonb;v_old_req jsonb;v_supply text;v_pos text;v_priced jsonb;v_normalized jsonb;
  v_quote0 jsonb;v_quote jsonb;v_bridge jsonb;v_source jsonb;v_sale_id uuid;v_sale_number text;v_line_ids jsonb;v_snapshot uuid;v_journal uuid;
  v_document_number text;v_response jsonb;v_totals jsonb;v_round numeric;v_payment_result jsonb;v_discount numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.manage')) then raise exception 'Sales permission required'; end if;
  if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required'; end if;
  if p_location_id is null then raise exception 'Business location is required'; end if;
  if p_sale_date is null then raise exception 'Sale date is required'; end if;
  if p_due_date is not null and p_due_date<p_sale_date then raise exception 'Due date cannot be before sale date'; end if;
  v_req_payload:=jsonb_build_object('customer_id',p_customer_id,'sale_date',p_sale_date,'due_date',p_due_date,'items',coalesce(p_items,'[]'::jsonb),
    'payment_allocations',coalesce(p_payment_allocations,'[]'::jsonb),'notes',nullif(trim(coalesce(p_notes,'')),''),'location_id',p_location_id,
    'device_id',p_device_id,'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),'') );
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.sale.create.v522',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response'; end if;
  v_old_req:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create');if v_old_req is not null then raise exception 'Request ID is already used by the legacy Sale path'; end if;
  v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);
  v_normalized:=private.v481_normalize_items(p_tenant_id,v_priced,'sale');
  v_supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,p_customer_id,p_sale_date,p_supply_type);
  v_pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,p_customer_id,p_location_id,p_sale_date,v_supply,v_normalized,p_place_of_supply_code);
  v_quote0:=public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_customer_id,p_sale_date,v_supply,v_pos,v_normalized,0,0);
  if coalesce((v_quote0->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Sale is not compliance-ready: %',coalesce(v_quote0->'errors','[]'::jsonb)::text; end if;
  v_round:=round(round(coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),0)-coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),2);
  v_quote:=public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_customer_id,p_sale_date,v_supply,v_pos,v_normalized,0,v_round);
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Sale is not compliance-ready after round-off: %',coalesce(v_quote->'errors','[]'::jsonb)::text; end if;
  v_totals:=v_quote->'totals';v_discount:=coalesce((v_totals->>'discount')::numeric,0);
  v_bridge:=private.gst_sale_bridge_v520(v_priced,v_normalized,(v_totals->>'grand_total')::numeric);
  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'sale');
  v_source:=public.sales_create_v483(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_bridge->'items',(v_bridge->>'additional_charges')::numeric,0,'cash',null,p_notes,p_location_id,p_device_id,p_request_id);
  v_sale_id:=nullif(v_source->>'sale_id','')::uuid;if v_sale_id is null then raise exception 'GST Sale source could not be resolved'; end if;
  perform private.gst_authoritative_context_bind_v520(v_sale_id);
  select sale_number into v_sale_number from public.sales where tenant_id=p_tenant_id and id=v_sale_id and status='posted' for update;
  if v_sale_number is null then raise exception 'GST Sale source is not posted'; end if;
  if exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and source_type='sale' and source_id=v_sale_id and status='posted') then raise exception 'Legacy Sale journal was created inside authoritative GST context'; end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 where tenant_id=p_tenant_id and source_type='sale' and source_id=v_sale_id) then raise exception 'Legacy GST evidence was created inside authoritative GST context'; end if;
  v_line_ids:=private.gst_sale_reconcile_source_v520(p_tenant_id,v_sale_id,v_quote);
  v_payment_result:=private.sale_payment_allocations_create_v522(p_tenant_id,v_sale_id,p_customer_id,(v_totals->>'grand_total')::numeric,coalesce(p_payment_allocations,'[]'::jsonb));
  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sale',v_sale_id,v_sale_number,p_location_id,p_sale_date,v_quote,v_line_ids);
  v_journal:=private.gst_authoritative_sale_journal_post_v522(p_tenant_id,v_snapshot);
  select document_number into v_document_number from public.gst_document_snapshots_v520 where id=v_snapshot and tenant_id=p_tenant_id;
  if v_document_number is null then raise exception 'GST Sale legal document number was not captured'; end if;
  v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object('success',true,'writer','gst_sale_create_v522','version','5.2.2','gst_engine',v_quote->>'engine',
    'gst_status','POSTED','gst_supply_type',v_supply,'place_of_supply_code',v_quote->>'place_of_supply_code','sale_id',v_sale_id,'sale_number',v_sale_number,
    'invoice_number',v_document_number,'subtotal',(v_totals->>'subtotal')::numeric,'discount_total',v_discount,'round_off',v_round,
    'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,
    'payments',v_payment_result,'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'gst_ready_for_compliance',true,'legacy_fallback_used',false);
  v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.sale.create.v522','sale',v_sale_id,v_snapshot,v_journal,v_response);
  update public.transaction_requests_v47 set response=v_response where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='sale.create';
  perform private.gst_authoritative_context_exit_v520();return v_response;
end;
$$;

create or replace function public.gst_pos_sale_create_v522(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,p_notes text default null,
  p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null,p_supply_type text default null,p_place_of_supply_code text default null
) returns jsonb language sql security definer set search_path=public,pg_temp as $$
 select public.gst_sale_create_v522(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code);
$$;

create or replace function public.gst_pos_offline_sale_sync_v522(p_payload jsonb)
returns jsonb language sql security definer set search_path=public,pg_temp as $$
 select public.gst_pos_sale_create_v522((p_payload->>'tenant_id')::uuid,(p_payload->>'customer_id')::uuid,(p_payload->>'sale_date')::date,
   nullif(p_payload->>'due_date','')::date,coalesce(p_payload->'items','[]'::jsonb),coalesce(p_payload->'payment_allocations','[]'::jsonb),p_payload->>'notes',
   nullif(p_payload->>'location_id','')::uuid,nullif(p_payload->>'device_id','')::uuid,p_payload->>'request_id',p_payload->>'supply_type',p_payload->>'place_of_supply_code');
$$;

create or replace function public.gst_mobile_pos_sale_sync_v522(p_payload jsonb)
returns jsonb language sql security definer set search_path=public,pg_temp as $$ select public.gst_pos_offline_sale_sync_v522(p_payload); $$;

create or replace function public.gst_transaction_cutover_contract_v522(p_tenant_id uuid,p_channel text default 'client',p_device_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_channel text:=lower(trim(coalesce(p_channel,'client')));
begin
  v:=public.gst_transaction_cutover_contract_v520(p_tenant_id,p_channel,p_device_id);
  v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('sale',case when v_channel='client' then 'gst_sale_create_v522' else 'gst_pos_sale_create_v522' end),true);
  if v_channel in ('pos','offline_pos','mobile_pos') then
    v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('offline_sale_sync','gst_pos_offline_sale_sync_v522'),true);
  end if;
  v:=v||jsonb_build_object('version','5.2.2','build',30,'multi_payment',true,'automatic_round_off',true,'legacy_fallback_after_v522_failure',false,
    'additional_charges','service_products_only','payment_methods',jsonb_build_array('cash','upi','card','bank','cheque','wallet','credit','other'));
  return v;
end;
$$;

grant execute on function public.payment_methods_list_v522(uuid) to authenticated;
grant execute on function public.payment_method_save_v522(uuid,text,text,uuid,boolean,integer) to authenticated;
grant execute on function public.gst_sale_create_v522(uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.gst_pos_sale_create_v522(uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.gst_pos_offline_sale_sync_v522(jsonb) to authenticated;
grant execute on function public.gst_mobile_pos_sale_sync_v522(jsonb) to authenticated;
grant execute on function public.gst_transaction_cutover_contract_v522(uuid,text,uuid) to authenticated;
;
