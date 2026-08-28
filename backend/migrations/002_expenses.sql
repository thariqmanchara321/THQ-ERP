create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, name)
);

create table if not exists public.expense_counters (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  last_number bigint not null default 0
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  expense_number text not null,
  category_id uuid not null references public.expense_categories(id),
  expense_date date not null default current_date,
  payee text,
  description text not null,
  amount numeric(18,2) not null check (amount > 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(18,2) generated always as (amount + tax_amount) stored,
  payment_method text not null default 'cash',
  reference_number text,
  notes text,
  status text not null default 'posted' check (status in ('posted','void')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, expense_number)
);

create index if not exists idx_expenses_tenant_date on public.expenses(tenant_id, expense_date desc);
create index if not exists idx_expenses_tenant_category on public.expenses(tenant_id, category_id);

alter table public.expense_categories enable row level security;
alter table public.expense_counters enable row level security;
alter table public.expenses enable row level security;

drop policy if exists expense_categories_select on public.expense_categories;
create policy expense_categories_select on public.expense_categories for select to authenticated
using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses for select to authenticated
using (private.erp_user_has_tenant_access(tenant_id));

revoke insert, update, delete on public.expense_categories from authenticated;
revoke all on public.expense_counters from authenticated;
revoke insert, update, delete on public.expenses from authenticated;

grant select on public.expense_categories, public.expenses to authenticated;

-- Seed default categories for existing tenants.
insert into public.expense_categories (tenant_id, name)
select t.id, c.name
from public.tenants t
cross join (values
  ('Rent'),('Electricity'),('Salary / Wages'),('Transport'),('Fuel'),
  ('Office Supplies'),('Repairs & Maintenance'),('Internet / Phone'),
  ('Bank Charges'),('Marketing'),('Miscellaneous')
) c(name)
on conflict (tenant_id, name) do nothing;

create or replace function private.seed_default_expense_categories()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  insert into public.expense_categories (tenant_id, name)
  select new.id, c.name
  from (values
    ('Rent'),('Electricity'),('Salary / Wages'),('Transport'),('Fuel'),
    ('Office Supplies'),('Repairs & Maintenance'),('Internet / Phone'),
    ('Bank Charges'),('Marketing'),('Miscellaneous')
  ) c(name)
  on conflict (tenant_id, name) do nothing;
  return new;
end $$;

drop trigger if exists trg_seed_default_expense_categories on public.tenants;
create trigger trg_seed_default_expense_categories
after insert on public.tenants
for each row execute function private.seed_default_expense_categories();

create or replace function public.expenses_list_categories(p_tenant_id uuid)
returns table(category_id uuid, category_name text, active boolean)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_module_enabled(p_tenant_id,'expenses') then raise exception 'Expenses module is disabled'; end if;
  return query select ec.id, ec.name, ec.active from public.expense_categories ec where ec.tenant_id=p_tenant_id and ec.active order by ec.name;
end $$;

create or replace function public.expenses_list(p_tenant_id uuid, p_from_date date default null, p_to_date date default null)
returns table(
  expense_id uuid, expense_number text, category_id uuid, category_name text,
  expense_date date, payee text, description text, amount numeric, tax_amount numeric,
  total_amount numeric, payment_method text, reference_number text, notes text,
  status text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_module_enabled(p_tenant_id,'expenses') then raise exception 'Expenses module is disabled'; end if;
  return query
  select e.id,e.expense_number,e.category_id,ec.name,e.expense_date,e.payee,e.description,
         e.amount,e.tax_amount,e.total_amount,e.payment_method,e.reference_number,e.notes,e.status,e.created_at
  from public.expenses e join public.expense_categories ec on ec.id=e.category_id
  where e.tenant_id=p_tenant_id
    and (p_from_date is null or e.expense_date>=p_from_date)
    and (p_to_date is null or e.expense_date<=p_to_date)
  order by e.expense_date desc,e.created_at desc;
end $$;

create or replace function public.expenses_create(
  p_tenant_id uuid, p_category_id uuid, p_expense_date date, p_payee text,
  p_description text, p_amount numeric, p_tax_amount numeric default 0,
  p_payment_method text default 'cash', p_reference_number text default '', p_notes text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_no bigint; v_id uuid; v_number text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_module_enabled(p_tenant_id,'expenses') then raise exception 'Expenses module is disabled'; end if;
  if not private.erp_has_permission(p_tenant_id,'expenses.manage') then raise exception 'Permission denied'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'Description is required'; end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Amount must be greater than zero'; end if;
  if coalesce(p_tax_amount,0)<0 then raise exception 'Tax cannot be negative'; end if;
  if not exists(select 1 from public.expense_categories where id=p_category_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid expense category'; end if;

  insert into public.expense_counters(tenant_id,last_number) values(p_tenant_id,1)
  on conflict(tenant_id) do update set last_number=public.expense_counters.last_number+1
  returning last_number into v_no;
  v_number := 'EXP-' || lpad(v_no::text,6,'0');

  insert into public.expenses(tenant_id,expense_number,category_id,expense_date,payee,description,amount,tax_amount,payment_method,reference_number,notes)
  values(p_tenant_id,v_number,p_category_id,coalesce(p_expense_date,current_date),nullif(trim(p_payee),''),trim(p_description),p_amount,coalesce(p_tax_amount,0),coalesce(nullif(trim(p_payment_method),''),'cash'),nullif(trim(p_reference_number),''),nullif(trim(p_notes),''))
  returning id into v_id;

  return jsonb_build_object('expense_id',v_id,'expense_number',v_number);
end $$;

grant execute on function public.expenses_list_categories(uuid) to authenticated;
grant execute on function public.expenses_list(uuid,date,date) to authenticated;
grant execute on function public.expenses_create(uuid,uuid,date,text,text,numeric,numeric,text,text,text) to authenticated;
