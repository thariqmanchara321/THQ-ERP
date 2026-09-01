-- THQ ERP v4.9.0 Build 21 complete database upgrade: migration 180 -> 193
-- Apply to a database whose latest completed migration is 180.
-- Generated from authoritative backend/migrations files.


-- ============================================================================
-- MIGRATION 181: 181_v490_loan_foundation.sql
-- ============================================================================

-- THQ ERP v4.9.0 — Loan & Credit Management foundation.
begin;

-- -----------------------------------------------------------------------------
-- Module, permissions, plan/template entitlement and navigation.
-- -----------------------------------------------------------------------------
insert into public.modules(key,name,description,category,is_core,sort_order)
values('loans','Loans & Credit','Customer/client loans, schedules, collections, warnings and accounting','Finance',false,86)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order;
update public.modules set is_active=true where key='loans';

insert into public.module_dependencies(module_key,depends_on_module_key)
values('loans','customers'),('loans','accounting')
on conflict do nothing;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select c.tenant_id,'loans',true
from public.tenant_modules c
join public.tenant_modules a on a.tenant_id=c.tenant_id and a.module_key='accounting' and a.enabled
where c.module_key='customers' and c.enabled
on conflict(tenant_id,module_key) do update set enabled=excluded.enabled;

insert into public.business_template_modules(template_id,module_key)
select distinct c.template_id,'loans'
from public.business_template_modules c
join public.business_template_modules a on a.template_id=c.template_id and a.module_key='accounting'
where c.module_key='customers'
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select id,'loans' from public.subscription_plans where key in('business','professional','enterprise')
on conflict do nothing;

do $$ begin
  if exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='permissions' and column_name='description'
  ) then
    insert into public.permissions(key,name,module_key,description) values
      ('loans.view','View Loans','loans','View customer loans, schedules, balances and warnings'),
      ('loans.create','Create Loans','loans','Create and submit loan applications'),
      ('loans.approve','Approve Loans','loans','Approve or reject submitted loans'),
      ('loans.disburse','Disburse Loans','loans','Disburse approved customer loans'),
      ('loans.collect','Collect Loan Payments','loans','Receive loan repayments and issue collection entries'),
      ('loans.rate_manage','Manage Variable Rates','loans','Change the effective rate on variable-rate loans'),
      ('loans.manage','Manage Loans','loans','Manage loan status, collateral, guarantors and corrections')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
      ('loans.view','View Loans','loans'),
      ('loans.create','Create Loans','loans'),
      ('loans.approve','Approve Loans','loans'),
      ('loans.disburse','Disburse Loans','loans'),
      ('loans.collect','Collect Loan Payments','loans'),
      ('loans.rate_manage','Manage Variable Rates','loans'),
      ('loans.manage','Manage Loans','loans')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key='loans' and tm.enabled
join public.permissions p on p.module_key='loans'
where r.key='owner'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key='loans' and tm.enabled
join public.permissions p on p.key in('loans.view','loans.create','loans.approve','loans.disburse','loans.collect','loans.rate_manage','loans.manage')
where r.key='manager'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key='loans' and tm.enabled
join public.permissions p on p.key in('loans.view','loans.collect')
where r.key='cashier'
on conflict do nothing;

-- Add Loan workspace to default and already-copied Client/POS menus.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'client','loans','module','loans',p.id,'Loans','loans',25
from public.app_menu_nodes_v45 p
where p.tenant_id is null and p.app_key='client' and p.node_key='finance'
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'pos','loans','module','loans',p.id,'Loans','loans',45
from public.app_menu_nodes_v45 p
where p.tenant_id is null and p.app_key='pos' and p.node_key='masters'
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select p.tenant_id,'client','loans','module','loans',p.id,'Loans','loans',25
from public.app_menu_nodes_v45 p
where p.tenant_id is not null and p.app_key='client' and p.node_key='finance'
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select p.tenant_id,'pos','loans','module','loans',p.id,'Loans','loans',45
from public.app_menu_nodes_v45 p
where p.tenant_id is not null and p.app_key='pos' and p.node_key='masters'
on conflict do nothing;

update public.business_devices
set allowed_modules=case when not('loans'=any(coalesce(allowed_modules,'{}'::text[]))) then array_append(coalesce(allowed_modules,'{}'::text[]),'loans') else allowed_modules end,
    updated_at=now()
where app_type='pos' and status='active' and 'customers'=any(allowed_modules);

-- -----------------------------------------------------------------------------
-- Accounting mappings used by loan disbursement and collection posting.
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- Loan master and sub-ledgers.
-- -----------------------------------------------------------------------------
create sequence if not exists public.loan_number_seq_v490;
create sequence if not exists public.loan_payment_number_seq_v490;

create table if not exists public.loan_accounts_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id),
  loan_number text not null,
  client_id uuid not null references public.customers(id) on delete restrict,
  external_client_reference text,
  purpose text,
  principal_amount numeric not null check(principal_amount>0),
  interest_rate numeric not null default 0 check(interest_rate>=0 and interest_rate<=1000),
  rate_type text not null default 'fixed' check(rate_type in('fixed','variable')),
  rate_index text,
  rate_margin numeric not null default 0,
  rate_reset_frequency text check(rate_reset_frequency is null or rate_reset_frequency in('monthly','quarterly','half_yearly','yearly')),
  next_rate_review_date date,
  amortization_method text not null default 'reducing_balance' check(amortization_method in('reducing_balance','flat')),
  repayment_frequency text not null default 'monthly' check(repayment_frequency in('weekly','biweekly','monthly','quarterly','half_yearly','yearly')),
  repayment_term_count integer not null check(repayment_term_count>0 and repayment_term_count<=1200),
  repayment_terms text,
  first_payment_date date not null,
  maturity_date date not null,
  disbursement_date date,
  payment_warning_days integer not null default 5 check(payment_warning_days between 0 and 365),
  maturity_warning_days integer not null default 30 check(maturity_warning_days between 0 and 3650),
  grace_days integer not null default 0 check(grace_days between 0 and 365),
  penalty_rate numeric not null default 0 check(penalty_rate>=0 and penalty_rate<=1000),
  collateral_summary text,
  notes text,
  status text not null default 'draft' check(status in('draft','submitted','approved','active','closed','defaulted','cancelled','rejected')),
  principal_outstanding numeric not null default 0,
  interest_outstanding numeric not null default 0,
  penalty_outstanding numeric not null default 0,
  total_paid numeric not null default 0,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejected_by uuid references auth.users(id),
  rejected_at timestamptz,
  rejection_reason text,
  disbursed_by uuid references auth.users(id),
  disbursed_at timestamptz,
  closed_at timestamptz,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,loan_number),
  check(maturity_date>=first_payment_date)
);

create index if not exists idx_loan_accounts_v490_tenant_client on public.loan_accounts_v490(tenant_id,client_id,status);
create index if not exists idx_loan_accounts_v490_location on public.loan_accounts_v490(tenant_id,location_id,status);
create index if not exists idx_loan_accounts_v490_maturity on public.loan_accounts_v490(tenant_id,maturity_date,status);

create table if not exists public.loan_schedule_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete cascade,
  installment_no integer not null,
  due_date date not null,
  opening_principal numeric not null default 0,
  principal_due numeric not null default 0,
  interest_due numeric not null default 0,
  penalty_due numeric not null default 0,
  principal_paid numeric not null default 0,
  interest_paid numeric not null default 0,
  penalty_paid numeric not null default 0,
  status text not null default 'pending' check(status in('pending','due','partial','paid','overdue','waived')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(loan_id,installment_no)
);
create index if not exists idx_loan_schedule_v490_due on public.loan_schedule_v490(tenant_id,due_date,status);

create table if not exists public.loan_payments_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete restrict,
  location_id uuid not null references public.business_locations(id),
  payment_number text not null,
  payment_date date not null,
  amount numeric not null check(amount>0),
  principal_amount numeric not null default 0,
  interest_amount numeric not null default 0,
  penalty_amount numeric not null default 0,
  payment_method text not null default 'cash',
  reference_number text,
  notes text,
  device_id uuid references public.business_devices(id),
  status text not null default 'posted' check(status in('posted','reversed')),
  reversed_by uuid references auth.users(id),
  reversed_at timestamptz,
  reversal_reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(tenant_id,payment_number)
);
create index if not exists idx_loan_payments_v490_loan on public.loan_payments_v490(tenant_id,loan_id,payment_date);

create table if not exists public.loan_payment_allocations_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payment_id uuid not null references public.loan_payments_v490(id) on delete cascade,
  schedule_id uuid not null references public.loan_schedule_v490(id) on delete restrict,
  principal_amount numeric not null default 0,
  interest_amount numeric not null default 0,
  penalty_amount numeric not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_loan_payment_alloc_v490_payment on public.loan_payment_allocations_v490(payment_id);

create table if not exists public.loan_rate_history_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete cascade,
  effective_date date not null,
  previous_rate numeric,
  new_rate numeric not null,
  rate_index text,
  rate_margin numeric,
  reason text,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now()
);
create index if not exists idx_loan_rate_history_v490_loan on public.loan_rate_history_v490(loan_id,effective_date desc);

create table if not exists public.loan_collateral_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete cascade,
  collateral_type text not null,
  description text not null,
  reference_number text,
  estimated_value numeric not null default 0,
  status text not null default 'active' check(status in('active','released','realized')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.loan_guarantors_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  name text not null,
  phone text,
  email text,
  guarantee_amount numeric,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.loan_events_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  loan_id uuid not null references public.loan_accounts_v490(id) on delete cascade,
  event_type text not null,
  event_date timestamptz not null default now(),
  message text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id)
);
create index if not exists idx_loan_events_v490_loan on public.loan_events_v490(loan_id,event_date desc);

alter table public.loan_accounts_v490 enable row level security;
alter table public.loan_schedule_v490 enable row level security;
alter table public.loan_payments_v490 enable row level security;
alter table public.loan_payment_allocations_v490 enable row level security;
alter table public.loan_rate_history_v490 enable row level security;
alter table public.loan_collateral_v490 enable row level security;
alter table public.loan_guarantors_v490 enable row level security;
alter table public.loan_events_v490 enable row level security;

revoke all on public.loan_accounts_v490,public.loan_schedule_v490,public.loan_payments_v490,
  public.loan_payment_allocations_v490,public.loan_rate_history_v490,public.loan_collateral_v490,
  public.loan_guarantors_v490,public.loan_events_v490 from anon,authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(181,'4.9.0','Loans & Credit','Loan module catalog, permissions, Client/POS navigation, finance accounts, loan master, schedules, payments, variable-rate history, collateral, guarantors and event ledger.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 181 loan foundation applied' as status;

-- ============================================================================
-- MIGRATION 182: 182_v490_loan_engine.sql
-- ============================================================================

-- THQ ERP v4.9.0 — Loan lifecycle, schedule, collection and accounting engine.
begin;

create or replace function private.loan_v490_access(
  p_tenant_id uuid,
  p_location_id uuid,
  p_permission text default 'loans.view',
  p_location_level text default 'view'
) returns void
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled) then
    raise exception 'Loans module is disabled';
  end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,p_location_level);end if;
  if private.erp_user_is_owner(p_tenant_id) then return;end if;
  if not private.erp_has_permission(p_tenant_id,p_permission) and not private.erp_has_permission(p_tenant_id,'loans.manage') then
    raise exception 'Loan permission required: %',p_permission;
  end if;
end $$;
revoke all on function private.loan_v490_access(uuid,uuid,text,text) from public;

create or replace function private.loan_v490_periods_per_year(p_frequency text)
returns numeric language sql immutable as $$
  select case lower(coalesce(p_frequency,'monthly'))
    when 'weekly' then 52::numeric
    when 'biweekly' then 26::numeric
    when 'monthly' then 12::numeric
    when 'quarterly' then 4::numeric
    when 'half_yearly' then 2::numeric
    when 'yearly' then 1::numeric
    else 12::numeric end
$$;
revoke all on function private.loan_v490_periods_per_year(text) from public;

create or replace function private.loan_v490_due_date(p_first date,p_frequency text,p_offset integer)
returns date language plpgsql immutable as $$ begin
  return case lower(coalesce(p_frequency,'monthly'))
    when 'weekly' then p_first+(greatest(p_offset,0)*7)
    when 'biweekly' then p_first+(greatest(p_offset,0)*14)
    when 'monthly' then (p_first+make_interval(months=>greatest(p_offset,0)))::date
    when 'quarterly' then (p_first+make_interval(months=>greatest(p_offset,0)*3))::date
    when 'half_yearly' then (p_first+make_interval(months=>greatest(p_offset,0)*6))::date
    when 'yearly' then (p_first+make_interval(years=>greatest(p_offset,0)))::date
    else (p_first+make_interval(months=>greatest(p_offset,0)))::date end;
end $$;
revoke all on function private.loan_v490_due_date(date,text,integer) from public;

