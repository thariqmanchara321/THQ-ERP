-- THQ ERP v6.0
-- Deferred commit-time accounting guards for posted business documents.

create or replace function private.accounting_commit_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_required boolean:=false;
  v_source_type text;
  v_source_id uuid;
  v_tenant_id uuid;
  v_count integer:=0;
begin
  v_source_id:=new.id;
  v_tenant_id:=new.tenant_id;

  case tg_table_name
    when 'sales' then
      v_source_type:='sale';
      select (status='posted') into v_required
      from public.sales where id=new.id and tenant_id=new.tenant_id;
    when 'purchases' then
      v_source_type:='purchase';
      select (status='posted') into v_required
      from public.purchases where id=new.id and tenant_id=new.tenant_id;
    when 'expenses' then
      v_source_type:='expense';
      select (status='posted') into v_required
      from public.expenses where id=new.id and tenant_id=new.tenant_id;
    when 'purchase_invoices_v484' then
      v_source_type:='purchase_invoice_v484';
      select (status in ('posted','part_paid','paid')) into v_required
      from public.purchase_invoices_v484 where id=new.id and tenant_id=new.tenant_id;
    when 'sales_returns' then
      v_source_type:='sales_return';
      select exists(select 1 from public.sales_returns where id=new.id and tenant_id=new.tenant_id)
      into v_required;
    when 'purchase_returns' then
      v_source_type:='purchase_return';
      select exists(select 1 from public.purchase_returns where id=new.id and tenant_id=new.tenant_id)
      into v_required;
    when 'supplier_payments_v484' then
      v_source_type:='supplier_payment_v484';
      select (status='posted') into v_required
      from public.supplier_payments_v484 where id=new.id and tenant_id=new.tenant_id;
    else
      return new;
  end case;

  if coalesce(v_required,false) is not true then return new; end if;

  select count(*) into v_count
  from public.journal_entries j
  where j.tenant_id=v_tenant_id
    and j.source_type=v_source_type
    and j.source_id=v_source_id
    and j.status='posted';

  if v_count=0 then
    raise exception 'Accounting integrity failure: % % has no posted journal',v_source_type,v_source_id;
  end if;
  if v_count>1 then
    raise exception 'Accounting integrity failure: % % has % posted journals',v_source_type,v_source_id,v_count;
  end if;

  return new;
end
$function$;

drop trigger if exists trg_accounting_guard_sales_v600 on public.sales;
create constraint trigger trg_accounting_guard_sales_v600
after insert or update on public.sales
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_purchases_v600 on public.purchases;
create constraint trigger trg_accounting_guard_purchases_v600
after insert or update on public.purchases
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_expenses_v600 on public.expenses;
create constraint trigger trg_accounting_guard_expenses_v600
after insert or update on public.expenses
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_purchase_invoices_v600 on public.purchase_invoices_v484;
create constraint trigger trg_accounting_guard_purchase_invoices_v600
after insert or update on public.purchase_invoices_v484
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_sales_returns_v600 on public.sales_returns;
create constraint trigger trg_accounting_guard_sales_returns_v600
after insert or update on public.sales_returns
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_purchase_returns_v600 on public.purchase_returns;
create constraint trigger trg_accounting_guard_purchase_returns_v600
after insert or update on public.purchase_returns
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_supplier_payments_v600 on public.supplier_payments_v484;
create constraint trigger trg_accounting_guard_supplier_payments_v600
after insert or update on public.supplier_payments_v484
deferrable initially deferred
for each row execute function private.accounting_commit_guard_v600();

revoke execute on function private.accounting_commit_guard_v600()
from public, anon, authenticated, service_role;
