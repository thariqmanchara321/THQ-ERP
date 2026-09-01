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