create or replace function private.loan_v490_event(
  p_tenant_id uuid,p_loan_id uuid,p_type text,p_message text default null,p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  insert into public.loan_events_v490(tenant_id,loan_id,event_type,message,metadata,created_by)
  values(p_tenant_id,p_loan_id,trim(p_type),nullif(trim(coalesce(p_message,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid());
end $$;
revoke all on function private.loan_v490_event(uuid,uuid,text,text,jsonb) from public;

create or replace function private.loan_v490_refresh(p_tenant_id uuid,p_loan_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;
  v_principal numeric:=0;v_interest numeric:=0;v_penalty numeric:=0;v_paid numeric:=0;
begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;
  if not found then raise exception 'Loan not found';end if;

  if v.status in('active','defaulted','closed') then
    update public.loan_schedule_v490 s
    set penalty_due=case
          when current_date>s.due_date+v.grace_days and s.status not in('paid','waived') and v.penalty_rate>0
            then round((s.principal_due+s.interest_due)*v.penalty_rate/100.0/365.0*
                 greatest(current_date-(s.due_date+v.grace_days),0),2)
          else greatest(s.penalty_due,0) end,
        updated_at=now()
    where s.tenant_id=p_tenant_id and s.loan_id=p_loan_id;

    update public.loan_schedule_v490 s
    set status=case
          when s.status='waived' then 'waived'
          when (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)<=0.005 then 'paid'
          when (s.principal_paid+s.interest_paid+s.penalty_paid)>0.005 then
            case when current_date>s.due_date+v.grace_days then 'overdue' else 'partial' end
          when current_date>s.due_date+v.grace_days then 'overdue'
          when current_date>=s.due_date then 'due'
          else 'pending' end,
        paid_at=case
          when (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)<=0.005
            then coalesce(s.paid_at,now()) else null end,
        updated_at=now()
    where s.tenant_id=p_tenant_id and s.loan_id=p_loan_id;
  end if;

  select
    coalesce(sum(greatest(principal_due-principal_paid,0)),0),
    coalesce(sum(greatest(interest_due-interest_paid,0)),0),
    coalesce(sum(greatest(penalty_due-penalty_paid,0)),0)
  into v_principal,v_interest,v_penalty
  from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived';

  select coalesce(sum(amount),0) into v_paid
  from public.loan_payments_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status='posted';

  update public.loan_accounts_v490
  set principal_outstanding=round(v_principal,2),interest_outstanding=round(v_interest,2),penalty_outstanding=round(v_penalty,2),
      total_paid=round(v_paid,2),
      status=case
        when status in('active','defaulted') and v_principal+v_interest+v_penalty<=0.005 then 'closed'
        else status end,
      closed_at=case when status in('active','defaulted') and v_principal+v_interest+v_penalty<=0.005 then coalesce(closed_at,now()) else closed_at end,
      updated_at=now()
  where tenant_id=p_tenant_id and id=p_loan_id;
end $$;
revoke all on function private.loan_v490_refresh(uuid,uuid) from public;

create or replace function public.loan_create_v490(p_tenant_id uuid,p_location_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_id uuid:=gen_random_uuid();v_no text;v_client uuid;v_principal numeric;v_rate numeric;v_rate_type text;
  v_freq text;v_terms integer;v_first date;v_maturity date;v_amort text;v_penalty numeric;
begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.create','operate');
  v_client:=nullif(p_payload->>'client_id','')::uuid;
  if v_client is null or not exists(select 1 from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false)) then raise exception 'An active non-walk-in client/customer is required';end if;
  v_principal:=coalesce(nullif(p_payload->>'principal_amount','')::numeric,0);if v_principal<=0 then raise exception 'Principal amount must be positive';end if;
  v_rate:=coalesce(nullif(p_payload->>'interest_rate','')::numeric,0);if v_rate<0 or v_rate>1000 then raise exception 'Invalid interest rate';end if;
  v_rate_type:=lower(coalesce(nullif(p_payload->>'rate_type',''),'fixed'));if v_rate_type not in('fixed','variable') then raise exception 'Rate type must be fixed or variable';end if;
  v_freq:=lower(coalesce(nullif(p_payload->>'repayment_frequency',''),'monthly'));
  if v_freq not in('weekly','biweekly','monthly','quarterly','half_yearly','yearly') then raise exception 'Invalid repayment frequency';end if;
  v_terms:=coalesce(nullif(p_payload->>'repayment_term_count','')::integer,0);if v_terms<=0 or v_terms>1200 then raise exception 'Invalid repayment term count';end if;
  v_first:=nullif(p_payload->>'first_payment_date','')::date;if v_first is null then raise exception 'First payment date is required';end if;
  v_maturity:=coalesce(nullif(p_payload->>'maturity_date','')::date,private.loan_v490_due_date(v_first,v_freq,v_terms-1));
  if v_maturity<v_first then raise exception 'Maturity date cannot be before first payment date';end if;
  if v_terms>1 and v_maturity<private.loan_v490_due_date(v_first,v_freq,v_terms-2) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
  v_amort:=lower(coalesce(nullif(p_payload->>'amortization_method',''),'reducing_balance'));
  if v_amort not in('reducing_balance','flat') then raise exception 'Invalid amortization method';end if;
  v_penalty:=coalesce(nullif(p_payload->>'penalty_rate','')::numeric,0);if v_penalty<0 or v_penalty>1000 then raise exception 'Invalid penalty rate';end if;
  if v_rate_type='variable' and nullif(trim(coalesce(p_payload->>'rate_index','')),'') is null then raise exception 'Variable-rate loans require a rate index';end if;

  v_no:='LOAN-'||lpad(nextval('public.loan_number_seq_v490')::text,8,'0');
  insert into public.loan_accounts_v490(
    id,tenant_id,location_id,loan_number,client_id,external_client_reference,purpose,principal_amount,interest_rate,rate_type,
    rate_index,rate_margin,rate_reset_frequency,next_rate_review_date,amortization_method,repayment_frequency,repayment_term_count,
    repayment_terms,first_payment_date,maturity_date,payment_warning_days,maturity_warning_days,grace_days,penalty_rate,
    collateral_summary,notes,status,created_by,updated_by
  ) values(
    v_id,p_tenant_id,p_location_id,v_no,v_client,nullif(trim(coalesce(p_payload->>'external_client_reference','')),''),
    nullif(trim(coalesce(p_payload->>'purpose','')),''),v_principal,v_rate,v_rate_type,
    nullif(trim(coalesce(p_payload->>'rate_index','')),''),coalesce(nullif(p_payload->>'rate_margin','')::numeric,0),
    nullif(lower(trim(coalesce(p_payload->>'rate_reset_frequency',''))),''),nullif(p_payload->>'next_rate_review_date','')::date,
    v_amort,v_freq,v_terms,nullif(trim(coalesce(p_payload->>'repayment_terms','')),''),v_first,v_maturity,
    coalesce(nullif(p_payload->>'payment_warning_days','')::integer,5),coalesce(nullif(p_payload->>'maturity_warning_days','')::integer,30),
    coalesce(nullif(p_payload->>'grace_days','')::integer,0),v_penalty,
    nullif(trim(coalesce(p_payload->>'collateral_summary','')),''),nullif(trim(coalesce(p_payload->>'notes','')),''),'draft',auth.uid(),auth.uid()
  );
  perform private.loan_v490_event(p_tenant_id,v_id,'created','Loan created',jsonb_build_object('principal_amount',v_principal,'rate_type',v_rate_type,'interest_rate',v_rate));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',v_id::text,'create');
  return jsonb_build_object('success',true,'loan_id',v_id,'loan_number',v_no,'status','draft');
end $$;
grant execute on function public.loan_create_v490(uuid,uuid,jsonb) to authenticated;

create or replace function public.loan_update_v490(p_tenant_id uuid,p_loan_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_client uuid;v_first date;v_mat date;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.create','operate');
  if v.status not in('draft','rejected') then raise exception 'Only Draft/Rejected loans can be edited';end if;
  v_client:=coalesce(nullif(p_payload->>'client_id','')::uuid,v.client_id);
  if not exists(select 1 from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false)) then raise exception 'Client/customer must be active and not walk-in';end if;
  v_first:=coalesce(nullif(p_payload->>'first_payment_date','')::date,v.first_payment_date);
  v_mat:=coalesce(nullif(p_payload->>'maturity_date','')::date,v.maturity_date);if v_mat<v_first then raise exception 'Maturity date cannot be before first payment date';end if;
  update public.loan_accounts_v490 set
    client_id=v_client,
    external_client_reference=coalesce(nullif(trim(p_payload->>'external_client_reference'),''),external_client_reference),
    purpose=coalesce(nullif(trim(p_payload->>'purpose'),''),purpose),
    principal_amount=coalesce(nullif(p_payload->>'principal_amount','')::numeric,principal_amount),
    interest_rate=coalesce(nullif(p_payload->>'interest_rate','')::numeric,interest_rate),
    rate_type=coalesce(nullif(lower(p_payload->>'rate_type'),''),rate_type),
    rate_index=coalesce(nullif(trim(p_payload->>'rate_index'),''),rate_index),
    rate_margin=coalesce(nullif(p_payload->>'rate_margin','')::numeric,rate_margin),
    rate_reset_frequency=coalesce(nullif(lower(p_payload->>'rate_reset_frequency'),''),rate_reset_frequency),
    next_rate_review_date=coalesce(nullif(p_payload->>'next_rate_review_date','')::date,next_rate_review_date),
    amortization_method=coalesce(nullif(lower(p_payload->>'amortization_method'),''),amortization_method),
    repayment_frequency=coalesce(nullif(lower(p_payload->>'repayment_frequency'),''),repayment_frequency),
    repayment_term_count=coalesce(nullif(p_payload->>'repayment_term_count','')::integer,repayment_term_count),
    repayment_terms=coalesce(nullif(trim(p_payload->>'repayment_terms'),''),repayment_terms),
    first_payment_date=v_first,maturity_date=v_mat,
    payment_warning_days=coalesce(nullif(p_payload->>'payment_warning_days','')::integer,payment_warning_days),
    maturity_warning_days=coalesce(nullif(p_payload->>'maturity_warning_days','')::integer,maturity_warning_days),
    grace_days=coalesce(nullif(p_payload->>'grace_days','')::integer,grace_days),
    penalty_rate=coalesce(nullif(p_payload->>'penalty_rate','')::numeric,penalty_rate),
    collateral_summary=coalesce(nullif(trim(p_payload->>'collateral_summary'),''),collateral_summary),
    notes=coalesce(nullif(trim(p_payload->>'notes'),''),notes),
    status='draft',rejection_reason=null,rejected_by=null,rejected_at=null,updated_by=auth.uid(),updated_at=now()
  where tenant_id=p_tenant_id and id=p_loan_id;
  if exists(
    select 1 from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id
      and rate_type='variable' and nullif(trim(coalesce(rate_index,'')),'') is null
  ) then raise exception 'Variable-rate loans require a rate index';end if;
  if exists(
    select 1 from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id
      and repayment_term_count>1
      and maturity_date<private.loan_v490_due_date(first_payment_date,repayment_frequency,repayment_term_count-2)
  ) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'updated','Loan details updated');
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'update');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status','draft');
end $$;
grant execute on function public.loan_update_v490(uuid,uuid,jsonb) to authenticated;

create or replace function public.loan_submit_v490(p_tenant_id uuid,p_loan_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.create','operate');
  if v.status<>'draft' then raise exception 'Only Draft loans can be submitted';end if;
  update public.loan_accounts_v490 set status='submitted',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'submitted','Loan submitted for approval');
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'submit');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status','submitted');
end $$;
grant execute on function public.loan_submit_v490(uuid,uuid) to authenticated;

create or replace function public.loan_decide_v490(p_tenant_id uuid,p_loan_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.approve','manage');
  if v.status<>'submitted' then raise exception 'Only Submitted loans can be approved/rejected';end if;
  if coalesce(p_approve,false) then
    update public.loan_accounts_v490 set status='approved',approved_by=auth.uid(),approved_at=now(),rejection_reason=null,rejected_by=null,rejected_at=null,updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
    perform private.loan_v490_event(p_tenant_id,p_loan_id,'approved',coalesce(nullif(trim(p_note),''),'Loan approved'));
  else
    if nullif(trim(coalesce(p_note,'')),'') is null then raise exception 'Rejection reason is required';end if;
    update public.loan_accounts_v490 set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=trim(p_note),updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
    perform private.loan_v490_event(p_tenant_id,p_loan_id,'rejected',trim(p_note));
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,case when p_approve then 'approve' else 'reject' end);
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status',case when p_approve then 'approved' else 'rejected' end);
end $$;
grant execute on function public.loan_decide_v490(uuid,uuid,boolean,text) to authenticated;

create or replace function public.loan_disburse_v490(
  p_tenant_id uuid,p_loan_id uuid,p_disbursement_date date default current_date,p_payment_method text default 'bank',
  p_reference_number text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;v_ppy numeric;v_period_rate numeric;v_installment numeric;v_flat_interest numeric;
  v_balance numeric;v_interest numeric;v_principal numeric;v_due date;v_i integer;v_lines jsonb;v_shift uuid;
begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.disburse','manage');
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active'
  ) then raise exception 'Invalid POS/device for this loan location';end if;
  if v.status='active' then return jsonb_build_object('success',true,'loan_id',v.id,'loan_number',v.loan_number,'status','active','idempotent',true);end if;
  if v.status<>'approved' then raise exception 'Only Approved loans can be disbursed';end if;
  if coalesce(p_disbursement_date,current_date)>v.first_payment_date then raise exception 'First payment date cannot be before disbursement date';end if;
  delete from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id;
  v_ppy:=private.loan_v490_periods_per_year(v.repayment_frequency);
  v_period_rate:=case when v_ppy=0 then 0 else v.interest_rate/100.0/v_ppy end;
  v_balance:=v.principal_amount;
  if v.amortization_method='flat' then
    v_flat_interest:=round(v.principal_amount*v.interest_rate/100.0*(v.repayment_term_count/v_ppy),2);
    v_installment:=round((v.principal_amount+v_flat_interest)/v.repayment_term_count,2);
  elsif abs(v_period_rate)<0.000000001 then
    v_installment:=round(v.principal_amount/v.repayment_term_count,2);
  else
    v_installment:=round(v.principal_amount*v_period_rate/(1-power(1+v_period_rate,-v.repayment_term_count)),2);
  end if;

  for v_i in 1..v.repayment_term_count loop
    v_due:=private.loan_v490_due_date(v.first_payment_date,v.repayment_frequency,v_i-1);
    if v_i=v.repayment_term_count or v_due>v.maturity_date then v_due:=v.maturity_date;end if;
    if v.amortization_method='flat' then
      v_interest:=case when v_i=v.repayment_term_count then round(v_flat_interest-coalesce((select sum(interest_due) from public.loan_schedule_v490 where loan_id=p_loan_id),0),2) else round(v_flat_interest/v.repayment_term_count,2) end;
      v_principal:=case when v_i=v.repayment_term_count then round(v_balance,2) else least(round(v.principal_amount/v.repayment_term_count,2),v_balance) end;
    else
      v_interest:=round(v_balance*v_period_rate,2);
      v_principal:=case when v_i=v.repayment_term_count then round(v_balance,2) else least(greatest(round(v_installment-v_interest,2),0),v_balance) end;
    end if;
    insert into public.loan_schedule_v490(tenant_id,loan_id,installment_no,due_date,opening_principal,principal_due,interest_due,status)
    values(p_tenant_id,p_loan_id,v_i,v_due,round(v_balance,2),v_principal,v_interest,case when v_due<=current_date then 'due' else 'pending' end);
    v_balance:=greatest(v_balance-v_principal,0);
  end loop;

  update public.loan_accounts_v490 set status='active',disbursement_date=coalesce(p_disbursement_date,current_date),disbursed_by=auth.uid(),disbursed_at=now(),
    principal_outstanding=principal_amount,updated_by=auth.uid(),updated_at=now() where id=p_loan_id;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',v.principal_amount,'credit',0,'party_type','customer','party_id',v.client_id,'description','Loan principal advanced'),
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',0,'credit',v.principal_amount,'party_type','customer','party_id',v.client_id,'description','Loan disbursement')
  );
  perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_disbursement_date,current_date),'Loan disbursement '||v.loan_number,'loan_disbursement_v490',v.id,v.loan_number,v_lines);

  if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(v.principal_amount),'loan_disbursement_v490',v.id,v.loan_number,'Loan disbursement',auth.uid());
    end if;
  end if;

  insert into public.loan_rate_history_v490(tenant_id,loan_id,effective_date,previous_rate,new_rate,rate_index,rate_margin,reason,changed_by)
  values(p_tenant_id,p_loan_id,coalesce(p_disbursement_date,current_date),null,v.interest_rate,v.rate_index,v.rate_margin,'Initial effective rate',auth.uid());
  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'disbursed','Loan disbursed',jsonb_build_object('amount',v.principal_amount,'payment_method',p_payment_method,'reference_number',p_reference_number));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'disburse');
  return jsonb_build_object('success',true,'loan_id',v.id,'loan_number',v.loan_number,'status','active','principal_amount',v.principal_amount);
