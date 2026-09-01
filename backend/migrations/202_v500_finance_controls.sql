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
