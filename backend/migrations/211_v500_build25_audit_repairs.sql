-- THQ ERP v5.0.0 Build 25 — verified audit repairs.
-- Additive upgrade from Build 24 / migration 210.
begin;

-- ---------------------------------------------------------------------------
-- Financial periods, opening balances and journal integrity
-- ---------------------------------------------------------------------------
alter table public.financial_years_v500 add column if not exists closing_journal_id uuid references public.journal_entries(id);

create table if not exists public.opening_balance_batches_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id),
  entry_date date not null,
  description text not null,
  journal_id uuid not null references public.journal_entries(id),
  status text not null default 'posted' check(status in('posted','reversed')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.opening_balance_batches_v500 enable row level security;
revoke all on public.opening_balance_batches_v500 from anon,authenticated;

create or replace function private.v500_assert_posting_period_open(p_tenant_id uuid,p_entry_date date)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if p_entry_date is null then raise exception 'Journal date is required';end if;
  if exists(
    select 1 from public.financial_years_v500 y
    where y.tenant_id=p_tenant_id
      and y.locked_through is not null
      and p_entry_date<=y.locked_through
  ) then
    raise exception 'Accounting period is locked through %',(
      select max(y.locked_through) from public.financial_years_v500 y
      where y.tenant_id=p_tenant_id and y.locked_through is not null and p_entry_date<=y.locked_through
    );
  end if;
end $$;
revoke all on function private.v500_assert_posting_period_open(uuid,date) from public;

create or replace function private.v4_journal_create(
  p_tenant_id uuid,p_location_id uuid,p_entry_date date,p_description text,
  p_source_type text,p_source_id uuid,p_source_reference text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_dr numeric:=0;v_cr numeric:=0;
  v_debit numeric;v_credit numeric;v_account uuid;v_count integer:=0;
begin
  -- Preserve idempotent retries before period validation.
  if p_source_type is not null and p_source_id is not null and exists(
    select 1 from public.journal_entries
    where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and status='posted'
  ) then
    select id into v_id from public.journal_entries
    where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and status='posted'
    order by created_at limit 1;
    return v_id;
  end if;

  perform private.v500_assert_posting_period_open(p_tenant_id,p_entry_date);
  if p_location_id is not null and not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id) then
    raise exception 'Invalid accounting location';
  end if;
  if jsonb_typeof(coalesce(p_lines,'null'::jsonb))<>'array' or jsonb_array_length(p_lines)<2 then
    raise exception 'Journal must contain at least two lines';
  end if;

  for x in select value from jsonb_array_elements(p_lines) loop
    begin
      v_account:=(x->>'account_id')::uuid;
      v_debit:=round(coalesce(nullif(x->>'debit','')::numeric,0),2);
      v_credit:=round(coalesce(nullif(x->>'credit','')::numeric,0),2);
    exception when others then raise exception 'Invalid journal line';end;
    if not exists(select 1 from public.accounting_accounts a where a.id=v_account and a.tenant_id=p_tenant_id and a.active) then
      raise exception 'Journal account % is missing, inactive or belongs to another business',v_account;
    end if;
    if v_debit<0 or v_credit<0 or (v_debit>0 and v_credit>0) or (v_debit=0 and v_credit=0) then
      raise exception 'Each journal line must contain exactly one positive debit or credit';
    end if;
    v_count:=v_count+1;v_dr:=v_dr+v_debit;v_cr:=v_cr+v_credit;
  end loop;
  v_dr:=round(v_dr,2);v_cr:=round(v_cr,2);
  if v_dr<=0 or v_cr<=0 or v_dr<>v_cr then raise exception 'Journal is not balanced. Debit %, Credit %',v_dr,v_cr;end if;

  v_no:='JRN-'||lpad(nextval('public.journal_entry_number_seq')::text,8,'0');
  insert into public.journal_entries(id,tenant_id,location_id,entry_number,entry_date,description,status,source_type,source_id,source_reference,created_by,posted_at)
  values(v_id,p_tenant_id,p_location_id,v_no,p_entry_date,coalesce(nullif(trim(p_description),''),'Journal entry'),'posted',nullif(trim(coalesce(p_source_type,'')),''),p_source_id,nullif(trim(coalesce(p_source_reference,'')),''),auth.uid(),now());
  for x in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(journal_entry_id,account_id,party_type,party_id,description,debit,credit)
    values(v_id,(x->>'account_id')::uuid,nullif(x->>'party_type',''),nullif(x->>'party_id','')::uuid,nullif(trim(coalesce(x->>'description','')),''),round(coalesce(nullif(x->>'debit','')::numeric,0),2),round(coalesce(nullif(x->>'credit','')::numeric,0),2));
  end loop;
  return v_id;
end $$;
revoke all on function private.v4_journal_create(uuid,uuid,date,text,text,uuid,text,jsonb) from public;

create or replace function public.accounting_accounts_list_v4(p_tenant_id uuid)
returns table(id uuid,code text,name text,account_type text,parent_id uuid,system_key text,description text,is_system boolean,active boolean,balance numeric)
language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'accounting.view') and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Accounting permission required';end if;
  return query
  select a.id,a.code,a.name,a.account_type,a.parent_id,a.system_key,a.description,a.is_system,a.active,
    coalesce((select sum(case when a.account_type in('asset','expense','cogs') then l.debit-l.credit else l.credit-l.debit end)
      from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id
      where l.account_id=a.id and j.tenant_id=p_tenant_id and j.status='posted'),0)::numeric
  from public.accounting_accounts a where a.tenant_id=p_tenant_id order by a.code;
end $$;
grant execute on function public.accounting_accounts_list_v4(uuid) to authenticated;

create or replace function public.financial_year_save_v500(p_tenant_id uuid,p_year_id uuid,p_name text,p_start_date date,p_end_date date,p_locked_through date default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if trim(coalesce(p_name,''))='' then raise exception 'Financial year name is required';end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Invalid financial year dates';end if;
  if p_locked_through is not null and (p_locked_through<p_start_date or p_locked_through>p_end_date) then raise exception 'Locked-through date must be inside the financial year';end if;
  if exists(select 1 from public.financial_years_v500 y where y.tenant_id=p_tenant_id and y.id is distinct from p_year_id and daterange(y.start_date,y.end_date,'[]') && daterange(p_start_date,p_end_date,'[]')) then
    raise exception 'Financial year overlaps an existing year';
  end if;
  if p_year_id is null then
    insert into public.financial_years_v500(tenant_id,name,start_date,end_date,locked_through,created_by)
    values(p_tenant_id,trim(p_name),p_start_date,p_end_date,p_locked_through,auth.uid()) returning id into v;
  else
    update public.financial_years_v500 set name=trim(p_name),start_date=p_start_date,end_date=p_end_date,locked_through=p_locked_through
    where id=p_year_id and tenant_id=p_tenant_id and status='open' returning id into v;
    if v is null then raise exception 'Open financial year not found';end if;
  end if;return v;
end $$;
grant execute on function public.financial_year_save_v500(uuid,uuid,text,date,date,date) to authenticated;

create or replace function public.opening_balance_post_v500(
  p_tenant_id uuid,p_entry_date date,p_lines jsonb,p_description text default 'Opening balances',p_location_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_journal uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if exists(select 1 from public.opening_balance_batches_v500 where tenant_id=p_tenant_id and status='posted' and entry_date=p_entry_date and coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_location_id,'00000000-0000-0000-0000-000000000000'::uuid)) then
    raise exception 'Opening balances already posted for this date and location';
  end if;
  v_journal:=private.v4_journal_create(p_tenant_id,p_location_id,p_entry_date,coalesce(nullif(trim(p_description),''),'Opening balances'),'opening_balance_v500',v_id,'OPENING',p_lines);
  insert into public.opening_balance_batches_v500(id,tenant_id,location_id,entry_date,description,journal_id,created_by)
  values(v_id,p_tenant_id,p_location_id,p_entry_date,coalesce(nullif(trim(p_description),''),'Opening balances'),v_journal,auth.uid());
  return jsonb_build_object('opening_balance_id',v_id,'journal_id',v_journal);
end $$;
grant execute on function public.opening_balance_post_v500(uuid,date,jsonb,text,uuid) to authenticated;

create or replace function public.opening_balances_list_v500(p_tenant_id uuid,p_from date default null,p_to date default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  perform private.v500_accounting_access(p_tenant_id,false);
  for r in select b.*,j.entry_number from public.opening_balance_batches_v500 b join public.journal_entries j on j.id=b.journal_id
    where b.tenant_id=p_tenant_id and (p_from is null or b.entry_date>=p_from) and (p_to is null or b.entry_date<=p_to)
    order by b.entry_date desc,b.created_at desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.opening_balances_list_v500(uuid,date,date) to authenticated;

create or replace function private.v500_retained_earnings_account(p_tenant_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;v_code text:='3990-RE';begin
  select id into v from public.accounting_accounts where tenant_id=p_tenant_id and system_key='retained_earnings' and active limit 1;
  if v is null then
    if exists(select 1 from public.accounting_accounts where tenant_id=p_tenant_id and code=v_code) then v_code:='3990-RE-'||substr(gen_random_uuid()::text,1,6);end if;
    insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
    values(p_tenant_id,v_code,'Retained Earnings','equity','retained_earnings',true,'Accumulated retained earnings from financial year closing') returning id into v;
  end if;
  return v;
end $$;
revoke all on function private.v500_retained_earnings_account(uuid) from public;

create or replace function public.financial_year_close_v500(p_tenant_id uuid,p_year_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare y public.financial_years_v500%rowtype;r record;v_lines jsonb:='[]'::jsonb;v_profit numeric:=0;v_re uuid;v_journal uuid;v_bal numeric;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  select * into y from public.financial_years_v500 where id=p_year_id and tenant_id=p_tenant_id and status='open' for update;
  if not found then raise exception 'Open financial year not found';end if;
  if y.end_date>current_date then raise exception 'Cannot close a financial year before its end date';end if;
  if exists(select 1 from public.financial_years_v500 x where x.tenant_id=p_tenant_id and x.status='open' and x.end_date<y.end_date and x.id<>y.id) then raise exception 'Close earlier financial years first';end if;
  v_re:=private.v500_retained_earnings_account(p_tenant_id);
  for r in
    select a.id,a.account_type,a.name,
      round(case when a.account_type='income' then coalesce(sum(case when j.id is not null then l.credit-l.debit else 0 end),0) else coalesce(sum(case when j.id is not null then l.debit-l.credit else 0 end),0) end,2) bal
    from public.accounting_accounts a
    left join public.journal_lines l on l.account_id=a.id
    left join public.journal_entries j on j.id=l.journal_entry_id and j.status='posted' and j.entry_date between y.start_date and y.end_date and j.tenant_id=p_tenant_id
    where a.tenant_id=p_tenant_id and a.account_type in('income','expense','cogs')
    group by a.id,a.account_type,a.name
  loop
    v_bal:=coalesce(r.bal,0);if abs(v_bal)<0.005 then continue;end if;
    if r.account_type='income' then
      v_profit:=v_profit+v_bal;
      if v_bal>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',v_bal,'credit',0,'description','Financial year close • '||r.name));
      else v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',0,'credit',abs(v_bal),'description','Financial year close • '||r.name));end if;
    else
      v_profit:=v_profit-v_bal;
      if v_bal>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',0,'credit',v_bal,'description','Financial year close • '||r.name));
      else v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',abs(v_bal),'credit',0,'description','Financial year close • '||r.name));end if;
    end if;
  end loop;
  v_profit:=round(v_profit,2);
  if jsonb_array_length(v_lines)>0 then
    if v_profit>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_re,'debit',0,'credit',v_profit,'description','Net profit transferred to retained earnings'));
    elsif v_profit<0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_re,'debit',abs(v_profit),'credit',0,'description','Net loss transferred to retained earnings'));end if;
    v_journal:=private.v4_journal_create(p_tenant_id,null,y.end_date,'Financial year closing • '||y.name,'financial_year_close_v500',y.id,y.name,v_lines);
  end if;
  update public.financial_years_v500 set status='closed',locked_through=end_date,closing_journal_id=v_journal,closed_by=auth.uid(),closed_at=now() where id=y.id;
end $$;
grant execute on function public.financial_year_close_v500(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Safer vouchers, reversals and bank reconciliation
-- ---------------------------------------------------------------------------
create or replace function public.finance_voucher_post_v500(p_tenant_id uuid,p_location_id uuid,p_voucher_type text,p_voucher_date date,p_amount numeric,p_debit_account_id uuid,p_credit_account_id uuid,p_party_type text default null,p_party_id uuid default null,p_payment_method text default null,p_reference_number text default null,p_narration text default '')
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_journal uuid;v_lines jsonb;v_bad text;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if p_voucher_type not in('payment','receipt','contra') then raise exception 'Invalid voucher type';end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Voucher amount must be greater than zero';end if;
  if p_debit_account_id=p_credit_account_id then raise exception 'Debit and credit accounts must be different';end if;
  select string_agg(coalesce(system_key,code),', ') into v_bad from public.accounting_accounts
  where tenant_id=p_tenant_id and id in(p_debit_account_id,p_credit_account_id) and system_key in('accounts_receivable','accounts_payable','inventory_asset','input_gst','output_gst','loan_receivable','loan_payable');
  if v_bad is not null then raise exception 'Use the source transaction/Payment Center for protected control account(s): %',v_bad;end if;
  if (select count(*) from public.accounting_accounts where id in(p_debit_account_id,p_credit_account_id) and tenant_id=p_tenant_id and active)<>2 then raise exception 'Invalid accounting account';end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'operate');end if;
  v_no:=upper(substr(p_voucher_type,1,3))||'-'||lpad(nextval('public.finance_voucher_number_seq_v500')::text,8,'0');
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',p_debit_account_id,'debit',round(p_amount,2),'credit',0,'party_type',p_party_type,'party_id',p_party_id,'description',coalesce(nullif(trim(p_narration),''),v_no)),
    jsonb_build_object('account_id',p_credit_account_id,'debit',0,'credit',round(p_amount,2),'party_type',p_party_type,'party_id',p_party_id,'description',coalesce(nullif(trim(p_narration),''),v_no)));
  v_journal:=private.v4_journal_create(p_tenant_id,p_location_id,coalesce(p_voucher_date,current_date),coalesce(nullif(trim(p_narration),''),initcap(p_voucher_type)||' voucher '||v_no),'finance_voucher_v500',v_id,v_no,v_lines);
  insert into public.finance_vouchers_v500(id,tenant_id,location_id,voucher_number,voucher_type,voucher_date,amount,debit_account_id,credit_account_id,party_type,party_id,payment_method,reference_number,narration,journal_id,created_by)
  values(v_id,p_tenant_id,p_location_id,v_no,p_voucher_type,coalesce(p_voucher_date,current_date),round(p_amount,2),p_debit_account_id,p_credit_account_id,nullif(trim(coalesce(p_party_type,'')),''),p_party_id,nullif(trim(coalesce(p_payment_method,'')),''),nullif(trim(coalesce(p_reference_number,'')),''),coalesce(nullif(trim(p_narration),''),initcap(p_voucher_type)||' voucher'),v_journal,auth.uid());
  return jsonb_build_object('voucher_id',v_id,'voucher_number',v_no,'journal_id',v_journal);
