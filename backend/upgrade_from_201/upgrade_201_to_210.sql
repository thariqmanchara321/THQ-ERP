-- THQ ERP v5.0.0 Build 24 — Upgrade from migration 201 to 210
-- Apply in order. Each migration owns its own transaction.


-- ============================================================================
-- MIGRATION 202: 202_v500_finance_controls.sql
-- ============================================================================

-- THQ ERP v5.0.0 — finance controls, vouchers, financial years, banking and Journal Center.
begin;

create sequence if not exists public.finance_voucher_number_seq_v500;

create table if not exists public.financial_years_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'open' check(status in('open','closed')),
  locked_through date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  closed_by uuid references auth.users(id),
  closed_at timestamptz,
  unique(tenant_id,start_date,end_date),
  check(end_date>=start_date)
);

create table if not exists public.bank_accounts_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  account_name text not null,
  bank_name text,
  account_number_masked text,
  ifsc_code text,
  accounting_account_id uuid not null references public.accounting_accounts(id),
  opening_balance numeric not null default 0,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,account_name)
);

create table if not exists public.finance_vouchers_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id),
  voucher_number text not null,
  voucher_type text not null check(voucher_type in('payment','receipt','contra')),
  voucher_date date not null default current_date,
  amount numeric not null check(amount>0),
  debit_account_id uuid not null references public.accounting_accounts(id),
  credit_account_id uuid not null references public.accounting_accounts(id),
  party_type text,
  party_id uuid,
  payment_method text,
  reference_number text,
  narration text not null,
  journal_id uuid references public.journal_entries(id),
  status text not null default 'posted' check(status in('posted','reversed')),
  reversal_journal_id uuid references public.journal_entries(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  reversed_by uuid references auth.users(id),
  reversed_at timestamptz,
  unique(tenant_id,voucher_number)
);

create table if not exists public.bank_statement_lines_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  bank_account_id uuid not null references public.bank_accounts_v500(id) on delete cascade,
  transaction_date date not null,
  direction text not null check(direction in('debit','credit')),
  amount numeric not null check(amount>0),
  reference text,
  description text,
  matched_journal_id uuid references public.journal_entries(id),
  status text not null default 'unmatched' check(status in('unmatched','matched','ignored')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  matched_by uuid references auth.users(id),
  matched_at timestamptz
);

create table if not exists public.recurring_expenses_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id),
  category_id uuid not null references public.expense_categories(id),
  title text not null,
  payee text,
  description text not null,
  amount numeric not null check(amount>0),
  tax_amount numeric not null default 0 check(tax_amount>=0),
  payment_method text not null default 'cash',
  reference_prefix text,
  frequency text not null default 'monthly' check(frequency in('weekly','monthly','quarterly','yearly')),
  next_run_date date not null,
  last_run_date date,
  active boolean not null default true,
  auto_post boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.financial_years_v500 enable row level security;
alter table public.bank_accounts_v500 enable row level security;
alter table public.finance_vouchers_v500 enable row level security;
alter table public.bank_statement_lines_v500 enable row level security;
alter table public.recurring_expenses_v500 enable row level security;
revoke all on public.financial_years_v500,public.bank_accounts_v500,public.finance_vouchers_v500,public.bank_statement_lines_v500,public.recurring_expenses_v500 from anon,authenticated;

create or replace function private.v500_accounting_access(p_tenant_id uuid,p_manage boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_manage then
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_has_permission(p_tenant_id,'accounting.journal') then raise exception 'Accounting manage permission required';end if;
  else
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'accounting.view') and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_has_permission(p_tenant_id,'accounting.journal') then raise exception 'Accounting permission required';end if;
  end if;
end $$;
revoke all on function private.v500_accounting_access(uuid,boolean) from public;

