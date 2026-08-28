-- FLEXI ERP V4 proper Chart of Accounts + double-entry journal foundation.
begin;

create table if not exists public.accounting_accounts(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,name text not null,account_type text not null check(account_type in('asset','liability','equity','income','expense','cogs')),
  parent_id uuid references public.accounting_accounts(id) on delete set null,system_key text,description text,is_system boolean not null default false,active boolean not null default true,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,code)
);
create unique index if not exists ux_accounting_accounts_system_key on public.accounting_accounts(tenant_id,system_key) where system_key is not null;

create table if not exists public.accounting_account_mappings(
  tenant_id uuid not null references public.tenants(id) on delete cascade,mapping_key text not null,account_id uuid not null references public.accounting_accounts(id),updated_at timestamptz not null default now(),primary key(tenant_id,mapping_key)
);

create table if not exists public.journal_entries(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid references public.business_locations(id),
  entry_number text not null,entry_date date not null,description text not null,status text not null default 'posted' check(status in('draft','posted','reversed')),
  source_type text,source_id uuid,source_reference text,reversal_of uuid references public.journal_entries(id),created_by uuid references auth.users(id),created_at timestamptz not null default now(),posted_at timestamptz,
  unique(tenant_id,entry_number)
);
create unique index if not exists ux_journal_source on public.journal_entries(tenant_id,source_type,source_id) where source_type is not null and source_id is not null and status<>'reversed';

create table if not exists public.journal_lines(
  id uuid primary key default gen_random_uuid(),journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,account_id uuid not null references public.accounting_accounts(id),
  party_type text,party_id uuid,description text,debit numeric not null default 0,credit numeric not null default 0,
  check(debit>=0 and credit>=0 and not(debit>0 and credit>0))
);
create index if not exists idx_journal_lines_account on public.journal_lines(account_id,journal_entry_id);

alter table public.accounting_accounts enable row level security;alter table public.accounting_account_mappings enable row level security;alter table public.journal_entries enable row level security;alter table public.journal_lines enable row level security;
revoke all on public.accounting_accounts,public.accounting_account_mappings,public.journal_entries,public.journal_lines from anon,authenticated;
create sequence if not exists public.journal_entry_number_seq;

-- Seed a practical default chart for every business.
insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
select t.id,x.code,x.name,x.type,x.key,true,x.description from public.tenants t cross join (values
 ('1000','Cash in Hand','asset','cash','Cash received at counters'),
 ('1010','Bank Account','asset','bank','Primary bank account'),
 ('1020','UPI Clearing','asset','upi','UPI collections/settlements'),
 ('1030','Card Clearing','asset','card','Card collections/settlements'),
 ('1100','Accounts Receivable','asset','accounts_receivable','Customer credit outstanding'),
 ('1200','Inventory Asset','asset','inventory_asset','Stock value'),
 ('1300','Input GST Receivable','asset','input_gst','Input GST credit'),
 ('2000','Accounts Payable','liability','accounts_payable','Supplier outstanding'),
 ('2100','Output GST Payable','liability','output_gst','GST collected on sales'),
 ('3000','Owner Equity','equity','owner_equity','Owner/capital equity'),
 ('4000','Sales Revenue','income','sales_revenue','Product/service sales'),
 ('4010','Other Revenue','income','other_revenue','Other operating revenue'),
 ('5000','Cost of Goods Sold','cogs','cogs','Inventory cost of sold goods'),
 ('6000','Operating Expenses','expense','operating_expense','General operating expenses'),
 ('6010','Purchase / Direct Expense','expense','purchase_expense','Direct purchase expense for non-stock items'),
 ('6900','Rounding / Variance','expense','rounding','Small rounding and cash variances')
) x(code,name,type,key,description)
on conflict(tenant_id,code) do nothing;

insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,'payment.'||a.system_key,a.id from public.accounting_accounts a where a.system_key in('cash','bank','upi','card')
on conflict(tenant_id,mapping_key) do nothing;
insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,a.system_key,a.id from public.accounting_accounts a where a.system_key in('accounts_receivable','accounts_payable','inventory_asset','input_gst','output_gst','sales_revenue','cogs','operating_expense','purchase_expense','rounding')
on conflict(tenant_id,mapping_key) do nothing;

create or replace function private.v4_account_id(p_tenant_id uuid,p_key text)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v uuid;begin
  select account_id into v from public.accounting_account_mappings where tenant_id=p_tenant_id and mapping_key=p_key;
  if v is null then select id into v from public.accounting_accounts where tenant_id=p_tenant_id and system_key=replace(p_key,'payment.','') and active limit 1;end if;
  if v is null then raise exception 'Accounting mapping % is not configured',p_key;end if;return v;
end $$;
revoke all on function private.v4_account_id(uuid,text) from public;

create or replace function private.v4_payment_account(p_tenant_id uuid,p_method text)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare k text:=lower(coalesce(p_method,'cash'));begin
  if k in('cash') then k:='cash';elsif k in('upi') then k:='upi';elsif k in('card','credit_card','debit_card') then k:='card';else k:='bank';end if;
  return private.v4_account_id(p_tenant_id,'payment.'||k);
end $$;
revoke all on function private.v4_payment_account(uuid,text) from public;