end $$;
grant execute on function public.finance_voucher_post_v500(uuid,uuid,text,date,numeric,uuid,uuid,text,uuid,text,text,text) to authenticated;

create or replace function public.journal_reverse_v500(p_tenant_id uuid,p_journal_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare j public.journal_entries%rowtype;x record;v_lines jsonb:='[]'::jsonb;v_new uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if trim(coalesce(p_reason,''))='' then raise exception 'Reversal reason is required';end if;
  select * into j from public.journal_entries where id=p_journal_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Journal not found';end if;if j.status<>'posted' then raise exception 'Only posted journals can be reversed';end if;
  if coalesce(j.source_type,'manual') not in('manual','finance_voucher_v500','opening_balance_v500') then
    raise exception 'Operational journal % must be reversed from its source transaction, not Journal Center',coalesce(j.source_type,'unknown');
  end if;
  perform private.v500_assert_posting_period_open(p_tenant_id,current_date);
  for x in select * from public.journal_lines where journal_entry_id=j.id order by id loop
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',x.account_id,'debit',x.credit,'credit',x.debit,'party_type',x.party_type,'party_id',x.party_id,'description','Reversal: '||coalesce(x.description,j.description)));
  end loop;
  update public.journal_entries set status='reversed' where id=j.id;
  v_new:=private.v4_journal_create(p_tenant_id,j.location_id,current_date,'Reversal of '||j.entry_number||' • '||trim(p_reason),'journal_reversal_v500',j.id,j.entry_number,v_lines);
  update public.journal_entries set reversal_of=j.id where id=v_new;
  update public.finance_vouchers_v500 set status='reversed',reversal_journal_id=v_new,reversed_by=auth.uid(),reversed_at=now() where tenant_id=p_tenant_id and journal_id=j.id;
  update public.opening_balance_batches_v500 set status='reversed' where tenant_id=p_tenant_id and journal_id=j.id;
  return v_new;
end $$;
grant execute on function public.journal_reverse_v500(uuid,uuid,text) to authenticated;

create or replace function public.bank_statement_match_v500(p_tenant_id uuid,p_line_id uuid,p_journal_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare s public.bank_statement_lines_v500%rowtype;v_account uuid;v_net numeric;v_expected numeric;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  select * into s from public.bank_statement_lines_v500 where id=p_line_id and tenant_id=p_tenant_id and status='unmatched' for update;
  if not found then raise exception 'Unmatched bank statement line not found';end if;
  select accounting_account_id into v_account from public.bank_accounts_v500 where id=s.bank_account_id and tenant_id=p_tenant_id and active;
  if v_account is null then raise exception 'Active bank account not found';end if;
  if not exists(select 1 from public.journal_entries where id=p_journal_id and tenant_id=p_tenant_id and status='posted') then raise exception 'Posted journal not found';end if;
  select round(coalesce(sum(l.debit-l.credit),0),2) into v_net from public.journal_lines l where l.journal_entry_id=p_journal_id and l.account_id=v_account;
  v_expected:=case when s.direction='credit' then round(s.amount,2) else -round(s.amount,2) end;
  if v_net<>v_expected then raise exception 'Journal bank movement % does not match statement % %',v_net,s.direction,s.amount;end if;
  update public.bank_statement_lines_v500 set matched_journal_id=p_journal_id,status='matched',matched_by=auth.uid(),matched_at=now() where id=s.id;
end $$;
grant execute on function public.bank_statement_match_v500(uuid,uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- CRM validation and customer-group pricing
-- ---------------------------------------------------------------------------
create or replace function public.customer_crm_save_v500(p_tenant_id uuid,p_customer_id uuid,p_group_id uuid,p_salesperson_user_id uuid,p_birthday date,p_anniversary date,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v500_customer_manage_access(p_tenant_id);
  if not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id) then raise exception 'Customer not found';end if;
  if p_group_id is not null and not exists(select 1 from public.customer_groups_v500 where id=p_group_id and tenant_id=p_tenant_id and active) then raise exception 'Active customer group not found';end if;
  if p_salesperson_user_id is not null and not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_salesperson_user_id and status='active') then raise exception 'Salesperson is not an active business member';end if;
  insert into public.customer_crm_profiles_v500(tenant_id,customer_id,group_id,salesperson_user_id,birthday,anniversary,notes,updated_by,updated_at)
  values(p_tenant_id,p_customer_id,p_group_id,p_salesperson_user_id,p_birthday,p_anniversary,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),now())
  on conflict(tenant_id,customer_id) do update set group_id=excluded.group_id,salesperson_user_id=excluded.salesperson_user_id,birthday=excluded.birthday,anniversary=excluded.anniversary,notes=excluded.notes,updated_by=auth.uid(),updated_at=now();
end $$;
grant execute on function public.customer_crm_save_v500(uuid,uuid,uuid,uuid,date,date,text) to authenticated;

create or replace function private.pricing_resolve_v482_internal(p_tenant_id uuid,p_variant_id uuid,p_customer_id uuid,p_unit_id uuid,p_quantity numeric,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_price numeric;v_source text;v_list uuid;v_list_name text;v_factor numeric:=1;v_qty numeric:=greatest(coalesce(p_quantity,1),0.000001);v_unit_id uuid:=p_unit_id;v_group_id uuid;v_group_name text;v_group_discount numeric:=0;begin
  if v_unit_id is null then select pu.unit_id into v_unit_id from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.active and pu.is_default_sale limit 1;end if;
  if v_unit_id is null then select pu.unit_id into v_unit_id from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.active and pu.is_base limit 1;end if;
  select pu.conversion_to_base into v_factor from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=v_unit_id and pu.active and pu.allow_sale;
  if v_factor is null then raise exception 'Sale unit is not enabled for this product';end if;
  if p_customer_id is not null then
    select cp.unit_price into v_price from public.customer_prices_v482 cp where cp.tenant_id=p_tenant_id and cp.customer_id=p_customer_id and cp.variant_id=p_variant_id and cp.unit_id=v_unit_id and cp.active and cp.min_quantity<=v_qty order by cp.min_quantity desc limit 1;
    if v_price is not null then v_source:='customer';end if;
  end if;
  if v_price is null then
    if p_customer_id is not null then select cpp.price_list_id into v_list from public.customer_pricing_profiles_v482 cpp where cpp.tenant_id=p_tenant_id and cpp.customer_id=p_customer_id and cpp.active;end if;
    if v_list is null then select pl.id into v_list from public.price_lists_v482 pl where pl.tenant_id=p_tenant_id and pl.active and pl.is_default limit 1;end if;
    if v_list is not null then
      select pli.unit_price,pl.name into v_price,v_list_name from public.price_list_items_v482 pli join public.price_lists_v482 pl on pl.id=pli.price_list_id
      where pli.tenant_id=p_tenant_id and pli.price_list_id=v_list and pli.variant_id=p_variant_id and pli.unit_id=v_unit_id and pli.active and pl.active and pli.min_quantity<=v_qty order by pli.min_quantity desc limit 1;
      if v_price is not null then v_source:='price_list';end if;
    end if;
  end if;
  if v_price is null then
    select coalesce(pu.sale_price,coalesce(lps.selling_price,pv.selling_price)*pu.conversion_to_base),case when pu.sale_price is not null then 'unit_price' when lps.selling_price is not null then 'location_price' else 'product_price' end
    into v_price,v_source from public.product_units_v481 pu join public.product_variants pv on pv.id=pu.variant_id
    left join public.location_product_settings lps on lps.tenant_id=p_tenant_id and lps.variant_id=p_variant_id and lps.location_id=p_location_id and lps.active
    where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.unit_id=v_unit_id and pu.active limit 1;
    if p_customer_id is not null then
      select g.id,g.name,least(greatest(coalesce(g.discount_percent,0),0),100) into v_group_id,v_group_name,v_group_discount
      from public.customer_crm_profiles_v500 c join public.customer_groups_v500 g on g.id=c.group_id and g.tenant_id=c.tenant_id
      where c.tenant_id=p_tenant_id and c.customer_id=p_customer_id and g.active limit 1;
      if coalesce(v_group_discount,0)>0 then v_price:=round(coalesce(v_price,0)*(100-v_group_discount)/100,4);v_source:='customer_group';end if;
    end if;
  end if;
  return jsonb_build_object('variant_id',p_variant_id,'customer_id',p_customer_id,'unit_id',v_unit_id,'quantity',v_qty,'unit_price',coalesce(v_price,0),'source',coalesce(v_source,'product_price'),'price_list_id',v_list,'price_list_name',v_list_name,'customer_group_id',v_group_id,'customer_group_name',v_group_name,'customer_group_discount_percent',coalesce(v_group_discount,0));
end $$;
revoke all on function private.pricing_resolve_v482_internal(uuid,uuid,uuid,uuid,numeric,uuid) from public;

-- ---------------------------------------------------------------------------
-- Purchasing quotation referential validation
-- ---------------------------------------------------------------------------
create or replace function public.purchase_quotation_save_v500(p_tenant_id uuid,p_quotation_id uuid,p_request_id uuid,p_location_id uuid,p_supplier_id uuid,p_supplier_quote_reference text,p_quote_date date,p_valid_until date,p_expected_delivery_date date,p_payment_terms text,p_items jsonb,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=coalesce(p_quotation_id,gen_random_uuid());v_no text;x jsonb;v_qty numeric;v_cost numeric;v_tax numeric;v_line numeric;v_sub numeric:=0;v_tax_total numeric:=0;v_request_item uuid;v_variant uuid;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active') then raise exception 'Active supplier not found';end if;
  if p_request_id is not null and not exists(select 1 from public.purchase_requests_v484 where id=p_request_id and tenant_id=p_tenant_id and location_id=p_location_id) then raise exception 'Purchase request not found for this business/location';end if;
  if jsonb_typeof(coalesce(p_items,'null'::jsonb))<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Quotation must contain items';end if;
  if p_valid_until is not null and p_valid_until<coalesce(p_quote_date,current_date) then raise exception 'Valid-until date cannot precede quote date';end if;
  if p_quotation_id is null then
    v_no:='PQT-'||to_char(coalesce(p_quote_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.purchase_quotation_number_seq_v500')::text,6,'0');
    insert into public.purchase_quotations_v500(id,tenant_id,request_id,location_id,supplier_id,quotation_number,supplier_quote_reference,quote_date,valid_until,expected_delivery_date,payment_terms,notes,created_by)
    values(v_id,p_tenant_id,p_request_id,p_location_id,p_supplier_id,v_no,nullif(trim(coalesce(p_supplier_quote_reference,'')),''),coalesce(p_quote_date,current_date),p_valid_until,p_expected_delivery_date,nullif(trim(coalesce(p_payment_terms,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  else
    select quotation_number into v_no from public.purchase_quotations_v500 where id=v_id and tenant_id=p_tenant_id and status in('draft','received') for update;
    if v_no is null then raise exception 'Editable quotation not found';end if;
    delete from public.purchase_quotation_items_v500 where quotation_id=v_id;
    update public.purchase_quotations_v500 set request_id=p_request_id,location_id=p_location_id,supplier_id=p_supplier_id,supplier_quote_reference=nullif(trim(coalesce(p_supplier_quote_reference,'')),''),quote_date=coalesce(p_quote_date,current_date),valid_until=p_valid_until,expected_delivery_date=p_expected_delivery_date,payment_terms=nullif(trim(coalesce(p_payment_terms,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=v_id;
  end if;
  for x in select value from jsonb_array_elements(p_items) loop
    begin v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=coalesce(nullif(x->>'unit_cost','')::numeric,0);v_tax:=coalesce(nullif(x->>'tax_rate','')::numeric,0);v_variant:=(x->>'variant_id')::uuid;v_request_item:=nullif(x->>'request_item_id','')::uuid;exception when others then raise exception 'Invalid quotation item';end;
    if v_qty<=0 or v_cost<0 or v_tax<0 or v_tax>100 then raise exception 'Invalid quotation quantity/cost/tax';end if;
    if not exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id where pv.id=v_variant and pv.tenant_id=p_tenant_id and pv.status='active' and p.status='active') then raise exception 'Quotation product is invalid/inactive';end if;
    if v_request_item is not null then
      if p_request_id is null or not exists(select 1 from public.purchase_request_items_v484 ri where ri.id=v_request_item and ri.request_id=p_request_id and ri.variant_id=v_variant) then raise exception 'Quotation request item does not belong to the selected purchase request/product';end if;
    end if;
    v_line:=round(v_qty*v_cost,2);v_sub:=v_sub+v_line;v_tax_total:=v_tax_total+round(v_line*v_tax/100,2);
    insert into public.purchase_quotation_items_v500(quotation_id,request_item_id,variant_id,quantity,unit_cost,tax_rate,line_total,note)
    values(v_id,v_request_item,v_variant,v_qty,v_cost,v_tax,round(v_line+v_line*v_tax/100,2),nullif(trim(coalesce(x->>'note','')),''));
  end loop;
  update public.purchase_quotations_v500 set subtotal=round(v_sub,2),tax_total=round(v_tax_total,2),grand_total=round(v_sub+v_tax_total,2),status='received',updated_at=now() where id=v_id;
  return jsonb_build_object('quotation_id',v_id,'quotation_number',v_no,'grand_total',round(v_sub+v_tax_total,2));
end $$;
grant execute on function public.purchase_quotation_save_v500(uuid,uuid,uuid,uuid,uuid,text,date,date,date,text,jsonb,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Approval-gated manual stock adjustment
-- ---------------------------------------------------------------------------
create table if not exists public.stock_adjustment_requests_v500(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id),device_id uuid references public.business_devices(id),variant_id uuid not null references public.product_variants(id),
  quantity_delta numeric not null check(quantity_delta<>0),note text not null,request_key text not null,status text not null default 'pending' check(status in('pending','approved','rejected','posted')),
  approval_request_id uuid references public.approval_requests(id),result jsonb,requested_by uuid references auth.users(id),requested_at timestamptz not null default now(),decided_by uuid references auth.users(id),decided_at timestamptz,
  unique(tenant_id,request_key)
);
alter table public.stock_adjustment_requests_v500 enable row level security;
revoke all on public.stock_adjustment_requests_v500 from anon,authenticated;

create or replace function public.stock_adjustment_request_v500(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_adjustment_requests_v500%rowtype;v_ap uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if coalesce(p_quantity_delta,0)=0 then raise exception 'Adjustment quantity cannot be zero';end if;if trim(coalesce(p_note,''))='' then raise exception 'Adjustment reason is required';end if;if trim(coalesce(p_request_id,''))='' then raise exception 'Request ID is required';end if;
  if private.v483_tracking_mode(p_tenant_id,p_variant_id)<>'none' then raise exception 'Use serial/batch trace operations for tracked products';end if;
  if not exists(select 1 from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id and status='active') then raise exception 'Active product variant not found';end if;
  select * into v from public.stock_adjustment_requests_v500 where tenant_id=p_tenant_id and request_key=p_request_id;
  if found then return jsonb_build_object('adjustment_request_id',v.id,'approval_request_id',v.approval_request_id,'status',v.status,'result',v.result);end if;
  insert into public.stock_adjustment_requests_v500(tenant_id,location_id,device_id,variant_id,quantity_delta,note,request_key,requested_by)
  values(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,trim(p_note),trim(p_request_id),auth.uid()) returning * into v;
  insert into public.approval_requests(tenant_id,module_key,action_key,entity_type,entity_id,amount,reason,requested_by)
  values(p_tenant_id,'inventory','stock_adjustment','stock_adjustment_v500',v.id,abs(p_quantity_delta),trim(p_note),auth.uid()) returning id into v_ap;
  update public.stock_adjustment_requests_v500 set approval_request_id=v_ap where id=v.id;
  return jsonb_build_object('adjustment_request_id',v.id,'approval_request_id',v_ap,'status','pending','message','Stock adjustment submitted for approval');
end $$;
grant execute on function public.stock_adjustment_request_v500(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.stock_adjustments_list_v500(p_tenant_id uuid,p_status text default null,p_location_id uuid default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select s.*,p.name product_name,pv.sku,l.location_code,l.name location_name from public.stock_adjustment_requests_v500 s join public.product_variants pv on pv.id=s.variant_id join public.products p on p.id=pv.product_id left join public.business_locations l on l.id=s.location_id
    where s.tenant_id=p_tenant_id and (p_status is null or s.status=p_status) and (p_location_id is null or s.location_id=p_location_id) and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,s.location_id,'view'))
    order by s.requested_at desc limit greatest(1,least(coalesce(p_limit,500),5000)) loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.stock_adjustments_list_v500(uuid,text,uuid,integer) to authenticated;

create or replace function private.v500_stock_adjustment_post(p_tenant_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare s public.stock_adjustment_requests_v500%rowtype;v jsonb;begin
  select * into s from public.stock_adjustment_requests_v500 where id=p_request_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Stock adjustment request not found';end if;
  if s.status='posted' then return coalesce(s.result,'{}'::jsonb);end if;
  if s.status<>'approved' then raise exception 'Stock adjustment must be approved before posting';end if;
  v:=public.inventory_adjust_stock_v47(p_tenant_id,s.location_id,s.device_id,s.variant_id,s.quantity_delta,s.note,'stock-adjustment-approved:'||s.id::text);
  update public.stock_adjustment_requests_v500 set status='posted',result=v,decided_by=coalesce(decided_by,auth.uid()),decided_at=coalesce(decided_at,now()) where id=s.id;
  return v||jsonb_build_object('adjustment_request_id',s.id,'status','posted');
end $$;
revoke all on function private.v500_stock_adjustment_post(uuid,uuid) from public;

create or replace function public.inventory_adjust_stock_v483(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  return public.stock_adjustment_request_v500(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,p_note,p_request_id);
end $$;
grant execute on function public.inventory_adjust_stock_v483(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.approval_request_decide_v4(p_tenant_id uuid,p_request_id uuid,p_approve boolean,p_note text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare a public.approval_requests%rowtype;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'approvals.approve') then raise exception 'Approval permission required';end if;
  select * into a from public.approval_requests where id=p_request_id and tenant_id=p_tenant_id and status='pending' for update;if not found then raise exception 'Pending approval not found';end if;
  update public.approval_requests set status=case when p_approve then 'approved' else 'rejected' end,decided_by=auth.uid(),decided_at=now(),decision_note=nullif(trim(coalesce(p_note,'')),'') where id=a.id;
  if a.entity_type='stock_adjustment_v500' and a.entity_id is not null then
    update public.stock_adjustment_requests_v500 set status=case when p_approve then 'approved' else 'rejected' end,decided_by=auth.uid(),decided_at=now() where id=a.entity_id and tenant_id=p_tenant_id and status='pending';
    if p_approve then perform private.v500_stock_adjustment_post(p_tenant_id,a.entity_id);end if;
  end if;
end $$;
grant execute on function public.approval_request_decide_v4(uuid,uuid,boolean,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Task visibility hardening
-- ---------------------------------------------------------------------------
create or replace function private.v500_task_visible(p_tenant_id uuid,p_task_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
select exists(
  select 1 from public.business_tasks t where t.id=p_task_id and t.tenant_id=p_tenant_id
    and private.erp_user_has_tenant_access(p_tenant_id)
    and (t.location_id is null or private.erp_user_location_allowed(p_tenant_id,t.location_id,'view') or private.erp_user_is_owner(p_tenant_id))
    and (t.assigned_to is null or t.assigned_to=auth.uid() or private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'tasks.manage'))
) $$;
revoke all on function private.v500_task_visible(uuid,uuid) from public;

create or replace function public.business_task_escalation_set_v500(p_tenant_id uuid,p_task_id uuid,p_escalation_at timestamptz,p_escalation_user_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  if p_escalation_user_id is not null and not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_escalation_user_id and status='active') then raise exception 'Escalation user is not an active business member';end if;
  update public.business_tasks set escalation_at=p_escalation_at,escalation_user_id=p_escalation_user_id,escalated_at=null,updated_at=now() where id=p_task_id and tenant_id=p_tenant_id;if not found then raise exception 'Task not found';end if;
end $$;
grant execute on function public.business_task_escalation_set_v500(uuid,uuid,timestamptz,uuid) to authenticated;

create or replace function public.business_task_comment_add_v500(p_tenant_id uuid,p_task_id uuid,p_comment text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin
  if not private.v500_task_visible(p_tenant_id,p_task_id) then raise exception 'Task not found or access denied';end if;if trim(coalesce(p_comment,''))='' then raise exception 'Comment is required';end if;
  insert into public.business_task_comments_v500(tenant_id,task_id,comment,created_by) values(p_tenant_id,p_task_id,trim(p_comment),auth.uid()) returning id into v;
  insert into public.business_task_history_v500(tenant_id,task_id,event_type,note,changed_by) values(p_tenant_id,p_task_id,'comment',trim(p_comment),auth.uid());return v;
end $$;
grant execute on function public.business_task_comment_add_v500(uuid,uuid,text) to authenticated;

create or replace function public.business_task_timeline_v500(p_tenant_id uuid,p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare h jsonb;c jsonb;t jsonb;begin
  if not private.v500_task_visible(p_tenant_id,p_task_id) then raise exception 'Task not found or access denied';end if;
  select to_jsonb(x) into t from public.business_tasks x where x.id=p_task_id and x.tenant_id=p_tenant_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.changed_at desc),'[]'::jsonb) into h from public.business_task_history_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'comment',x.comment,'created_by',x.created_by,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into c from public.business_task_comments_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  return jsonb_build_object('task',t,'history',h,'comments',c);
end $$;
grant execute on function public.business_task_timeline_v500(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Expanded financial reconciliation
-- ---------------------------------------------------------------------------
create or replace function public.finance_reconciliation_v500(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  ar_op numeric:=0;ap_op numeric:=0;ar_gl numeric:=0;ap_gl numeric:=0;inv_op numeric:=0;inv_gl numeric:=0;cogs_op numeric:=0;cogs_gl numeric:=0;out_tax_op numeric:=0;out_tax_gl numeric:=0;in_tax_op numeric:=0;in_tax_gl numeric:=0;
  ar uuid;ap uuid;inv uuid;cogs uuid;ot uuid;it uuid;unbalanced bigint:=0;zero_lines bigint:=0;duplicate_sources bigint:=0;missing_source bigint:=0;
begin
  perform private.v500_accounting_access(p_tenant_id,false);
  ar:=private.v4_account_id(p_tenant_id,'accounts_receivable');ap:=private.v4_account_id(p_tenant_id,'accounts_payable');inv:=private.v4_account_id(p_tenant_id,'inventory_asset');cogs:=private.v4_account_id(p_tenant_id,'cogs');ot:=private.v4_account_id(p_tenant_id,'output_gst');it:=private.v4_account_id(p_tenant_id,'input_gst');
  select coalesce(sum(greatest(s.grand_total-coalesce(rt.x,0)-coalesce(py.x,0),0)),0) into ar_op from public.sales s left join(select sale_id,sum(grand_total)x from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id left join(select sale_id,sum(amount)x from public.sale_payments group by sale_id)py on py.sale_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled');
  select coalesce(sum(x.balance),0) into ap_op from (
    select greatest(p.grand_total-coalesce(rt.x,0)-coalesce(py.x,0),0) balance from public.purchases p left join(select purchase_id,sum(grand_total)x from public.purchase_returns where credit_status<>'waived' group by purchase_id)rt on rt.purchase_id=p.id left join(select purchase_id,sum(amount)x from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    union all select greatest(i.balance_due,0) from public.purchase_invoices_v484 i where i.tenant_id=p_tenant_id and i.status in('posted','part_paid'))x;
  select coalesce(sum(b.quantity*coalesce(nullif(b.average_cost,0),pv.cost_price,0)),0) into inv_op from public.location_stock_balances b join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id where b.tenant_id=p_tenant_id;
  select coalesce(sum(si.cost_total),0)-coalesce((select sum(ri.quantity*coalesce(si2.unit_cost,0)) from public.sales_return_items ri join public.sales_returns r on r.id=ri.sales_return_id and r.tenant_id=p_tenant_id and r.refund_status<>'waived' join public.sale_items si2 on si2.id=ri.sale_item_id),0) into cogs_op from public.sale_items si join public.sales s on s.id=si.sale_id where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled');
  select coalesce(sum(tax_total),0)-coalesce((select sum(tax_total) from public.sales_returns where tenant_id=p_tenant_id and refund_status<>'waived'),0) into out_tax_op from public.sales where tenant_id=p_tenant_id and coalesce(status,'') not in('void','cancelled');
  select coalesce(sum(x.tax_total),0) into in_tax_op from (select tax_total from public.purchases where tenant_id=p_tenant_id and coalesce(status,'') not in('void','cancelled') union all select tax_total from public.purchase_invoices_v484 where tenant_id=p_tenant_id and status in('posted','part_paid','paid'))x;
  in_tax_op:=in_tax_op+coalesce((select sum(tax_amount) from public.expenses where tenant_id=p_tenant_id and status='posted'),0)-coalesce((select sum(tax_total) from public.purchase_returns where tenant_id=p_tenant_id and credit_status<>'waived'),0);
  select coalesce(sum(l.debit-l.credit),0) into ar_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=ar;
  select coalesce(sum(l.credit-l.debit),0) into ap_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=ap;
  select coalesce(sum(l.debit-l.credit),0) into inv_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=inv;
  select coalesce(sum(l.debit-l.credit),0) into cogs_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=cogs;
  select coalesce(sum(l.credit-l.debit),0) into out_tax_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=ot;
  select coalesce(sum(l.debit-l.credit),0) into in_tax_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=it;
  select count(*) into unbalanced from (select j.id from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id where j.tenant_id=p_tenant_id and j.status='posted' group by j.id having round(sum(l.debit),2)<>round(sum(l.credit),2))q;
  select count(*) into zero_lines from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and round(l.debit,2)=0 and round(l.credit,2)=0;
  select count(*) into duplicate_sources from (select source_type,source_id from public.journal_entries where tenant_id=p_tenant_id and status='posted' and source_type is not null and source_id is not null group by source_type,source_id having count(*)>1)q;
  select count(*) into missing_source from (
    select s.id from public.sales s where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled') and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted')
    union all select p.id from public.purchases p where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled') and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted')
    union all select r.id from public.sales_returns r where r.tenant_id=p_tenant_id and r.refund_status<>'waived' and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted')
    union all select r.id from public.purchase_returns r where r.tenant_id=p_tenant_id and r.credit_status<>'waived' and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted')
  )q;
  return jsonb_build_object('ready',unbalanced=0 and zero_lines=0 and duplicate_sources=0 and missing_source=0 and abs(ar_op-ar_gl)<=0.05 and abs(ap_op-ap_gl)<=0.05 and abs(inv_op-inv_gl)<=0.05 and abs(cogs_op-cogs_gl)<=0.05 and abs(out_tax_op-out_tax_gl)<=0.05 and abs(in_tax_op-in_tax_gl)<=0.05,
    'accounts_receivable',jsonb_build_object('operational',round(ar_op,2),'general_ledger',round(ar_gl,2),'difference',round(ar_op-ar_gl,2),'reconciled',abs(ar_op-ar_gl)<=0.05),
    'accounts_payable',jsonb_build_object('operational',round(ap_op,2),'general_ledger',round(ap_gl,2),'difference',round(ap_op-ap_gl,2),'reconciled',abs(ap_op-ap_gl)<=0.05),
    'inventory',jsonb_build_object('operational_value',round(inv_op,2),'general_ledger',round(inv_gl,2),'difference',round(inv_op-inv_gl,2)),
    'cogs',jsonb_build_object('operational',round(cogs_op,2),'general_ledger',round(cogs_gl,2),'difference',round(cogs_op-cogs_gl,2)),
    'output_gst',jsonb_build_object('operational',round(out_tax_op,2),'general_ledger',round(out_tax_gl,2),'difference',round(out_tax_op-out_tax_gl,2)),
    'input_gst',jsonb_build_object('operational',round(in_tax_op,2),'general_ledger',round(in_tax_gl,2),'difference',round(in_tax_op-in_tax_gl,2)),
    'integrity',jsonb_build_object('unbalanced_posted_journals',unbalanced,'zero_value_posted_lines',zero_lines,'duplicate_source_journals',duplicate_sources,'missing_source_journals',missing_source),'checked_at',now());
end $$;
grant execute on function public.finance_reconciliation_v500(uuid) to authenticated;

create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin return public.finance_reconciliation_v500(p_tenant_id);end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;


create or replace function private.v500_document_location(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns uuid language sql stable security definer set search_path=public,private,pg_temp as $$
  select o.location_id from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id limit 1
$$;
revoke all on function private.v500_document_location(uuid,text,uuid) from public;

-- ---------------------------------------------------------------------------
-- Corrected BI: return-aware COGS, cash/bank, store/POS, hour/day/month trends
-- ---------------------------------------------------------------------------
create or replace function public.dashboard_business_intelligence_v500(p_tenant_id uuid,p_location_id uuid default null,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  sales_taxable numeric:=0;returns_taxable numeric:=0;sales_cost numeric:=0;return_cost numeric:=0;expenses numeric:=0;receivable numeric:=0;payable numeric:=0;cash_bank numeric:=0;
  low_stock bigint:=0;dead_stock bigint:=0;best jsonb:='[]';slow jsonb:='[]';stores jsonb:='[]';pos jsonb:='[]';hourly jsonb:='[]';daily jsonb:='[]';monthly jsonb:='[]';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(sum(taxable_total),0),coalesce(sum(cost_total),0) into sales_taxable,sales_cost from public.sales where tenant_id=p_tenant_id and sale_date=p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',id)=p_location_id);
  select coalesce(sum(subtotal),0) into returns_taxable from public.sales_returns where tenant_id=p_tenant_id and return_date=p_day and refund_status<>'waived' and (p_location_id is null or location_id=p_location_id);
  select coalesce(sum(ri.quantity*coalesce(si.unit_cost,0)),0) into return_cost from public.sales_return_items ri join public.sales_returns r on r.id=ri.sales_return_id join public.sale_items si on si.id=ri.sale_item_id where r.tenant_id=p_tenant_id and r.return_date=p_day and r.refund_status<>'waived' and (p_location_id is null or r.location_id=p_location_id);
  select coalesce(sum(total_amount),0) into expenses from public.expenses e left join public.document_origins o on o.tenant_id=e.tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.tenant_id=p_tenant_id and e.expense_date=p_day and e.status='posted' and (p_location_id is null or o.location_id=p_location_id);
  select coalesce(sum(total_outstanding),0) into receivable from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into payable from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(case when a.account_type='asset' then l.debit-l.credit else 0 end),0) into cash_bank
  from public.accounting_accounts a join public.journal_lines l on l.account_id=a.id join public.journal_entries j on j.id=l.journal_entry_id and j.status='posted' and j.tenant_id=p_tenant_id
  where a.tenant_id=p_tenant_id and a.system_key in('cash','bank','upi','card') and (p_location_id is null or j.location_id is null or j.location_id=p_location_id);
  select count(*) filter(where status in('low_stock','out_of_stock')),count(*) filter(where status='dead_stock') into low_stock,dead_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,30,'',5000);
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into best from (select pr.name product_name,sum(si.quantity) quantity,round(sum(si.taxable_amount),2) sales_value from public.sale_items si join public.sales s on s.id=si.sale_id join public.product_variants pv on pv.id=si.variant_id join public.products pr on pr.id=pv.product_id where s.tenant_id=p_tenant_id and s.sale_date between p_day-29 and p_day and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',s.id)=p_location_id) group by pr.id,pr.name order by quantity desc limit 10)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into slow from (select product_name,sku,available,last_sale_date,case when last_sale_date is null then null else (p_day-last_sale_date) end days_since_last_sale,status from public.inventory_intelligence_v480(p_tenant_id,p_location_id,30,'',5000) where status in('slow_moving','dead_stock') order by last_sale_date nulls first limit 10)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into stores from (select l.id location_id,l.name,round(coalesce(sum(s.taxable_total),0),2) net_sales from public.business_locations l left join public.document_origins so on so.tenant_id=p_tenant_id and so.entity_type='sale' and so.location_id=l.id left join public.sales s on s.id=so.entity_id and s.tenant_id=p_tenant_id and s.sale_date=p_day and coalesce(s.status,'') not in('void','cancelled') where l.tenant_id=p_tenant_id group by l.id,l.name order by net_sales desc)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into pos from (select d.id device_id,coalesce(d.device_code,d.name) device,round(coalesce(sum(s.taxable_total),0),2) net_sales,count(s.id) invoices from public.business_devices d left join public.document_origins o on o.tenant_id=p_tenant_id and o.device_id=d.id and o.entity_type='sale' left join public.sales s on s.id=o.entity_id and s.sale_date=p_day and coalesce(s.status,'') not in('void','cancelled') where d.tenant_id=p_tenant_id and d.app_type='pos' and (p_location_id is null or d.location_id=p_location_id) group by d.id,d.device_code,d.name order by net_sales desc)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into hourly from (select date_part('hour',created_at)::int hour_of_day,round(sum(taxable_total),2) sales from public.sales where tenant_id=p_tenant_id and sale_date=p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',id)=p_location_id) group by 1 order by 1)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into daily from (select sale_date day_key,round(sum(taxable_total),2) sales from public.sales where tenant_id=p_tenant_id and sale_date between p_day-29 and p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',id)=p_location_id) group by sale_date order by sale_date)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into monthly from (select date_trunc('month',sale_date)::date month_start,round(sum(taxable_total),2) sales from public.sales where tenant_id=p_tenant_id and sale_date>=date_trunc('month',p_day)::date-interval '11 months' and sale_date<=p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',id)=p_location_id) group by 1 order by 1)q;
  return jsonb_build_object('day',p_day,'net_sales',round(sales_taxable-returns_taxable,2),'gross_profit',round((sales_taxable-returns_taxable)-(sales_cost-return_cost),2),'gross_margin_pct',case when sales_taxable-returns_taxable>0 then round(((sales_taxable-returns_taxable)-(sales_cost-return_cost))*100/(sales_taxable-returns_taxable),2) else 0 end,'expenses',round(expenses,2),'estimated_profit',round((sales_taxable-returns_taxable)-(sales_cost-return_cost)-expenses,2),'cash_bank',round(cash_bank,2),'receivables',round(receivable,2),'payables',round(payable,2),'low_stock_count',low_stock,'dead_stock_count',dead_stock,'best_sellers',best,'slow_dead_stock',slow,'store_comparison',stores,'pos_comparison',pos,'hourly_sales',hourly,'daily_sales',daily,'monthly_sales',monthly);
end $$;
grant execute on function public.dashboard_business_intelligence_v500(uuid,uuid,date) to authenticated;

-- ---------------------------------------------------------------------------
-- Reports Center: implement the whole advertised catalogue.
-- ---------------------------------------------------------------------------
create or replace function public.reports_center_data_v500(p_tenant_id uuid,p_report_key text,p_from date,p_to date,p_location_id uuid default null,p_query text default '',p_limit integer default 1000)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;k text:=lower(trim(coalesce(p_report_key,'')));q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if p_from is null or p_to is null or p_to<p_from then raise exception 'Valid report date range is required';end if;
  if k='sales_summary' then return next public.reports_get_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='sales_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'sales',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_product' then for r in select si.variant_id,si.product_name,si.sku,sum(si.quantity) quantity,round(sum(si.taxable_amount),2) taxable_sales,round(sum(si.tax_amount),2) tax,round(sum(si.line_total),2) total,round(sum(si.gross_profit),2) gross_profit from public.sale_items si join public.sales s on s.id=si.sale_id where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',s.id)=p_location_id) and (trim(coalesce(p_query,''))='' or lower(si.product_name) like q or lower(coalesce(si.sku,'')) like q) group by si.variant_id,si.product_name,si.sku order by total desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_customer' then for r in select s.customer_id,s.customer_name,count(*) invoices,round(sum(s.taxable_total),2) taxable_sales,round(sum(s.tax_total),2) tax,round(sum(s.grand_total),2) total,round(sum(s.gross_profit),2) gross_profit from public.sales s where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',s.id)=p_location_id) and (trim(coalesce(p_query,''))='' or lower(s.customer_name) like q) group by s.customer_id,s.customer_name order by total desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_salesperson' then for r in select cp.salesperson_user_id,coalesce(u.username::text,'Unassigned') salesperson,count(*) invoices,round(sum(s.taxable_total),2) taxable_sales,round(sum(s.grand_total),2) total from public.sales s left join public.customer_crm_profiles_v500 cp on cp.tenant_id=s.tenant_id and cp.customer_id=s.customer_id left join public.user_login_names u on u.user_id=cp.salesperson_user_id where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',s.id)=p_location_id) group by cp.salesperson_user_id,u.username order by total desc loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_store' then for r in select l.id location_id,l.location_code,l.name,count(s.id) invoices,round(coalesce(sum(s.taxable_total),0),2) taxable_sales,round(coalesce(sum(s.grand_total),0),2) total from public.business_locations l left join public.document_origins so on so.tenant_id=p_tenant_id and so.entity_type='sale' and so.location_id=l.id left join public.sales s on s.id=so.entity_id and s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') where l.tenant_id=p_tenant_id and (p_location_id is null or l.id=p_location_id) group by l.id,l.location_code,l.name order by total desc loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_pos' then for r in select d.id device_id,coalesce(d.device_code,d.name) terminal,count(s.id) invoices,round(coalesce(sum(s.grand_total),0),2) total from public.business_devices d left join public.document_origins o on o.tenant_id=p_tenant_id and o.device_id=d.id and o.entity_type='sale' left join public.sales s on s.id=o.entity_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') where d.tenant_id=p_tenant_id and d.app_type='pos' and (p_location_id is null or d.location_id=p_location_id) group by d.id,d.device_code,d.name order by total desc loop return next to_jsonb(r);end loop;return;
  elsif k='sales_by_payment_method' then for r in select lower(coalesce(payment_method,'unknown')) payment_method,count(*) payment_count,round(sum(amount),2) amount from public.sale_payments py join public.sales s on s.id=py.sale_id where py.tenant_id=p_tenant_id and py.paid_at::date between p_from and p_to and (p_location_id is null or private.v500_document_location(p_tenant_id,'sale',s.id)=p_location_id) group by 1 order by amount desc loop return next to_jsonb(r);end loop;return;
  elsif k='purchase_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'purchases',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k='supplier_purchase' then for r in select p.supplier_id,s.name supplier_name,count(*) bills,round(sum(p.grand_total),2) total from public.purchases p join public.suppliers s on s.id=p.supplier_id where p.tenant_id=p_tenant_id and p.purchase_date between p_from and p_to and coalesce(p.status,'') not in('void','cancelled') and (p_location_id is null or private.v500_document_location(p_tenant_id,'purchase',p.id)=p_location_id) and (trim(coalesce(p_query,''))='' or lower(s.name) like q) group by p.supplier_id,s.name order by total desc loop return next to_jsonb(r);end loop;return;
  elsif k='price_history' then for r in select * from public.purchase_price_history_v484(p_tenant_id,null,null,p_location_id,p_query,p_limit) x where x.purchase_date between p_from and p_to loop return next to_jsonb(r);end loop;return;
  elsif k='supplier_performance' then for r in select * from public.supplier_performance_v500(p_tenant_id,p_from,p_to,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('returns','purchase_returns') then for r in select x row_json from public.returns_report_v500(p_tenant_id,case when k='purchase_returns' then 'purchase' else 'all' end,p_from,p_to,p_location_id,p_query,p_limit) x loop return next r.row_json;end loop;return;
  elsif k in('current_stock','stock_valuation','stock_aging','dead_stock','low_stock') then for r in select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,greatest(1,least((p_to-p_from)+1,365)),p_query,p_limit) x where (k not in('dead_stock','low_stock') or (k='dead_stock' and x.status='dead_stock') or (k='low_stock' and x.status in('low_stock','out_of_stock'))) loop return next to_jsonb(r);end loop;return;
  elsif k='stock_movement' then for r in select m.created_at,m.location_id,l.location_code,p.name product_name,pv.sku,m.movement_type,m.quantity_delta,m.unit_cost,m.reference_type,m.reference_number,m.note from public.location_stock_movements m join public.product_variants pv on pv.id=m.variant_id join public.products p on p.id=pv.product_id left join public.business_locations l on l.id=m.location_id where m.tenant_id=p_tenant_id and m.created_at::date between p_from and p_to and (p_location_id is null or m.location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(coalesce(pv.sku,'')) like q or lower(coalesce(m.reference_number,'')) like q) order by m.created_at desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k='expiry' then for r in select b.id batch_id,p.name product_name,pv.sku,b.batch_number,b.expiry_on,bb.location_id,l.location_code,bb.quantity from public.inventory_batches_v483 b join public.product_variants pv on pv.id=b.variant_id join public.products p on p.id=pv.product_id join public.inventory_batch_balances_v483 bb on bb.batch_id=b.id left join public.business_locations l on l.id=bb.location_id where b.tenant_id=p_tenant_id and b.expiry_on between p_from and p_to and bb.quantity>0 and (p_location_id is null or bb.location_id=p_location_id) order by b.expiry_on limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k='serials' then for r in select s.serial_number,s.status,s.current_location_id location_id,l.location_code,p.name product_name,pv.sku,s.updated_at from public.inventory_serials_v483 s join public.product_variants pv on pv.id=s.variant_id join public.products p on p.id=pv.product_id left join public.business_locations l on l.id=s.current_location_id where s.tenant_id=p_tenant_id and (p_location_id is null or s.current_location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(s.serial_number) like q or lower(p.name) like q or lower(coalesce(pv.sku,'')) like q) order by s.updated_at desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k='batches' then for r in select b.batch_number,b.manufactured_on,b.expiry_on,p.name product_name,pv.sku,bb.location_id,l.location_code,bb.quantity from public.inventory_batches_v483 b join public.product_variants pv on pv.id=b.variant_id join public.products p on p.id=pv.product_id join public.inventory_batch_balances_v483 bb on bb.batch_id=b.id left join public.business_locations l on l.id=bb.location_id where b.tenant_id=p_tenant_id and (p_location_id is null or bb.location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(b.batch_number) like q or lower(p.name) like q) order by b.created_at desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  elsif k in('general_ledger','journal_register') then for r in select * from public.journal_center_list_v500(p_tenant_id,p_from,p_to,p_query,null,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k='balance_sheet' then return next public.accounting_balance_sheet_v500(p_tenant_id,p_to,p_location_id);return;elsif k in('trial_balance','profit_loss','cash_flow') then return next public.accounting_statement_v41(p_tenant_id,k,p_from,p_to,p_location_id);return;
  elsif k='receivables' then for r in select * from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('payables','supplier_outstanding') then for r in select * from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k='reconciliation' then return next public.finance_reconciliation_v500(p_tenant_id);return;
  elsif k='tax' then return next public.gst_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='expenses' then for r in select e.expense_date,e.expense_number,c.name category,e.payee,e.description,e.amount,e.tax_amount,e.total_amount,e.payment_method,e.reference_number,e.status from public.expenses e join public.expense_categories c on c.id=e.category_id left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.tenant_id=p_tenant_id and e.expense_date between p_from and p_to and e.status='posted' and (p_location_id is null or o.location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(e.expense_number) like q or lower(e.description) like q or lower(coalesce(e.payee,'')) like q) order by e.expense_date desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  else raise exception 'Unsupported report key: %',p_report_key;end if;
end $$;
grant execute on function public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer) to authenticated;

-- ---------------------------------------------------------------------------
-- v5 task list + closing / CRM reminders
-- ---------------------------------------------------------------------------
create or replace function public.business_tasks_list_v500(p_tenant_id uuid,p_location_id uuid default null,p_status text default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select t.id,t.title,t.description,t.priority,t.status,t.assigned_to,coalesce(u.username::text,'') assigned_username,t.due_at,t.reminder_at,t.location_id,coalesce(l.location_code,'') location_code,t.entity_type,t.entity_id,t.source_notification_id,coalesce(t.metadata,'{}'::jsonb) metadata,t.escalation_at,t.escalated_at,t.escalation_user_id,coalesce(eu.username::text,'') escalation_username,t.created_at,t.updated_at
    from public.business_tasks t left join public.user_login_names u on u.user_id=t.assigned_to left join public.user_login_names eu on eu.user_id=t.escalation_user_id left join public.business_locations l on l.id=t.location_id
    where t.tenant_id=p_tenant_id and (p_location_id is null or t.location_id=p_location_id) and (p_status is null or p_status='' or t.status=p_status) and private.v500_task_visible(p_tenant_id,t.id)
    order by case when t.status in('done','cancelled') then 1 else 0 end,case when t.due_at is not null and t.due_at<now() and t.status not in('done','cancelled') then 0 else 1 end,case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,coalesce(t.due_at,'infinity'::timestamptz),t.created_at desc
  loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.business_tasks_list_v500(uuid,uuid,text) to authenticated;

create or replace function private.v500_build25_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  if private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'accounting.manage') then
    for r in select id,name,end_date from public.financial_years_v500 where tenant_id=p_tenant_id and status='open' and end_date<=current_date+7 order by end_date loop
      if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='closing' and n.entity_type='financial_year' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '24 hours') then
        insert into public.notifications(tenant_id,user_id,category,severity,title,message,entity_type,entity_id)
        values(p_tenant_id,p_user_id,'closing',case when r.end_date<current_date then 'critical' else 'warning' end,'Financial year closing • '||r.name,case when r.end_date<current_date then 'Year ended '||r.end_date::text||' and is still open' else 'Year ends '||r.end_date::text end,'financial_year',r.id);
      end if;
    end loop;
  end if;
  for r in select c.id,c.name,cp.birthday,cp.anniversary from public.customer_crm_profiles_v500 cp join public.customers c on c.id=cp.customer_id and c.tenant_id=cp.tenant_id
    where cp.tenant_id=p_tenant_id and c.status='active' and ((cp.birthday is not null and extract(month from cp.birthday)=extract(month from current_date) and extract(day from cp.birthday)=extract(day from current_date)) or (cp.anniversary is not null and extract(month from cp.anniversary)=extract(month from current_date) and extract(day from cp.anniversary)=extract(day from current_date))) loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='crm' and n.entity_type='customer' and n.entity_id=r.id and n.created_at::date=current_date) then
      insert into public.notifications(tenant_id,user_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,'crm','info',case when r.birthday is not null and extract(month from r.birthday)=extract(month from current_date) and extract(day from r.birthday)=extract(day from current_date) then 'Customer birthday • ' else 'Customer anniversary • ' end||r.name,'CRM reminder for today','customer',r.id);
    end if;
  end loop;
end $$;
revoke all on function private.v500_build25_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());perform private.v495_refresh_notifications(p_tenant_id,auth.uid());perform private.v500_refresh_notifications(p_tenant_id,auth.uid());perform private.v500_build25_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) order by case severity when 'critical' then 0 when 'warning' then 1 when 'success' then 2 else 3 end,(read_at is null) desc,created_at desc limit greatest(1,least(coalesce(p_limit,50),300));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Dynamic completion contract / stronger verifier
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- Legacy accounting repair and purchase-cost basis reconciliation.
-- Purchase Inventory follows gross item cost (the ERP moving-average cost basis);
-- discounts and generic additional charges remain explicit P&L lines.
-- ---------------------------------------------------------------------------
create or replace function private.v500_purchase_discount_account(p_tenant_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;v_code text:='4040';begin
  select id into v from public.accounting_accounts where tenant_id=p_tenant_id and system_key='purchase_discount' and active limit 1;
  if v is not null then return v;end if;
  if exists(select 1 from public.accounting_accounts where tenant_id=p_tenant_id and code=v_code) then v_code:='4040-PD';end if;
  insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description,active)
  values(p_tenant_id,v_code,'Purchase Discounts','income','purchase_discount',true,'Supplier discounts kept separate from the ERP gross-item inventory cost basis',true)
  returning id into v;
  return v;
end $$;
revoke all on function private.v500_purchase_discount_account(uuid) from public;

create or replace function private.v4_accounting_post_document(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_loc uuid;v_origin_created timestamptz;v_total numeric;v_tax numeric;v_net numeric;v_cost numeric:=0;v_paid numeric:=0;v_round numeric:=0;
  v_subtotal numeric:=0;v_discount numeric:=0;v_charges numeric:=0;
  v_method text:='cash';v_date date;v_ref text;v_party uuid;v_lines jsonb:='[]'::jsonb;v_pay_account uuid;
begin
  select location_id,created_at into v_loc,v_origin_created from public.document_origins
  where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id order by created_at limit 1;
  if p_entity_type='sale' then
    select grand_total,tax_total,round_off,greatest(grand_total-tax_total-round_off,0),cost_total,sale_date,sale_number,customer_id
    into v_total,v_tax,v_round,v_net,v_cost,v_date,v_ref,v_party from public.sales where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method
    from public.sale_payments where sale_id=p_entity_id and (v_origin_created is null or created_at<=v_origin_created);
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Sale receipt'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',v_total-v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Customer receivable'));end if;
    if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'sales_revenue'),'debit',0,'credit',v_net,'party_type','customer','party_id',v_party,'description','Sales revenue'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'output_gst'),'debit',0,'credit',v_tax,'description','Output GST'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',v_round,'description','Sale round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',abs(v_round),'credit',0,'description','Sale round off'));end if;
    if coalesce(v_cost,0)>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'cogs'),'debit',v_cost,'credit',0,'description','Cost of goods sold'),jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',0,'credit',v_cost,'description','Inventory issued'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Sale '||v_ref,'sale',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='purchase' then
    select grand_total,tax_total,round_off,subtotal,discount_total,additional_charges,purchase_date,purchase_number,supplier_id
    into v_total,v_tax,v_round,v_subtotal,v_discount,v_charges,v_date,v_ref,v_party from public.purchases where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method
    from public.purchase_payments where purchase_id=p_entity_id and (v_origin_created is null or created_at<=v_origin_created);
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_subtotal>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_subtotal,'credit',0,'party_type','supplier','party_id',v_party,'description','Purchased inventory at ERP item cost'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    if v_charges>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'purchase_expense'),'debit',v_charges,'credit',0,'description','Purchase additional charges'));end if;
    if v_discount>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v500_purchase_discount_account(p_tenant_id),'debit',0,'credit',v_discount,'description','Supplier purchase discount'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',v_round,'credit',0,'description','Purchase round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(v_round),'description','Purchase round off'));end if;
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payment'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',v_total-v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payable'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Purchase '||v_ref,'purchase',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='expense' then
    select total_amount,tax_amount,round_off,greatest(total_amount-tax_amount-round_off,0),expense_date,expense_number
    into v_total,v_tax,v_round,v_net,v_date,v_ref from public.expenses where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select payment_method into v_method from public.expenses where id=p_entity_id;v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_net>0 then v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'operating_expense'),'debit',v_net,'credit',0,'description','Operating expense'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',v_round,'credit',0,'description','Expense round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(v_round),'description','Expense round off'));end if;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_total,'description','Expense payment'));
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Expense '||v_ref,'expense',p_entity_id,v_ref,v_lines);
  end if;
  return null;