end $$;
grant execute on function public.loan_disburse_v490(uuid,uuid,date,text,text,uuid) to authenticated;

create or replace function public.loan_payment_create_v490(
  p_tenant_id uuid,p_loan_id uuid,p_amount numeric,p_payment_date date default current_date,p_payment_method text default 'cash',
  p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;v_payment uuid:=gen_random_uuid();v_no text;v_amount numeric:=round(coalesce(p_amount,0),2);v_remaining numeric:=round(coalesce(p_amount,0),2);
  r record;v_pen numeric;v_int numeric;v_prin numeric;v_take numeric;v_total_pen numeric:=0;v_total_int numeric:=0;v_total_prin numeric:=0;
  v_lines jsonb:='[]'::jsonb;v_shift uuid;
begin
  if v_remaining<=0 then raise exception 'Payment amount must be positive';end if;
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.collect','operate');
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active'
  ) then raise exception 'Invalid POS/device for this loan location';end if;
  if v.status not in('active','defaulted') then raise exception 'Payments are allowed only for Active/Defaulted loans';end if;
  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;
  if v_remaining>v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding+0.005 then raise exception 'Payment exceeds loan outstanding';end if;

  v_no:='LPAY-'||lpad(nextval('public.loan_payment_number_seq_v490')::text,9,'0');
  insert into public.loan_payments_v490(id,tenant_id,loan_id,location_id,payment_number,payment_date,amount,payment_method,reference_number,notes,device_id,created_by)
  values(v_payment,p_tenant_id,p_loan_id,v.location_id,v_no,coalesce(p_payment_date,current_date),v_remaining,lower(coalesce(nullif(trim(p_payment_method),''),'cash')),
    nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),p_device_id,auth.uid());

  for r in select * from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived'
           and (principal_due+interest_due+penalty_due)-(principal_paid+interest_paid+penalty_paid)>0.005 order by due_date,installment_no for update loop
    exit when v_remaining<=0.005;
    v_pen:=greatest(r.penalty_due-r.penalty_paid,0);v_int:=greatest(r.interest_due-r.interest_paid,0);v_prin:=greatest(r.principal_due-r.principal_paid,0);
    v_take:=least(v_remaining,v_pen);v_pen:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_int);v_int:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_prin);v_prin:=v_take;v_remaining:=v_remaining-v_take;
    if v_pen+v_int+v_prin>0 then
      update public.loan_schedule_v490 set penalty_paid=penalty_paid+v_pen,interest_paid=interest_paid+v_int,principal_paid=principal_paid+v_prin,updated_at=now() where id=r.id;
      insert into public.loan_payment_allocations_v490(tenant_id,payment_id,schedule_id,principal_amount,interest_amount,penalty_amount)
      values(p_tenant_id,v_payment,r.id,v_prin,v_int,v_pen);
      v_total_pen:=v_total_pen+v_pen;v_total_int:=v_total_int+v_int;v_total_prin:=v_total_prin+v_prin;
    end if;
  end loop;
  if v_remaining>0.005 then raise exception 'Payment could not be fully allocated';end if;
  update public.loan_payments_v490 set principal_amount=round(v_total_prin,2),interest_amount=round(v_total_int,2),penalty_amount=round(v_total_pen,2) where id=v_payment;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',v_amount,'credit',0,'party_type','customer','party_id',v.client_id,'description','Loan repayment received'));
  if v_total_prin>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',0,'credit',v_total_prin,'party_type','customer','party_id',v.client_id,'description','Loan principal repaid'));end if;
  if v_total_int>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_interest_income'),'debit',0,'credit',v_total_int,'party_type','customer','party_id',v.client_id,'description','Loan interest income'));end if;
  if v_total_pen>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_penalty_income'),'debit',0,'credit',v_total_pen,'party_type','customer','party_id',v.client_id,'description','Loan penalty income'));end if;
  perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_payment_date,current_date),'Loan payment '||v_no,'loan_payment_v490',v_payment,v_no,v_lines);

  if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_in',abs(v_amount),'loan_payment_v490',v_payment,v_no,'Loan repayment',auth.uid());
    end if;
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'payment','Loan payment received',jsonb_build_object('payment_id',v_payment,'payment_number',v_no,'amount',v_amount,'principal',v_total_prin,'interest',v_total_int,'penalty',v_total_pen));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v_payment::text,'create');
  return jsonb_build_object('success',true,'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,'principal_amount',round(v_total_prin,2),'interest_amount',round(v_total_int,2),'penalty_amount',round(v_total_pen,2));
end $$;
grant execute on function public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid) to authenticated;

create or replace function public.loan_payment_reverse_v490(p_tenant_id uuid,p_payment_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_payments_v490%rowtype;a record;v_shift uuid;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reversal reason is required';end if;
  select * into v from public.loan_payments_v490 where tenant_id=p_tenant_id and id=p_payment_id for update;if not found then raise exception 'Loan payment not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if v.status='reversed' then return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed','idempotent',true);end if;
  for a in select * from public.loan_payment_allocations_v490 where tenant_id=p_tenant_id and payment_id=p_payment_id loop
    update public.loan_schedule_v490 set principal_paid=greatest(principal_paid-a.principal_amount,0),interest_paid=greatest(interest_paid-a.interest_amount,0),penalty_paid=greatest(penalty_paid-a.penalty_amount,0),paid_at=null,updated_at=now() where id=a.schedule_id;
  end loop;
  update public.loan_payments_v490 set status='reversed',reversed_by=auth.uid(),reversed_at=now(),reversal_reason=trim(p_reason) where id=p_payment_id;
  update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='loan_payment_v490' and source_id=p_payment_id and status='posted';
  if v.device_id is not null and lower(v.payment_method)='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v.device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(v.amount),'loan_payment_reversal_v490',v.id,v.payment_number,'Loan payment reversal: '||trim(p_reason),auth.uid());
    end if;
  end if;
  perform private.loan_v490_refresh(p_tenant_id,v.loan_id);
  perform private.loan_v490_event(p_tenant_id,v.loan_id,'payment_reversed','Loan payment reversed: '||trim(p_reason),jsonb_build_object('payment_id',v.id,'payment_number',v.payment_number,'amount',v.amount));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v.id::text,'reverse');
  return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed');
end $$;
grant execute on function public.loan_payment_reverse_v490(uuid,uuid,text) to authenticated;

create or replace function public.loan_rate_change_v490(
  p_tenant_id uuid,p_loan_id uuid,p_new_rate numeric,p_effective_date date default current_date,p_rate_index text default null,p_rate_margin numeric default null,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;r record;v_ppy numeric;v_interest numeric;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.rate_manage','manage');
  if v.rate_type<>'variable' then raise exception 'Only variable-rate loans can change rate';end if;
  if v.status not in('approved','active','defaulted') then raise exception 'Rate cannot be changed in the current loan status';end if;
  if coalesce(p_new_rate,-1)<0 or p_new_rate>1000 then raise exception 'Invalid new interest rate';end if;
  insert into public.loan_rate_history_v490(tenant_id,loan_id,effective_date,previous_rate,new_rate,rate_index,rate_margin,reason,changed_by)
  values(p_tenant_id,p_loan_id,coalesce(p_effective_date,current_date),v.interest_rate,p_new_rate,coalesce(nullif(trim(p_rate_index),''),v.rate_index),coalesce(p_rate_margin,v.rate_margin),nullif(trim(coalesce(p_reason,'')),''),auth.uid());
  update public.loan_accounts_v490 set interest_rate=p_new_rate,rate_index=coalesce(nullif(trim(p_rate_index),''),rate_index),rate_margin=coalesce(p_rate_margin,rate_margin),updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  if v.status in('active','defaulted') then
    v_ppy:=private.loan_v490_periods_per_year(v.repayment_frequency);
    for r in select * from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and due_date>=coalesce(p_effective_date,current_date)
             and principal_paid+interest_paid+penalty_paid<=0.005 and status<>'waived' order by installment_no for update loop
      v_interest:=round(r.opening_principal*p_new_rate/100.0/v_ppy,2);
      update public.loan_schedule_v490 set interest_due=v_interest,updated_at=now() where id=r.id;
    end loop;
    perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'rate_changed','Interest rate changed',jsonb_build_object('previous_rate',v.interest_rate,'new_rate',p_new_rate,'effective_date',coalesce(p_effective_date,current_date)));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'rate_change');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'interest_rate',p_new_rate,'rate_type','variable');
end $$;
grant execute on function public.loan_rate_change_v490(uuid,uuid,numeric,date,text,numeric,text) to authenticated;

create or replace function public.loan_status_v490(p_tenant_id uuid,p_loan_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_status text:=lower(trim(coalesce(p_status,'')));begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if v_status='cancelled' and v.status in('draft','submitted','approved','rejected') then
    update public.loan_accounts_v490 set status='cancelled',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  elsif v_status='defaulted' and v.status='active' then
    update public.loan_accounts_v490 set status='defaulted',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  elsif v_status='active' and v.status='defaulted' then
    update public.loan_accounts_v490 set status='active',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  else raise exception 'Invalid loan status transition % -> %',v.status,v_status;end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'status_changed',coalesce(nullif(trim(p_reason),''),'Loan status changed to '||v_status),jsonb_build_object('from',v.status,'to',v_status));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'status');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status',v_status);
end $$;
grant execute on function public.loan_status_v490(uuid,uuid,text,text) to authenticated;

