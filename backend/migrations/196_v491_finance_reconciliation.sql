-- THQ ERP v4.9.1 — financial reconciliation diagnostics and accounting cross-check.
begin;

create or replace function public.finance_reconciliation_v491(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  unbalanced bigint:=0;
  duplicate_journals bigint:=0;
  missing text[]:='{}';
  sales_missing bigint:=0;
  purchases_missing bigint:=0;
  purchase_invoices_missing bigint:=0;
  expenses_missing bigint:=0;
  sret_missing bigint:=0;
  pret_missing bigint:=0;
  loan_missing bigint:=0;
  sale_overpayments bigint:=0;
  purchase_overpayments bigint:=0;
  purchase_invoice_overpayments bigint:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) and not private.platform_v2_is_admin() then
    raise exception 'Access denied';
  end if;

  select count(*) into unbalanced
  from (
    select j.id
    from public.journal_entries j
    join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted'
    group by j.id
    having abs(sum(coalesce(l.debit,0))-sum(coalesce(l.credit,0)))>0.005
  ) q;

  -- More than one posted journal for the same source indicates a double-posting risk.
  select count(*) into duplicate_journals
  from (
    select source_type,source_id
    from public.journal_entries
    where tenant_id=p_tenant_id and status='posted' and source_id is not null
    group by source_type,source_id
    having count(*)>1
  ) q;

  select array_agg(k) into missing
  from unnest(array[
    'sales_revenue','output_gst','accounts_receivable','inventory_asset','cogs',
    'accounts_payable','input_gst','operating_expense','rounding',
    'customer_credits','supplier_credits','loan_receivable','loan_payable',
    'loan_interest_income','loan_interest_expense','loan_penalty_income','loan_penalty_expense'
  ]) k
  where private.v4_account_id(p_tenant_id,k) is null;

  select count(*) into sales_missing
  from public.sales s
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted');

  select count(*) into purchases_missing
  from public.purchases p
  where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted');

  select count(*) into purchase_invoices_missing
  from public.purchase_invoices_v484 p
  where p.tenant_id=p_tenant_id and p.status in('posted','part_paid','paid')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=p.id and j.status='posted');

  select count(*) into expenses_missing
  from public.expenses e
  where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted');

  select count(*) into sret_missing
  from public.sales_returns r
  where r.tenant_id=p_tenant_id and coalesce(r.grand_total,0)>0 and coalesce(r.refund_status,'')<>'waived'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted');

  select count(*) into pret_missing
  from public.purchase_returns r
  where r.tenant_id=p_tenant_id and coalesce(r.grand_total,0)>0 and coalesce(r.credit_status,'')<>'waived'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted');

  select count(*) into loan_missing
  from public.loan_accounts_v490 l
  where l.tenant_id=p_tenant_id and l.accounting_enabled and l.status in('active','closed','defaulted')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_id=l.id and j.source_type in('loan_activation_v491','loan_disbursement_v490') and j.status='posted');

  select count(*) into sale_overpayments
  from public.sales s
  where s.tenant_id=p_tenant_id
    and coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0)>coalesce(s.grand_total,0)+0.01;

  select count(*) into purchase_overpayments
  from public.purchases p
  where p.tenant_id=p_tenant_id
    and coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0)>coalesce(p.grand_total,0)+0.01;

  select count(*) into purchase_invoice_overpayments
  from public.purchase_invoices_v484 p
  where p.tenant_id=p_tenant_id and coalesce(p.paid_total,0)>coalesce(p.grand_total,0)+0.01;

  return jsonb_build_object(
    'ok',unbalanced=0 and duplicate_journals=0 and cardinality(coalesce(missing,'{}'))=0
      and sales_missing=0 and purchases_missing=0 and purchase_invoices_missing=0 and expenses_missing=0
      and sret_missing=0 and pret_missing=0 and loan_missing=0
      and sale_overpayments=0 and purchase_overpayments=0 and purchase_invoice_overpayments=0,
    'unbalanced_journals',unbalanced,
    'duplicate_posted_source_journals',duplicate_journals,
    'missing_mappings',to_jsonb(coalesce(missing,'{}')),
    'operational_without_journal',jsonb_build_object(
      'sales',sales_missing,
      'purchases',purchases_missing,
      'purchase_invoices',purchase_invoices_missing,
      'expenses',expenses_missing,
      'sales_returns',sret_missing,
      'purchase_returns',pret_missing,
      'accounted_loans',loan_missing
    ),
    'overpayments',jsonb_build_object(
      'sales',sale_overpayments,
      'purchases',purchase_overpayments,
      'purchase_invoices',purchase_invoice_overpayments
    ),
    'checked_at',now()
  );
end $$;
grant execute on function public.finance_reconciliation_v491(uuid) to authenticated;

create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  return public.finance_reconciliation_v491(p_tenant_id);
end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(196,'4.9.1','Finance Reconciliation','Cross-checks double-entry balance, duplicate source journals, accounting mappings, Sales/Purchase/Purchase Invoice/Expense/Return/Loan journal coverage and overpayments.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 196 applied' as status;