end $$;
revoke all on function private.v4_accounting_post_document(uuid,text,uuid) from public;

create or replace function public.finance_repair_inventory_residual_v500(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_inv uuid;v_equity uuid;v_operational numeric:=0;v_gl numeric:=0;v_diff numeric:=0;v_lines jsonb;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  v_inv:=private.v4_account_id(p_tenant_id,'inventory_asset');v_equity:=private.v4_account_id(p_tenant_id,'owner_equity');
  select round(coalesce(sum(b.quantity*coalesce(nullif(b.average_cost,0),pv.cost_price,0)),0),2) into v_operational
  from public.location_stock_balances b join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id where b.tenant_id=p_tenant_id;
  select round(coalesce(sum(l.debit-l.credit),0),2) into v_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id
  where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=v_inv;
  v_diff:=round(v_operational-v_gl,2);
  if abs(v_diff)>0.005 and not exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and status='posted' and source_type='inventory_legacy_balance_v500' and source_id=p_tenant_id) then
    if v_diff>0 then v_lines:=jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',v_diff,'credit',0,'description','Legacy inventory balance bootstrap'),jsonb_build_object('account_id',v_equity,'debit',0,'credit',v_diff,'description','Legacy inventory opening equity'));
    else v_lines:=jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',0,'credit',abs(v_diff),'description','Legacy inventory balance bootstrap'),jsonb_build_object('account_id',v_equity,'debit',abs(v_diff),'credit',0,'description','Legacy inventory opening equity'));end if;
    perform private.v4_journal_create(p_tenant_id,null,current_date,'Legacy inventory balance reconciliation','inventory_legacy_balance_v500',p_tenant_id,'LEGACY-INVENTORY',v_lines);
  end if;
  return jsonb_build_object('operational_inventory',v_operational,'general_ledger_before',v_gl,'posted_difference',v_diff);