create or replace function public.loan_collateral_save_v490(
  p_tenant_id uuid,p_loan_id uuid,p_collateral_id uuid,p_type text,p_description text,p_reference_number text,p_estimated_value numeric,p_status text default 'active',p_notes text default null
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_id uuid:=coalesce(p_collateral_id,gen_random_uuid());begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if nullif(trim(coalesce(p_type,'')),'') is null or nullif(trim(coalesce(p_description,'')),'') is null then raise exception 'Collateral type and description are required';end if;
  insert into public.loan_collateral_v490(id,tenant_id,loan_id,collateral_type,description,reference_number,estimated_value,status,notes,created_by)
  values(v_id,p_tenant_id,p_loan_id,trim(p_type),trim(p_description),nullif(trim(coalesce(p_reference_number,'')),''),greatest(coalesce(p_estimated_value,0),0),coalesce(nullif(lower(trim(p_status)),''),'active'),nullif(trim(coalesce(p_notes,'')),''),auth.uid())
  on conflict(id) do update set collateral_type=excluded.collateral_type,description=excluded.description,reference_number=excluded.reference_number,estimated_value=excluded.estimated_value,status=excluded.status,notes=excluded.notes,updated_at=now();
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'collateral_updated','Loan collateral updated');return v_id;
end $$;
grant execute on function public.loan_collateral_save_v490(uuid,uuid,uuid,text,text,text,numeric,text,text) to authenticated;

create or replace function public.loan_guarantor_save_v490(
  p_tenant_id uuid,p_loan_id uuid,p_guarantor_id uuid,p_customer_id uuid,p_name text,p_phone text,p_email text,p_guarantee_amount numeric,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_id uuid:=coalesce(p_guarantor_id,gen_random_uuid());begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id) then raise exception 'Guarantor customer not found';end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Guarantor name is required';end if;
  insert into public.loan_guarantors_v490(id,tenant_id,loan_id,customer_id,name,phone,email,guarantee_amount,notes,created_by)
  values(v_id,p_tenant_id,p_loan_id,p_customer_id,trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),p_guarantee_amount,nullif(trim(coalesce(p_notes,'')),''),auth.uid())
  on conflict(id) do update set customer_id=excluded.customer_id,name=excluded.name,phone=excluded.phone,email=excluded.email,guarantee_amount=excluded.guarantee_amount,notes=excluded.notes,updated_at=now();
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'guarantor_updated','Loan guarantor updated');return v_id;
end $$;
grant execute on function public.loan_guarantor_save_v490(uuid,uuid,uuid,uuid,text,text,text,numeric,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(182,'4.9.0','Loans & Credit','Loan lifecycle engine: create/edit/submit/approval/disbursement, amortization schedules, fixed/variable rates, collections, payment reversal, penalties, collateral, guarantors, journal posting and POS cash-drawer integration.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 182 loan engine applied' as status;

-- ============================================================================
-- MIGRATION 183: 183_v490_loan_reporting_api.sql
-- ============================================================================

-- THQ ERP v4.9.0 — Loan reporting, warnings and shared API read model.
begin;

create or replace function public.loan_list_v490(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default '',
  p_limit integer default 500
) returns table(
  loan_id uuid,
  loan_number text,
  client_id uuid,
  client_public_id text,
  client_name text,
  location_id uuid,
  location_name text,
  purpose text,
  principal_amount numeric,
  interest_rate numeric,
  rate_type text,
  rate_index text,
  rate_margin numeric,
  amortization_method text,
  repayment_frequency text,
  repayment_term_count integer,
  repayment_terms text,
  first_payment_date date,
  maturity_date date,
  disbursement_date date,
  status text,
  principal_outstanding numeric,
  interest_outstanding numeric,
  penalty_outstanding numeric,
  total_outstanding numeric,
  total_paid numeric,
  next_due_date date,
  next_due_amount numeric,
  overdue_installments bigint,
  overdue_amount numeric,
  days_to_maturity integer,
  warning_level text,
  warning_message text,
  created_at timestamptz,
  updated_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  select
    l.id,l.loan_number,l.client_id,c.tracking_code,c.name,l.location_id,bl.name,l.purpose,
    l.principal_amount,l.interest_rate,l.rate_type,l.rate_index,l.rate_margin,l.amortization_method,
    l.repayment_frequency,l.repayment_term_count,l.repayment_terms,l.first_payment_date,l.maturity_date,l.disbursement_date,l.status,
    l.principal_outstanding,l.interest_outstanding,l.penalty_outstanding,
    round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),l.total_paid,
    nd.due_date,coalesce(nd.due_amount,0),coalesce(ov.cnt,0),coalesce(ov.amount,0),
    (l.maturity_date-current_date)::integer,
    case
      when coalesce(ov.cnt,0)>0 then 'danger'
      when l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days then 'warning'
      when l.status in('active','defaulted') and nd.due_date is not null and nd.due_date<=current_date+l.payment_warning_days then 'warning'
      when l.rate_type='variable' and l.next_rate_review_date is not null and l.next_rate_review_date<=current_date+l.payment_warning_days then 'info'
      when l.status='defaulted' then 'danger'
      else 'normal' end,
    case
      when coalesce(ov.cnt,0)>0 then coalesce(ov.cnt,0)::text||' overdue installment(s)'
      when l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days then 'Matures in '||(l.maturity_date-current_date)::text||' day(s)'
      when l.status in('active','defaulted') and nd.due_date is not null and nd.due_date<=current_date+l.payment_warning_days then 'Payment due '||to_char(nd.due_date,'DD Mon YYYY')
      when l.rate_type='variable' and l.next_rate_review_date is not null and l.next_rate_review_date<=current_date+l.payment_warning_days then 'Variable rate review due '||to_char(l.next_rate_review_date,'DD Mon YYYY')
      when l.status='defaulted' then 'Loan marked defaulted'
      else null end,
    l.created_at,l.updated_at
  from public.loan_accounts_v490 l
  join public.customers c on c.id=l.client_id and c.tenant_id=l.tenant_id
  join public.business_locations bl on bl.id=l.location_id
  left join lateral(
    select s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2) due_amount
    from public.loan_schedule_v490 s
    where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    order by s.due_date,s.installment_no limit 1
  ) nd on true
  left join lateral(
    select count(*)::bigint cnt,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from public.loan_schedule_v490 s
    where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
      and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ) ov on true
  where l.tenant_id=p_tenant_id
    and (p_location_id is null or l.location_id=p_location_id)
    and (p_status is null or trim(p_status)='' or l.status=lower(trim(p_status)))
    and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    and (trim(coalesce(p_query,''))='' or lower(concat_ws(' ',l.loan_number,c.name,c.tracking_code,l.external_client_reference,l.purpose,l.status)) like v_q)
  order by case when coalesce(ov.cnt,0)>0 then 0 when l.status in('active','defaulted') then 1 else 2 end,l.updated_at desc
  limit least(greatest(coalesce(p_limit,500),1),2000);
end $$;
grant execute on function public.loan_list_v490(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.loan_detail_v490(p_tenant_id uuid,p_loan_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_result jsonb;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;
  if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.view','view');
  if v.status in('active','defaulted','closed') then perform private.loan_v490_refresh(p_tenant_id,p_loan_id);end if;
  select jsonb_build_object(
    'loan',to_jsonb(l)||jsonb_build_object(
      'total_outstanding',round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),
      'client_name',c.name,'client_public_id',c.tracking_code,'client_phone',c.phone,'client_email',c.email,
      'location_name',bl.name,'location_code',bl.location_code
    ),
    'customer',jsonb_build_object('id',c.id,'public_id',c.tracking_code,'name',c.name,'phone',c.phone,'email',c.email,'tax_number',c.tax_number,'credit_limit',c.credit_limit,'status',c.status),
    'schedule',coalesce((select jsonb_agg(to_jsonb(s) order by s.installment_no) from public.loan_schedule_v490 s where s.tenant_id=p_tenant_id and s.loan_id=l.id),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.payment_date desc,p.created_at desc) from public.loan_payments_v490 p where p.tenant_id=p_tenant_id and p.loan_id=l.id),'[]'::jsonb),
    'rate_history',coalesce((select jsonb_agg(to_jsonb(r) order by r.effective_date desc,r.changed_at desc) from public.loan_rate_history_v490 r where r.tenant_id=p_tenant_id and r.loan_id=l.id),'[]'::jsonb),
    'collateral',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.loan_collateral_v490 x where x.tenant_id=p_tenant_id and x.loan_id=l.id),'[]'::jsonb),
    'guarantors',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at) from public.loan_guarantors_v490 g where g.tenant_id=p_tenant_id and g.loan_id=l.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.event_date desc) from public.loan_events_v490 e where e.tenant_id=p_tenant_id and e.loan_id=l.id),'[]'::jsonb)
  ) into v_result
  from public.loan_accounts_v490 l
  join public.customers c on c.id=l.client_id
  join public.business_locations bl on bl.id=l.location_id
  where l.tenant_id=p_tenant_id and l.id=p_loan_id;
  return v_result;
end $$;
grant execute on function public.loan_detail_v490(uuid,uuid) to authenticated;