create or replace function public.accounting_accounts_list_v4(p_tenant_id uuid)
returns table(id uuid,code text,name text,account_type text,parent_id uuid,system_key text,description text,is_system boolean,active boolean,balance numeric)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'accounting.view') and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Accounting permission required';end if;
  return query select a.id,a.code,a.name,a.account_type,a.parent_id,a.system_key,a.description,a.is_system,a.active,
    coalesce(sum(case when a.account_type in('asset','expense','cogs') then l.debit-l.credit else l.credit-l.debit end),0)
  from public.accounting_accounts a left join public.journal_lines l on l.account_id=a.id left join public.journal_entries j on j.id=l.journal_entry_id and j.status='posted'
  where a.tenant_id=p_tenant_id group by a.id order by a.code;
end $$;
grant execute on function public.accounting_accounts_list_v4(uuid) to authenticated;

create or replace function public.accounting_account_save_v4(p_tenant_id uuid,p_account_id uuid,p_code text,p_name text,p_account_type text,p_parent_id uuid,p_description text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v uuid;v_system boolean;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'accounting.manage') then raise exception 'Accounting manage permission required';end if;
  if trim(coalesce(p_code,''))='' or trim(coalesce(p_name,''))='' then raise exception 'Account code and name are required';end if;
  if p_account_type not in('asset','liability','equity','income','expense','cogs') then raise exception 'Invalid account type';end if;
  if p_account_id is null then
    insert into public.accounting_accounts(tenant_id,code,name,account_type,parent_id,description,active) values(p_tenant_id,upper(trim(p_code)),trim(p_name),p_account_type,p_parent_id,nullif(trim(coalesce(p_description,'')),''),coalesce(p_active,true)) returning id into v;
  else
    select is_system into v_system from public.accounting_accounts where id=p_account_id and tenant_id=p_tenant_id;if not found then raise exception 'Account not found';end if;
    if coalesce(v_system,false) and not coalesce(p_active,true) then raise exception 'System accounts cannot be archived. Change its mapping or keep it active.';end if;
    update public.accounting_accounts set code=upper(trim(p_code)),name=trim(p_name),account_type=p_account_type,parent_id=p_parent_id,description=nullif(trim(coalesce(p_description,'')),''),active=coalesce(p_active,true),updated_at=now() where id=p_account_id returning id into v;
  end if;return v;
end $$;
grant execute on function public.accounting_account_save_v4(uuid,uuid,text,text,text,uuid,text,boolean) to authenticated;

create or replace function public.accounting_mapping_set_v4(p_tenant_id uuid,p_mapping_key text,p_account_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'accounting.manage') then raise exception 'Accounting manage permission required';end if;
  if not exists(select 1 from public.accounting_accounts where id=p_account_id and tenant_id=p_tenant_id and active) then raise exception 'Account not found';end if;
  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id,updated_at) values(p_tenant_id,p_mapping_key,p_account_id,now()) on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();
end $$;
grant execute on function public.accounting_mapping_set_v4(uuid,text,uuid) to authenticated;

create or replace function private.v4_journal_create(p_tenant_id uuid,p_location_id uuid,p_entry_date date,p_description text,p_source_type text,p_source_id uuid,p_source_reference text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_dr numeric:=0;v_cr numeric:=0;begin
  if exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and status='posted') then select id into v_id from public.journal_entries where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and status='posted' limit 1;return v_id;end if;
  for x in select value from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop v_dr:=v_dr+coalesce((x->>'debit')::numeric,0);v_cr:=v_cr+coalesce((x->>'credit')::numeric,0);end loop;
  if abs(v_dr-v_cr)>0.01 then raise exception 'Journal is not balanced. Debit %, Credit %',v_dr,v_cr;end if;
  v_no:='JRN-'||lpad(nextval('public.journal_entry_number_seq')::text,8,'0');
  insert into public.journal_entries(id,tenant_id,location_id,entry_number,entry_date,description,status,source_type,source_id,source_reference,created_by,posted_at) values(v_id,p_tenant_id,p_location_id,v_no,p_entry_date,p_description,'posted',p_source_type,p_source_id,p_source_reference,auth.uid(),now());
  for x in select value from jsonb_array_elements(p_lines) loop insert into public.journal_lines(journal_entry_id,account_id,party_type,party_id,description,debit,credit) values(v_id,(x->>'account_id')::uuid,nullif(x->>'party_type',''),nullif(x->>'party_id','')::uuid,x->>'description',coalesce((x->>'debit')::numeric,0),coalesce((x->>'credit')::numeric,0));end loop;
  return v_id;
end $$;
revoke all on function private.v4_journal_create(uuid,uuid,date,text,text,uuid,text,jsonb) from public;

create or replace function public.accounting_mappings_list_v4(p_tenant_id uuid)
returns table(mapping_key text,account_id uuid,account_code text,account_name text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'accounting.view') and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Accounting permission required';end if;
  return query
  select m.mapping_key,m.account_id,a.code,a.name
  from public.accounting_account_mappings m
  join public.accounting_accounts a on a.id=m.account_id and a.tenant_id=m.tenant_id
  where m.tenant_id=p_tenant_id
  order by m.mapping_key;
end $$;
grant execute on function public.accounting_mappings_list_v4(uuid) to authenticated;

commit;
select 'Flexi ERP V4 Chart of Accounts ready' as status;