end $$;
grant execute on function public.finance_repair_inventory_residual_v500(uuid) to authenticated;

create or replace function public.finance_repair_legacy_accounting_v500(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;v_inv uuid;v_equity uuid;v_discount_account uuid;v_purchase_expense uuid;v_existing_inventory numeric;v_delta numeric;v_lines jsonb;v_open_value numeric;v_open_date date;v_journal uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  -- Recreate source journals that legacy data never received.
  for r in select id from public.sales s where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled') and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted') loop perform private.v4_accounting_post_document(p_tenant_id,'sale',r.id);end loop;
  for r in select id from public.purchases p where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled') and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted') loop perform private.v4_accounting_post_document(p_tenant_id,'purchase',r.id);end loop;

  v_inv:=private.v4_account_id(p_tenant_id,'inventory_asset');v_equity:=private.v4_account_id(p_tenant_id,'owner_equity');
  v_purchase_expense:=private.v4_account_id(p_tenant_id,'purchase_expense');v_discount_account:=private.v500_purchase_discount_account(p_tenant_id);
  -- Non-destructive reclassifications for legacy purchase journals that embedded discounts/charges in Inventory.
  for r in select p.id,p.purchase_number,p.subtotal,p.discount_total,p.additional_charges,
      coalesce((select sum(l.debit-l.credit) from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id where j.tenant_id=p_tenant_id and j.status='posted' and j.source_type='purchase' and j.source_id=p.id and l.account_id=v_inv),0) source_inventory
    from public.purchases p where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
  loop
    v_delta:=round(coalesce(r.subtotal,0)-coalesce(r.source_inventory,0),2);
    if (abs(v_delta)>0.005 or coalesce(r.discount_total,0)>0.005 or coalesce(r.additional_charges,0)>0.005)
       and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and j.source_type='purchase_cost_reclass_v500' and j.source_id=r.id) then
      v_lines:='[]'::jsonb;
      if v_delta>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',v_delta,'credit',0,'description','Purchase inventory cost-basis correction'));
      elsif v_delta<0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',0,'credit',abs(v_delta),'description','Purchase inventory cost-basis correction'));end if;
      if coalesce(r.additional_charges,0)>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_purchase_expense,'debit',round(r.additional_charges,2),'credit',0,'description','Purchase additional charges reclass'));
      end if;
      if coalesce(r.discount_total,0)>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_discount_account,'debit',0,'credit',round(r.discount_total,2),'description','Purchase discount reclass'));end if;
      if jsonb_array_length(v_lines)>=2 then perform private.v4_journal_create(p_tenant_id,null,current_date,'Purchase cost reclassification • '||r.purchase_number,'purchase_cost_reclass_v500',r.id,r.purchase_number,v_lines);end if;
    end if;
  end loop;

  -- Legacy product opening stock was operational only. Mirror it once to Inventory/Owner Equity.
  select round(coalesce(sum(quantity_delta*coalesce(unit_cost,0)),0),2),min(created_at)::date into v_open_value,v_open_date
  from public.location_stock_movements where tenant_id=p_tenant_id and movement_type='opening' and reference_type='product';
  if abs(coalesce(v_open_value,0))>0.005 and not exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and status='posted' and source_type='inventory_opening_v500' and source_id=p_tenant_id) then
    if v_open_value>0 then v_lines:=jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',v_open_value,'credit',0,'description','Legacy opening inventory'),jsonb_build_object('account_id',v_equity,'debit',0,'credit',v_open_value,'description','Opening inventory equity'));
    else v_lines:=jsonb_build_array(jsonb_build_object('account_id',v_inv,'debit',0,'credit',abs(v_open_value),'description','Legacy opening inventory'),jsonb_build_object('account_id',v_equity,'debit',abs(v_open_value),'credit',0,'description','Opening inventory equity'));end if;
    v_journal:=private.v4_journal_create(p_tenant_id,null,coalesce(v_open_date,current_date),'Legacy opening inventory reconciliation','inventory_opening_v500',p_tenant_id,'OPENING-STOCK',v_lines);
  end if;
  perform public.finance_repair_inventory_residual_v500(p_tenant_id);
  return public.finance_reconciliation_v500(p_tenant_id);
