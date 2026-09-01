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