create or replace function public.loan_dashboard_v490(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_result jsonb;begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  with scoped as(
    select l.* from public.loan_accounts_v490 l
    where l.tenant_id=p_tenant_id
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), overdue as(
    select count(*)::bigint installments,
      count(distinct l.id)::bigint loans,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ), due7 as(
    select count(*)::bigint installments,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and s.due_date between current_date and current_date+7
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ), collected as(
    select round(coalesce(sum(p.amount),0),2) amount
    from public.loan_payments_v490 p join scoped l on l.id=p.loan_id
    where p.status='posted' and p.payment_date=current_date
  )
  select jsonb_build_object(
    'total_loans',count(*),
    'draft',count(*) filter(where s.status='draft'),
    'submitted',count(*) filter(where s.status='submitted'),
    'approved',count(*) filter(where s.status='approved'),
    'active',count(*) filter(where s.status='active'),
    'defaulted',count(*) filter(where s.status='defaulted'),
    'closed',count(*) filter(where s.status='closed'),
    'active_principal',round(coalesce(sum(s.principal_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'outstanding_interest',round(coalesce(sum(s.interest_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'outstanding_penalty',round(coalesce(sum(s.penalty_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'total_outstanding',round(coalesce(sum(s.principal_outstanding+s.interest_outstanding+s.penalty_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'overdue_loans',(select loans from overdue),'overdue_installments',(select installments from overdue),'overdue_amount',(select amount from overdue),
    'due_next_7_days',(select installments from due7),'due_next_7_days_amount',(select amount from due7),
    'maturing_next_30_days',count(*) filter(where s.status in('active','defaulted') and s.maturity_date between current_date and current_date+30),
    'variable_rate_reviews',count(*) filter(where s.status in('approved','active','defaulted') and s.rate_type='variable' and s.next_rate_review_date between current_date and current_date+30),
    'collections_today',(select amount from collected)
  ) into v_result from scoped s;
  return coalesce(v_result,'{}'::jsonb);
end $$;
grant execute on function public.loan_dashboard_v490(uuid,uuid) to authenticated;

create or replace function public.loan_warnings_v490(
  p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 250
) returns table(
  warning_type text,severity text,loan_id uuid,loan_number text,client_id uuid,client_name text,location_id uuid,
  event_date date,amount numeric,days_until integer,message text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  with scoped as(
    select l.*,c.name client_name
    from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id
    where l.tenant_id=p_tenant_id and l.status in('approved','active','defaulted')
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), warnings as(
    select 'overdue_payment'::text,'danger'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      'Installment #'||s.installment_no::text||' overdue by '||(current_date-s.due_date)::text||' day(s)'::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'payment_due'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      'Installment #'||s.installment_no::text||' due in '||greatest(s.due_date-current_date,0)::text||' day(s)'::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and s.due_date between current_date and current_date+l.payment_warning_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'maturity'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.maturity_date,
      round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),(l.maturity_date-current_date)::integer,
      'Loan matures in '||greatest(l.maturity_date-current_date,0)::text||' day(s)'::text
    from scoped l where l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days
    union all
    select 'rate_review'::text,'info'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.next_rate_review_date,
      null::numeric,(l.next_rate_review_date-current_date)::integer,
      'Variable interest rate review due in '||greatest(l.next_rate_review_date-current_date,0)::text||' day(s)'::text
    from scoped l where l.rate_type='variable' and l.next_rate_review_date is not null
      and l.next_rate_review_date between current_date and current_date+greatest(l.payment_warning_days,7)
  )
  select w.* from warnings w
  order by case w.severity when 'danger' then 0 when 'warning' then 1 else 2 end,w.event_date,w.loan_number
  limit least(greatest(coalesce(p_limit,250),1),2000);
end $$;
grant execute on function public.loan_warnings_v490(uuid,uuid,integer) to authenticated;

create or replace function public.customer_loan_summary_v490(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_customer jsonb;v_summary jsonb;begin
  perform private.loan_v490_access(p_tenant_id,null,'loans.view','view');
  select jsonb_build_object('id',c.id,'public_id',c.tracking_code,'name',c.name,'phone',c.phone,'email',c.email)
  into v_customer from public.customers c where c.tenant_id=p_tenant_id and c.id=p_customer_id;
  if v_customer is null then raise exception 'Customer/client not found';end if;
  with scoped as(
    select l.* from public.loan_accounts_v490 l where l.tenant_id=p_tenant_id and l.client_id=p_customer_id
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view')
  ) select jsonb_build_object(
    'customer',v_customer,
    'loan_count',count(*),
    'active_count',count(*) filter(where status in('active','defaulted')),
    'principal_outstanding',round(coalesce(sum(principal_outstanding) filter(where status in('active','defaulted')),0),2),
    'interest_outstanding',round(coalesce(sum(interest_outstanding) filter(where status in('active','defaulted')),0),2),
    'penalty_outstanding',round(coalesce(sum(penalty_outstanding) filter(where status in('active','defaulted')),0),2),
    'total_outstanding',round(coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where status in('active','defaulted')),0),2),
    'loans',coalesce(jsonb_agg(jsonb_build_object(
      'loan_id',id,'loan_number',loan_number,'status',status,'principal_amount',principal_amount,'principal_outstanding',principal_outstanding,
      'interest_outstanding',interest_outstanding,'penalty_outstanding',penalty_outstanding,'rate_type',rate_type,'interest_rate',interest_rate,
      'repayment_frequency',repayment_frequency,'maturity_date',maturity_date,'location_id',location_id
    ) order by updated_at desc),'[]'::jsonb)
  ) into v_summary from scoped;
  return coalesce(v_summary,jsonb_build_object('customer',v_customer,'loan_count',0,'active_count',0,'principal_outstanding',0,'interest_outstanding',0,'penalty_outstanding',0,'total_outstanding',0,'loans','[]'::jsonb));
end $$;
grant execute on function public.customer_loan_summary_v490(uuid,uuid) to authenticated;

-- Feed loan risk into the existing THQ notification center without changing
-- the generic notification table or requiring a separate alert subsystem.
create or replace function private.loan_v490_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  if p_user_id is null or p_user_id<>auth.uid() then return;end if;
  if not exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled) then return;end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'loans.view')
     and not private.erp_has_permission(p_tenant_id,'loans.manage') then return;end if;

  for r in select * from public.loan_warnings_v490(p_tenant_id,null,100) loop
    if not exists(
      select 1 from public.notifications n
      where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='loan'
        and n.entity_type='loan' and n.entity_id=r.loan_id and n.read_at is null
        and n.title=('Loan '||replace(r.warning_type,'_',' '))
        and n.created_at>now()-interval '12 hours'
    ) then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(
        p_tenant_id,p_user_id,r.location_id,'loan',
        case r.severity when 'danger' then 'critical' when 'warning' then 'warning' else 'info' end,
        'Loan '||replace(r.warning_type,'_',' '),
        r.loan_number||' • '||r.client_name||' • '||r.message,
        'loan',r.loan_id
      );
    end if;
  end loop;
end $$;
revoke all on function private.loan_v490_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications
    where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid())
    order by created_at desc limit greatest(1,least(coalesce(p_limit,50),200));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

-- Extend the existing cross-module attention summary with loan exposure/risk.
-- Users without loan visibility simply receive zeroed loan metrics.
create or replace function public.business_attention_summary_v480(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_low bigint:=0;v_out bigint:=0;v_dead bigint:=0;v_stock numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_overdue numeric:=0;
  v_pipeline jsonb;v_loans jsonb:='{}'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) filter(where status='low_stock'),count(*) filter(where status='out_of_stock'),count(*) filter(where status='dead_stock'),coalesce(sum(stock_value),0)
    into v_low,v_out,v_dead,v_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,'',5000);
  select coalesce(sum(total_outstanding),0),coalesce(sum(days_1_30+days_31_60+days_61_90+days_90_plus),0)
    into v_recv,v_overdue from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into v_pay from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  v_pipeline:=public.operations_pipeline_v489(p_tenant_id,p_location_id);
  if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled)
     and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'loans.view') or private.erp_has_permission(p_tenant_id,'loans.manage')) then
    v_loans:=public.loan_dashboard_v490(p_tenant_id,p_location_id);
  end if;
  return jsonb_build_object(
    'low_stock',v_low,'out_of_stock',v_out,'dead_stock',v_dead,'inventory_value',round(v_stock,2),
    'receivables',round(v_recv,2),'overdue_receivables',round(v_overdue,2),'payables',round(v_pay,2),'days',greatest(1,least(coalesce(p_days,30),365)),
    'loan_total_outstanding',coalesce((v_loans->>'total_outstanding')::numeric,0),
    'loan_overdue_amount',coalesce((v_loans->>'overdue_amount')::numeric,0),
    'loan_overdue_count',coalesce((v_loans->>'overdue_loans')::bigint,0),
    'loan_due_next_7_days',coalesce((v_loans->>'due_next_7_days')::bigint,0),
    'loan_maturing_next_30_days',coalesce((v_loans->>'maturing_next_30_days')::bigint,0),
    'loan_variable_rate_reviews',coalesce((v_loans->>'variable_rate_reviews')::bigint,0)
  )||v_pipeline;
end $$;
grant execute on function public.business_attention_summary_v480(uuid,uuid,integer) to authenticated;


-- Keep Loans searchable from the existing THQ global search without exposing
-- loan values to users who do not have loan visibility.
create or replace function public.global_search_v4(p_tenant_id uuid,p_query text,p_limit integer default 60)
returns table(entity_type text,entity_id uuid,public_id text,title text,subtitle text,module_key text,location_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim integer:=greatest(5,least(coalesce(p_limit,60),150));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if trim(coalesce(p_query,''))='' then return;end if;
  return query select * from (
    select 'product'::text,pv.id,coalesce(p.tracking_code,pv.sku),p.name,concat_ws(' • ','SKU '||pv.sku,nullif(pv.part_number,''),nullif(pv.barcode,'')),'inventory'::text,null::uuid from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and (lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'customer',c.id,c.tracking_code,c.name,concat_ws(' • ',c.phone,c.email,c.tax_number),'customers',null::uuid from public.customers c where c.tenant_id=p_tenant_id and (lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.email,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
    union all select 'supplier',s.id,s.tracking_code,s.name,concat_ws(' • ',s.phone,s.email,s.tax_number),'suppliers',null::uuid from public.suppliers s where s.tenant_id=p_tenant_id and (lower(s.name) like q or lower(coalesce(s.phone,'')) like q or lower(coalesce(s.email,'')) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'sale',s.id,s.tracking_code,coalesce(dn.terminal_number,ln.local_number,s.sale_number),c.name||' • '||s.grand_total::text,'sales',o.location_id from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id where s.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(s.sale_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(c.name) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'purchase',p.id,p.tracking_code,coalesce(dn.terminal_number,ln.local_number,p.purchase_number),s.name||' • '||p.grand_total::text,'purchases',o.location_id from public.purchases p join public.suppliers s on s.id=p.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id where p.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(p.purchase_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(s.name) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'loan',l.id,l.loan_number,l.loan_number,c.name||' • '||l.status||' • outstanding '||round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2)::text,'loans',l.location_id from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id where l.tenant_id=p_tenant_id and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key='loans' and tm.enabled) and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'loans.view') or private.erp_has_permission(p_tenant_id,'loans.manage')) and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view') and (lower(l.loan_number) like q or lower(c.name) like q or lower(coalesce(c.tracking_code,'')) like q or lower(coalesce(l.external_client_reference,'')) like q or lower(coalesce(l.purpose,'')) like q)
    union all select 'account',a.id,a.code,a.name,a.account_type,'accounting',null::uuid from public.accounting_accounts a where a.tenant_id=p_tenant_id and active and (lower(a.code) like q or lower(a.name) like q)
    union all select 'stock_transfer',t.id,t.transfer_number,t.transfer_number,fl.location_code||' → '||tl.location_code||' • '||t.status,'stock_transfers',t.from_location_id from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id where t.tenant_id=p_tenant_id and lower(t.transfer_number) like q
    union all select 'task',t.id,null,t.title,coalesce(t.status,'')||' • '||coalesce(t.description,''),'tasks',t.location_id from public.business_tasks t where t.tenant_id=p_tenant_id and (lower(t.title) like q or lower(coalesce(t.description,'')) like q)
    union all select 'workshop_job',j.id,j.job_number,j.job_number,coalesce(v.vehicle_number,'')||' • '||j.status,'workshop',j.location_id from public.workshop_job_cards j join public.workshop_vehicles v on v.id=j.vehicle_id where j.tenant_id=p_tenant_id and (lower(j.job_number) like q or lower(v.vehicle_number) like q)
  )z limit lim;
end $$;
grant execute on function public.global_search_v4(uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(183,'4.9.0','Loans & Credit','Shared Client/POS loan list/detail/dashboard, proactive overdue/payment/maturity/rate warnings and customer loan summary API read models.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 183 loan reporting API applied' as status;

-- ============================================================================
-- MIGRATION 184: 184_v490_api_contract.sql
-- ============================================================================

-- THQ ERP v4.9.0 — THQ API contract for Loans & Credit.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
      'loans','loan-dashboard','loan-warnings','customer-loans',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'loan_engine','v4.9.0','loan_accounting','double_entry','loan_warnings',true,
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(184,'4.9.0','Loans & Credit','THQ API v1 contract expanded with shared loan lifecycle, dashboard, warnings and customer loan summary resources.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 184 API contract applied' as status;

-- ============================================================================
-- MIGRATION 185: 185_v490_release_contract.sql
-- ============================================================================

-- THQ ERP v4.9.0 — Loans & Credit release contract and deployment verification.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Loans & Credit',
   'api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'purchases_list_v32','purchases_create_v489','purchase_request_list_v484','purchasing_dashboard_v484','purchase_invoice_create_v489',
    'loan_create_v490','loan_update_v490','loan_submit_v490','loan_decide_v490','loan_disburse_v490',
    'loan_payment_create_v490','loan_payment_reverse_v490','loan_rate_change_v490','loan_status_v490',
    'loan_collateral_save_v490','loan_guarantor_save_v490','loan_list_v490','loan_detail_v490',
    'loan_dashboard_v490','loan_warnings_v490','customer_loan_summary_v490','notifications_list_v4','business_attention_summary_v480','thq_api_contract_v480'
  ];
begin
  if to_regclass('public.loan_accounts_v490') is null then v_missing:=array_append(v_missing,'loan_accounts_v490');end if;
  if to_regclass('public.loan_schedule_v490') is null then v_missing:=array_append(v_missing,'loan_schedule_v490');end if;
  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.loan_payment_allocations_v490') is null then v_missing:=array_append(v_missing,'loan_payment_allocations_v490');end if;
  if to_regclass('public.loan_rate_history_v490') is null then v_missing:=array_append(v_missing,'loan_rate_history_v490');end if;
  if to_regclass('public.loan_collateral_v490') is null then v_missing:=array_append(v_missing,'loan_collateral_v490');end if;
  if to_regclass('public.loan_guarantors_v490') is null then v_missing:=array_append(v_missing,'loan_guarantors_v490');end if;
  if to_regclass('public.loan_events_v490') is null then v_missing:=array_append(v_missing,'loan_events_v490');end if;

  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if not exists(select 1 from public.modules where key='loans' and is_active) then v_missing:=array_append(v_missing,'module.loans');end if;
  if not exists(select 1 from public.permissions where key='loans.view') then v_missing:=array_append(v_missing,'permission.loans.view');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_income') then v_missing:=array_append(v_missing,'mapping.loan_interest_income');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_penalty_income') then v_missing:=array_append(v_missing,'mapping.loan_penalty_income');end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where app_key='client' and module_key='loans') then v_missing:=array_append(v_missing,'navigation.client.loans');end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where app_key='pos' and module_key='loans') then v_missing:=array_append(v_missing,'navigation.pos.loans');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',185,
    'api_version','v1',
    'purchasing_v2_resilience',true,
    'loans_client',true,
    'loans_pos',true,
    'fixed_variable_interest',true,
    'repayment_schedule',true,
    'maturity_warnings',true,
    'notification_attention_integration',true,
    'overdue_penalties',true,
    'loan_accounting',true,
    'cash_drawer_collection',true,
    'collateral_guarantors',true,
    'customer_linkage',true
  );
end $$;
grant execute on function public.thq_v490_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(185,'4.9.0','Loans & Credit','Client/POS loan management release with fixed/variable rates, schedules, warnings, collections, accounting integration, collateral/guarantors and Purchasing V2 resilience.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 185 release contract applied' as status;

-- ============================================================================
-- MIGRATION 186: 186_v490_transaction_workspaces.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 19 — fast transaction entry + detail workspaces.
-- Keeps schema_version on the 4.9.0 compatibility line so existing Build 18
-- clients remain valid while Build 19 introduces forward-compatible checks.
begin;

-- -----------------------------------------------------------------------------
-- Module catalogue: keep the stable sales/purchases keys but present them as
-- fast entry modules, then add separate management/detail modules.
-- -----------------------------------------------------------------------------
update public.modules
set name='New Sale',
    description='Fast sales invoice entry'
where key='sales';

update public.modules
set name='New Purchase',
    description='Fast direct purchase entry'
where key='purchases';

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values
  ('sales_details','Sales Details','Sales history and invoice detail workspace','Operations',false,31,true,false,false),
  ('purchase_details','Purchase Details','Purchase requests, orders, GRN, supplier invoices, ledger, price history and purchase history','Operations',false,41,true,false,false)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  is_beta=false;

insert into public.module_dependencies(module_key,depends_on_module_key)
values
  ('sales_details','sales'),
  ('purchase_details','purchases')
on conflict do nothing;

-- Existing tenants that can transact automatically receive the matching detail
-- workspace. This is additive; no existing base module is renamed or removed.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tenant_id,'sales_details',true
from public.tenant_modules
where module_key='sales' and enabled
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select tenant_id,'purchase_details',true
from public.tenant_modules
where module_key='purchases' and enabled
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.business_template_modules(template_id,module_key)
select distinct template_id,'sales_details'
from public.business_template_modules
where module_key='sales'
on conflict do nothing;

insert into public.business_template_modules(template_id,module_key)
select distinct template_id,'purchase_details'
from public.business_template_modules
where module_key='purchases'
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'sales_details'
from public.subscription_plan_modules
where module_key='sales'
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'purchase_details'
from public.subscription_plan_modules
where module_key='purchases'
on conflict do nothing;

-- Keep the companion detail workspaces automatically entitled on all future
-- plan edits/creates. The existing procedure name/signature is preserved for
-- older Admin builds.
create or replace function public.platform_subscription_plan_upsert(
  p_id uuid,p_key text,p_name text,p_description text,p_monthly_price numeric,p_yearly_price numeric,p_currency_code text,p_is_active boolean,p_sort_order integer,p_module_keys text[],p_limits jsonb
)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.platform_v2_has_role('billing_admin') then raise exception 'Billing admin access required'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Plan key and name are required'; end if;
  if coalesce(p_monthly_price,0)<0 or coalesce(p_yearly_price,0)<0 then raise exception 'Prices cannot be negative'; end if;
  if p_id is null then
    insert into public.subscription_plans(key,name,description,monthly_price,yearly_price,currency_code,is_active,sort_order,limits)
    values(trim(p_key),trim(p_name),nullif(trim(p_description),''),coalesce(p_monthly_price,0),coalesce(p_yearly_price,0),upper(coalesce(nullif(trim(p_currency_code),''),'INR')),coalesce(p_is_active,true),coalesce(p_sort_order,100),coalesce(p_limits,'{}'::jsonb))
    on conflict(key) do update set name=excluded.name,description=excluded.description,monthly_price=excluded.monthly_price,yearly_price=excluded.yearly_price,currency_code=excluded.currency_code,is_active=excluded.is_active,sort_order=excluded.sort_order,limits=excluded.limits,updated_at=now()
    returning id into v_id;
  else
    update public.subscription_plans set name=trim(p_name),description=nullif(trim(p_description),''),monthly_price=coalesce(p_monthly_price,0),yearly_price=coalesce(p_yearly_price,0),currency_code=upper(coalesce(nullif(trim(p_currency_code),''),'INR')),is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,100),limits=coalesce(p_limits,limits),updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Plan not found'; end if;
  end if;

  delete from public.subscription_plan_modules where plan_id=v_id;
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,x
  from unnest(coalesce(p_module_keys,array[]::text[])) x
  where exists(select 1 from public.modules m where m.key=x and m.is_active)
  on conflict do nothing;

  -- Required base dependencies when a detail module is selected directly.
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,md.depends_on_module_key
  from public.subscription_plan_modules chosen
  join public.module_dependencies md on md.module_key=chosen.module_key
  join public.modules dependency on dependency.key=md.depends_on_module_key and dependency.is_active
  where chosen.plan_id=v_id
  on conflict do nothing;

  -- Companion workspaces always follow the fast transaction module.
  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,'sales_details'
  where exists(select 1 from public.subscription_plan_modules where plan_id=v_id and module_key='sales')
    and exists(select 1 from public.modules where key='sales_details' and is_active)
  on conflict do nothing;

  insert into public.subscription_plan_modules(plan_id,module_key)
  select v_id,'purchase_details'
  where exists(select 1 from public.subscription_plan_modules where plan_id=v_id and module_key='purchases')
    and exists(select 1 from public.modules where key='purchase_details' and is_active)
  on conflict do nothing;

  insert into public.subscription_plan_modules(plan_id,module_key) values(v_id,'dashboard') on conflict do nothing;
  perform private.platform_audit_write('subscription_plan.upsert','subscription_plan',v_id::text,null,jsonb_build_object('key',p_key));
  return v_id;
end $$;
grant execute on function public.platform_subscription_plan_upsert(uuid,text,text,text,numeric,numeric,text,boolean,integer,text[],jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Client navigation. Add to both the global/default menu and any tenant menu
-- that has already been cloned/customized. Existing New Sale/New Purchase nodes
-- are retained, so older Client builds keep resolving the same module keys.
-- -----------------------------------------------------------------------------
insert into public.app_menu_nodes_v45(
  tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata
)
select p.tenant_id,'client','sales_details','module','sales_details',p.id,
       'Sales Details','sales',25,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p
where p.app_key='client' and p.node_key='operations' and p.node_type='group'
on conflict do nothing;

insert into public.app_menu_nodes_v45(
  tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata
)
select p.tenant_id,'client','purchase_details','module','purchase_details',p.id,
       'Purchase Details','purchases',35,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p
where p.app_key='client' and p.node_key='operations' and p.node_type='group'
on conflict do nothing;

-- Keep default labels explicit without changing tenant-customized labels.
update public.app_menu_nodes_v45
set label='New Sale', sort_order=20, updated_at=now()
where tenant_id is null and app_key='client' and node_key='sales' and module_key='sales';

update public.app_menu_nodes_v45
set label='New Purchase', sort_order=30, updated_at=now()
where tenant_id is null and app_key='client' and node_key='purchases' and module_key='purchases';

-- -----------------------------------------------------------------------------
-- Compatibility contract.
-- schema_version stays 4.9.0 intentionally. Build 18's exact-version startup
-- check therefore continues to work after migration 186. Build 19 and later use
-- minimum_app_version instead of exact schema equality, allowing future additive
-- backend migrations without forcing a Client EXE replacement.
-- -----------------------------------------------------------------------------
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Transaction Workspaces',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build19_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
begin
  if not exists(select 1 from public.modules where key='sales' and is_active) then
    v_missing:=array_append(v_missing,'module.sales');
  end if;
  if not exists(select 1 from public.modules where key='sales_details' and is_active) then
    v_missing:=array_append(v_missing,'module.sales_details');
  end if;
  if not exists(select 1 from public.modules where key='purchases' and is_active) then
    v_missing:=array_append(v_missing,'module.purchases');
  end if;
  if not exists(select 1 from public.modules where key='purchase_details' and is_active) then
    v_missing:=array_append(v_missing,'module.purchase_details');
  end if;
  if not exists(select 1 from public.module_dependencies where module_key='sales_details' and depends_on_module_key='sales') then
    v_missing:=array_append(v_missing,'dependency.sales_details.sales');
  end if;
  if not exists(select 1 from public.module_dependencies where module_key='purchase_details' and depends_on_module_key='purchases') then
    v_missing:=array_append(v_missing,'dependency.purchase_details.purchases');
  end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='sales_details' and module_key='sales_details') then
    v_missing:=array_append(v_missing,'navigation.client.sales_details');
  end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where tenant_id is null and app_key='client' and node_key='purchase_details' and module_key='purchase_details') then
    v_missing:=array_append(v_missing,'navigation.client.purchase_details');
  end if;
  if to_regprocedure('public.purchases_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,uuid,uuid,text)') is null then
    v_missing:=array_append(v_missing,'purchases_create_v489');
  end if;
  if to_regprocedure('public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then
    v_missing:=array_append(v_missing,'sales_create_v489');
  end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',186,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'new_purchase_fast_entry',true,
    'purchase_details_workspace',true,
    'new_sale_fast_entry',true,
    'sales_details_workspace',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build19_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  186,
  '4.9.0',
  'Transaction Workspaces',
  'Build 19 separates fast New Purchase/New Sale entry from Purchase Details/Sales Details and introduces forward-compatible Client/backend version checks.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 19 migration 186 transaction workspaces applied' as status;

-- ============================================================================
-- MIGRATION 187: 187_v490_purchase_loan_completion.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchasing/Loan completion and runtime fixes.
begin;

-- Fix loan warning CTE column names. The original UNION CTE inherited unnamed
-- literal columns, so ORDER BY w.severity failed with 42703 on PostgreSQL.
create or replace function public.loan_warnings_v490(
  p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 250
) returns table(
  warning_type text,severity text,loan_id uuid,loan_number text,client_id uuid,client_name text,location_id uuid,
  event_date date,amount numeric,days_until integer,message text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  with scoped as(
    select l.*,c.name client_name
    from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id
    where l.tenant_id=p_tenant_id and l.status in('approved','active','defaulted')
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), warnings(warning_type,severity,loan_id,loan_number,client_id,client_name,location_id,event_date,amount,days_until,message) as(
    select 'overdue_payment'::text,'danger'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      ('Installment #'||s.installment_no::text||' overdue by '||(current_date-s.due_date)::text||' day(s)')::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'payment_due'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      ('Installment #'||s.installment_no::text||' due in '||greatest(s.due_date-current_date,0)::text||' day(s)')::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and s.due_date between current_date and current_date+l.payment_warning_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'maturity'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.maturity_date,
      round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),(l.maturity_date-current_date)::integer,
      ('Loan matures in '||greatest(l.maturity_date-current_date,0)::text||' day(s)')::text
    from scoped l where l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days
    union all
    select 'rate_review'::text,'info'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.next_rate_review_date,
      null::numeric,(l.next_rate_review_date-current_date)::integer,
      ('Variable interest rate review due in '||greatest(l.next_rate_review_date-current_date,0)::text||' day(s)')::text
    from scoped l where l.rate_type='variable' and l.next_rate_review_date is not null
      and l.next_rate_review_date between current_date and current_date+greatest(l.payment_warning_days,7)
  )
  select w.warning_type,w.severity,w.loan_id,w.loan_number,w.client_id,w.client_name,w.location_id,
         w.event_date,w.amount,w.days_until,w.message
  from warnings w
  order by case w.severity when 'danger' then 0 when 'warning' then 1 else 2 end,w.event_date,w.loan_number
  limit least(greatest(coalesce(p_limit,250),1),2000);
end $$;
grant execute on function public.loan_warnings_v490(uuid,uuid,integer) to authenticated;

-- Fix Purchase Price History. The original anonymous UNION subquery did not
-- expose document_number/purchase_date/supplier_name/product_name aliases.
create or replace function public.purchase_price_history_v484(
 p_tenant_id uuid,p_variant_id uuid default null,p_supplier_id uuid default null,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns table(
 source_type text,document_id uuid,document_number text,purchase_date date,location_id uuid,location_name text,supplier_id uuid,supplier_name text,
 variant_id uuid,product_name text,sku text,quantity numeric,unit_cost numeric,tax_rate numeric,line_total numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query
 with history(source_type,document_id,document_number,purchase_date,location_id,location_name,supplier_id,supplier_name,variant_id,product_name,sku,quantity,unit_cost,tax_rate,line_total) as (
   select 'purchase_invoice_v484'::text, ih.id,ih.invoice_number::text,ih.invoice_date,ih.location_id,l.name::text,ih.supplier_id,s.name::text,ii.variant_id,p.name::text,pv.sku::text,ii.quantity::numeric,ii.unit_cost::numeric,ii.tax_rate::numeric,ii.line_total::numeric
   from public.purchase_invoices_v484 ih
   join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id=ih.id
   join public.product_variants pv on pv.id=ii.variant_id
   join public.products p on p.id=pv.product_id
   join public.suppliers s on s.id=ih.supplier_id
   join public.business_locations l on l.id=ih.location_id
   where ih.tenant_id=p_tenant_id and ih.status in('posted','part_paid','paid')
   union all
   select 'direct_purchase'::text,ph.id,ph.purchase_number::text,ph.purchase_date,o.location_id,l.name::text,ph.supplier_id,s.name::text,pi.variant_id,p.name::text,pv.sku::text,
          coalesce(pi.entered_quantity,pi.quantity)::numeric,coalesce(pi.entered_unit_cost,pi.unit_cost)::numeric,pi.tax_rate::numeric,pi.line_total::numeric
   from public.purchases ph
   join public.purchase_items pi on pi.purchase_id=ph.id
   join public.product_variants pv on pv.id=pi.variant_id
   join public.products p on p.id=pv.product_id
   join public.suppliers s on s.id=ph.supplier_id
   left join public.document_origins o on o.entity_type='purchase' and o.entity_id=ph.id and o.tenant_id=ph.tenant_id
   left join public.business_locations l on l.id=o.location_id
   where ph.tenant_id=p_tenant_id and coalesce(ph.status,'') not in('cancelled','void')
 )
 select h.source_type,h.document_id,h.document_number,h.purchase_date,h.location_id,h.location_name,h.supplier_id,h.supplier_name,
        h.variant_id,h.product_name,h.sku,h.quantity,h.unit_cost,h.tax_rate,h.line_total
 from history h
 where (p_variant_id is null or h.variant_id=p_variant_id)
   and (p_supplier_id is null or h.supplier_id=p_supplier_id)
   and (p_location_id is null or h.location_id=p_location_id)
   and (h.location_id is null or private.erp_document_scope_allowed(p_tenant_id,h.location_id,p_location_id,'view'))
   and (trim(coalesce(p_query,''))='' or lower(coalesce(h.document_number,'')) like q or lower(coalesce(h.supplier_name,'')) like q or lower(coalesce(h.product_name,'')) like q or lower(coalesce(h.sku,'')) like q)
 order by h.purchase_date desc,h.document_number desc
 limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer) to authenticated;

-- A compact, user-facing purchasing lifecycle summary used by the details UI.
create or replace function public.purchase_cycle_summary_v490(p_tenant_id uuid,p_purchase_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id;
  if v_loc is null then raise exception 'Purchase Order not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
  select jsonb_build_object(
    'purchase_order_id',po.id,'order_number',po.order_number,'status',po.status,
    'request_id',po.request_id,'request_number',pr.request_number,
    'supplier_id',po.supplier_id,'supplier_name',s.name,'location_id',po.location_id,'location_name',l.name,
    'ordered_quantity',coalesce(sum(i.quantity),0),'received_quantity',coalesce(sum(i.received_quantity),0),
    'accepted_quantity',coalesce(sum(i.accepted_quantity),0),'damaged_quantity',coalesce(sum(i.damaged_quantity),0),
    'rejected_quantity',coalesce(sum(i.rejected_quantity),0),'invoiced_quantity',coalesce(sum(i.invoiced_quantity),0),
    'remaining_receive_quantity',coalesce(sum(greatest(i.quantity-i.received_quantity,0)),0),
    'remaining_invoice_quantity',coalesce(sum(greatest(i.accepted_quantity+i.damaged_quantity-i.invoiced_quantity,0)),0),
    'po_total',po.grand_total,
    'posted_invoice_total',coalesce((select sum(pi.grand_total) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status in('posted','part_paid','paid')),0),
    'invoice_balance_due',coalesce((select sum(pi.balance_due) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status in('posted','part_paid')),0),
    'grn_count',(select count(*) from public.goods_receipts_v484 g where g.purchase_order_id=po.id and g.status='posted'),
    'invoice_count',(select count(*) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status<>'void')
  ) into v
  from public.purchase_orders_v480 po
  join public.suppliers s on s.id=po.supplier_id
  join public.business_locations l on l.id=po.location_id
  left join public.purchase_requests_v484 pr on pr.id=po.request_id
  left join public.purchase_order_items_v480 i on i.purchase_order_id=po.id
  where po.tenant_id=p_tenant_id and po.id=p_purchase_order_id
  group by po.id,pr.request_number,s.name,l.name;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.purchase_cycle_summary_v490(uuid,uuid) to authenticated;

-- Keep the rounded v4.8.9 invoice posting semantics, but finish the PO
-- automatically once everything received is invoiced and all ordered quantity
-- has been physically processed.
create or replace function public.purchase_invoice_post_v484(p_tenant_id uuid,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_lines jsonb:='[]'::jsonb;v_net numeric;v_open boolean;v_old_status text;begin
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;
  if not found then raise exception 'Purchase Invoice not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status in('posted','part_paid','paid') then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status',i.status,'idempotent',true);end if;
  if i.status<>'draft' then raise exception 'Only Draft invoices can be posted';end if;
  if i.grand_total<=0 then raise exception 'Purchase Invoice total must be positive';end if;
  v_net:=greatest(i.subtotal+i.additional_charges,0);
  if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',i.supplier_id,'description','Purchase invoice / inventory'));end if;
  if i.tax_total>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',i.tax_total,'credit',0,'description','Input GST'));end if;
  if i.round_off>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',i.round_off,'credit',0,'description','Purchase invoice round off'));end if;
  if i.round_off< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(i.round_off),'description','Purchase invoice round off'));end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',i.grand_total,'party_type','supplier','party_id',i.supplier_id,'description','Supplier payable'));
  perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,'Purchase Invoice '||i.invoice_number,'purchase_invoice_v484',i.id,i.invoice_number,v_lines);
  update public.purchase_invoices_v484 set status='posted',posted_by=auth.uid(),posted_at=now(),balance_due=grand_total-paid_total,updated_at=now() where id=i.id;
  for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop
    update public.purchase_order_items_v480 set invoiced_quantity=invoiced_quantity+li.qty where id=li.purchase_order_item_id;
  end loop;

  select exists(
    select 1 from public.purchase_order_items_v480 poi
    where poi.purchase_order_id=i.purchase_order_id
      and (poi.received_quantity+0.000001<poi.quantity or poi.invoiced_quantity+0.000001<poi.accepted_quantity+poi.damaged_quantity)
  ) into v_open;
  if not v_open then
    select status into v_old_status from public.purchase_orders_v480 where id=i.purchase_order_id for update;
    if v_old_status not in('closed','cancelled') then
      update public.purchase_orders_v480 set status='closed',closed_at=coalesce(closed_at,now()),updated_at=now() where id=i.purchase_order_id;
      insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
      values(i.purchase_order_id,v_old_status,'closed','All received quantities invoiced; Purchase Order closed automatically',auth.uid());
    end if;
  end if;

  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'post');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','posted','grand_total',i.grand_total,'round_off',i.round_off,'purchase_order_status',case when v_open then null else 'closed' end);
end $$;
grant execute on function public.purchase_invoice_post_v484(uuid,uuid) to authenticated;

-- A single server-side health check for the two workflows. It lets the Client
-- present a clean actionable message instead of raw FunctionsHttp/PostgREST errors.
create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if to_regprocedure('public.loan_warnings_v490(uuid,uuid,integer)') is null then v_missing:=array_append(v_missing,'loan_warnings_v490');end if;
  if to_regprocedure('public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid)') is null then v_missing:=array_append(v_missing,'loan_payment_create_v490');end if;
  if to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_create_v484');end if;
  if to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'goods_receipt_post_v484');end if;
  if to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is null then v_missing:=array_append(v_missing,'purchase_invoice_post_v484');end if;
  if to_regprocedure('public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_price_history_v484');end if;
  return jsonb_build_object('ok',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'migration_required',187);
end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(187,'4.9.0','Purchase & Loan Completion','Fixes loan warnings and purchase price history, adds purchase-cycle summary and automatic PO closing after complete receiving/invoicing.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 187 purchase/loan completion applied' as status;

-- ============================================================================
-- MIGRATION 188: 188_v490_transaction_bulk_import.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — auditable bulk Sales/Purchase import.
begin;

create table if not exists public.transaction_import_runs_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  location_id uuid not null references public.business_locations(id) on delete restrict,
  source_name text,
  source_key text not null,
  row_count integer not null default 0,
  document_count integer not null default 0,
  success_count integer not null default 0,
  failed_count integer not null default 0,
  skipped_count integer not null default 0,
  status text not null default 'processing' check(status in('processing','completed','completed_with_errors','failed')),
  result jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(tenant_id,import_type,source_key)
);
create index if not exists idx_transaction_import_runs_v490 on public.transaction_import_runs_v490(tenant_id,created_at desc);
alter table public.transaction_import_runs_v490 enable row level security;
revoke all on public.transaction_import_runs_v490 from anon,authenticated;

create table if not exists public.transaction_import_documents_v490(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.transaction_import_runs_v490(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  external_key text not null,
  entity_id uuid,
  entity_number text,
  status text not null default 'processing' check(status in('processing','success','failed')),
  error_message text,
  response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,import_type,external_key)
);
create index if not exists idx_transaction_import_documents_v490_run on public.transaction_import_documents_v490(run_id,status);
alter table public.transaction_import_documents_v490 enable row level security;
revoke all on public.transaction_import_documents_v490 from anon,authenticated;

create or replace function public.transaction_bulk_import_v490(
  p_tenant_id uuid,
  p_import_type text,
  p_location_id uuid,
  p_device_id uuid,
  p_source_name text,
  p_source_key text,
  p_documents jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_type text:=lower(trim(coalesce(p_import_type,'')));
  v_run uuid;v_existing public.transaction_import_runs_v490%rowtype;
  v_success integer:=0;v_failed integer:=0;v_skipped integer:=0;v_rows integer:=0;
  v_results jsonb:='[]'::jsonb;d jsonb;v_external text;v_doc public.transaction_import_documents_v490%rowtype;
  v_result jsonb;v_entity uuid;v_number text;v_request text;v_message text;
  v_party uuid;v_items jsonb;v_date date;v_due date;v_amount numeric;v_add numeric;v_round numeric;
begin
  if v_type not in('sales','purchases') then raise exception 'Import type must be sales or purchases';end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then raise exception 'Import source key is required';end if;
  if p_documents is null or jsonb_typeof(p_documents)<>'array' or jsonb_array_length(p_documents)=0 then raise exception 'At least one document is required';end if;
  if jsonb_array_length(p_documents)>1000 then raise exception 'A single import is limited to 1000 documents';end if;
  if p_location_id is null then raise exception 'A concrete store/location is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  if v_type='purchases' then perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  else
    if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales management permission required';end if;
  end if;

  select * into v_existing from public.transaction_import_runs_v490 where tenant_id=p_tenant_id and import_type=v_type and source_key=trim(p_source_key) for update;
  if found and v_existing.status in('completed','completed_with_errors') then
    return coalesce(v_existing.result,'{}'::jsonb)||jsonb_build_object('idempotent_replay',true,'run_id',v_existing.id);
  end if;
  if found then
    v_run:=v_existing.id;
    update public.transaction_import_runs_v490 set status='processing',source_name=nullif(trim(coalesce(p_source_name,'')),''),completed_at=null where id=v_run;
  else
    insert into public.transaction_import_runs_v490(tenant_id,import_type,location_id,source_name,source_key,document_count,created_by)
    values(p_tenant_id,v_type,p_location_id,nullif(trim(coalesce(p_source_name,'')),''),trim(p_source_key),jsonb_array_length(p_documents),auth.uid()) returning id into v_run;
  end if;

  for d in select value from jsonb_array_elements(p_documents) loop
    v_rows:=v_rows+greatest(coalesce(nullif(d->>'source_row_count','')::integer,1),1);
    v_external:=nullif(trim(coalesce(d->>'external_key',d->>'document_ref','')),'');
    if v_external is null then
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('status','failed','error','Each document requires external_key/document_ref'));
      continue;
    end if;

    select * into v_doc from public.transaction_import_documents_v490 where tenant_id=p_tenant_id and import_type=v_type and external_key=v_external for update;
    if found and v_doc.status='success' then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_doc.entity_id,'entity_number',v_doc.entity_number,'idempotent_replay',true));
      continue;
    end if;
    if found then
      update public.transaction_import_documents_v490 set run_id=v_run,status='processing',error_message=null,updated_at=now() where id=v_doc.id;
    else
      insert into public.transaction_import_documents_v490(run_id,tenant_id,import_type,external_key,status)
      values(v_run,p_tenant_id,v_type,v_external,'processing') returning * into v_doc;
    end if;

    begin
      v_items:=coalesce(d->'items','[]'::jsonb);
      if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Document has no items';end if;
      v_date:=coalesce(nullif(d->>'document_date','')::date,current_date);
      v_due:=nullif(d->>'due_date','')::date;
      v_add:=greatest(coalesce(nullif(d->>'additional_charges','')::numeric,0),0);
      v_round:=coalesce(nullif(d->>'round_off','')::numeric,0);
      v_amount:=greatest(coalesce(nullif(d->>'initial_payment','')::numeric,0),0);
      v_request:='bulk-'||v_type||'-'||md5(p_tenant_id::text||':'||v_external);

      if v_type='sales' then
        v_party:=nullif(d->>'customer_id','')::uuid;
        if v_party is null then raise exception 'Customer is required';end if;
        v_result:=public.sales_create_v489(
          p_tenant_id,v_party,v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'cash'),coalesce(d->>'payment_reference',''),coalesce(d->>'notes',''),
          p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'sale_id','')::uuid;v_number:=coalesce(v_result->>'invoice_number',v_result->>'sale_number');
      else
        v_party:=nullif(d->>'supplier_id','')::uuid;
        if v_party is null then raise exception 'Supplier is required';end if;
        if nullif(trim(coalesce(d->>'supplier_invoice_number','')),'') is null then raise exception 'Supplier invoice number is required';end if;
        v_result:=public.purchases_create_v489(
          p_tenant_id,v_party,trim(d->>'supplier_invoice_number'),v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'bank'),coalesce(d->>'notes',''),p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'purchase_id','')::uuid;v_number:=v_result->>'purchase_number';
      end if;
      if v_entity is null then raise exception 'Transaction creation returned no document ID';end if;
      update public.transaction_import_documents_v490 set status='success',entity_id=v_entity,entity_number=v_number,response=coalesce(v_result,'{}'::jsonb),error_message=null,updated_at=now() where id=v_doc.id;
      v_success:=v_success+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_entity,'entity_number',v_number,'response',v_result));
    exception when others then
      v_message:=sqlerrm;
      update public.transaction_import_documents_v490 set status='failed',error_message=v_message,response='{}'::jsonb,updated_at=now() where id=v_doc.id;
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','failed','error',v_message));
    end;
  end loop;

  v_result:=jsonb_build_object(
    'success',v_failed=0,'run_id',v_run,'import_type',v_type,'source_key',trim(p_source_key),
    'success_count',v_success,'failed_count',v_failed,'skipped_count',v_skipped,'document_count',jsonb_array_length(p_documents),'row_count',v_rows,
    'documents',v_results
  );
  update public.transaction_import_runs_v490
  set row_count=v_rows,document_count=jsonb_array_length(p_documents),success_count=v_success,failed_count=v_failed,skipped_count=v_skipped,
      status=case when v_failed=0 then 'completed' else 'completed_with_errors' end,result=v_result,completed_at=now()
  where id=v_run;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','bulk_'||v_type,v_run::text,'import');
  return v_result;