end $$;
grant execute on function public.finance_repair_legacy_accounting_v500(uuid) to authenticated;

-- Fix legacy Balance Sheet CTE scope bug found by authenticated report runtime testing.
create or replace function public.accounting_statement_v41(
  p_tenant_id uuid,
  p_statement text,
  p_from date,
  p_to date,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_key text:=lower(trim(coalesce(p_statement,'')));
  v_rows jsonb:='[]'::jsonb;
  v_summary jsonb:='{}'::jsonb;
  v_revenue numeric:=0; v_cogs numeric:=0; v_expenses numeric:=0; v_net numeric:=0;
  v_assets numeric:=0; v_liabilities numeric:=0; v_equity numeric:=0; v_current_earnings numeric:=0;
  v_dr numeric:=0; v_cr numeric:=0; v_in numeric:=0; v_out numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'accounting.view')
     and not private.erp_has_permission(p_tenant_id,'accounting.manage') then
    raise exception 'Accounting permission required';
  end if;
  if p_to is null then raise exception 'End date is required';end if;
  if p_from is null then p_from:=date '2000-01-01';end if;
  if p_from>p_to then raise exception 'Invalid date range';end if;

  if v_key='trial_balance' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric debit,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric credit
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'account_id',id,'code',code,'name',name,'account_type',account_type,
      'debit',debit,'credit',credit,
      'balance',case when account_type in('asset','expense','cogs') then debit-credit else credit-debit end
    ) order by code),'[]'::jsonb),coalesce(sum(debit),0),coalesce(sum(credit),0)
    into v_rows,v_dr,v_cr from balances where abs(debit)>0.0001 or abs(credit)>0.0001;
    v_summary:=jsonb_build_object('total_debit',v_dr,'total_credit',v_cr,'difference',v_dr-v_cr);

  elsif v_key='profit_loss' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='income' then coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0)
             else coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active and a.account_type in('income','cogs','expense')
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='income'),0),
      coalesce(sum(amount) filter(where account_type='cogs'),0),
      coalesce(sum(amount) filter(where account_type='expense'),0)
    into v_rows,v_revenue,v_cogs,v_expenses from balances where abs(amount)>0.0001;
    v_net:=v_revenue-v_cogs-v_expenses;
    v_summary:=jsonb_build_object('revenue',v_revenue,'cogs',v_cogs,'expenses',v_expenses,'net_profit',v_net,'from',p_from,'to',p_to);

  elsif v_key='balance_sheet' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='asset' then coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0)
             else coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active and a.account_type in('asset','liability','equity')
      group by a.id,a.code,a.name,a.account_type
    ), earnings as (
      select coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit when a.account_type in('expense','cogs') then -(jl.debit-jl.credit) else 0 end),0)::numeric amount
      from public.journal_lines jl
      join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=p_tenant_id
      join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
      where a.account_type in('income','expense','cogs') and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='asset'),0),
      coalesce(sum(amount) filter(where account_type='liability'),0),
      coalesce(sum(amount) filter(where account_type='equity'),0),
      coalesce((select amount from earnings),0)
    into v_rows,v_assets,v_liabilities,v_equity,v_current_earnings from balances where abs(amount)>0.0001;
    v_summary:=jsonb_build_object(
      'assets',v_assets,'liabilities',v_liabilities,'equity',v_equity,
      'current_earnings',v_current_earnings,
      'liabilities_and_equity',v_liabilities+v_equity+v_current_earnings,
      'difference',v_assets-(v_liabilities+v_equity+v_current_earnings),'as_of',p_to
    );

  elsif v_key='cash_flow' then
    with cash_accounts as (
      select distinct a.id,a.code::text code,a.name::text name,a.system_key::text system_key
      from public.accounting_accounts a
      left join public.accounting_account_mappings m on m.tenant_id=a.tenant_id and m.account_id=a.id
      where a.tenant_id=p_tenant_id and a.active
        and (a.system_key in('cash','bank','upi','card') or m.mapping_key in('payment.cash','payment.bank','payment.upi','payment.card'))
    ), moves as (
      select a.id,a.code,a.name,a.system_key,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric inflow,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric outflow
      from cash_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      group by a.id,a.code,a.name,a.system_key
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'system_key',system_key,'inflow',inflow,'outflow',outflow,'net_change',inflow-outflow) order by code),'[]'::jsonb),
      coalesce(sum(inflow),0),coalesce(sum(outflow),0)
    into v_rows,v_in,v_out from moves where abs(inflow)>0.0001 or abs(outflow)>0.0001;
    v_summary:=jsonb_build_object('inflow',v_in,'outflow',v_out,'net_change',v_in-v_out,'from',p_from,'to',p_to,'note','Cash/Bank/UPI/Card account movement');
  else
    raise exception 'Unknown accounting statement %',p_statement;
  end if;

  return jsonb_build_object('statement',v_key,'rows',v_rows,'summary',v_summary,'location_id',p_location_id);