create or replace function public.financial_years_list_v500(p_tenant_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  perform private.v500_accounting_access(p_tenant_id,false);
  for r in select * from public.financial_years_v500 where tenant_id=p_tenant_id order by start_date desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.financial_years_list_v500(uuid) to authenticated;

create or replace function public.financial_year_save_v500(p_tenant_id uuid,p_year_id uuid,p_name text,p_start_date date,p_end_date date,p_locked_through date default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if p_end_date<p_start_date then raise exception 'Financial year end date cannot be before start date';end if;
  if p_year_id is null then
    insert into public.financial_years_v500(tenant_id,name,start_date,end_date,locked_through,created_by) values(p_tenant_id,trim(p_name),p_start_date,p_end_date,p_locked_through,auth.uid()) returning id into v;
  else
    update public.financial_years_v500 set name=trim(p_name),start_date=p_start_date,end_date=p_end_date,locked_through=p_locked_through where id=p_year_id and tenant_id=p_tenant_id and status='open' returning id into v;
    if v is null then raise exception 'Open financial year not found';end if;
  end if;return v;
end $$;
grant execute on function public.financial_year_save_v500(uuid,uuid,text,date,date,date) to authenticated;

create or replace function public.financial_year_close_v500(p_tenant_id uuid,p_year_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v500_accounting_access(p_tenant_id,true);
  update public.financial_years_v500 set status='closed',locked_through=end_date,closed_by=auth.uid(),closed_at=now() where id=p_year_id and tenant_id=p_tenant_id and status='open';
  if not found then raise exception 'Open financial year not found';end if;
end $$;
grant execute on function public.financial_year_close_v500(uuid,uuid) to authenticated;

create or replace function public.bank_accounts_list_v500(p_tenant_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin perform private.v500_accounting_access(p_tenant_id,false);
  for r in select b.*,a.code account_code,a.name accounting_account_name from public.bank_accounts_v500 b join public.accounting_accounts a on a.id=b.accounting_account_id where b.tenant_id=p_tenant_id order by b.active desc,b.account_name loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.bank_accounts_list_v500(uuid) to authenticated;

create or replace function public.bank_account_save_v500(p_tenant_id uuid,p_bank_account_id uuid,p_account_name text,p_bank_name text,p_account_number_masked text,p_ifsc_code text,p_accounting_account_id uuid,p_opening_balance numeric default 0,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin perform private.v500_accounting_access(p_tenant_id,true);
  if not exists(select 1 from public.accounting_accounts where id=p_accounting_account_id and tenant_id=p_tenant_id and active and account_type='asset') then raise exception 'Active asset accounting account required';end if;
  if p_bank_account_id is null then insert into public.bank_accounts_v500(tenant_id,account_name,bank_name,account_number_masked,ifsc_code,accounting_account_id,opening_balance,active,created_by) values(p_tenant_id,trim(p_account_name),nullif(trim(coalesce(p_bank_name,'')),''),nullif(trim(coalesce(p_account_number_masked,'')),''),nullif(trim(coalesce(p_ifsc_code,'')),''),p_accounting_account_id,coalesce(p_opening_balance,0),coalesce(p_active,true),auth.uid()) returning id into v;
  else update public.bank_accounts_v500 set account_name=trim(p_account_name),bank_name=nullif(trim(coalesce(p_bank_name,'')),''),account_number_masked=nullif(trim(coalesce(p_account_number_masked,'')),''),ifsc_code=nullif(trim(coalesce(p_ifsc_code,'')),''),accounting_account_id=p_accounting_account_id,opening_balance=coalesce(p_opening_balance,0),active=coalesce(p_active,true),updated_at=now() where id=p_bank_account_id and tenant_id=p_tenant_id returning id into v;end if;
  if v is null then raise exception 'Bank account not found';end if;return v;
end $$;
grant execute on function public.bank_account_save_v500(uuid,uuid,text,text,text,text,uuid,numeric,boolean) to authenticated;

create or replace function public.finance_voucher_post_v500(p_tenant_id uuid,p_location_id uuid,p_voucher_type text,p_voucher_date date,p_amount numeric,p_debit_account_id uuid,p_credit_account_id uuid,p_party_type text default null,p_party_id uuid default null,p_payment_method text default null,p_reference_number text default null,p_narration text default '')
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_journal uuid;v_lines jsonb;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if p_voucher_type not in('payment','receipt','contra') then raise exception 'Invalid voucher type';end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Voucher amount must be greater than zero';end if;
  if p_debit_account_id=p_credit_account_id then raise exception 'Debit and credit accounts must be different';end if;
  if not exists(select 1 from public.accounting_accounts where id=p_debit_account_id and tenant_id=p_tenant_id and active) or not exists(select 1 from public.accounting_accounts where id=p_credit_account_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid accounting account';end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'operate');end if;
  v_no:=upper(substr(p_voucher_type,1,3))||'-'||lpad(nextval('public.finance_voucher_number_seq_v500')::text,8,'0');
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',p_debit_account_id,'debit',round(p_amount,2),'credit',0,'party_type',p_party_type,'party_id',p_party_id,'description',coalesce(nullif(trim(p_narration),''),v_no)),
    jsonb_build_object('account_id',p_credit_account_id,'debit',0,'credit',round(p_amount,2),'party_type',p_party_type,'party_id',p_party_id,'description',coalesce(nullif(trim(p_narration),''),v_no))
  );
  v_journal:=private.v4_journal_create(p_tenant_id,p_location_id,coalesce(p_voucher_date,current_date),coalesce(nullif(trim(p_narration),''),initcap(p_voucher_type)||' voucher '||v_no),'finance_voucher_v500',v_id,v_no,v_lines);
  insert into public.finance_vouchers_v500(id,tenant_id,location_id,voucher_number,voucher_type,voucher_date,amount,debit_account_id,credit_account_id,party_type,party_id,payment_method,reference_number,narration,journal_id,created_by)
  values(v_id,p_tenant_id,p_location_id,v_no,p_voucher_type,coalesce(p_voucher_date,current_date),round(p_amount,2),p_debit_account_id,p_credit_account_id,nullif(trim(coalesce(p_party_type,'')),''),p_party_id,nullif(trim(coalesce(p_payment_method,'')),''),nullif(trim(coalesce(p_reference_number,'')),''),coalesce(nullif(trim(p_narration),''),initcap(p_voucher_type)||' voucher'),v_journal,auth.uid());
  return jsonb_build_object('voucher_id',v_id,'voucher_number',v_no,'journal_id',v_journal);
end $$;
grant execute on function public.finance_voucher_post_v500(uuid,uuid,text,date,numeric,uuid,uuid,text,uuid,text,text,text) to authenticated;

create or replace function public.finance_vouchers_list_v500(p_tenant_id uuid,p_from date default null,p_to date default null,p_type text default null,p_query text default '')
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin perform private.v500_accounting_access(p_tenant_id,false);
  for r in select v.*,da.code debit_code,da.name debit_name,ca.code credit_code,ca.name credit_name from public.finance_vouchers_v500 v join public.accounting_accounts da on da.id=v.debit_account_id join public.accounting_accounts ca on ca.id=v.credit_account_id where v.tenant_id=p_tenant_id and (p_from is null or v.voucher_date>=p_from) and (p_to is null or v.voucher_date<=p_to) and (p_type is null or v.voucher_type=p_type) and (trim(coalesce(p_query,''))='' or lower(v.voucher_number) like q or lower(coalesce(v.reference_number,'')) like q or lower(v.narration) like q) order by v.voucher_date desc,v.created_at desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.finance_vouchers_list_v500(uuid,date,date,text,text) to authenticated;

create or replace function public.journal_center_list_v500(p_tenant_id uuid,p_from date default null,p_to date default null,p_query text default '',p_status text default null,p_limit integer default 1000)
returns table(journal_id uuid,entry_number text,entry_date date,description text,status text,source_type text,source_id uuid,source_reference text,location_id uuid,location_name text,total_debit numeric,total_credit numeric,line_count bigint,created_at timestamptz,created_by uuid)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin perform private.v500_accounting_access(p_tenant_id,false);
  return query select j.id,j.entry_number,j.entry_date,j.description,j.status,coalesce(j.source_type,''),j.source_id,coalesce(j.source_reference,''),j.location_id,coalesce(l.location_code||' • '||l.name,l.name,''),coalesce(sum(x.debit),0)::numeric,coalesce(sum(x.credit),0)::numeric,count(x.id),j.created_at,j.created_by
  from public.journal_entries j left join public.journal_lines x on x.journal_entry_id=j.id left join public.business_locations l on l.id=j.location_id
  where j.tenant_id=p_tenant_id and (p_from is null or j.entry_date>=p_from) and (p_to is null or j.entry_date<=p_to) and (p_status is null or j.status=p_status) and (trim(coalesce(p_query,''))='' or lower(j.entry_number) like q or lower(j.description) like q or lower(coalesce(j.source_reference,'')) like q or lower(coalesce(j.source_type,'')) like q)
  group by j.id,l.id order by j.entry_date desc,j.created_at desc limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.journal_center_list_v500(uuid,date,date,text,text,integer) to authenticated;

create or replace function public.journal_center_detail_v500(p_tenant_id uuid,p_journal_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare h jsonb;lines jsonb;begin perform private.v500_accounting_access(p_tenant_id,false);
  select to_jsonb(j) into h from public.journal_entries j where j.id=p_journal_id and j.tenant_id=p_tenant_id;if h is null then raise exception 'Journal not found';end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_id',l.id,'account_id',l.account_id,'account_code',a.code,'account_name',a.name,'account_type',a.account_type,'party_type',l.party_type,'party_id',l.party_id,'description',l.description,'debit',l.debit,'credit',l.credit) order by a.code,l.id),'[]'::jsonb) into lines from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=p_journal_id;
  return jsonb_build_object('journal',h,'lines',lines,'balanced',abs(coalesce((select sum(debit-credit) from public.journal_lines where journal_entry_id=p_journal_id),0))<=0.005);
end $$;
grant execute on function public.journal_center_detail_v500(uuid,uuid) to authenticated;

create or replace function public.journal_reverse_v500(p_tenant_id uuid,p_journal_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare j public.journal_entries%rowtype;x record;v_lines jsonb:='[]'::jsonb;v_new uuid;begin
  perform private.v500_accounting_access(p_tenant_id,true);
  if trim(coalesce(p_reason,''))='' then raise exception 'Reversal reason is required';end if;
  select * into j from public.journal_entries where id=p_journal_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Journal not found';end if;
  if j.status<>'posted' then raise exception 'Only posted journals can be reversed';end if;
  for x in select * from public.journal_lines where journal_entry_id=j.id order by id loop v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',x.account_id,'debit',x.credit,'credit',x.debit,'party_type',x.party_type,'party_id',x.party_id,'description','Reversal: '||coalesce(x.description,j.description)));end loop;
  update public.journal_entries set status='reversed' where id=j.id;
  v_new:=private.v4_journal_create(p_tenant_id,j.location_id,current_date,'Reversal of '||j.entry_number||' • '||trim(p_reason),'journal_reversal_v500',j.id,j.entry_number,v_lines);
  update public.journal_entries set reversal_of=j.id where id=v_new;
  update public.finance_vouchers_v500 set status='reversed',reversal_journal_id=v_new,reversed_by=auth.uid(),reversed_at=now() where tenant_id=p_tenant_id and journal_id=j.id;
  return v_new;
end $$;
grant execute on function public.journal_reverse_v500(uuid,uuid,text) to authenticated;

create or replace function public.bank_statement_line_save_v500(p_tenant_id uuid,p_bank_account_id uuid,p_line_id uuid,p_transaction_date date,p_direction text,p_amount numeric,p_reference text,p_description text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin perform private.v500_accounting_access(p_tenant_id,true);
  if not exists(select 1 from public.bank_accounts_v500 where id=p_bank_account_id and tenant_id=p_tenant_id) then raise exception 'Bank account not found';end if;
  if p_direction not in('debit','credit') or coalesce(p_amount,0)<=0 then raise exception 'Invalid statement transaction';end if;
  if p_line_id is null then insert into public.bank_statement_lines_v500(tenant_id,bank_account_id,transaction_date,direction,amount,reference,description,created_by) values(p_tenant_id,p_bank_account_id,p_transaction_date,p_direction,p_amount,nullif(trim(coalesce(p_reference,'')),''),nullif(trim(coalesce(p_description,'')),''),auth.uid()) returning id into v;
  else update public.bank_statement_lines_v500 set transaction_date=p_transaction_date,direction=p_direction,amount=p_amount,reference=nullif(trim(coalesce(p_reference,'')),''),description=nullif(trim(coalesce(p_description,'')),'') where id=p_line_id and tenant_id=p_tenant_id and status='unmatched' returning id into v;end if;
  if v is null then raise exception 'Unmatched bank statement line not found';end if;return v;
end $$;
grant execute on function public.bank_statement_line_save_v500(uuid,uuid,uuid,date,text,numeric,text,text) to authenticated;

create or replace function public.bank_statement_list_v500(p_tenant_id uuid,p_bank_account_id uuid,p_from date default null,p_to date default null,p_status text default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin perform private.v500_accounting_access(p_tenant_id,false);
  for r in select s.*,j.entry_number,j.description journal_description from public.bank_statement_lines_v500 s left join public.journal_entries j on j.id=s.matched_journal_id where s.tenant_id=p_tenant_id and s.bank_account_id=p_bank_account_id and (p_from is null or s.transaction_date>=p_from) and (p_to is null or s.transaction_date<=p_to) and (p_status is null or s.status=p_status) order by s.transaction_date desc,s.created_at desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.bank_statement_list_v500(uuid,uuid,date,date,text) to authenticated;

create or replace function public.bank_statement_match_v500(p_tenant_id uuid,p_line_id uuid,p_journal_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin perform private.v500_accounting_access(p_tenant_id,true);
  if not exists(select 1 from public.journal_entries where id=p_journal_id and tenant_id=p_tenant_id and status='posted') then raise exception 'Posted journal not found';end if;
  update public.bank_statement_lines_v500 set matched_journal_id=p_journal_id,status='matched',matched_by=auth.uid(),matched_at=now() where id=p_line_id and tenant_id=p_tenant_id and status='unmatched';if not found then raise exception 'Unmatched bank statement line not found';end if;
end $$;
grant execute on function public.bank_statement_match_v500(uuid,uuid,uuid) to authenticated;

create or replace function public.recurring_expenses_list_v500(p_tenant_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;begin perform private.v500_accounting_access(p_tenant_id,false);for r in select e.*,c.name category_name,l.location_code,l.name location_name from public.recurring_expenses_v500 e join public.expense_categories c on c.id=e.category_id join public.business_locations l on l.id=e.location_id where e.tenant_id=p_tenant_id order by e.active desc,e.next_run_date,e.title loop return next to_jsonb(r);end loop;return;end $$;
grant execute on function public.recurring_expenses_list_v500(uuid) to authenticated;

create or replace function public.recurring_expense_save_v500(p_tenant_id uuid,p_id uuid,p_location_id uuid,p_category_id uuid,p_title text,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,p_payment_method text,p_frequency text,p_next_run_date date,p_auto_post boolean,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;begin perform private.v500_accounting_access(p_tenant_id,true);perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if p_frequency not in('weekly','monthly','quarterly','yearly') then raise exception 'Invalid recurrence frequency';end if;if coalesce(p_amount,0)<=0 then raise exception 'Amount must be positive';end if;
  if p_id is null then insert into public.recurring_expenses_v500(tenant_id,location_id,category_id,title,payee,description,amount,tax_amount,payment_method,frequency,next_run_date,auto_post,active,created_by) values(p_tenant_id,p_location_id,p_category_id,trim(p_title),nullif(trim(coalesce(p_payee,'')),''),trim(p_description),p_amount,coalesce(p_tax_amount,0),coalesce(nullif(trim(p_payment_method),''),'cash'),p_frequency,p_next_run_date,coalesce(p_auto_post,false),coalesce(p_active,true),auth.uid()) returning id into v;
  else update public.recurring_expenses_v500 set location_id=p_location_id,category_id=p_category_id,title=trim(p_title),payee=nullif(trim(coalesce(p_payee,'')),''),description=trim(p_description),amount=p_amount,tax_amount=coalesce(p_tax_amount,0),payment_method=coalesce(nullif(trim(p_payment_method),''),'cash'),frequency=p_frequency,next_run_date=p_next_run_date,auto_post=coalesce(p_auto_post,false),active=coalesce(p_active,true),updated_at=now() where id=p_id and tenant_id=p_tenant_id returning id into v;end if;
  if v is null then raise exception 'Recurring expense not found';end if;return v;
end $$;
grant execute on function public.recurring_expense_save_v500(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,text,text,date,boolean,boolean) to authenticated;

create or replace function public.recurring_expenses_process_v500(p_tenant_id uuid,p_through_date date default current_date)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r public.recurring_expenses_v500%rowtype;v_result jsonb;v_count integer:=0;v_next date;v_request text;begin perform private.v500_accounting_access(p_tenant_id,true);
  for r in select * from public.recurring_expenses_v500 where tenant_id=p_tenant_id and active and auto_post and next_run_date<=coalesce(p_through_date,current_date) order by next_run_date for update loop
    v_request:='recurring-expense:'||r.id::text||':'||r.next_run_date::text;
    v_result:=public.expenses_create_v489(r.tenant_id,r.category_id,r.next_run_date,r.payee,r.description,r.amount,r.tax_amount,0,r.payment_method,coalesce(r.reference_prefix,'REC')||'-'||to_char(r.next_run_date,'YYYYMMDD'),'Recurring expense: '||r.title,r.location_id,null,v_request);
    v_next:=case r.frequency when 'weekly' then r.next_run_date+7 when 'monthly' then (r.next_run_date+interval '1 month')::date when 'quarterly' then (r.next_run_date+interval '3 months')::date else (r.next_run_date+interval '1 year')::date end;
    update public.recurring_expenses_v500 set last_run_date=r.next_run_date,next_run_date=v_next,updated_at=now() where id=r.id;v_count:=v_count+1;
  end loop;return jsonb_build_object('processed',v_count,'through_date',coalesce(p_through_date,current_date));
end $$;
grant execute on function public.recurring_expenses_process_v500(uuid,date) to authenticated;

create or replace function public.finance_controls_summary_v500(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_unmatched bigint;v_due bigint;v_open_years bigint;v_banks bigint;begin perform private.v500_accounting_access(p_tenant_id,false);
 select count(*) into v_unmatched from public.bank_statement_lines_v500 where tenant_id=p_tenant_id and status='unmatched';select count(*) into v_due from public.recurring_expenses_v500 where tenant_id=p_tenant_id and active and next_run_date<=current_date;select count(*) into v_open_years from public.financial_years_v500 where tenant_id=p_tenant_id and status='open';select count(*) into v_banks from public.bank_accounts_v500 where tenant_id=p_tenant_id and active;return jsonb_build_object('unmatched_bank_lines',v_unmatched,'due_recurring_expenses',v_due,'open_financial_years',v_open_years,'active_bank_accounts',v_banks,'reconciliation',public.finance_reconciliation_v491(p_tenant_id));end $$;
grant execute on function public.finance_controls_summary_v500(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(202,'5.0.0','Finance Controls & Journal Center','Financial years, payment/receipt/contra vouchers, bank accounts/reconciliation, recurring expenses and safe journal detail/reversal controls.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 202 applied' as status;


-- ============================================================================
-- MIGRATION 203: 203_v500_crm_purchasing_intelligence.sql
-- ============================================================================

-- THQ ERP v5.0.0 — CRM, supplier quotations/performance and smart reorder intelligence.
begin;

create table if not exists public.customer_groups_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  description text,
  discount_percent numeric not null default 0 check(discount_percent between 0 and 100),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(tenant_id,name)
);

create table if not exists public.customer_crm_profiles_v500(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  group_id uuid references public.customer_groups_v500(id) on delete set null,
  salesperson_user_id uuid references auth.users(id) on delete set null,
  birthday date,
  anniversary date,
  loyalty_points numeric not null default 0,
  notes text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,customer_id)
);

create table if not exists public.customer_loyalty_ledger_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  points numeric not null,
  source_type text not null,
  source_id uuid,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create sequence if not exists public.purchase_quotation_number_seq_v500;
create table if not exists public.purchase_quotations_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id uuid references public.purchase_requests_v484(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  quotation_number text not null,
  supplier_quote_reference text,
  quote_date date not null default current_date,
  valid_until date,
  expected_delivery_date date,
  payment_terms text,
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  grand_total numeric not null default 0,
  status text not null default 'received' check(status in('draft','received','selected','rejected','expired','converted')),
  notes text,
  converted_purchase_order_id uuid references public.purchase_orders_v480(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,quotation_number)
);

create table if not exists public.purchase_quotation_items_v500(
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.purchase_quotations_v500(id) on delete cascade,
  request_item_id uuid references public.purchase_request_items_v484(id) on delete set null,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tax_rate numeric not null default 0 check(tax_rate>=0),
  line_total numeric not null default 0,
  note text
);

alter table public.customer_groups_v500 enable row level security;
alter table public.customer_crm_profiles_v500 enable row level security;
alter table public.customer_loyalty_ledger_v500 enable row level security;
alter table public.purchase_quotations_v500 enable row level security;
alter table public.purchase_quotation_items_v500 enable row level security;
revoke all on public.customer_groups_v500,public.customer_crm_profiles_v500,public.customer_loyalty_ledger_v500,public.purchase_quotations_v500,public.purchase_quotation_items_v500 from anon,authenticated;

create or replace function private.v500_customer_manage_access(p_tenant_id uuid)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'customers.manage') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Customer management permission required';end if;
end $$;
revoke all on function private.v500_customer_manage_access(uuid) from public;

create or replace function public.customer_groups_list_v500(p_tenant_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select * from public.customer_groups_v500 where tenant_id=p_tenant_id order by active desc,name loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.customer_groups_list_v500(uuid) to authenticated;

create or replace function public.customer_group_save_v500(p_tenant_id uuid,p_group_id uuid,p_name text,p_description text,p_discount_percent numeric,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v uuid;begin
  perform private.v500_customer_manage_access(p_tenant_id);
  if trim(coalesce(p_name,''))='' then raise exception 'Group name is required';end if;if coalesce(p_discount_percent,0)<0 or coalesce(p_discount_percent,0)>100 then raise exception 'Invalid group discount';end if;
  if p_group_id is null then insert into public.customer_groups_v500(tenant_id,name,description,discount_percent,active,created_by) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_description,'')),''),coalesce(p_discount_percent,0),coalesce(p_active,true),auth.uid()) returning id into v;
  else update public.customer_groups_v500 set name=trim(p_name),description=nullif(trim(coalesce(p_description,'')),''),discount_percent=coalesce(p_discount_percent,0),active=coalesce(p_active,true) where id=p_group_id and tenant_id=p_tenant_id returning id into v;end if;
  if v is null then raise exception 'Customer group not found';end if;return v;
end $$;
grant execute on function public.customer_group_save_v500(uuid,uuid,text,text,numeric,boolean) to authenticated;

create or replace function public.customer_crm_profile_v500(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare c jsonb;crm jsonb;v_sales numeric:=0;v_returns numeric:=0;v_paid numeric:=0;v_outstanding numeric:=0;v_loans_given numeric:=0;v_loans_taken numeric:=0;v_last_sale date;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select to_jsonb(x) into c from public.customers x where x.tenant_id=p_tenant_id and x.id=p_customer_id;if c is null then raise exception 'Customer not found';end if;
  select jsonb_build_object('group_id',p.group_id,'group_name',g.name,'group_discount_percent',coalesce(g.discount_percent,0),'salesperson_user_id',p.salesperson_user_id,'birthday',p.birthday,'anniversary',p.anniversary,'loyalty_points',coalesce(p.loyalty_points,0),'notes',p.notes) into crm from public.customer_crm_profiles_v500 p left join public.customer_groups_v500 g on g.id=p.group_id where p.tenant_id=p_tenant_id and p.customer_id=p_customer_id;
  select coalesce(sum(s.grand_total),0),max(s.sale_date) into v_sales,v_last_sale from public.sales s where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled');
  select coalesce(sum(r.grand_total),0) into v_returns from public.sales_returns r join public.sales s on s.id=r.sale_id where r.tenant_id=p_tenant_id and s.customer_id=p_customer_id and r.refund_status<>'waived';
  select coalesce(sum(sp.amount),0) into v_paid from public.sale_payments sp join public.sales s on s.id=sp.sale_id where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id;
  v_outstanding:=greatest(v_sales-v_returns-v_paid,0);
  if to_regclass('public.loan_accounts_v490') is not null then
    select coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding),0) into v_loans_given from public.loan_accounts_v490 where tenant_id=p_tenant_id and client_id=p_customer_id and direction='given' and status in('active','defaulted');
    select coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding),0) into v_loans_taken from public.loan_accounts_v490 where tenant_id=p_tenant_id and client_id=p_customer_id and direction='taken' and status in('active','defaulted');
  end if;
  return jsonb_build_object('customer',c,'crm',coalesce(crm,'{}'::jsonb),'summary',jsonb_build_object('gross_sales',v_sales,'returns',v_returns,'payments',v_paid,'outstanding_sales',v_outstanding,'loan_receivable',v_loans_given,'loan_payable',v_loans_taken,'last_sale_date',v_last_sale));
end $$;
grant execute on function public.customer_crm_profile_v500(uuid,uuid) to authenticated;

create or replace function public.customer_crm_save_v500(p_tenant_id uuid,p_customer_id uuid,p_group_id uuid,p_salesperson_user_id uuid,p_birthday date,p_anniversary date,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  perform private.v500_customer_manage_access(p_tenant_id);if not exists(select 1 from public.customers where tenant_id=p_tenant_id and id=p_customer_id) then raise exception 'Customer not found';end if;
  if p_group_id is not null and not exists(select 1 from public.customer_groups_v500 where tenant_id=p_tenant_id and id=p_group_id and active) then raise exception 'Customer group not found';end if;
  insert into public.customer_crm_profiles_v500(tenant_id,customer_id,group_id,salesperson_user_id,birthday,anniversary,notes,updated_by,updated_at) values(p_tenant_id,p_customer_id,p_group_id,p_salesperson_user_id,p_birthday,p_anniversary,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),now()) on conflict(tenant_id,customer_id) do update set group_id=excluded.group_id,salesperson_user_id=excluded.salesperson_user_id,birthday=excluded.birthday,anniversary=excluded.anniversary,notes=excluded.notes,updated_by=auth.uid(),updated_at=now();
end $$;
grant execute on function public.customer_crm_save_v500(uuid,uuid,uuid,uuid,date,date,text) to authenticated;

create or replace function public.customer_loyalty_adjust_v500(p_tenant_id uuid,p_customer_id uuid,p_points numeric,p_source_type text,p_source_id uuid,p_note text)
returns numeric language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v numeric;begin
  perform private.v500_customer_manage_access(p_tenant_id);if coalesce(p_points,0)=0 then raise exception 'Points adjustment cannot be zero';end if;
  insert into public.customer_crm_profiles_v500(tenant_id,customer_id,loyalty_points,updated_by) values(p_tenant_id,p_customer_id,0,auth.uid()) on conflict(tenant_id,customer_id) do nothing;
  update public.customer_crm_profiles_v500 set loyalty_points=greatest(loyalty_points+p_points,0),updated_by=auth.uid(),updated_at=now() where tenant_id=p_tenant_id and customer_id=p_customer_id returning loyalty_points into v;
  insert into public.customer_loyalty_ledger_v500(tenant_id,customer_id,points,source_type,source_id,note,created_by) values(p_tenant_id,p_customer_id,p_points,coalesce(nullif(trim(p_source_type),''),'manual'),p_source_id,nullif(trim(coalesce(p_note,'')),''),auth.uid());return v;
end $$;
grant execute on function public.customer_loyalty_adjust_v500(uuid,uuid,numeric,text,uuid,text) to authenticated;

create or replace function public.purchase_quotation_save_v500(p_tenant_id uuid,p_quotation_id uuid,p_request_id uuid,p_location_id uuid,p_supplier_id uuid,p_supplier_quote_reference text,p_quote_date date,p_valid_until date,p_expected_delivery_date date,p_payment_terms text,p_items jsonb,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_no text;x jsonb;v_qty numeric;v_cost numeric;v_tax numeric;v_sub numeric:=0;v_tax_total numeric:=0;v_line numeric;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active') then raise exception 'Active supplier not found';end if;
  if p_request_id is not null and not exists(select 1 from public.purchase_requests_v484 where id=p_request_id and tenant_id=p_tenant_id and location_id=p_location_id and status in('submitted','approved')) then raise exception 'Eligible purchase request not found';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Quotation items are required';end if;
  if p_quotation_id is null then v_id:=gen_random_uuid();v_no:='PQT-'||to_char(coalesce(p_quote_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.purchase_quotation_number_seq_v500')::text,6,'0');insert into public.purchase_quotations_v500(id,tenant_id,request_id,location_id,supplier_id,quotation_number,supplier_quote_reference,quote_date,valid_until,expected_delivery_date,payment_terms,notes,created_by) values(v_id,p_tenant_id,p_request_id,p_location_id,p_supplier_id,v_no,nullif(trim(coalesce(p_supplier_quote_reference,'')),''),coalesce(p_quote_date,current_date),p_valid_until,p_expected_delivery_date,nullif(trim(coalesce(p_payment_terms,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  else select id,quotation_number into v_id,v_no from public.purchase_quotations_v500 where id=p_quotation_id and tenant_id=p_tenant_id and status in('draft','received') for update;if v_id is null then raise exception 'Editable quotation not found';end if;delete from public.purchase_quotation_items_v500 where quotation_id=v_id;update public.purchase_quotations_v500 set request_id=p_request_id,location_id=p_location_id,supplier_id=p_supplier_id,supplier_quote_reference=nullif(trim(coalesce(p_supplier_quote_reference,'')),''),quote_date=coalesce(p_quote_date,current_date),valid_until=p_valid_until,expected_delivery_date=p_expected_delivery_date,payment_terms=nullif(trim(coalesce(p_payment_terms,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=v_id;end if;
  for x in select value from jsonb_array_elements(p_items) loop v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=greatest(coalesce(nullif(x->>'unit_cost','')::numeric,0),0);v_tax:=greatest(coalesce(nullif(x->>'tax_rate','')::numeric,0),0);if v_qty<=0 or nullif(x->>'variant_id','') is null then raise exception 'Invalid quotation item';end if;v_line:=round(v_qty*v_cost,2);v_sub:=v_sub+v_line;v_tax_total:=v_tax_total+round(v_line*v_tax/100,2);insert into public.purchase_quotation_items_v500(quotation_id,request_item_id,variant_id,quantity,unit_cost,tax_rate,line_total,note) values(v_id,nullif(x->>'request_item_id','')::uuid,(x->>'variant_id')::uuid,v_qty,v_cost,v_tax,round(v_line+v_line*v_tax/100,2),nullif(trim(coalesce(x->>'note','')),''));end loop;
  update public.purchase_quotations_v500 set subtotal=v_sub,tax_total=v_tax_total,grand_total=round(v_sub+v_tax_total,2),status='received',updated_at=now() where id=v_id;return jsonb_build_object('quotation_id',v_id,'quotation_number',v_no,'grand_total',round(v_sub+v_tax_total,2));
end $$;
grant execute on function public.purchase_quotation_save_v500(uuid,uuid,uuid,uuid,uuid,text,date,date,date,text,jsonb,text) to authenticated;

create or replace function public.purchase_quotations_list_v500(p_tenant_id uuid,p_request_id uuid default null,p_status text default null,p_query text default '')
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin perform private.purchasing_v484_permission(p_tenant_id,false);
  for r in select qh.*,s.name supplier_name,s.phone supplier_phone,pr.request_number,po.order_number converted_order_number from public.purchase_quotations_v500 qh join public.suppliers s on s.id=qh.supplier_id left join public.purchase_requests_v484 pr on pr.id=qh.request_id left join public.purchase_orders_v480 po on po.id=qh.converted_purchase_order_id where qh.tenant_id=p_tenant_id and (p_request_id is null or qh.request_id=p_request_id) and (p_status is null or qh.status=p_status) and (trim(coalesce(p_query,''))='' or lower(qh.quotation_number) like q or lower(s.name) like q or lower(coalesce(qh.supplier_quote_reference,'')) like q) order by qh.quote_date desc,qh.created_at desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.purchase_quotations_list_v500(uuid,uuid,text,text) to authenticated;

create or replace function public.purchase_quotation_detail_v500(p_tenant_id uuid,p_quotation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare h jsonb;i jsonb;begin perform private.purchasing_v484_permission(p_tenant_id,false);select to_jsonb(q) into h from public.purchase_quotations_v500 q where q.id=p_quotation_id and q.tenant_id=p_tenant_id;if h is null then raise exception 'Quotation not found';end if;select coalesce(jsonb_agg(jsonb_build_object('id',qi.id,'variant_id',qi.variant_id,'product_name',p.name,'sku',pv.sku,'quantity',qi.quantity,'unit_cost',qi.unit_cost,'tax_rate',qi.tax_rate,'line_total',qi.line_total,'request_item_id',qi.request_item_id,'note',qi.note) order by p.name),'[]'::jsonb) into i from public.purchase_quotation_items_v500 qi join public.product_variants pv on pv.id=qi.variant_id join public.products p on p.id=pv.product_id where qi.quotation_id=p_quotation_id;return jsonb_build_object('quotation',h,'items',i);end $$;
grant execute on function public.purchase_quotation_detail_v500(uuid,uuid) to authenticated;

create or replace function public.purchase_quotation_convert_v500(p_tenant_id uuid,p_quotation_id uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare q public.purchase_quotations_v500%rowtype;v_items jsonb;v_po jsonb;v_po_id uuid;begin
  select * into q from public.purchase_quotations_v500 where id=p_quotation_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Quotation not found';end if;perform private.purchasing_v484_access(p_tenant_id,q.location_id,true);if q.status not in('received','selected') then raise exception 'Only received/selected quotation can be converted';end if;
  select coalesce(jsonb_agg(jsonb_build_object('variant_id',i.variant_id,'quantity',i.quantity,'unit_cost',i.unit_cost,'tax_rate',i.tax_rate,'note',i.note)),'[]'::jsonb) into v_items from public.purchase_quotation_items_v500 i where i.quotation_id=q.id;
  v_po:=public.purchase_order_create_v484(p_tenant_id,q.location_id,q.supplier_id,v_items,q.expected_delivery_date,concat_ws(' • ',nullif(trim(coalesce(p_notes,'')),''),'Quotation '||q.quotation_number),q.request_id);v_po_id:=nullif(v_po->>'purchase_order_id','')::uuid;
  update public.purchase_quotations_v500 set status='converted',converted_purchase_order_id=v_po_id,updated_at=now() where id=q.id;update public.purchase_quotations_v500 set status='rejected',updated_at=now() where tenant_id=p_tenant_id and request_id=q.request_id and id<>q.id and status in('received','selected');return v_po||jsonb_build_object('quotation_id',q.id,'quotation_number',q.quotation_number);
end $$;
grant execute on function public.purchase_quotation_convert_v500(uuid,uuid,text) to authenticated;

create or replace function public.supplier_performance_v500(p_tenant_id uuid,p_from date default null,p_to date default null,p_limit integer default 500)
returns table(supplier_id uuid,supplier_name text,purchase_value numeric,po_count bigint,grn_count bigint,accepted_qty numeric,damaged_qty numeric,rejected_qty numeric,damage_reject_pct numeric,on_time_pct numeric,avg_delivery_days numeric,last_purchase_date date)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin perform private.purchasing_v484_permission(p_tenant_id,false);
  return query with po as(select p.supplier_id,count(*) po_count,max(p.order_date) last_purchase,coalesce(sum(p.grand_total),0) value from public.purchase_orders_v480 p where p.tenant_id=p_tenant_id and p.status<>'cancelled' and (p_from is null or p.order_date>=p_from) and (p_to is null or p.order_date<=p_to) group by p.supplier_id),gr as(select g.supplier_id,count(distinct g.id) grn_count,coalesce(sum(i.accepted_quantity),0) accepted,coalesce(sum(i.damaged_quantity),0) damaged,coalesce(sum(i.rejected_quantity),0) rejected,avg(g.receipt_date-po2.order_date)::numeric avg_days,avg(case when po2.expected_date is null or g.receipt_date<=po2.expected_date then 100 else 0 end)::numeric ontime from public.goods_receipts_v484 g join public.goods_receipt_items_v484 i on i.goods_receipt_id=g.id join public.purchase_orders_v480 po2 on po2.id=g.purchase_order_id where g.tenant_id=p_tenant_id and g.status='posted' and (p_from is null or g.receipt_date>=p_from) and (p_to is null or g.receipt_date<=p_to) group by g.supplier_id) select s.id,s.name,coalesce(po.value,0)::numeric,coalesce(po.po_count,0),coalesce(gr.grn_count,0),coalesce(gr.accepted,0)::numeric,coalesce(gr.damaged,0)::numeric,coalesce(gr.rejected,0)::numeric,case when coalesce(gr.accepted,0)+coalesce(gr.damaged,0)+coalesce(gr.rejected,0)>0 then round((coalesce(gr.damaged,0)+coalesce(gr.rejected,0))*100/(coalesce(gr.accepted,0)+coalesce(gr.damaged,0)+coalesce(gr.rejected,0)),2) else 0 end::numeric,round(coalesce(gr.ontime,0),2)::numeric,round(coalesce(gr.avg_days,0),2)::numeric,po.last_purchase from public.suppliers s left join po on po.supplier_id=s.id left join gr on gr.supplier_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active' order by coalesce(po.value,0) desc,s.name limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.supplier_performance_v500(uuid,date,date,integer) to authenticated;

create or replace function public.reorder_suggestions_v500(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30,p_query text default '',p_limit integer default 1000)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;v_supplier uuid;v_supplier_name text;v_last_cost numeric;begin
  for r in select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,p_query,p_limit) where status in('out_of_stock','low_stock') and suggested_reorder>0 loop
    select p.supplier_id,s.name,pi.unit_cost into v_supplier,v_supplier_name,v_last_cost from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id join public.suppliers s on s.id=p.supplier_id where p.tenant_id=p_tenant_id and pi.variant_id=r.variant_id and coalesce(p.status,'') not in('void','cancelled') order by p.purchase_date desc,p.created_at desc limit 1;
    return next to_jsonb(r)||jsonb_build_object('suggested_supplier_id',v_supplier,'suggested_supplier_name',v_supplier_name,'last_unit_cost',coalesce(v_last_cost,r.average_cost));
  end loop;return;
end $$;
grant execute on function public.reorder_suggestions_v500(uuid,uuid,integer,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(203,'5.0.0','CRM & Purchasing Intelligence','Customer groups/CRM/loyalty, supplier quotation comparison and conversion, supplier performance and smart reorder recommendations.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 203 applied' as status;


-- ============================================================================
-- MIGRATION 204: 204_v500_reports_center.sql
-- ============================================================================

-- THQ ERP v5.0.0 — centralized Reports Center and detailed returns reporting.
begin;

create or replace function public.reports_catalog_v500()
returns jsonb language sql immutable as $$
select jsonb_build_array(
  jsonb_build_object('category','Sales','reports',jsonb_build_array('sales_summary','sales_register','sales_by_product','sales_by_customer','sales_by_salesperson','sales_by_store','sales_by_pos','sales_by_payment_method','returns')),
  jsonb_build_object('category','Inventory','reports',jsonb_build_array('current_stock','stock_valuation','stock_movement','stock_aging','expiry','dead_stock','low_stock','serials','batches')),
  jsonb_build_object('category','Purchase','reports',jsonb_build_array('purchase_register','supplier_purchase','purchase_returns','supplier_outstanding','supplier_performance','price_history')),
  jsonb_build_object('category','Accounting','reports',jsonb_build_array('profit_loss','balance_sheet','trial_balance','general_ledger','cash_flow','receivables','payables','journal_register','expenses','tax','reconciliation'))
)
$$;
grant execute on function public.reports_catalog_v500() to authenticated;

create or replace function public.returns_report_v500(
  p_tenant_id uuid,p_kind text default 'all',p_from date default null,p_to date default null,p_location_id uuid default null,p_query text default '',p_limit integer default 5000
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if lower(coalesce(p_kind,'all')) not in('all','sales','purchase') then raise exception 'Invalid return type';end if;
  for r in
    with rows as (
      select
        'sales'::text return_side,sr.id return_id,sr.return_number::text return_number,sr.return_date return_date,
        s.id source_id,coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text source_number,
        c.id party_id,c.name::text party_name,'customer'::text party_type,
        sri.variant_id,p.name::text product_name,pv.sku::text sku,pv.barcode::text barcode,pv.part_number::text part_number,
        pia.hsn_sac::text hsn_sac,coalesce(pia.unit_code,'')::text unit_code,
        sri.quantity::numeric quantity,sri.unit_price::numeric unit_rate,sri.discount_amount::numeric discount_amount,sri.tax_rate::numeric tax_rate,
        round(greatest(sri.line_total-((sri.unit_price*sri.quantity)-sri.discount_amount),0),2)::numeric tax_amount,
        round((sri.unit_price*sri.quantity)-sri.discount_amount,2)::numeric taxable_amount,sri.line_total::numeric line_total,
        sr.subtotal::numeric document_subtotal,sr.tax_total::numeric document_tax,sr.grand_total::numeric document_total,
        sr.reason::text reason,sr.refund_status::text settlement_status,
        sr.location_id,bl.location_code::text location_code,bl.name::text location_name,sr.created_by,sr.created_at,
        (select j.id from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sales_return' and j.source_id=sr.id and j.status='posted' limit 1) accounting_journal_id,
        'inventory_in / cogs_reversal / output_tax_reversal / customer_credit_or_ar'::text accounting_effect
      from public.sales_returns sr
      join public.sales_return_items sri on sri.sales_return_id=sr.id
      join public.sales s on s.id=sr.sale_id
      join public.customers c on c.id=s.customer_id
      join public.product_variants pv on pv.id=sri.variant_id
      join public.products p on p.id=pv.product_id
      left join public.product_invoice_attributes_v45 pia on pia.tenant_id=sr.tenant_id and pia.variant_id=sri.variant_id
      left join public.business_locations bl on bl.id=sr.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where sr.tenant_id=p_tenant_id and sr.refund_status<>'waived'
        and (p_from is null or sr.return_date>=p_from) and (p_to is null or sr.return_date<=p_to)
        and (p_location_id is null or sr.location_id=p_location_id)
      union all
      select
        'purchase'::text,pr.id,pr.return_number::text,pr.return_date,
        pch.id,coalesce(dn.terminal_number,ln.local_number,pch.purchase_number)::text,
        s.id,s.name::text,'supplier'::text,
        pri.variant_id,prod.name::text,pv.sku::text,pv.barcode::text,pv.part_number::text,
        pia.hsn_sac::text,coalesce(pia.unit_code,'')::text,
        pri.quantity::numeric,pri.unit_cost::numeric,pri.discount_amount::numeric,pri.tax_rate::numeric,
        round(greatest(pri.line_total-((pri.unit_cost*pri.quantity)-pri.discount_amount),0),2)::numeric,
        round((pri.unit_cost*pri.quantity)-pri.discount_amount,2)::numeric,pri.line_total::numeric,
        pr.subtotal::numeric,pr.tax_total::numeric,pr.grand_total::numeric,
        pr.reason::text,pr.credit_status::text,
        pr.location_id,bl.location_code::text,bl.name::text,pr.created_by,pr.created_at,
        (select j.id from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_return' and j.source_id=pr.id and j.status='posted' limit 1),
        'inventory_out / input_tax_reversal / supplier_credit_or_ap'::text
      from public.purchase_returns pr
      join public.purchase_return_items pri on pri.purchase_return_id=pr.id
      join public.purchases pch on pch.id=pr.purchase_id
      join public.suppliers s on s.id=pch.supplier_id
      join public.product_variants pv on pv.id=pri.variant_id
      join public.products prod on prod.id=pv.product_id
      left join public.product_invoice_attributes_v45 pia on pia.tenant_id=pr.tenant_id and pia.variant_id=pri.variant_id
      left join public.business_locations bl on bl.id=pr.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=pch.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=pch.id
      where pr.tenant_id=p_tenant_id and pr.credit_status<>'waived'
        and (p_from is null or pr.return_date>=p_from) and (p_to is null or pr.return_date<=p_to)
        and (p_location_id is null or pr.location_id=p_location_id)
    )
    select * from rows x
    where (lower(coalesce(p_kind,'all'))='all' or x.return_side=lower(p_kind))
      and (trim(coalesce(p_query,''))='' or lower(x.return_number) like q or lower(coalesce(x.source_number,'')) like q or lower(x.party_name) like q or lower(x.product_name) like q or lower(coalesce(x.sku,'')) like q or lower(coalesce(x.barcode,'')) like q or lower(coalesce(x.hsn_sac,'')) like q or lower(coalesce(x.reason,'')) like q)
    order by return_date desc,created_at desc
    limit greatest(1,least(coalesce(p_limit,5000),10000))
  loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.returns_report_v500(uuid,text,date,date,uuid,text,integer) to authenticated;

create or replace function public.reports_center_data_v500(
  p_tenant_id uuid,p_report_key text,p_from date,p_to date,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;k text:=lower(trim(coalesce(p_report_key,'')));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if k='sales_summary' then return next public.reports_get_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='sales_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'sales',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k='purchase_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'purchases',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k in('general_ledger','journal_register') then for r in select * from public.journal_center_list_v500(p_tenant_id,p_from,p_to,p_query,null,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('trial_balance','profit_loss','balance_sheet','cash_flow') then return next public.accounting_statement_v41(p_tenant_id,k,p_from,p_to,p_location_id);return;
  elsif k='receivables' then for r in select * from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('payables','supplier_outstanding') then for r in select * from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k='supplier_performance' then for r in select * from public.supplier_performance_v500(p_tenant_id,p_from,p_to,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('current_stock','stock_valuation','stock_aging','dead_stock','low_stock') then for r in select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,greatest(1,least((p_to-p_from)+1,365)),p_query,p_limit) x where (k not in('dead_stock','low_stock') or (k='dead_stock' and x.status='dead_stock') or (k='low_stock' and x.status in('low_stock','out_of_stock'))) loop return next to_jsonb(r);end loop;return;
  elsif k in('returns','purchase_returns') then for r in select value row_json from jsonb_array_elements(coalesce((select jsonb_agg(x) from public.returns_report_v500(p_tenant_id,case when k='purchase_returns' then 'purchase' else 'all' end,p_from,p_to,p_location_id,p_query,p_limit) x),'[]'::jsonb)) loop return next r.row_json;end loop;return;
  elsif k='reconciliation' then return next public.finance_reconciliation_v491(p_tenant_id);return;
  elsif k='tax' then return next public.gst_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='expenses' then for r in select e.expense_date,e.expense_number,c.name category,e.payee,e.description,e.amount,e.tax_amount,e.total_amount,e.payment_method,e.reference_number,e.status from public.expenses e join public.expense_categories c on c.id=e.category_id left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.tenant_id=p_tenant_id and e.expense_date between p_from and p_to and e.status='posted' and (p_location_id is null or o.location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(e.expense_number) like '%'||lower(trim(p_query))||'%' or lower(e.description) like '%'||lower(trim(p_query))||'%' or lower(coalesce(e.payee,'')) like '%'||lower(trim(p_query))||'%') order by e.expense_date desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  else raise exception 'Unsupported report key: %',p_report_key;end if;
end $$;
grant execute on function public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(204,'5.0.0','THQ Reports Center','Central report catalogue, detailed Sales/Purchase Returns data and unified report data endpoints for accounting, inventory, purchasing and sales.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 204 applied' as status;


-- ============================================================================
-- MIGRATION 205: 205_v500_tasks_notifications.sql
-- ============================================================================

-- THQ ERP v5.0.0 — centralized tasks/notifications hardening, history and escalation.
begin;

alter table public.business_tasks add column if not exists escalation_at timestamptz;
alter table public.business_tasks add column if not exists escalated_at timestamptz;
alter table public.business_tasks add column if not exists escalation_user_id uuid references auth.users(id) on delete set null;

create table if not exists public.business_task_history_v500(
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.business_tasks(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  note text,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists idx_task_history_v500 on public.business_task_history_v500(tenant_id,task_id,id desc);
alter table public.business_task_history_v500 enable row level security;
revoke all on public.business_task_history_v500 from anon,authenticated;

create table if not exists public.business_task_comments_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.business_tasks(id) on delete cascade,
  comment text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.business_task_comments_v500 enable row level security;
revoke all on public.business_task_comments_v500 from anon,authenticated;

create or replace function private.v500_task_audit_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_op='INSERT' then
    insert into public.business_task_history_v500(tenant_id,task_id,event_type,to_status,note,changed_by,metadata)
    values(new.tenant_id,new.id,'created',new.status,'Task created',coalesce(auth.uid(),new.created_by),jsonb_build_object('priority',new.priority,'assigned_to',new.assigned_to));
  elsif tg_op='UPDATE' then
    if old.status is distinct from new.status or old.assigned_to is distinct from new.assigned_to or old.due_at is distinct from new.due_at or old.priority is distinct from new.priority then
      insert into public.business_task_history_v500(tenant_id,task_id,event_type,from_status,to_status,note,changed_by,metadata)
      values(new.tenant_id,new.id,'updated',old.status,new.status,'Task updated',auth.uid(),jsonb_build_object('old_priority',old.priority,'priority',new.priority,'old_assigned_to',old.assigned_to,'assigned_to',new.assigned_to,'old_due_at',old.due_at,'due_at',new.due_at));
    end if;
  end if;return new;
end $$;
revoke all on function private.v500_task_audit_trigger() from public;
drop trigger if exists trg_business_task_audit_v500 on public.business_tasks;
create trigger trg_business_task_audit_v500 after insert or update on public.business_tasks for each row execute function private.v500_task_audit_trigger();

-- Fix the v4.9.5 citext/text mismatch explicitly and surface v5 escalation columns.
create or replace function public.business_tasks_list_v495(p_tenant_id uuid,p_location_id uuid default null,p_status text default null)
returns table(
  id uuid,title text,description text,priority text,status text,assigned_to uuid,assigned_username text,
  due_at timestamptz,reminder_at timestamptz,location_id uuid,location_code text,entity_type text,entity_id uuid,
  source_notification_id uuid,metadata jsonb,created_at timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select t.id,t.title::text,t.description::text,t.priority::text,t.status::text,t.assigned_to,coalesce(u.username::text,''::text),
    t.due_at,t.reminder_at,t.location_id,coalesce(l.location_code::text,''::text),t.entity_type::text,t.entity_id,
    t.source_notification_id,coalesce(t.metadata,'{}'::jsonb),t.created_at,t.updated_at
  from public.business_tasks t
  left join public.user_login_names u on u.user_id=t.assigned_to
  left join public.business_locations l on l.id=t.location_id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.location_id=p_location_id)
    and (p_status is null or p_status='' or t.status=p_status)
    and (t.location_id is null or private.erp_user_location_allowed(p_tenant_id,t.location_id,'view') or private.erp_user_is_owner(p_tenant_id))
    and (t.assigned_to is null or t.assigned_to=auth.uid() or private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'tasks.manage'))
  order by case when t.status in('done','cancelled') then 1 else 0 end,case when t.due_at is not null and t.due_at<now() and t.status not in('done','cancelled') then 0 else 1 end,case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,coalesce(t.due_at,'infinity'::timestamptz),t.created_at desc;
end $$;
grant execute on function public.business_tasks_list_v495(uuid,uuid,text) to authenticated;

create or replace function public.business_task_escalation_set_v500(p_tenant_id uuid,p_task_id uuid,p_escalation_at timestamptz,p_escalation_user_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  update public.business_tasks set escalation_at=p_escalation_at,escalation_user_id=p_escalation_user_id,escalated_at=null,updated_at=now() where id=p_task_id and tenant_id=p_tenant_id;if not found then raise exception 'Task not found';end if;
end $$;
grant execute on function public.business_task_escalation_set_v500(uuid,uuid,timestamptz,uuid) to authenticated;

create or replace function public.business_task_comment_add_v500(p_tenant_id uuid,p_task_id uuid,p_comment text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if trim(coalesce(p_comment,''))='' then raise exception 'Comment is required';end if;
  if not exists(select 1 from public.business_tasks where tenant_id=p_tenant_id and id=p_task_id) then raise exception 'Task not found';end if;
  insert into public.business_task_comments_v500(tenant_id,task_id,comment,created_by) values(p_tenant_id,p_task_id,trim(p_comment),auth.uid()) returning id into v;
  insert into public.business_task_history_v500(tenant_id,task_id,event_type,note,changed_by) values(p_tenant_id,p_task_id,'comment',trim(p_comment),auth.uid());return v;
end $$;
grant execute on function public.business_task_comment_add_v500(uuid,uuid,text) to authenticated;

create or replace function public.business_task_timeline_v500(p_tenant_id uuid,p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare h jsonb;c jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.changed_at desc),'[]'::jsonb) into h from public.business_task_history_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'comment',x.comment,'created_by',x.created_by,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into c from public.business_task_comments_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  return jsonb_build_object('history',h,'comments',c);
end $$;
grant execute on function public.business_task_timeline_v500(uuid,uuid) to authenticated;

create or replace function private.v500_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  -- Inventory severity: out-of-stock, low-stock and dead-stock.
  for r in select * from public.inventory_intelligence_v480(p_tenant_id,null,30,'',1000) where status in('out_of_stock','low_stock','dead_stock') order by case status when 'out_of_stock' then 0 when 'low_stock' then 1 else 2 end limit 150 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='inventory' and n.entity_type='product_variant' and n.entity_id=r.variant_id and n.title like case when r.status='out_of_stock' then 'Out of stock%' when r.status='low_stock' then 'Low stock%' else 'Dead stock%' end and n.read_at is null and n.created_at>now()-interval '12 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'inventory',case when r.status='out_of_stock' then 'critical' when r.status='low_stock' then 'warning' else 'info' end,case when r.status='out_of_stock' then 'Out of stock • ' when r.status='low_stock' then 'Low stock • ' else 'Dead stock • ' end||r.product_name,'Available '||round(r.available,2)||' • reorder '||round(r.suggested_reorder,2),'product_variant',r.variant_id);
    end if;
  end loop;

  -- POS/client systems that have not checked in for two hours.
  for r in select d.id,d.location_id,d.device_code,d.name,d.app_type,d.last_seen_at from public.business_devices d where d.tenant_id=p_tenant_id and d.status='active' and d.app_type in('pos','client') and d.last_seen_at is not null and d.last_seen_at<now()-interval '2 hours' order by d.last_seen_at limit 100 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='sync' and n.entity_type='device' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '6 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,p_user_id,r.location_id,'sync','critical',upper(r.app_type)||' not synchronized • '||coalesce(r.device_code,r.name),'Last seen '||r.last_seen_at,'device',r.id);
    end if;
  end loop;

  -- Recurring expenses due now.
  for r in select id,location_id,title,next_run_date,amount from public.recurring_expenses_v500 where tenant_id=p_tenant_id and active and next_run_date<=current_date order by next_run_date limit 100 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='expense' and n.entity_type='recurring_expense' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,p_user_id,r.location_id,'expense','warning','Recurring expense due • '||r.title,'Amount '||round(r.amount,2)||' • due '||r.next_run_date,'recurring_expense',r.id);
    end if;
  end loop;

  -- Task escalation.
  for r in select id,location_id,title,assigned_to,escalation_user_id,due_at from public.business_tasks where tenant_id=p_tenant_id and status not in('done','cancelled') and escalation_at is not null and escalation_at<=now() and escalated_at is null for update loop
    insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,coalesce(r.escalation_user_id,r.assigned_to,p_user_id),r.location_id,'task','critical','Task escalated • '||r.title,case when r.due_at is null then 'Task requires immediate attention' else 'Due '||r.due_at end,'task',r.id);
    update public.business_tasks set escalated_at=now(),updated_at=now() where id=r.id;
  end loop;
end $$;
revoke all on function private.v500_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());
  perform private.v495_refresh_notifications(p_tenant_id,auth.uid());
  perform private.v500_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) order by case severity when 'critical' then 0 when 'warning' then 1 when 'info' then 2 else 3 end,(read_at is null) desc,created_at desc limit greatest(1,least(coalesce(p_limit,50),300));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(205,'5.0.0','Notification & Task Center','Fixes task citext runtime mismatch and adds task history/comments/escalation plus inventory, sync, recurring-expense and task escalation notifications.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 205 applied' as status;


-- ============================================================================
-- MIGRATION 206: 206_v500_finance_reconciliation.sql
-- ============================================================================

-- THQ ERP v5.0.0 — milestone financial reconciliation and integrity diagnostics.
begin;

create or replace function public.finance_reconciliation_v500(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  base jsonb;
  ar_operational numeric:=0; ap_operational numeric:=0;
  ar_gl numeric:=0; ap_gl numeric:=0;
  loan_recv_operational numeric:=0; loan_pay_operational numeric:=0;
  loan_recv_gl numeric:=0; loan_pay_gl numeric:=0;
  inventory_gl numeric:=0;
  ar_id uuid; ap_id uuid; lr_id uuid; lp_id uuid; inv_id uuid;
  orphan_lines bigint:=0; posted_zero_lines bigint:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) and not private.platform_v2_is_admin() then raise exception 'Access denied';end if;
  base:=public.finance_reconciliation_v491(p_tenant_id);
  ar_id:=private.v4_account_id(p_tenant_id,'accounts_receivable'); ap_id:=private.v4_account_id(p_tenant_id,'accounts_payable');
  lr_id:=private.v4_account_id(p_tenant_id,'loan_receivable'); lp_id:=private.v4_account_id(p_tenant_id,'loan_payable'); inv_id:=private.v4_account_id(p_tenant_id,'inventory_asset');

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.total,0)-coalesce(py.total,0),0)),0) into ar_operational
  from public.sales s
  left join(select sale_id,sum(grand_total) total from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
  left join(select sale_id,sum(amount) total from public.sale_payments group by sale_id) py on py.sale_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled');

  select coalesce(sum(x.balance),0) into ap_operational from (
    select greatest(p.grand_total-coalesce(rt.total,0)-coalesce(py.total,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(grand_total) total from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join(select purchase_id,sum(amount) total from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    union all
    select greatest(i.balance_due,0)::numeric from public.purchase_invoices_v484 i where i.tenant_id=p_tenant_id and i.status in('posted','part_paid')
  ) x;

  if ar_id is not null then select coalesce(sum(l.debit-l.credit),0) into ar_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=ar_id;end if;
  if ap_id is not null then select coalesce(sum(l.credit-l.debit),0) into ap_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=ap_id;end if;
  if to_regclass('public.loan_accounts_v490') is not null then
    select coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where direction='given' and accounting_enabled and status in('active','defaulted')),0),coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where direction='taken' and accounting_enabled and status in('active','defaulted')),0) into loan_recv_operational,loan_pay_operational from public.loan_accounts_v490 where tenant_id=p_tenant_id;
  end if;
  if lr_id is not null then select coalesce(sum(l.debit-l.credit),0) into loan_recv_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=lr_id;end if;
  if lp_id is not null then select coalesce(sum(l.credit-l.debit),0) into loan_pay_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=lp_id;end if;
  if inv_id is not null then select coalesce(sum(l.debit-l.credit),0) into inventory_gl from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and l.account_id=inv_id;end if;

  select count(*) into orphan_lines from public.journal_lines l left join public.journal_entries j on j.id=l.journal_entry_id where j.id is null;
  select count(*) into posted_zero_lines from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id and j.status='posted' and abs(coalesce(l.debit,0))+abs(coalesce(l.credit,0))<=0.000001;

  return base||jsonb_build_object(
    'v5',jsonb_build_object(
      'accounts_receivable',jsonb_build_object('operational',round(ar_operational,2),'general_ledger',round(ar_gl,2),'difference',round(ar_operational-ar_gl,2),'reconciled',abs(ar_operational-ar_gl)<=0.05),
      'accounts_payable',jsonb_build_object('operational',round(ap_operational,2),'general_ledger',round(ap_gl,2),'difference',round(ap_operational-ap_gl,2),'reconciled',abs(ap_operational-ap_gl)<=0.05),
      'loan_receivable',jsonb_build_object('operational',round(loan_recv_operational,2),'general_ledger',round(loan_recv_gl,2),'difference',round(loan_recv_operational-loan_recv_gl,2)),
      'loan_payable',jsonb_build_object('operational',round(loan_pay_operational,2),'general_ledger',round(loan_pay_gl,2),'difference',round(loan_pay_operational-loan_pay_gl,2)),
      'inventory_gl_balance',round(inventory_gl,2),'orphan_journal_lines',orphan_lines,'zero_value_posted_lines',posted_zero_lines
    ),'checked_at',now()
  );
end $$;
grant execute on function public.finance_reconciliation_v500(uuid) to authenticated;

create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin return public.finance_reconciliation_v500(p_tenant_id);end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;


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

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(206,'5.0.0','Milestone Financial Reconciliation','Extends finance diagnostics with operational-vs-GL AR/AP and bidirectional loan balances plus journal integrity checks.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 206 applied' as status;


-- ============================================================================
-- MIGRATION 207: 207_v500_dashboard_bi.sql
-- ============================================================================

-- THQ ERP v5.0.0 — milestone dashboard / business intelligence.
begin;
create or replace function public.dashboard_business_intelligence_v500(p_tenant_id uuid,p_location_id uuid default null,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  sales numeric:=0; returns numeric:=0; cost numeric:=0; expenses numeric:=0; receivable numeric:=0; payable numeric:=0;
  low_stock bigint:=0; dead_stock bigint:=0; best jsonb:='[]'::jsonb; slow jsonb:='[]'::jsonb; stores jsonb:='[]'::jsonb; pos jsonb:='[]'::jsonb; hourly jsonb:='[]'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(sum(grand_total),0),coalesce(sum(cost_total),0) into sales,cost from public.sales where tenant_id=p_tenant_id and sale_date=p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or location_id=p_location_id);
  select coalesce(sum(r.grand_total),0) into returns from public.sales_returns r where r.tenant_id=p_tenant_id and r.return_date=p_day and r.refund_status<>'waived' and (p_location_id is null or r.location_id=p_location_id);
  select coalesce(sum(total_amount),0) into expenses from public.expenses e left join public.document_origins o on o.tenant_id=e.tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.tenant_id=p_tenant_id and e.expense_date=p_day and e.status='posted' and (p_location_id is null or o.location_id=p_location_id);
  select coalesce(sum(balance),0) into receivable from (select greatest(s.grand_total-coalesce(rt.x,0)-coalesce(py.x,0),0) balance from public.sales s left join(select sale_id,sum(grand_total)x from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id left join(select sale_id,sum(amount)x from public.sale_payments group by sale_id)py on py.sale_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or s.location_id=p_location_id))q;
  select coalesce(sum(balance),0) into payable from (select greatest(p.grand_total-coalesce(rt.x,0)-coalesce(py.x,0),0) balance from public.purchases p left join(select purchase_id,sum(grand_total)x from public.purchase_returns where credit_status<>'waived' group by purchase_id)rt on rt.purchase_id=p.id left join(select purchase_id,sum(amount)x from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled') and (p_location_id is null or p.location_id=p_location_id) union all select greatest(i.balance_due,0) from public.purchase_invoices_v484 i where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and (p_location_id is null or i.location_id=p_location_id))q;
  select count(*) filter(where status in('low_stock','out_of_stock')),count(*) filter(where status='dead_stock') into low_stock,dead_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,30,'',5000);
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into best from (select pr.name product_name,sum(si.quantity) quantity,sum(si.line_total) sales_value from public.sale_items si join public.sales s on s.id=si.sale_id join public.product_variants pv on pv.id=si.variant_id join public.products pr on pr.id=pv.product_id where s.tenant_id=p_tenant_id and s.sale_date between p_day-29 and p_day and coalesce(s.status,'') not in('void','cancelled') and (p_location_id is null or s.location_id=p_location_id) group by pr.id,pr.name order by quantity desc limit 10)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into stores from (select l.id location_id,l.name,coalesce(sum(s.grand_total),0) gross_sales from public.business_locations l left join public.sales s on s.location_id=l.id and s.tenant_id=p_tenant_id and s.sale_date=p_day and coalesce(s.status,'') not in('void','cancelled') where l.tenant_id=p_tenant_id group by l.id,l.name order by gross_sales desc)q;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into hourly from (select extract(hour from created_at)::int hour,round(sum(grand_total),2) sales from public.sales where tenant_id=p_tenant_id and sale_date=p_day and coalesce(status,'') not in('void','cancelled') and (p_location_id is null or location_id=p_location_id) group by 1 order by 1)q;
  return jsonb_build_object('day',p_day,'net_sales',round(sales-returns,2),'gross_sales',round(sales,2),'sales_returns',round(returns,2),'gross_profit',round((sales-returns)-cost,2),'gross_margin_pct',case when sales-returns>0 then round(((sales-returns)-cost)*100/(sales-returns),2) else 0 end,'expenses',round(expenses,2),'estimated_profit',round((sales-returns)-cost-expenses,2),'receivables',round(receivable,2),'payables',round(payable,2),'low_stock_count',low_stock,'dead_stock_count',dead_stock,'best_sellers',best,'store_comparison',stores,'hourly_sales',hourly);
end $$;
grant execute on function public.dashboard_business_intelligence_v500(uuid,uuid,date) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(207,'5.0.0','Dashboard & Business Intelligence','Return-aware sales/profit, dues, stock risk, best sellers, store comparison and hourly trends.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 207 applied' as status;


-- ============================================================================
-- MIGRATION 208: 208_v500_platform_completion.sql
-- ============================================================================

-- THQ ERP v5.0.0 — platform completion helpers.
begin;
create or replace function public.thq_v500_capabilities()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select jsonb_build_object(
 'finance_controls',true,'journal_center',true,'bank_reconciliation',true,'recurring_expenses',true,'crm',true,'loyalty',true,
 'purchase_quotations',true,'supplier_performance',true,'reorder_suggestions',true,'reports_center',true,'returns_report',true,
 'task_notification_sync',true,'notification_center',true,'dashboard_bi',true,'finance_reconciliation',true,
 'searchable_selectors',true,'invoice_designer',true,'print_pdf_excel',true,'change_business_supported',true
) $$;
grant execute on function public.thq_v500_capabilities() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(208,'5.0.0','Platform Completion','Capability contract for v5 milestone workspaces and cross-module controls.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 208 applied' as status;


-- ============================================================================
-- MIGRATION 209: 209_v500_verification.sql
-- ============================================================================

-- THQ ERP v5.0.0 — milestone database verification.
begin;
create or replace function public.thq_v500_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare miss text[]:='{}'; n text; req text[]:=array[
'finance_reconciliation_v500','financial_years_list_v500','finance_voucher_post_v500','bank_accounts_list_v500','bank_statement_list_v500','recurring_expenses_process_v500','journal_center_list_v500','journal_center_detail_v500','journal_reverse_v500',
'customer_crm_profile_v500','customer_groups_list_v500','purchase_quotations_list_v500','supplier_performance_v500','reorder_suggestions_v500','reports_catalog_v500','returns_report_v500','reports_center_data_v500','dashboard_business_intelligence_v500','business_tasks_list_v495','notifications_list_v4','thq_v500_capabilities'];begin
 foreach n in array req loop if to_regprocedure('public.'||n||case n when 'thq_v500_capabilities' then '()' else null end) is null and not exists(select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=n) then miss:=array_append(miss,n);end if;end loop;
 if not exists(select 1 from public.thq_schema_releases where migration_no=208 and schema_version='5.0.0') then miss:=array_append(miss,'migration.208');end if;
 return jsonb_build_object('ready',cardinality(miss)=0,'missing',to_jsonb(miss),'schema_version','5.0.0','migration_no',210,'build',24,'capabilities',public.thq_v500_capabilities());
end $$;
grant execute on function public.thq_v500_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(209,'5.0.0','Milestone Verification','Database contract verifier for finance, CRM, purchasing intelligence, reports, tasks/notifications and BI.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 209 applied' as status;


-- ============================================================================
-- MIGRATION 210: 210_v500_release.sql
-- ============================================================================

-- THQ ERP v5.0.0 Build 24 release contract.
begin;
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select jsonb_build_object(
 'product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
 'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.9.0',
 'release','THQ ERP 5 Milestone','api_version','v1','backward_compatible',true
) $$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select public.thq_backend_contract_v47()||jsonb_build_object('app_version','5.0.0','build',24,'minimum_migration',210,'capabilities',public.thq_v500_capabilities()) $$;
grant execute on function public.thq_api_contract_v480() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(210,'5.0.0','THQ ERP 5 Milestone','Build 24 milestone release contract. Finance, CRM, intelligent purchasing, reports, notifications/tasks, BI and reconciliation.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 Build 24 migration 210 applied' as status;