exception when others then
  if v_run is not null then
    update public.transaction_import_runs_v490 set status='failed',result=jsonb_build_object('error',sqlerrm),completed_at=now() where id=v_run;
  end if;
  raise;
end $$;
grant execute on function public.transaction_bulk_import_v490(uuid,text,uuid,uuid,text,text,jsonb) to authenticated;

create or replace function public.transaction_bulk_import_history_v490(p_tenant_id uuid,p_import_type text default null,p_limit integer default 100)
returns table(run_id uuid,import_type text,location_id uuid,location_name text,source_name text,source_key text,row_count integer,document_count integer,success_count integer,failed_count integer,skipped_count integer,status text,created_at timestamptz,completed_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  return query
  select r.id,r.import_type,r.location_id,l.name::text,r.source_name,r.source_key,r.row_count,r.document_count,r.success_count,r.failed_count,r.skipped_count,r.status,r.created_at,r.completed_at
  from public.transaction_import_runs_v490 r join public.business_locations l on l.id=r.location_id
  where r.tenant_id=p_tenant_id and (p_import_type is null or trim(p_import_type)='' or r.import_type=lower(trim(p_import_type)))
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view')
  order by r.created_at desc limit greatest(1,least(coalesce(p_limit,100),1000));
end $$;
grant execute on function public.transaction_bulk_import_history_v490(uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(188,'4.9.0','Transaction Bulk Import','Auditable, idempotent Excel bulk import engine for Sales and Direct Purchases using the normal stock, tax, payment and accounting transaction functions.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 188 transaction bulk import applied' as status;

-- ============================================================================
-- MIGRATION 189: 189_v490_purchase_controls.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchasing operational controls and reversals.
begin;

create or replace function public.goods_receipt_cancel_v490(
  p_tenant_id uuid,p_goods_receipt_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare g public.goods_receipts_v484%rowtype;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required';end if;
  select * into g from public.goods_receipts_v484 where tenant_id=p_tenant_id and id=p_goods_receipt_id for update;
  if not found then raise exception 'GRN not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,g.location_id,true);
  if g.status='cancelled' then return jsonb_build_object('success',true,'goods_receipt_id',g.id,'status','cancelled','idempotent',true);end if;
  if g.status<>'draft' then raise exception 'Only Draft GRNs can be cancelled. Posted receipts require a controlled purchase return/reversal so stock traceability is preserved';end if;
  update public.goods_receipts_v484 set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),notes=concat_ws(E'\n',notes,'Cancelled: '||trim(p_reason)),updated_at=now() where id=g.id;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','goods_receipt',g.id::text,'cancel');
  return jsonb_build_object('success',true,'goods_receipt_id',g.id,'grn_number',g.grn_number,'status','cancelled');
end $$;
grant execute on function public.goods_receipt_cancel_v490(uuid,uuid,text) to authenticated;

create or replace function public.purchase_invoice_void_v490(
  p_tenant_id uuid,p_purchase_invoice_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_po_status text;v_new_po_status text;v_has_received boolean;v_complete_received boolean;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;
  if not found then raise exception 'Purchase Invoice not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status='void' then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'status','void','idempotent',true);end if;
  if i.status not in('draft','posted') then raise exception 'Only Draft or unpaid Posted invoices can be voided';end if;
  if coalesce(i.paid_total,0)>0.005 or exists(
    select 1 from public.supplier_payment_allocations_v484 a
    join public.supplier_payments_v484 p on p.id=a.supplier_payment_id
    where a.purchase_invoice_id=i.id and p.status='posted'
  ) then raise exception 'Invoice has supplier payments. Void/reverse those payments first';end if;

  if i.status='posted' then
    update public.journal_entries set status='reversed'
    where tenant_id=p_tenant_id and source_type='purchase_invoice_v484' and source_id=i.id and status='posted';
    insert into public.supplier_ledger_entries_v484(
      tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
    ) values(
      p_tenant_id,i.supplier_id,i.location_id,current_date,'void',i.id,i.invoice_number,
      'Void purchase invoice: '||trim(p_reason),0,i.grand_total,auth.uid()
    ) on conflict(tenant_id,entry_type,source_id) do nothing;
    for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop
      update public.purchase_order_items_v480
      set invoiced_quantity=greatest(invoiced_quantity-li.qty,0)
      where id=li.purchase_order_item_id;
    end loop;
  end if;

  update public.purchase_invoices_v484
  set status='void',balance_due=0,updated_at=now(),notes=concat_ws(E'\n',notes,'Voided: '||trim(p_reason))
  where id=i.id;

  if i.purchase_order_id is not null then
    select status into v_po_status from public.purchase_orders_v480 where id=i.purchase_order_id for update;
    select exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity>0.000001),
           not exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity+0.000001<quantity)
    into v_has_received,v_complete_received;
    v_new_po_status:=case when v_complete_received then 'received' when v_has_received then 'partially_received' else case when v_po_status='draft' then 'draft' else 'ordered' end end;
    if v_po_status='closed' or v_po_status='received' then
      update public.purchase_orders_v480 set status=v_new_po_status,closed_at=null,updated_at=now() where id=i.purchase_order_id;
      insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
      values(i.purchase_order_id,v_po_status,v_new_po_status,'Reopened because invoice '||i.invoice_number||' was voided',auth.uid());
    end if;
  end if;

  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'void');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','void','purchase_order_status',v_new_po_status);
end $$;
grant execute on function public.purchase_invoice_void_v490(uuid,uuid,text) to authenticated;

create or replace function public.supplier_payment_create_v490(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,
  p_allocations jsonb default '[]'::jsonb,p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_payment uuid;v_no text;v_shift uuid;begin
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=p_location_id and d.status='active'
  ) then raise exception 'Invalid device for supplier payment location';end if;
  v:=public.supplier_payment_create_v484(p_tenant_id,p_location_id,p_supplier_id,p_payment_date,p_amount,p_payment_method,p_allocations,p_reference_number,p_notes);
  v_payment:=nullif(v->>'supplier_payment_id','')::uuid;v_no:=v->>'payment_number';
  if v_payment is not null and p_device_id is not null and lower(trim(coalesce(p_payment_method,'')))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_v490' and reference_id=v_payment) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(p_amount),'supplier_payment_v490',v_payment,v_no,'Supplier cash payment',auth.uid());
    end if;
  end if;
  return v||jsonb_build_object('payment_engine','v4.9.0');
end $$;
grant execute on function public.supplier_payment_create_v490(uuid,uuid,uuid,date,numeric,text,jsonb,text,text,uuid) to authenticated;

create or replace function public.supplier_payment_void_v490(
  p_tenant_id uuid,p_supplier_payment_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.supplier_payments_v484%rowtype;a record;v_device uuid;v_shift uuid;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into p from public.supplier_payments_v484 where tenant_id=p_tenant_id and id=p_supplier_payment_id for update;
  if not found then raise exception 'Supplier payment not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,p.location_id,true);
  if p.status='void' then return jsonb_build_object('success',true,'supplier_payment_id',p.id,'status','void','idempotent',true);end if;

  update public.supplier_payments_v484 set status='void',voided_by=auth.uid(),voided_at=now(),void_reason=trim(p_reason) where id=p.id;
  for a in select purchase_invoice_id from public.supplier_payment_allocations_v484 where supplier_payment_id=p.id loop
    perform private.v484_refresh_invoice_payment_status(a.purchase_invoice_id);
  end loop;
  update public.journal_entries set status='reversed'
  where tenant_id=p_tenant_id and source_type='supplier_payment_v484' and source_id=p.id and status='posted';
  insert into public.supplier_ledger_entries_v484(
    tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
  ) values(
    p_tenant_id,p.supplier_id,p.location_id,current_date,'void',p.id,p.payment_number,
    'Void supplier payment: '||trim(p_reason),p.amount,0,auth.uid()
  ) on conflict(tenant_id,entry_type,source_id) do nothing;

  select d.id into v_device
  from public.business_devices d join public.cashier_shifts s on s.device_id=d.id and s.tenant_id=p_tenant_id and s.status='open'
  where d.tenant_id=p_tenant_id and d.location_id=p.location_id and d.status='active'
    and exists(select 1 from public.cash_drawer_movements m where m.shift_id=s.id and m.reference_type='supplier_payment_v490' and m.reference_id=p.id)
  order by s.opened_at desc limit 1;
  if v_device is not null and lower(p.payment_method)='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v_device and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_void_v490' and reference_id=p.id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_in',abs(p.amount),'supplier_payment_void_v490',p.id,p.payment_number,'Supplier payment void: '||trim(p_reason),auth.uid());
    end if;
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','supplier_payment',p.id::text,'void');
  return jsonb_build_object('success',true,'supplier_payment_id',p.id,'payment_number',p.payment_number,'status','void');
end $$;
grant execute on function public.supplier_payment_void_v490(uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(189,'4.9.0','Purchase Controls','Draft GRN cancellation, controlled Purchase Invoice void/reopen, supplier payment cash-drawer integration and payment reversal.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 189 purchase controls applied' as status;

-- ============================================================================
-- MIGRATION 190: 190_v490_purchase_loan_operations_release.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchase + Loan operations release contract.
begin;

-- Bulk Import now also includes transaction templates/imports, not only masters.
update public.modules
set description='Bulk products, customers, suppliers, sales and purchases import'
where key='bulk_import';

-- Publish the complete API surface used by Build 20. The previous API contract
-- stays source-compatible; these resources are additive.
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','purchase-cycle',
      'loans','loan-dashboard','loan-warnings','customer-loans',
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
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

-- Build 20 remains on the 4.9.0 compatibility line. Older 4.9.0 clients can
-- keep working after these additive migrations while Build 20 requires the
-- corrected Purchase/Loan functions for its enhanced workspaces.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Purchase & Loan Operations',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build20_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'loan_create_v490','loan_update_v490','loan_submit_v490','loan_decide_v490','loan_disburse_v490',
    'loan_payment_create_v490','loan_payment_reverse_v490','loan_rate_change_v490','loan_status_v490',
    'loan_list_v490','loan_detail_v490','loan_dashboard_v490','loan_warnings_v490','customer_loan_summary_v490',
    'purchase_request_create_v484','purchase_request_list_v484','purchase_request_detail_v484','purchase_request_status_v484',
    'purchase_order_create_v484','purchase_order_list_v484','purchase_order_detail_v484','purchase_order_decide_v484',
    'goods_receipt_create_v484','goods_receipt_post_v484','goods_receipt_cancel_v490','goods_receipt_detail_v484',
    'purchase_invoice_create_v489','purchase_invoice_post_v484','purchase_invoice_void_v490','purchase_invoice_detail_v484',
    'supplier_payment_create_v490','supplier_payment_void_v490','suppliers_get_statement_v484','purchase_price_history_v484',
    'purchasing_dashboard_v484','purchase_cycle_summary_v490','finance_operations_health_v490',
    'transaction_bulk_import_v490','transaction_bulk_import_history_v490','thq_api_contract_v480'
  ];
begin
  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if to_regclass('public.loan_accounts_v490') is null then v_missing:=array_append(v_missing,'loan_accounts_v490');end if;
  if to_regclass('public.loan_schedule_v490') is null then v_missing:=array_append(v_missing,'loan_schedule_v490');end if;
  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.transaction_import_runs_v490') is null then v_missing:=array_append(v_missing,'transaction_import_runs_v490');end if;
  if to_regclass('public.transaction_import_documents_v490') is null then v_missing:=array_append(v_missing,'transaction_import_documents_v490');end if;

  if not exists(select 1 from public.modules where key='loans' and is_active) then v_missing:=array_append(v_missing,'module.loans');end if;
  if not exists(select 1 from public.modules where key='purchases' and is_active) then v_missing:=array_append(v_missing,'module.purchases');end if;
  if not exists(select 1 from public.modules where key='purchase_details' and is_active) then v_missing:=array_append(v_missing,'module.purchase_details');end if;
  if not exists(select 1 from public.modules where key='sales' and is_active) then v_missing:=array_append(v_missing,'module.sales');end if;
  if not exists(select 1 from public.modules where key='bulk_import' and is_active) then v_missing:=array_append(v_missing,'module.bulk_import');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.permissions where key='purchases.manage') then v_missing:=array_append(v_missing,'permission.purchases.manage');end if;
  if not exists(select 1 from public.permissions where key='bulk_import.use') then v_missing:=array_append(v_missing,'permission.bulk_import.use');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='accounts_payable') then v_missing:=array_append(v_missing,'mapping.accounts_payable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='input_gst') then v_missing:=array_append(v_missing,'mapping.input_gst');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',190,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'loan_runtime_fix',true,
    'loan_collection_and_details',true,
    'loan_accounting',true,
    'purchase_price_history_fix',true,
    'purchase_request_to_payment_cycle',true,
    'grn_stock_traceability',true,
    'purchase_invoice_accounts_payable',true,
    'supplier_payment_allocation',true,
    'controlled_purchase_reversals',true,
    'bulk_sales_import',true,
    'bulk_purchase_import',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build20_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  190,
  '4.9.0',
  'Purchase & Loan Operations',
  'Build 20 completes loan collection/details, repairs loan warnings and purchase price history, completes PR/PO/GRN/invoice/supplier-payment operations and adds auditable bulk Sales/Purchase import.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 190 purchase/loan operations release applied' as status;


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