end $$;

revoke all on function public.accounting_statement_v41(uuid,text,date,date,uuid) from public,anon;
grant execute on function public.accounting_statement_v41(uuid,text,date,date,uuid) to authenticated;


-- Runtime-tested v5 finance summary and Balance Sheet path.
create or replace function public.finance_controls_summary_v500(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_unmatched bigint;v_due bigint;v_open_years bigint;v_banks bigint;begin
  perform private.v500_accounting_access(p_tenant_id,false);
  select count(*) into v_unmatched from public.bank_statement_lines_v500 where tenant_id=p_tenant_id and status='unmatched';
  select count(*) into v_due from public.recurring_expenses_v500 where tenant_id=p_tenant_id and active and next_run_date<=current_date;
  select count(*) into v_open_years from public.financial_years_v500 where tenant_id=p_tenant_id and status='open';
  select count(*) into v_banks from public.bank_accounts_v500 where tenant_id=p_tenant_id and active;
  return jsonb_build_object('unmatched_bank_lines',v_unmatched,'due_recurring_expenses',v_due,'open_financial_years',v_open_years,'active_bank_accounts',v_banks,'reconciliation',public.finance_reconciliation_v500(p_tenant_id));
end $$;
grant execute on function public.finance_controls_summary_v500(uuid) to authenticated;

create or replace function public.accounting_balance_sheet_v500(p_tenant_id uuid,p_to date,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_rows jsonb;v_assets numeric:=0;v_liabilities numeric:=0;v_equity numeric:=0;v_earnings numeric:=0;begin
  perform private.v500_accounting_access(p_tenant_id,false);if p_to is null then raise exception 'End date is required';end if;
  with balances as (
    select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
      case when a.account_type='asset' then coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0) else coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0) end::numeric amount
    from public.accounting_accounts a left join public.journal_lines jl on jl.account_id=a.id
    left join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    where a.tenant_id=p_tenant_id and a.active and a.account_type in('asset','liability','equity') group by a.id,a.code,a.name,a.account_type
  ), earnings as (
    select coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit when a.account_type in('expense','cogs') then -(jl.debit-jl.credit) else 0 end),0)::numeric amount
    from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=p_tenant_id
    join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
    where a.account_type in('income','expense','cogs') and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
  )
  select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code) filter(where abs(amount)>0.0001),'[]'::jsonb),
    coalesce(sum(amount) filter(where account_type='asset'),0),coalesce(sum(amount) filter(where account_type='liability'),0),coalesce(sum(amount) filter(where account_type='equity'),0),coalesce((select amount from earnings),0)
  into v_rows,v_assets,v_liabilities,v_equity,v_earnings from balances;
  return jsonb_build_object('statement','balance_sheet','rows',v_rows,'summary',jsonb_build_object('assets',v_assets,'liabilities',v_liabilities,'equity',v_equity,'current_earnings',v_earnings,'liabilities_and_equity',v_liabilities+v_equity+v_earnings,'difference',v_assets-(v_liabilities+v_equity+v_earnings),'as_of',p_to),'location_id',p_location_id);
end $$;
grant execute on function public.accounting_balance_sheet_v500(uuid,date,uuid) to authenticated;

-- Keep the tenant directory protected for direct Client/POS session lookup.
alter table public.tenants enable row level security;
revoke all on table public.tenants from anon,authenticated;
grant select on table public.tenants to authenticated;
drop policy if exists tenants_select_member on public.tenants;
create policy tenants_select_member on public.tenants for select to authenticated
using (private.is_tenant_member(id) or public.current_user_is_platform_admin());

create or replace function public.thq_v500_capabilities()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object(
 'finance_controls',to_regprocedure('public.finance_controls_summary_v500(uuid)') is not null,
 'journal_center',to_regprocedure('public.journal_center_list_v500(uuid,date,date,text,text,integer)') is not null,
 'bank_reconciliation',to_regprocedure('public.bank_statement_match_v500(uuid,uuid,uuid)') is not null,
 'financial_closing',to_regprocedure('public.financial_year_close_v500(uuid,uuid)') is not null,
 'opening_balances',to_regprocedure('public.opening_balance_post_v500(uuid,date,jsonb,text,uuid)') is not null,
 'recurring_expenses',to_regprocedure('public.recurring_expenses_process_v500(uuid,date)') is not null,
 'crm',to_regprocedure('public.customer_crm_profile_v500(uuid,uuid)') is not null,
 'loyalty',to_regprocedure('public.customer_loyalty_adjust_v500(uuid,uuid,numeric,text,uuid,text)') is not null,
 'purchase_quotations',to_regprocedure('public.purchase_quotations_list_v500(uuid,uuid,text,text)') is not null,
 'supplier_performance',to_regprocedure('public.supplier_performance_v500(uuid,date,date,integer)') is not null,
 'reorder_suggestions',to_regprocedure('public.reorder_suggestions_v500(uuid,uuid,integer,text,integer)') is not null,
 'approved_stock_adjustment',to_regprocedure('public.stock_adjustment_request_v500(uuid,uuid,uuid,uuid,numeric,text,text)') is not null,
 'reports_center',to_regprocedure('public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer)') is not null,
 'returns_report',to_regprocedure('public.returns_report_v500(uuid,text,date,date,uuid,text,integer)') is not null,
 'task_notification_sync',to_regprocedure('public.business_task_timeline_v500(uuid,uuid)') is not null,
 'notification_center',to_regprocedure('public.notifications_list_v4(uuid,integer)') is not null,
 'dashboard_bi',to_regprocedure('public.dashboard_business_intelligence_v500(uuid,uuid,date)') is not null,
 'finance_reconciliation',to_regprocedure('public.finance_reconciliation_v500(uuid)') is not null,
 'invoice_designer',to_regprocedure('public.invoice_template_capabilities_v495(uuid)') is not null,
 'change_business_supported',true
) $$;
grant execute on function public.thq_v500_capabilities() to authenticated;

-- ---------------------------------------------------------------------------
-- Legacy baseline RPC compatibility
create or replace function private.is_platform_admin() returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from private.platform_admins pa where pa.user_id=(select auth.uid()) and pa.status='active');$$;
revoke all on function private.is_platform_admin() from public;

create or replace function private.is_tenant_member(target_tenant_id uuid) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from public.tenant_memberships tm where tm.tenant_id=target_tenant_id and tm.user_id=(select auth.uid()) and tm.status='active');$$;
revoke all on function private.is_tenant_member(uuid) from public;

create or replace function private.has_permission(target_tenant_id uuid,target_permission_key text) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from public.tenant_memberships tm join public.user_roles ur on ur.tenant_id=tm.tenant_id and ur.membership_id=tm.id join public.role_permissions rp on rp.role_id=ur.role_id where tm.tenant_id=target_tenant_id and tm.user_id=(select auth.uid()) and tm.status='active' and rp.permission_key=target_permission_key);$$;
revoke all on function private.has_permission(uuid,text) from public;

create or replace function private.grant_default_role_permissions(target_tenant_id uuid,target_role_id uuid,target_role_key text) returns void
language plpgsql security definer set search_path='' as $$declare v_keys text[];begin
 if target_role_key='owner' then
  insert into public.role_permissions(role_id,permission_key)
  select target_role_id,p.key from public.permissions p join public.tenant_modules tm on tm.module_key=p.module_key where tm.tenant_id=target_tenant_id and tm.enabled on conflict do nothing;return;
 end if;
 v_keys:=case target_role_key
  when 'manager' then array['dashboard.view','inventory.view','inventory.manage','sales.view','sales.manage','purchases.view','purchases.manage','customers.view','customers.manage','suppliers.view','suppliers.manage','expenses.view','expenses.manage','accounting.view','reports.view','barcode.use','warranty.view','warranty.manage','vehicle_compatibility.view','vehicle_compatibility.manage']::text[]
  when 'cashier' then array['dashboard.view','inventory.view','sales.view','sales.manage','customers.view','customers.manage','barcode.use','warranty.view']::text[]
  when 'salesperson' then array['dashboard.view','inventory.view','sales.view','sales.manage','customers.view','customers.manage','barcode.use','warranty.view','warranty.manage','vehicle_compatibility.view']::text[]
  when 'store_keeper' then array['dashboard.view','inventory.view','inventory.manage','purchases.view','purchases.manage','suppliers.view','suppliers.manage','barcode.use','warranty.view','warranty.manage','vehicle_compatibility.view','vehicle_compatibility.manage']::text[]
  when 'accountant' then array['dashboard.view','sales.view','purchases.view','customers.view','suppliers.view','expenses.view','expenses.manage','accounting.view','accounting.manage','reports.view']::text[]
  else array[]::text[] end;
 insert into public.role_permissions(role_id,permission_key)
 select target_role_id,p.key from public.permissions p join public.tenant_modules tm on tm.module_key=p.module_key where tm.tenant_id=target_tenant_id and tm.enabled and p.key=any(v_keys) on conflict do nothing;
end$$;
revoke all on function private.grant_default_role_permissions(uuid,uuid,text) from public;

create or replace function private.seed_default_roles(target_tenant_id uuid) returns void
language plpgsql security definer set search_path='' as $$declare r record;v_role_id uuid;begin
 for r in select * from (values ('owner','Owner'),('manager','Manager'),('cashier','Cashier'),('salesperson','Salesperson'),('store_keeper','Store Keeper'),('accountant','Accountant')) x(role_key,role_name) loop
  v_role_id:=null;
  insert into public.roles(tenant_id,key,name,is_system) values(target_tenant_id,r.role_key,r.role_name,true) on conflict(tenant_id,key) do nothing returning id into v_role_id;
  if v_role_id is not null then perform private.grant_default_role_permissions(target_tenant_id,v_role_id,r.role_key);end if;
 end loop;
end$$;
revoke all on function private.seed_default_roles(uuid) from public;

-- These RPCs existed in the deployed pre-migration baseline and are still
-- called by current Dart code. Keep their definitions in source so 210->211
-- upgrades are self-contained.
-- ---------------------------------------------------------------------------
create or replace function public.current_user_is_platform_admin() returns boolean
language sql stable security definer set search_path='' as $$select private.is_platform_admin();$$;
grant execute on function public.current_user_is_platform_admin() to authenticated;

create or replace function public.platform_list_modules()
returns table(key text,name text,description text,category text,is_core boolean,sort_order integer)
language plpgsql stable security definer set search_path='' as $$begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 return query select m.key,m.name,m.description,m.category,m.is_core,m.sort_order from public.modules m order by m.category,m.sort_order,m.name;
end$$;
grant execute on function public.platform_list_modules() to authenticated;

create or replace function public.platform_get_business_modules(p_tenant_id uuid)
returns table(module_key text,module_name text,description text,category text,is_core boolean,enabled boolean,sort_order integer)
language plpgsql stable security definer set search_path='' as $$begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 if not exists(select 1 from public.tenants t where t.id=p_tenant_id) then raise exception 'Business not found';end if;
 return query select m.key,m.name,m.description,m.category,m.is_core,coalesce(tm.enabled,false),m.sort_order from public.modules m left join public.tenant_modules tm on tm.module_key=m.key and tm.tenant_id=p_tenant_id order by m.category,m.sort_order,m.name;
end$$;
grant execute on function public.platform_get_business_modules(uuid) to authenticated;

create or replace function public.platform_get_business_permissions(p_tenant_id uuid)
returns table(permission_key text,permission_name text,module_key text,module_name text)
language plpgsql stable security definer set search_path='' as $$begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 return query select p.key,p.name,p.module_key,m.name from public.permissions p join public.modules m on m.key=p.module_key join public.tenant_modules tm on tm.module_key=p.module_key and tm.tenant_id=p_tenant_id and tm.enabled order by m.sort_order,m.name,p.name;
end$$;
grant execute on function public.platform_get_business_permissions(uuid) to authenticated;

create or replace function public.platform_get_business_roles(p_tenant_id uuid)
returns table(role_id uuid,role_key text,role_name text,is_system boolean,permission_keys text[])
language plpgsql stable security definer set search_path='' as $$begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 if not exists(select 1 from public.tenants t where t.id=p_tenant_id) then raise exception 'Business not found';end if;
 return query select r.id,r.key,r.name,r.is_system,coalesce(array_agg(rp.permission_key order by rp.permission_key) filter(where rp.permission_key is not null),array[]::text[]) from public.roles r left join public.role_permissions rp on rp.role_id=r.id where r.tenant_id=p_tenant_id group by r.id,r.key,r.name,r.is_system order by case r.key when 'owner' then 1 when 'manager' then 2 when 'cashier' then 3 when 'salesperson' then 4 when 'store_keeper' then 5 when 'accountant' then 6 else 100 end,r.name;
end$$;
grant execute on function public.platform_get_business_roles(uuid) to authenticated;

create or replace function public.platform_update_role_permissions(p_tenant_id uuid,p_role_id uuid,p_permission_keys text[])
returns void language plpgsql security definer set search_path='' as $$declare v_role_key text;begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 select r.key into v_role_key from public.roles r where r.id=p_role_id and r.tenant_id=p_tenant_id;
 if v_role_key is null then raise exception 'Role not found';end if;if v_role_key='owner' then raise exception 'Owner permissions cannot be manually restricted';end if;
 if exists(select 1 from unnest(coalesce(p_permission_keys,array[]::text[])) q(permission_key) left join public.permissions p on p.key=q.permission_key left join public.tenant_modules tm on tm.tenant_id=p_tenant_id and tm.module_key=p.module_key and tm.enabled where p.key is null or tm.module_key is null) then raise exception 'One or more permissions are invalid or belong to disabled modules';end if;
 delete from public.role_permissions where role_id=p_role_id;
 insert into public.role_permissions(role_id,permission_key) select p_role_id,q.permission_key from unnest(coalesce(p_permission_keys,array[]::text[])) q(permission_key) on conflict do nothing;
end$$;
grant execute on function public.platform_update_role_permissions(uuid,uuid,text[]) to authenticated;

create or replace function public.platform_create_business(p_name text,p_slug text,p_business_type text,p_module_keys text[])
returns uuid language plpgsql security definer set search_path='' as $$declare v_tenant_id uuid;v_slug text;begin
 if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501';end if;
 if nullif(trim(p_name),'') is null then raise exception 'Business name is required';end if;v_slug:=lower(trim(p_slug));if nullif(v_slug,'') is null then raise exception 'Business slug is required';end if;if v_slug!~'^[a-z0-9]+(-[a-z0-9]+)*$' then raise exception 'Slug may contain only lowercase letters, numbers and hyphens';end if;
 if exists(select 1 from public.tenants t where t.slug=v_slug) then raise exception 'A business with this slug already exists';end if;
 if exists(select 1 from unnest(coalesce(p_module_keys,array[]::text[])) q(module_key) left join public.modules m on m.key=q.module_key where m.key is null) then raise exception 'One or more selected modules do not exist';end if;
 insert into public.tenants(name,slug,business_type,status) values(trim(p_name),v_slug,nullif(trim(p_business_type),''),'active') returning id into v_tenant_id;
 insert into public.tenant_settings(tenant_id,currency_code,timezone,locale) values(v_tenant_id,'INR','Asia/Kolkata','en_IN');
 insert into public.tenant_modules(tenant_id,module_key,enabled) select v_tenant_id,m.key,true from public.modules m where m.key='dashboard' or m.key=any(coalesce(p_module_keys,array[]::text[])) on conflict(tenant_id,module_key) do update set enabled=true;
 perform private.seed_default_roles(v_tenant_id);return v_tenant_id;
end$$;
grant execute on function public.platform_create_business(text,text,text,text[]) to authenticated;

create or replace function public.customers_create(p_tenant_id uuid,p_name text,p_contact_person text,p_phone text,p_email text,p_tax_number text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,p_country text,p_credit_limit numeric,p_notes text)
returns uuid language plpgsql security definer set search_path='' as $$declare v_id uuid;v_tax text;begin
 if not private.has_permission(p_tenant_id,'customers.manage') then raise exception 'Access denied' using errcode='42501';end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Customer name is required';end if;if coalesce(p_credit_limit,0)<0 then raise exception 'Credit limit cannot be negative';end if;
 v_tax:=nullif(upper(trim(coalesce(p_tax_number,''))),'');if v_tax is not null and exists(select 1 from public.customers c where c.tenant_id=p_tenant_id and upper(c.tax_number)=v_tax) then raise exception 'A customer with this Tax ID already exists';end if;
 insert into public.customers(tenant_id,name,contact_person,phone,email,tax_number,address_line1,address_line2,city,state,postal_code,country,credit_limit,notes,is_walk_in,status,created_by) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_contact_person,'')),''),nullif(trim(coalesce(p_phone,'')),''),nullif(lower(trim(coalesce(p_email,''))),''),v_tax,nullif(trim(coalesce(p_address_line1,'')),''),nullif(trim(coalesce(p_address_line2,'')),''),nullif(trim(coalesce(p_city,'')),''),nullif(trim(coalesce(p_state,'')),''),nullif(trim(coalesce(p_postal_code,'')),''),coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),coalesce(p_credit_limit,0),nullif(trim(coalesce(p_notes,'')),''),false,'active',auth.uid()) returning id into v_id;return v_id;
end$$;
grant execute on function public.customers_create(uuid,text,text,text,text,text,text,text,text,text,text,text,numeric,text) to authenticated;

create or replace function public.customers_update(p_tenant_id uuid,p_customer_id uuid,p_name text,p_contact_person text,p_phone text,p_email text,p_tax_number text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,p_country text,p_credit_limit numeric,p_notes text,p_status text)
returns void language plpgsql security definer set search_path='' as $$declare v_tax text;v_walk boolean;begin
 if not private.has_permission(p_tenant_id,'customers.manage') then raise exception 'Access denied' using errcode='42501';end if;select c.is_walk_in into v_walk from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id;if v_walk is null then raise exception 'Customer not found';end if;if v_walk then raise exception 'Walk-in Customer is a protected system customer';end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Customer name is required';end if;if p_status not in('active','inactive') then raise exception 'Invalid customer status';end if;if coalesce(p_credit_limit,0)<0 then raise exception 'Credit limit cannot be negative';end if;
 v_tax:=nullif(upper(trim(coalesce(p_tax_number,''))),'');if v_tax is not null and exists(select 1 from public.customers c where c.tenant_id=p_tenant_id and c.id<>p_customer_id and upper(c.tax_number)=v_tax) then raise exception 'A customer with this Tax ID already exists';end if;
 update public.customers set name=trim(p_name),contact_person=nullif(trim(coalesce(p_contact_person,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(lower(trim(coalesce(p_email,''))),''),tax_number=v_tax,address_line1=nullif(trim(coalesce(p_address_line1,'')),''),address_line2=nullif(trim(coalesce(p_address_line2,'')),''),city=nullif(trim(coalesce(p_city,'')),''),state=nullif(trim(coalesce(p_state,'')),''),postal_code=nullif(trim(coalesce(p_postal_code,'')),''),country=coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),credit_limit=coalesce(p_credit_limit,0),notes=nullif(trim(coalesce(p_notes,'')),''),status=p_status where id=p_customer_id and tenant_id=p_tenant_id;
end$$;
grant execute on function public.customers_update(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,numeric,text,text) to authenticated;

create or replace function public.suppliers_create(p_tenant_id uuid,p_name text,p_contact_person text,p_phone text,p_email text,p_tax_number text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,p_country text,p_notes text)
returns uuid language plpgsql security definer set search_path='' as $$declare v_id uuid;v_tax text;begin
 if not private.has_permission(p_tenant_id,'suppliers.manage') then raise exception 'Access denied' using errcode='42501';end if;if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Supplier name is required';end if;v_tax:=nullif(upper(trim(coalesce(p_tax_number,''))),'');if v_tax is not null and exists(select 1 from public.suppliers s where s.tenant_id=p_tenant_id and upper(s.tax_number)=v_tax) then raise exception 'A supplier with this Tax ID already exists';end if;
 insert into public.suppliers(tenant_id,name,contact_person,phone,email,tax_number,address_line1,address_line2,city,state,postal_code,country,notes,status,created_by) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_contact_person,'')),''),nullif(trim(coalesce(p_phone,'')),''),nullif(lower(trim(coalesce(p_email,''))),''),v_tax,nullif(trim(coalesce(p_address_line1,'')),''),nullif(trim(coalesce(p_address_line2,'')),''),nullif(trim(coalesce(p_city,'')),''),nullif(trim(coalesce(p_state,'')),''),nullif(trim(coalesce(p_postal_code,'')),''),coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),nullif(trim(coalesce(p_notes,'')),''),'active',auth.uid()) returning id into v_id;return v_id;
end$$;
grant execute on function public.suppliers_create(uuid,text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;

create or replace function public.suppliers_update(p_tenant_id uuid,p_supplier_id uuid,p_name text,p_contact_person text,p_phone text,p_email text,p_tax_number text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,p_country text,p_notes text,p_status text)
returns void language plpgsql security definer set search_path='' as $$declare v_tax text;begin
 if not private.has_permission(p_tenant_id,'suppliers.manage') then raise exception 'Access denied' using errcode='42501';end if;if not exists(select 1 from public.suppliers s where s.id=p_supplier_id and s.tenant_id=p_tenant_id) then raise exception 'Supplier not found';end if;if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Supplier name is required';end if;if p_status not in('active','inactive') then raise exception 'Invalid supplier status';end if;v_tax:=nullif(upper(trim(coalesce(p_tax_number,''))),'');if v_tax is not null and exists(select 1 from public.suppliers s where s.tenant_id=p_tenant_id and s.id<>p_supplier_id and upper(s.tax_number)=v_tax) then raise exception 'A supplier with this Tax ID already exists';end if;
 update public.suppliers set name=trim(p_name),contact_person=nullif(trim(coalesce(p_contact_person,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(lower(trim(coalesce(p_email,''))),''),tax_number=v_tax,address_line1=nullif(trim(coalesce(p_address_line1,'')),''),address_line2=nullif(trim(coalesce(p_address_line2,'')),''),city=nullif(trim(coalesce(p_city,'')),''),state=nullif(trim(coalesce(p_state,'')),''),postal_code=nullif(trim(coalesce(p_postal_code,'')),''),country=coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),notes=nullif(trim(coalesce(p_notes,'')),''),status=p_status where id=p_supplier_id and tenant_id=p_tenant_id;
end$$;
grant execute on function public.suppliers_update(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;

create or replace function public.inventory_list_products(p_tenant_id uuid)
returns table(product_id uuid,variant_id uuid,product_name text,variant_name text,item_type text,category_name text,brand_name text,unit_name text,unit_code text,sku text,barcode text,part_number text,cost_price numeric,selling_price numeric,list_price numeric,tax_rate numeric,reorder_level numeric,stock_quantity numeric,product_status text,variant_status text,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$begin
 if not(private.has_permission(p_tenant_id,'inventory.view') or private.has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Access denied' using errcode='42501';end if;
 return query select p.id,pv.id,p.name,pv.name,p.item_type,pc.name,pb.name,iu.name,iu.code,pv.sku,pv.barcode,pv.part_number,pv.cost_price,pv.selling_price,pv.list_price,p.tax_rate,pv.reorder_level,coalesce(sum(sb.quantity),0)::numeric,p.status,pv.status,greatest(p.updated_at,pv.updated_at) from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id left join public.product_categories pc on pc.id=p.category_id and pc.tenant_id=p.tenant_id left join public.product_brands pb on pb.id=p.brand_id and pb.tenant_id=p.tenant_id left join public.inventory_units iu on iu.id=p.base_unit_id and iu.tenant_id=p.tenant_id left join public.stock_balances sb on sb.variant_id=pv.id and sb.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id group by p.id,pv.id,pc.name,pb.name,iu.name,iu.code order by p.name,pv.name;
end$$;
grant execute on function public.inventory_list_products(uuid) to authenticated;

create or replace function public.inventory_get_product_detail(p_tenant_id uuid,p_variant_id uuid)
returns table(product_id uuid,variant_id uuid,product_name text,description text,item_type text,category_name text,brand_name text,unit_name text,unit_code text,sku text,barcode text,part_number text,cost_price numeric,selling_price numeric,list_price numeric,tax_rate numeric,reorder_level numeric,stock_quantity numeric,product_status text,variant_status text,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$begin
 if not(private.has_permission(p_tenant_id,'inventory.view') or private.has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Access denied' using errcode='42501';end if;
 return query select p.id,pv.id,p.name,p.description,p.item_type,pc.name,pb.name,iu.name,iu.code,pv.sku,pv.barcode,pv.part_number,pv.cost_price,pv.selling_price,pv.list_price,p.tax_rate,pv.reorder_level,coalesce(sum(sb.quantity),0)::numeric,p.status,pv.status,p.created_at,greatest(p.updated_at,pv.updated_at) from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id left join public.product_categories pc on pc.id=p.category_id and pc.tenant_id=p.tenant_id left join public.product_brands pb on pb.id=p.brand_id and pb.tenant_id=p.tenant_id left join public.inventory_units iu on iu.id=p.base_unit_id and iu.tenant_id=p.tenant_id left join public.stock_balances sb on sb.variant_id=pv.id and sb.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and pv.id=p_variant_id group by p.id,pv.id,pc.name,pb.name,iu.name,iu.code;
end$$;
grant execute on function public.inventory_get_product_detail(uuid,uuid) to authenticated;

create or replace function public.inventory_create_product(p_tenant_id uuid,p_name text,p_sku text,p_item_type text,p_description text,p_category_name text,p_brand_name text,p_barcode text,p_part_number text,p_cost_price numeric,p_selling_price numeric,p_list_price numeric,p_tax_rate numeric,p_reorder_level numeric,p_opening_stock numeric)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_product uuid;v_variant uuid;v_cat uuid;v_brand uuid;v_unit uuid;v_loc uuid;v_open numeric:=coalesce(p_opening_stock,0);v_lines jsonb;begin
 if not private.has_permission(p_tenant_id,'inventory.manage') then raise exception 'Access denied' using errcode='42501';end if;if nullif(trim(coalesce(p_name,'')),'') is null or nullif(trim(coalesce(p_sku,'')),'') is null then raise exception 'Product name and SKU are required';end if;if p_item_type not in('stock','non_stock','service') then raise exception 'Invalid item type';end if;if coalesce(p_cost_price,0)<0 or coalesce(p_selling_price,0)<0 or coalesce(p_tax_rate,0)<0 or coalesce(p_tax_rate,0)>100 or coalesce(p_reorder_level,0)<0 or v_open<0 then raise exception 'Invalid product numeric values';end if;if p_item_type<>'stock' and v_open<>0 then raise exception 'Opening stock is only allowed for stock items';end if;if exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and lower(pv.sku)=lower(trim(p_sku))) then raise exception 'A product with this SKU already exists';end if;
 select id into v_unit from public.inventory_units where tenant_id=p_tenant_id and code='PCS' and is_active limit 1;if v_unit is null then raise exception 'Default inventory unit PCS does not exist';end if;select id into v_loc from public.inventory_locations where tenant_id=p_tenant_id and is_active order by is_default desc,created_at limit 1;if v_loc is null then raise exception 'No active inventory location exists';end if;
 if nullif(trim(coalesce(p_category_name,'')),'') is not null then select id into v_cat from public.product_categories where tenant_id=p_tenant_id and lower(name)=lower(trim(p_category_name)) limit 1;if v_cat is null then insert into public.product_categories(tenant_id,name,is_active) values(p_tenant_id,trim(p_category_name),true) returning id into v_cat;end if;end if;
 if nullif(trim(coalesce(p_brand_name,'')),'') is not null then select id into v_brand from public.product_brands where tenant_id=p_tenant_id and lower(name)=lower(trim(p_brand_name)) limit 1;if v_brand is null then insert into public.product_brands(tenant_id,name,is_active) values(p_tenant_id,trim(p_brand_name),true) returning id into v_brand;end if;end if;
 insert into public.products(tenant_id,name,description,item_type,category_id,brand_id,base_unit_id,tax_rate,status,created_by) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_description,'')),''),p_item_type,v_cat,v_brand,v_unit,coalesce(p_tax_rate,0),'active',auth.uid()) returning id into v_product;
 insert into public.product_variants(tenant_id,product_id,name,sku,barcode,part_number,cost_price,selling_price,list_price,reorder_level,is_default,status) values(p_tenant_id,v_product,'Default',trim(p_sku),nullif(trim(coalesce(p_barcode,'')),''),nullif(trim(coalesce(p_part_number,'')),''),coalesce(p_cost_price,0),coalesce(p_selling_price,0),p_list_price,coalesce(p_reorder_level,0),true,'active') returning id into v_variant;
 if p_item_type='stock' and v_open>0 then insert into public.stock_movements(tenant_id,variant_id,location_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,reference_number,note,created_by) values(p_tenant_id,v_variant,v_loc,'opening',v_open,coalesce(p_cost_price,0),'product',v_variant,trim(p_sku),'Opening stock',auth.uid());insert into public.stock_balances(tenant_id,location_id,variant_id,quantity,updated_at) values(p_tenant_id,v_loc,v_variant,v_open,now()) on conflict(tenant_id,location_id,variant_id) do update set quantity=public.stock_balances.quantity+excluded.quantity,updated_at=now();
   if coalesce(p_cost_price,0)>0 then v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',round(v_open*p_cost_price,2),'credit',0,'description','Opening inventory • '||trim(p_name)),jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'owner_equity'),'debit',0,'credit',round(v_open*p_cost_price,2),'description','Opening inventory equity'));perform private.v4_journal_create(p_tenant_id,null,current_date,'Opening inventory • '||trim(p_name),'product_opening_stock',v_variant,trim(p_sku),v_lines);end if;
 end if;return jsonb_build_object('success',true,'product_id',v_product,'variant_id',v_variant,'sku',trim(p_sku),'opening_stock',v_open);
end$$;
grant execute on function public.inventory_create_product(uuid,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;

create or replace function public.inventory_update_product(p_tenant_id uuid,p_variant_id uuid,p_name text,p_description text,p_category_name text,p_brand_name text,p_sku text,p_barcode text,p_part_number text,p_cost_price numeric,p_selling_price numeric,p_list_price numeric,p_tax_rate numeric,p_reorder_level numeric)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_product uuid;v_cat uuid;v_brand uuid;begin
 if not private.has_permission(p_tenant_id,'inventory.manage') then raise exception 'Access denied' using errcode='42501';end if;select product_id into v_product from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id;if v_product is null then raise exception 'Product not found';end if;if nullif(trim(coalesce(p_name,'')),'') is null or nullif(trim(coalesce(p_sku,'')),'') is null then raise exception 'Product name and SKU are required';end if;if coalesce(p_cost_price,0)<0 or coalesce(p_selling_price,0)<0 or coalesce(p_tax_rate,0)<0 or coalesce(p_tax_rate,0)>100 or coalesce(p_reorder_level,0)<0 then raise exception 'Invalid product numeric values';end if;if exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id<>p_variant_id and lower(sku)=lower(trim(p_sku))) then raise exception 'A product with this SKU already exists';end if;
 if nullif(trim(coalesce(p_category_name,'')),'') is not null then select id into v_cat from public.product_categories where tenant_id=p_tenant_id and lower(name)=lower(trim(p_category_name)) limit 1;if v_cat is null then insert into public.product_categories(tenant_id,name,is_active) values(p_tenant_id,trim(p_category_name),true) returning id into v_cat;end if;end if;if nullif(trim(coalesce(p_brand_name,'')),'') is not null then select id into v_brand from public.product_brands where tenant_id=p_tenant_id and lower(name)=lower(trim(p_brand_name)) limit 1;if v_brand is null then insert into public.product_brands(tenant_id,name,is_active) values(p_tenant_id,trim(p_brand_name),true) returning id into v_brand;end if;end if;
 update public.products set name=trim(p_name),description=nullif(trim(coalesce(p_description,'')),''),category_id=v_cat,brand_id=v_brand,tax_rate=coalesce(p_tax_rate,0) where id=v_product and tenant_id=p_tenant_id;update public.product_variants set sku=trim(p_sku),barcode=nullif(trim(coalesce(p_barcode,'')),''),part_number=nullif(trim(coalesce(p_part_number,'')),''),cost_price=coalesce(p_cost_price,0),selling_price=coalesce(p_selling_price,0),list_price=p_list_price,reorder_level=coalesce(p_reorder_level,0) where id=p_variant_id and tenant_id=p_tenant_id;return jsonb_build_object('success',true,'product_id',v_product,'variant_id',p_variant_id);
end$$;
grant execute on function public.inventory_update_product(uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric) to authenticated;


insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(211,'5.0.0','Build 25 Audit Repairs','Audit-driven v5 completion: period locks/opening/closing, journal safety, bank reconciliation, CRM pricing validation, purchasing validation, approved stock adjustments, task security, BI, reports and reconciliation hardening.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

create or replace function public.thq_v500_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare miss text[]:='{}';r record;begin
  for r in select * from (values
    ('finance_reconciliation_v500','public.finance_reconciliation_v500(uuid)'),
    ('financial_years_list_v500','public.financial_years_list_v500(uuid)'),
    ('financial_year_close_v500','public.financial_year_close_v500(uuid,uuid)'),
    ('opening_balance_post_v500','public.opening_balance_post_v500(uuid,date,jsonb,text,uuid)'),
    ('finance_voucher_post_v500','public.finance_voucher_post_v500(uuid,uuid,text,date,numeric,uuid,uuid,text,uuid,text,text,text)'),
    ('bank_statement_match_v500','public.bank_statement_match_v500(uuid,uuid,uuid)'),
    ('journal_reverse_v500','public.journal_reverse_v500(uuid,uuid,text)'),
    ('customer_crm_profile_v500','public.customer_crm_profile_v500(uuid,uuid)'),
    ('purchase_quotations_list_v500','public.purchase_quotations_list_v500(uuid,uuid,text,text)'),
    ('reorder_suggestions_v500','public.reorder_suggestions_v500(uuid,uuid,integer,text,integer)'),
    ('stock_adjustment_request_v500','public.stock_adjustment_request_v500(uuid,uuid,uuid,uuid,numeric,text,text)'),
    ('reports_center_data_v500','public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer)'),
    ('dashboard_business_intelligence_v500','public.dashboard_business_intelligence_v500(uuid,uuid,date)'),
    ('business_tasks_list_v500','public.business_tasks_list_v500(uuid,uuid,text)'),
    ('business_task_timeline_v500','public.business_task_timeline_v500(uuid,uuid)'),
    ('notifications_list_v4','public.notifications_list_v4(uuid,integer)')
  ) v(name,sig) loop if to_regprocedure(r.sig) is null then miss:=array_append(miss,r.name);end if;end loop;
  if not exists(select 1 from public.thq_schema_releases where migration_no=211 and schema_version='5.0.0') then miss:=array_append(miss,'migration.211');end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='stock_adjustment_requests_v500' and c.relrowsecurity) then miss:=array_append(miss,'rls.stock_adjustment_requests_v500');end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='opening_balance_batches_v500' and c.relrowsecurity) then miss:=array_append(miss,'rls.opening_balance_batches_v500');end if;
  return jsonb_build_object('ready',cardinality(miss)=0,'missing',to_jsonb(miss),'schema_version','5.0.0','migration_no',211,'build',25,'capabilities',public.thq_v500_capabilities());
end $$;
grant execute on function public.thq_v500_verify() to authenticated;

-- Keep the API/release contract authoritative at Build 25.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object('product','THQ ERP','schema_version','5.0.0','migration_no',211,'minimum_app_version','5.0.0','minimum_client_migration',211,'build',25,'release','Milestone Finance, Intelligence & Control — Audit Repairs','api_version','v1','backward_compatible',true,'verified_by','thq_v500_verify') $$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select public.thq_backend_contract_v47()||jsonb_build_object('app_version','5.0.0','build',25,'minimum_migration',211,'capabilities',public.thq_v500_capabilities()) $$;
grant execute on function public.thq_api_contract_v480() to authenticated;

commit;
select 'THQ ERP v5.0.0 Build 25 migration 211 applied' as status;
