-- ============================================================================
-- Migration: Operations Intelligence Phase 6 (Financial, Accounting & Expense Intelligence)
-- Release: #711 (v8.3.5)
-- Description: Ledger-backed double-entry financial performance, cash flow,
--              working capital, accounting trial balance, tax/GST intelligence,
--              and deep expense intelligence with deterministic anomaly detection.
-- ============================================================================

-- 1. Performance Indexes
create index if not exists idx_journal_entries_tenant_status_date
  on public.journal_entries (tenant_id, status, entry_date);

create index if not exists idx_journal_lines_entry_account
  on public.journal_lines (journal_entry_id, account_id);

create index if not exists idx_expenses_tenant_status_date
  on public.expenses (tenant_id, status, expense_date);

create index if not exists idx_accounting_accounts_tenant_type
  on public.accounting_accounts (tenant_id, account_type);

-- 2. Financial Intelligence RPC (v8.3.5)
create or replace function public.financial_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days int default 30,
  p_query text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_is_owner boolean := false;
  v_can_view_cost boolean := false;
  v_period_days int;
  v_to date := current_date;
  v_from date;
  v_prev_to date;
  v_prev_from date;

  -- Profit & Loss (Current Window)
  v_rev numeric := 0;
  v_cogs numeric := 0;
  v_gross_profit numeric := 0;
  v_op_expenses numeric := 0;
  v_op_profit numeric := 0;
  v_other_income numeric := 0;
  v_other_expense numeric := 0;
  v_net_profit numeric := 0;
  v_gross_margin_pct numeric := 0;
  v_net_margin_pct numeric := 0;

  -- Profit & Loss (Previous Window)
  v_prev_rev numeric := 0;
  v_prev_cogs numeric := 0;
  v_prev_gross_profit numeric := 0;
  v_prev_op_expenses numeric := 0;
  v_prev_op_profit numeric := 0;
  v_prev_net_profit numeric := 0;
  v_prev_gross_margin_pct numeric := 0;
  v_prev_net_margin_pct numeric := 0;

  -- Cash & Bank (Current Window)
  v_cash_opening numeric := 0;
  v_cash_in numeric := 0;
  v_cash_out numeric := 0;
  v_cash_closing numeric := 0;

  v_bank_opening numeric := 0;
  v_bank_in numeric := 0;
  v_bank_out numeric := 0;
  v_bank_closing numeric := 0;

  v_transfers_contra numeric := 0;
  v_net_cash_movement numeric := 0;
  v_cash_flow_daily jsonb := '[]'::jsonb;

  -- Working Capital
  v_ar_closing numeric := 0;
  v_ap_closing numeric := 0;
  v_inv_valuation numeric := 0;
  v_net_working_capital numeric := 0;
  v_current_assets numeric := 0;
  v_current_liabilities numeric := 0;
  v_wc_ratio numeric := 1.0;

  -- Aging buckets
  v_ar_aging jsonb := '{}'::jsonb;
  v_ap_aging jsonb := '{}'::jsonb;

  -- Trial Balance & Ledger Verification
  v_tb_debits numeric := 0;
  v_tb_credits numeric := 0;
  v_tb_diff numeric := 0;
  v_tb_balanced boolean := true;
  v_journal_count int := 0;
  v_account_groups jsonb := '[]'::jsonb;

  -- GST & Tax
  v_tax_mode text := 'gst';
  v_output_cgst numeric := 0;
  v_output_sgst numeric := 0;
  v_output_igst numeric := 0;
  v_output_cess numeric := 0;
  v_output_total numeric := 0;

  v_input_cgst numeric := 0;
  v_input_sgst numeric := 0;
  v_input_igst numeric := 0;
  v_input_cess numeric := 0;
  v_input_total numeric := 0;

  -- Anomalies & Projections
  v_anomalies jsonb := '[]'::jsonb;
  v_projections jsonb := '{}'::jsonb;

  v_daily_rec_avg numeric := 0;
  v_daily_pay_avg numeric := 0;
  v_rec_expenses_monthly numeric := 0;
begin
  -- 1. Tenant access check
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  -- 2. Cost / Financial permission check
  v_can_view_cost := private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'accounting.view')
    or private.erp_has_permission(p_tenant_id, 'reports.view')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- 3. Date window computation
  v_period_days := coalesce(p_days, 30);
  if v_period_days <= 0 then v_period_days := 30; end if;
  v_to := current_date;
  v_from := v_to - v_period_days + 1;
  v_prev_to := v_from - 1;
  v_prev_from := v_prev_to - v_period_days + 1;

  -- 4. Current Period Ledger Profit & Loss
  select
    coalesce(sum(case when a.account_type = 'income' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'cogs' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'expense' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'income' and a.system_key in ('other_revenue', 'loan_interest_income') then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'expense' and a.system_key in ('rounding', 'customer_bad_debt_writeoff', 'loan_interest_expense') then jl.debit - jl.credit else 0 end), 0)
  into v_rev, v_cogs, v_op_expenses, v_other_income, v_other_expense
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_gross_profit := v_rev - v_cogs;
  v_op_profit := v_gross_profit - v_op_expenses;
  v_net_profit := v_op_profit + v_other_income - v_other_expense;
  v_gross_margin_pct := case when v_rev > 0 then round((v_gross_profit / v_rev) * 100, 2) else 0 end;
  v_net_margin_pct := case when v_rev > 0 then round((v_net_profit / v_rev) * 100, 2) else 0 end;

  -- 5. Previous Period Ledger Profit & Loss
  select
    coalesce(sum(case when a.account_type = 'income' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'cogs' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.account_type = 'expense' then jl.debit - jl.credit else 0 end), 0)
  into v_prev_rev, v_prev_cogs, v_prev_op_expenses
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_prev_from and v_prev_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_prev_gross_profit := v_prev_rev - v_prev_cogs;
  v_prev_op_profit := v_prev_gross_profit - v_prev_op_expenses;
  v_prev_net_profit := v_prev_op_profit;
  v_prev_gross_margin_pct := case when v_prev_rev > 0 then round((v_prev_gross_profit / v_prev_rev) * 100, 2) else 0 end;
  v_prev_net_margin_pct := case when v_prev_rev > 0 then round((v_prev_net_profit / v_prev_rev) * 100, 2) else 0 end;

  -- 6. Cash & Bank Balances and Flow
  -- Cash Opening
  select coalesce(sum(jl.debit - jl.credit), 0) into v_cash_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < v_from
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- Cash Current Activity
  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
  into v_cash_in, v_cash_out
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_cash_closing := v_cash_opening + v_cash_in - v_cash_out;

  -- Bank Opening
  select coalesce(sum(jl.debit - jl.credit), 0) into v_bank_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < v_from
    and (a.system_key in ('bank_account', 'undeposited_funds', 'clearing_account') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'upi', 'card'))
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- Bank Current Activity
  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
  into v_bank_in, v_bank_out
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (a.system_key in ('bank_account', 'undeposited_funds', 'clearing_account') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'upi', 'card'))
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_bank_closing := v_bank_opening + v_bank_in - v_bank_out;

  -- Contra Transfers
  select coalesce(sum(jl.debit), 0) into v_transfers_contra
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and j.source_type in ('contra', 'transfer')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_net_cash_movement := (v_cash_in + v_bank_in) - (v_cash_out + v_bank_out);

  -- Daily Inflow vs Outflow timeline
  with day_series as (
    select generate_series(v_from, v_to, '1 day'::interval)::date as day_dt
  ),
  day_in_out as (
    select
      j.entry_date as day_dt,
      sum(case when (a.system_key in ('cash_drawer', 'cash_in_hand', 'bank_account', 'undeposited_funds') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('cash', 'bank', 'upi', 'card')) and jl.debit > jl.credit then jl.debit - jl.credit else 0 end) as inflow,
      sum(case when (a.system_key in ('cash_drawer', 'cash_in_hand', 'bank_account', 'undeposited_funds') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('cash', 'bank', 'upi', 'card')) and jl.credit > jl.debit then jl.credit - jl.debit else 0 end) as outflow
    from public.journal_lines jl
    join public.journal_entries j on j.id = jl.journal_entry_id
    join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
    where j.tenant_id = p_tenant_id
      and j.status = 'posted'
      and j.entry_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'))
    group by j.entry_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'day_date', ds.day_dt::text,
    'label', to_char(ds.day_dt, 'Dy, Mon DD'),
    'inflow', round(coalesce(dio.inflow, 0), 2),
    'outflow', round(coalesce(dio.outflow, 0), 2),
    'net', round(coalesce(dio.inflow, 0) - coalesce(dio.outflow, 0), 2)
  ) order by ds.day_dt), '[]'::jsonb)
  into v_cash_flow_daily
  from day_series ds
  left join day_in_out dio on dio.day_dt = ds.day_dt;

  -- 7. Working Capital & Balance Sheet Components
  -- Accounts Receivable
  select coalesce(sum(jl.debit - jl.credit), 0) into v_ar_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date <= v_to
    and a.system_key in ('accounts_receivable', 'customer_credits')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- Accounts Payable
  select coalesce(sum(jl.credit - jl.debit), 0) into v_ap_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date <= v_to
    and a.system_key in ('accounts_payable', 'supplier_credits')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- Inventory Asset
  select coalesce(sum(jl.debit - jl.credit), 0) into v_inv_valuation
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date <= v_to
    and a.system_key = 'inventory_asset'
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_net_working_capital := v_inv_valuation + v_ar_closing - v_ap_closing;
  v_current_assets := v_cash_closing + v_bank_closing + v_ar_closing + v_inv_valuation;
  v_current_liabilities := greatest(v_ap_closing, 0);
  v_wc_ratio := case when v_current_liabilities > 0 then round(v_current_assets / v_current_liabilities, 2) else 1.0 end;

  -- 8. Customer Receivables & Supplier Payables Aging
  -- Customer AR Aging
  with cust_due as (
    select
      c.id as customer_id,
      c.name as customer_name,
      coalesce(c.phone, '') as phone,
      coalesce(sum(case when s.sale_date > v_to - 30 then s.grand_total - coalesce(p.paid, 0) else 0 end), 0) as current_bucket,
      coalesce(sum(case when s.sale_date between v_to - 60 and v_to - 30 then s.grand_total - coalesce(p.paid, 0) else 0 end), 0) as days_31_60_bucket,
      coalesce(sum(case when s.sale_date between v_to - 90 and v_to - 61 then s.grand_total - coalesce(p.paid, 0) else 0 end), 0) as days_61_90_bucket,
      coalesce(sum(case when s.sale_date < v_to - 90 then s.grand_total - coalesce(p.paid, 0) else 0 end), 0) as days_90_plus_bucket,
      coalesce(sum(s.grand_total - coalesce(p.paid, 0)), 0) as total_due
    from public.customers c
    join public.sales s on s.customer_id = c.id and s.tenant_id = c.tenant_id
    left join lateral (
      select sum(sp.amount) as paid
      from public.sale_payments sp
      where sp.sale_id = s.id and sp.tenant_id = s.tenant_id and (sp.paid_at)::date <= v_to
    ) p on true
    where c.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('draft', 'void', 'cancelled')
      and s.sale_date <= v_to
    group by c.id, c.name, c.phone
    having sum(s.grand_total - coalesce(p.paid, 0)) > 0.01
  ),
  cust_summary as (
    select
      round(coalesce(sum(total_due), 0), 2) as total_rec,
      round(coalesce(sum(current_bucket), 0), 2) as cur_rec,
      round(coalesce(sum(days_31_60_bucket), 0), 2) as d30_rec,
      round(coalesce(sum(days_61_90_bucket), 0), 2) as d60_rec,
      round(coalesce(sum(days_90_plus_bucket), 0), 2) as d90_rec
    from cust_due
  ),
  top_cust as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'customer_id', cd.customer_id,
      'customer_name', cd.customer_name,
      'outstanding', round(cd.total_due, 2),
      'share_pct', case when cs.total_rec > 0 then round((cd.total_due / cs.total_rec) * 100, 2) else 0 end
    ) order by cd.total_due desc), '[]'::jsonb) as debtors_json
    from (
      select * from cust_due order by total_due desc limit 5
    ) cd
    cross join cust_summary cs
    group by cs.total_rec
  )
  select jsonb_build_object(
    'total_receivables', coalesce(cs.total_rec, 0),
    'current', coalesce(cs.cur_rec, 0),
    'days_1_30', coalesce(cs.d30_rec, 0),
    'days_31_60', coalesce(cs.d60_rec, 0),
    'days_90_plus', coalesce(cs.d90_rec, 0),
    'overdue_total', round(coalesce(cs.d30_rec, 0) + coalesce(cs.d60_rec, 0) + coalesce(cs.d90_rec, 0), 2),
    'overdue_share_pct', case when coalesce(cs.total_rec, 0) > 0 then round(((coalesce(cs.d30_rec, 0) + coalesce(cs.d60_rec, 0) + coalesce(cs.d90_rec, 0)) / cs.total_rec) * 100, 2) else 0 end,
    'top_debtors', coalesce(tc.debtors_json, '[]'::jsonb)
  )
  into v_ar_aging
  from cust_summary cs
  left join top_cust tc on true;

  -- Supplier AP Aging
  with supp_due as (
    select
      sup.id as supplier_id,
      sup.name as supplier_name,
      coalesce(sum(case when pur.purchase_date > v_to - 30 then pur.grand_total - coalesce(pp.paid, 0) else 0 end), 0) as current_bucket,
      coalesce(sum(case when pur.purchase_date between v_to - 60 and v_to - 30 then pur.grand_total - coalesce(pp.paid, 0) else 0 end), 0) as days_31_60_bucket,
      coalesce(sum(case when pur.purchase_date between v_to - 90 and v_to - 61 then pur.grand_total - coalesce(pp.paid, 0) else 0 end), 0) as days_61_90_bucket,
      coalesce(sum(case when pur.purchase_date < v_to - 90 then pur.grand_total - coalesce(pp.paid, 0) else 0 end), 0) as days_90_plus_bucket,
      coalesce(sum(pur.grand_total - coalesce(pp.paid, 0)), 0) as total_due
    from public.suppliers sup
    join public.purchases pur on pur.supplier_id = sup.id and pur.tenant_id = sup.tenant_id
    left join lateral (
      select sum(pay.amount) as paid
      from public.purchase_payments pay
      where pay.purchase_id = pur.id and pay.tenant_id = pur.tenant_id and (pay.paid_at)::date <= v_to
    ) pp on true
    where sup.tenant_id = p_tenant_id
      and coalesce(pur.status, '') not in ('draft', 'void', 'cancelled')
      and pur.purchase_date <= v_to
    group by sup.id, sup.name
    having sum(pur.grand_total - coalesce(pp.paid, 0)) > 0.01
  ),
  supp_summary as (
    select
      round(coalesce(sum(total_due), 0), 2) as total_pay,
      round(coalesce(sum(current_bucket), 0), 2) as cur_pay,
      round(coalesce(sum(days_31_60_bucket), 0), 2) as d30_pay,
      round(coalesce(sum(days_61_90_bucket), 0), 2) as d60_pay,
      round(coalesce(sum(days_90_plus_bucket), 0), 2) as d90_pay
    from supp_due
  ),
  top_supp as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'supplier_id', sd.supplier_id,
      'supplier_name', sd.supplier_name,
      'outstanding', round(sd.total_due, 2),
      'share_pct', case when ss.total_pay > 0 then round((sd.total_due / ss.total_pay) * 100, 2) else 0 end
    ) order by sd.total_due desc), '[]'::jsonb) as creditors_json
    from (
      select * from supp_due order by total_due desc limit 5
    ) sd
    cross join supp_summary ss
    group by ss.total_pay
  )
  select jsonb_build_object(
    'total_payables', coalesce(ss.total_pay, 0),
    'current', coalesce(ss.cur_pay, 0),
    'days_1_30', coalesce(ss.d30_pay, 0),
    'days_31_60', coalesce(ss.d60_pay, 0),
    'days_90_plus', coalesce(ss.d90_pay, 0),
    'overdue_total', round(coalesce(ss.d30_pay, 0) + coalesce(ss.d60_pay, 0) + coalesce(ss.d90_pay, 0), 2),
    'overdue_share_pct', case when coalesce(ss.total_pay, 0) > 0 then round(((coalesce(ss.d30_pay, 0) + coalesce(ss.d60_pay, 0) + coalesce(ss.d90_pay, 0)) / ss.total_pay) * 100, 2) else 0 end,
    'top_creditors', coalesce(ts.creditors_json, '[]'::jsonb)
  )
  into v_ap_aging
  from supp_summary ss
  left join top_supp ts on true;

  -- 9. Trial Balance Verification
  select
    coalesce(sum(jl.debit), 0),
    coalesce(sum(jl.credit), 0),
    count(distinct j.id)
  into v_tb_debits, v_tb_credits, v_journal_count
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  v_tb_diff := abs(v_tb_debits - v_tb_credits);
  v_tb_balanced := (v_tb_diff < 0.01);

  -- Account Groups Summary
  with group_summary as (
    select
      a.account_type,
      case a.account_type
        when 'asset' then 'Assets'
        when 'liability' then 'Liabilities'
        when 'equity' then 'Equity'
        when 'income' then 'Revenue'
        when 'cogs' then 'Cost of Goods Sold'
        when 'expense' then 'Operating Expenses'
        else 'Other'
      end as group_label,
      round(sum(jl.debit), 2) as debits,
      round(sum(jl.credit), 2) as credits,
      round(sum(case when a.account_type in ('asset', 'cogs', 'expense') then jl.debit - jl.credit else jl.credit - jl.debit end), 2) as balance
    from public.journal_lines jl
    join public.journal_entries j on j.id = jl.journal_entry_id
    join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
    where j.tenant_id = p_tenant_id
      and j.status = 'posted'
      and j.entry_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'))
    group by a.account_type
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'account_type', gs.account_type,
    'group_label', gs.group_label,
    'debits', gs.debits,
    'credits', gs.credits,
    'balance', gs.balance
  ) order by case gs.account_type when 'asset' then 1 when 'liability' then 2 when 'equity' then 3 when 'income' then 4 when 'cogs' then 5 else 6 end), '[]'::jsonb)
  into v_account_groups
  from group_summary gs;

  -- 10. GST and Tax Intelligence
  -- Output GST
  select
    coalesce(sum(case when a.system_key = 'output_cgst' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'output_sgst' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'output_igst' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'output_cess' then jl.credit - jl.debit else 0 end), 0),
    coalesce(sum(case when a.system_key in ('output_gst', 'output_cgst', 'output_sgst', 'output_igst', 'output_cess') then jl.credit - jl.debit else 0 end), 0)
  into v_output_cgst, v_output_sgst, v_output_igst, v_output_cess, v_output_total
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- Input GST
  select
    coalesce(sum(case when a.system_key = 'input_cgst' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'input_sgst' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'input_igst' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.system_key = 'input_cess' then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when a.system_key in ('input_gst', 'input_cgst', 'input_sgst', 'input_igst', 'input_cess') then jl.debit - jl.credit else 0 end), 0)
  into v_input_cgst, v_input_sgst, v_input_igst, v_input_cess, v_input_total
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between v_from and v_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, j.location_id, p_location_id, 'view'));

  -- 11. Financial Anomalies Detection
  if v_gross_profit < 0 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'id', 'anom-fin-neg-gross',
      'rule_code', 'ANOM-FIN-01',
      'title', 'Negative Gross Profit Detected',
      'severity', 'critical',
      'description', 'Cost of goods sold (' || round(v_cogs, 2)::text || ') exceeds sales revenue (' || round(v_rev, 2)::text || ') in this period.',
      'evidence', jsonb_build_object('revenue', v_rev, 'cogs', v_cogs, 'gross_profit', v_gross_profit),
      'timestamp', now()::text
    ));
  end if;

  if not v_tb_balanced then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'id', 'anom-fin-unbalanced-tb',
      'rule_code', 'ANOM-FIN-02',
      'title', 'Unbalanced General Ledger Debits/Credits',
      'severity', 'critical',
      'description', 'Ledger has an imbalance of ' || round(v_tb_diff, 2)::text || ' between total debits and credits.',
      'evidence', jsonb_build_object('debits', v_tb_debits, 'credits', v_tb_credits, 'variance', v_tb_diff),
      'timestamp', now()::text
    ));
  end if;

  if v_cash_closing < 0 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'id', 'anom-fin-neg-cash',
      'rule_code', 'ANOM-FIN-03',
      'title', 'Overdrawn Cash Balance Warning',
      'severity', 'warning',
      'description', 'Calculated cash drawer balance is negative (' || round(v_cash_closing, 2)::text || '). Verify unrecorded cash deposits or physical count.',
      'evidence', jsonb_build_object('closing_cash', v_cash_closing),
      'timestamp', now()::text
    ));
  end if;

  if coalesce((v_ar_aging->>'overdue_share_pct')::numeric, 0) > 40.0 and coalesce((v_ar_aging->>'total_receivables')::numeric, 0) > 1000 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'id', 'anom-fin-ar-overdue-spike',
      'rule_code', 'ANOM-FIN-04',
      'title', 'Severe Receivables Overdue Concentration',
      'severity', 'warning',
      'description', 'Overdue receivables represent ' || (v_ar_aging->>'overdue_share_pct') || '% of customer credit portfolio.',
      'evidence', jsonb_build_object('overdue_total', v_ar_aging->'overdue_total', 'total_ar', v_ar_aging->'total_receivables'),
      'timestamp', now()::text
    ));
  end if;

  if coalesce((v_ap_aging->>'overdue_share_pct')::numeric, 0) > 50.0 and coalesce((v_ap_aging->>'total_payables')::numeric, 0) > 1000 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'id', 'anom-fin-ap-overdue-spike',
      'rule_code', 'ANOM-FIN-05',
      'title', 'High Overdue Supplier Payables Exposure',
      'severity', 'warning',
      'description', 'Overdue supplier payables represent ' || (v_ap_aging->>'overdue_share_pct') || '% of total liabilities.',
      'evidence', jsonb_build_object('overdue_total', v_ap_aging->'overdue_total', 'total_ap', v_ap_aging->'total_payables'),
      'timestamp', now()::text
    ));
  end if;

  -- 12. Predictive Readiness Baseline Trend Projections
  v_daily_rec_avg := case when v_period_days > 0 then (v_cash_in + v_bank_in) / v_period_days else 0 end;
  v_daily_pay_avg := case when v_period_days > 0 then (v_cash_out + v_bank_out) / v_period_days else 0 end;
  v_rec_expenses_monthly := v_op_expenses;

  v_projections := jsonb_build_object(
    'expected_collections_next_30d', round(v_daily_rec_avg * 30, 2),
    'expected_payables_next_30d', round(v_daily_pay_avg * 30, 2),
    'projected_recurring_expenses_monthly', round(v_rec_expenses_monthly, 2),
    'projected_net_cash_next_30d', round((v_daily_rec_avg - v_daily_pay_avg) * 30, 2),
    'baseline_model', 'deterministic_daily_runrate',
    'assumptions', 'Projections extrapolated from ' || v_period_days::text || '-day historical cash velocity without external AI or speculative trend weighting.'
  );

  -- 13. Assemble Final Payload
  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_period_days,
    'from_date', v_from::text,
    'to_date', v_to::text,
    'can_view_cost', v_can_view_cost,
    'performance', jsonb_build_object(
      'current', jsonb_build_object(
        'revenue', case when v_can_view_cost then round(v_rev, 2) else 0 end,
        'cogs', case when v_can_view_cost then round(v_cogs, 2) else 0 end,
        'gross_profit', case when v_can_view_cost then round(v_gross_profit, 2) else 0 end,
        'gross_margin_pct', case when v_can_view_cost then v_gross_margin_pct else 0 end,
        'operating_expenses', case when v_can_view_cost then round(v_op_expenses, 2) else 0 end,
        'operating_profit', case when v_can_view_cost then round(v_op_profit, 2) else 0 end,
        'operating_margin_pct', case when v_can_view_cost then case when v_rev > 0 then round((v_op_profit / v_rev) * 100, 2) else 0 end else 0 end,
        'other_income', case when v_can_view_cost then round(v_other_income, 2) else 0 end,
        'other_expense', case when v_can_view_cost then round(v_other_expense, 2) else 0 end,
        'net_profit', case when v_can_view_cost then round(v_net_profit, 2) else 0 end,
        'net_margin_pct', case when v_can_view_cost then v_net_margin_pct else 0 end
      ),
      'previous', jsonb_build_object(
        'revenue', case when v_can_view_cost then round(v_prev_rev, 2) else 0 end,
        'cogs', case when v_can_view_cost then round(v_prev_cogs, 2) else 0 end,
        'gross_profit', case when v_can_view_cost then round(v_prev_gross_profit, 2) else 0 end,
        'gross_margin_pct', case when v_can_view_cost then v_prev_gross_margin_pct else 0 end,
        'operating_expenses', case when v_can_view_cost then round(v_prev_op_expenses, 2) else 0 end,
        'operating_profit', case when v_can_view_cost then round(v_prev_op_profit, 2) else 0 end,
        'net_profit', case when v_can_view_cost then round(v_prev_net_profit, 2) else 0 end,
        'net_margin_pct', case when v_can_view_cost then v_prev_net_margin_pct else 0 end
      ),
      'growth', jsonb_build_object(
        'revenue_pct', case when v_prev_rev > 0 then round(((v_rev - v_prev_rev) / v_prev_rev) * 100, 2) else 0 end,
        'gross_profit_pct', case when v_prev_gross_profit > 0 then round(((v_gross_profit - v_prev_gross_profit) / v_prev_gross_profit) * 100, 2) else 0 end,
        'expenses_pct', case when v_prev_op_expenses > 0 then round(((v_op_expenses - v_prev_op_expenses) / v_prev_op_expenses) * 100, 2) else 0 end,
        'net_profit_pct', case when abs(v_prev_net_profit) > 0 then round(((v_net_profit - v_prev_net_profit) / abs(v_prev_net_profit)) * 100, 2) else 0 end
      )
    ),
    'cash_flow', jsonb_build_object(
      'cash_opening', case when v_can_view_cost then round(v_cash_opening, 2) else 0 end,
      'cash_in', case when v_can_view_cost then round(v_cash_in, 2) else 0 end,
      'cash_out', case when v_can_view_cost then round(v_cash_out, 2) else 0 end,
      'cash_closing', case when v_can_view_cost then round(v_cash_closing, 2) else 0 end,
      'bank_opening', case when v_can_view_cost then round(v_bank_opening, 2) else 0 end,
      'bank_in', case when v_can_view_cost then round(v_bank_in, 2) else 0 end,
      'bank_out', case when v_can_view_cost then round(v_bank_out, 2) else 0 end,
      'bank_closing', case when v_can_view_cost then round(v_bank_closing, 2) else 0 end,
      'contra_transfers', case when v_can_view_cost then round(v_transfers_contra, 2) else 0 end,
      'net_movement', case when v_can_view_cost then round(v_net_cash_movement, 2) else 0 end,
      'total_liquidity', case when v_can_view_cost then round(v_cash_closing + v_bank_closing, 2) else 0 end,
      'daily_timeline', case when v_can_view_cost then v_cash_flow_daily else '[]'::jsonb end
    ),
    'working_capital', jsonb_build_object(
      'ar_closing', case when v_can_view_cost then round(v_ar_closing, 2) else 0 end,
      'ap_closing', case when v_can_view_cost then round(v_ap_closing, 2) else 0 end,
      'inventory_valuation', case when v_can_view_cost then round(v_inv_valuation, 2) else 0 end,
      'net_working_capital', case when v_can_view_cost then round(v_net_working_capital, 2) else 0 end,
      'current_assets', case when v_can_view_cost then round(v_current_assets, 2) else 0 end,
      'current_liabilities', case when v_can_view_cost then round(v_current_liabilities, 2) else 0 end,
      'working_capital_ratio', v_wc_ratio,
      'receivables_aging', case when v_can_view_cost then v_ar_aging else '{}'::jsonb end,
      'payables_aging', case when v_can_view_cost then v_ap_aging else '{}'::jsonb end
    ),
    'accounting_health', jsonb_build_object(
      'is_balanced', v_tb_balanced,
      'debits', case when v_can_view_cost then round(v_tb_debits, 2) else 0 end,
      'credits', case when v_can_view_cost then round(v_tb_credits, 2) else 0 end,
      'difference', case when v_can_view_cost then round(v_tb_diff, 2) else 0 end,
      'journal_count', v_journal_count,
      'account_groups', case when v_can_view_cost then v_account_groups else '[]'::jsonb end
    ),
    'gst_and_tax', jsonb_build_object(
      'tax_mode', v_tax_mode,
      'output_tax', jsonb_build_object(
        'cgst', case when v_can_view_cost then round(v_output_cgst, 2) else 0 end,
        'sgst', case when v_can_view_cost then round(v_output_sgst, 2) else 0 end,
        'igst', case when v_can_view_cost then round(v_output_igst, 2) else 0 end,
        'cess', case when v_can_view_cost then round(v_output_cess, 2) else 0 end,
        'total', case when v_can_view_cost then round(v_output_total, 2) else 0 end
      ),
      'input_tax', jsonb_build_object(
        'cgst', case when v_can_view_cost then round(v_input_cgst, 2) else 0 end,
        'sgst', case when v_can_view_cost then round(v_input_sgst, 2) else 0 end,
        'igst', case when v_can_view_cost then round(v_input_igst, 2) else 0 end,
        'cess', case when v_can_view_cost then round(v_input_cess, 2) else 0 end,
        'total', case when v_can_view_cost then round(v_input_total, 2) else 0 end
      ),
      'net_liability', case when v_can_view_cost then round(greatest(v_output_total - v_input_total, 0), 2) else 0 end,
      'itc_credit_balance', case when v_can_view_cost then round(greatest(v_input_total - v_output_total, 0), 2) else 0 end
    ),
    'anomalies', v_anomalies,
    'projections', v_projections
  );
end;
$$;

-- 3. Expense Intelligence RPC (v8.3.5)
create or replace function public.expense_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days int default 30,
  p_query text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_is_owner boolean := false;
  v_can_view_cost boolean := false;
  v_period_days int;
  v_to date := current_date;
  v_from date;
  v_prev_to date;
  v_prev_from date;

  v_curr_total numeric := 0;
  v_curr_count int := 0;
  v_prev_total numeric := 0;
  v_prev_count int := 0;
  v_growth_pct numeric := 0;
  v_avg_daily numeric := 0;
  v_avg_txn numeric := 0;

  v_categories jsonb := '[]'::jsonb;
  v_daily_trends jsonb := '[]'::jsonb;
  v_locations jsonb := '[]'::jsonb;
  v_top_payees jsonb := '[]'::jsonb;
  v_recurring jsonb := '[]'::jsonb;
  v_anomalies jsonb := '[]'::jsonb;
  v_active_categories_count int := 0;
  r record;
begin
  -- 1. Tenant access check
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  -- 2. Cost / Financial permission check
  v_can_view_cost := private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'accounting.view')
    or private.erp_has_permission(p_tenant_id, 'reports.view')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- 3. Date window computation
  v_period_days := coalesce(p_days, 30);
  if v_period_days <= 0 then v_period_days := 30; end if;
  v_to := current_date;
  v_from := v_to - v_period_days + 1;
  v_prev_to := v_from - 1;
  v_prev_from := v_prev_to - v_period_days + 1;

  -- 4. Current Window Expense Summary
  select
    coalesce(sum(e.total_amount), 0),
    count(e.id)
  into v_curr_total, v_curr_count
  from public.expenses e
  left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.status = 'posted'
    and e.expense_date between v_from and v_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
    and (p_query = '' or e.payee ilike '%' || p_query || '%' or e.description ilike '%' || p_query || '%');

  -- 5. Prior Window Expense Summary
  select
    coalesce(sum(e.total_amount), 0),
    count(e.id)
  into v_prev_total, v_prev_count
  from public.expenses e
  left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.status = 'posted'
    and e.expense_date between v_prev_from and v_prev_to
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
    and (p_query = '' or e.payee ilike '%' || p_query || '%' or e.description ilike '%' || p_query || '%');

  v_growth_pct := case when v_prev_total > 0 then round(((v_curr_total - v_prev_total) / v_prev_total) * 100, 2) else 0 end;
  v_avg_daily := case when v_period_days > 0 then round(v_curr_total / v_period_days, 2) else 0 end;
  v_avg_txn := case when v_curr_count > 0 then round(v_curr_total / v_curr_count, 2) else 0 end;

  -- 6. Category Breakdown with Prior Comparison
  with curr_cat as (
    select
      ec.id as cat_id,
      coalesce(ec.name, 'Uncategorized') as cat_name,
      sum(e.total_amount) as total_amt,
      count(e.id) as cnt
    from public.expenses e
    left join public.expense_categories ec on ec.id = e.category_id
    left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
      and (p_query = '' or e.payee ilike '%' || p_query || '%' or e.description ilike '%' || p_query || '%')
    group by ec.id, ec.name
  ),
  prev_cat as (
    select
      ec.id as cat_id,
      sum(e.total_amount) as prev_total_amt
    from public.expenses e
    left join public.expense_categories ec on ec.id = e.category_id
    left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_prev_from and v_prev_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
    group by ec.id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'category_id', c.cat_id,
      'category_name', c.cat_name,
      'total_amount', round(c.total_amt, 2),
      'expense_count', c.cnt,
      'share_pct', case when v_curr_total > 0 then round((c.total_amt / v_curr_total) * 100, 2) else 0 end,
      'prior_amount', round(coalesce(p.prev_total_amt, 0), 2),
      'growth_pct', case when coalesce(p.prev_total_amt, 0) > 0 then round(((c.total_amt - p.prev_total_amt) / p.prev_total_amt) * 100, 2) else 0 end
    ) order by c.total_amt desc), '[]'::jsonb),
    count(c.cat_id)
  into v_categories, v_active_categories_count
  from curr_cat c
  left join prev_cat p on p.cat_id = c.cat_id;

  -- 7. Daily Trends
  with day_series as (
    select generate_series(v_from, v_to, '1 day'::interval)::date as day_dt
  ),
  day_expenses as (
    select
      e.expense_date as day_dt,
      sum(e.total_amount) as total,
      count(*) as cnt
    from public.expenses e
    left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
      and (p_query = '' or e.payee ilike '%' || p_query || '%' or e.description ilike '%' || p_query || '%')
    group by e.expense_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'day_date', ds.day_dt::text,
    'label', to_char(ds.day_dt, 'Dy, Mon DD'),
    'amount', round(coalesce(de.total, 0), 2),
    'transaction_count', coalesce(de.cnt, 0)
  ) order by ds.day_dt), '[]'::jsonb)
  into v_daily_trends
  from day_series ds
  left join day_expenses de on de.day_dt = ds.day_dt;

  -- 8. Location Comparisons
  with loc_agg as (
    select
      oe.location_id,
      coalesce(bl.name, 'Default Location') as location_name,
      sum(e.total_amount) as total,
      count(e.id) as cnt
    from public.expenses e
    left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
    left join public.business_locations bl on bl.id = oe.location_id and bl.tenant_id = e.tenant_id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
    group by oe.location_id, bl.name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'location_id', location_id,
    'location_name', location_name,
    'total_amount', round(total, 2),
    'expense_count', cnt,
    'share_pct', case when v_curr_total > 0 then round((total / v_curr_total) * 100, 2) else 0 end
  ) order by total desc), '[]'::jsonb)
  into v_locations
  from loc_agg;

  -- 9. Top Payees / Vendors
  with payee_agg as (
    select
      coalesce(nullif(trim(e.payee), ''), 'Unknown Payee') as payee_name,
      sum(e.total_amount) as total,
      count(*) as cnt,
      max(e.expense_date)::text as latest_dt
    from public.expenses e
    left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_from and v_to
      and (p_location_id is null or private.reports_scope_v631(p_tenant_id, oe.location_id, p_location_id, 'view'))
      and (p_query = '' or e.payee ilike '%' || p_query || '%' or e.description ilike '%' || p_query || '%')
    group by coalesce(nullif(trim(e.payee), ''), 'Unknown Payee')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'payee', payee_name,
    'total_amount', round(total, 2),
    'expense_count', cnt,
    'share_pct', case when v_curr_total > 0 then round((total / v_curr_total) * 100, 2) else 0 end,
    'latest_date', latest_dt
  ) order by total desc), '[]'::jsonb)
  into v_top_payees
  from payee_agg;

  -- 10. Recurring Expenses Detection
  with rec_payees as (
    select
      e.payee,
      coalesce(ec.name, 'General') as category_name,
      count(*) as occurrence_count,
      round(avg(e.total_amount), 2) as avg_amount,
      round(sum(e.total_amount), 2) as total_amount
    from public.expenses e
    left join public.expense_categories ec on ec.id = e.category_id
    where e.tenant_id = p_tenant_id
      and e.status = 'posted'
      and e.expense_date between v_from and v_to
    group by e.payee, ec.name
    having count(*) >= 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'payee', rp.payee,
    'category_name', rp.category_name,
    'occurrence_count', rp.occurrence_count,
    'avg_amount', rp.avg_amount,
    'estimated_monthly', round(rp.avg_amount * 30.0 / nullif(v_period_days, 0), 2),
    'is_recurring', true
  ) order by rp.total_amount desc), '[]'::jsonb)
  into v_recurring
  from rec_payees rp;

  -- 11. Expense Anomalies
  -- Check category spikes (>50% increase)
  for r in select * from jsonb_to_recordset(v_categories) as x(category_name text, total_amount numeric, prior_amount numeric, growth_pct numeric) loop
    if r.prior_amount > 200 and r.growth_pct > 50.0 then
      v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
        'id', 'anom-exp-spike-' || md5(r.category_name),
        'rule_code', 'ANOM-EXP-01',
        'title', 'Sudden Expense Spike in ' || r.category_name,
        'severity', 'warning',
        'description', r.category_name || ' spend surged by ' || r.growth_pct::text || '% (from ' || r.prior_amount::text || ' to ' || r.total_amount::text || ') compared to prior window.',
        'evidence', jsonb_build_object('category', r.category_name, 'current', r.total_amount, 'previous', r.prior_amount, 'growth_pct', r.growth_pct),
        'timestamp', now()::text
      ));
    end if;
  end loop;

  -- Check unusually large transactions (> 2.5x average)
  if v_avg_txn > 0 then
    for r in
      select e.id, e.expense_number, e.payee, e.total_amount, e.expense_date
      from public.expenses e
      where e.tenant_id = p_tenant_id
        and e.status = 'posted'
        and e.expense_date between v_from and v_to
        and e.total_amount > (v_avg_txn * 2.5)
        and e.total_amount > 2000
      order by e.total_amount desc
      limit 3
    loop
      v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
        'id', 'anom-exp-large-' || r.id::text,
        'rule_code', 'ANOM-EXP-02',
        'title', 'Unusually Large Expense: ' || r.expense_number,
        'severity', 'info',
        'description', 'Single transaction to ' || coalesce(r.payee, 'Unknown') || ' of ' || r.total_amount::text || ' exceeds 2.5x the average transaction size (' || v_avg_txn::text || ').',
        'evidence', jsonb_build_object('expense_number', r.expense_number, 'payee', r.payee, 'amount', r.total_amount, 'expense_date', r.expense_date),
        'timestamp', now()::text
      ));
    end loop;
  end if;

  -- Check duplicate-looking payments (same payee, same amount within 48h)
  with dupes as (
    select
      e1.id as id1,
      e1.expense_number as num1,
      e2.id as id2,
      e2.expense_number as num2,
      e1.payee,
      e1.total_amount,
      e1.expense_date as dt1,
      e2.expense_date as dt2
    from public.expenses e1
    join public.expenses e2 on e2.tenant_id = e1.tenant_id
      and e2.payee = e1.payee
      and e2.total_amount = e1.total_amount
      and e2.id > e1.id
      and abs(e2.expense_date - e1.expense_date) <= 2
    where e1.tenant_id = p_tenant_id
      and e1.status = 'posted'
      and e2.status = 'posted'
      and e1.expense_date between v_from and v_to
    limit 3
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', 'anom-exp-dupe-' || d.id1::text,
    'rule_code', 'ANOM-EXP-03',
    'title', 'Potential Duplicate Expense Entry: ' || d.payee,
    'severity', 'warning',
    'description', 'Entries ' || d.num1 || ' and ' || d.num2 || ' both pay ' || d.total_amount::text || ' to ' || d.payee || ' within 48 hours (' || d.dt1::text || ' and ' || d.dt2::text || ').',
    'evidence', jsonb_build_object('payee', d.payee, 'amount', d.total_amount, 'voucher_1', d.num1, 'voucher_2', d.num2),
    'timestamp', now()::text
  )), '[]'::jsonb)
  into v_anomalies
  from dupes d;

  -- 12. Final Payload
  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_period_days,
    'from_date', v_from::text,
    'to_date', v_to::text,
    'can_view_cost', v_can_view_cost,
    'summary', jsonb_build_object(
      'current', jsonb_build_object(
        'total_expenses', case when v_can_view_cost then round(v_curr_total, 2) else 0 end,
        'transaction_count', v_curr_count,
        'avg_daily_expense', case when v_can_view_cost then v_avg_daily else 0 end,
        'avg_transaction_size', case when v_can_view_cost then v_avg_txn else 0 end,
        'active_categories_count', v_active_categories_count
      ),
      'previous', jsonb_build_object(
        'total_expenses', case when v_can_view_cost then round(v_prev_total, 2) else 0 end,
        'transaction_count', v_prev_count,
        'avg_daily_expense', case when v_can_view_cost then case when v_period_days > 0 then round(v_prev_total / v_period_days, 2) else 0 end else 0 end
      ),
      'growth', jsonb_build_object(
        'total_expenses_pct', v_growth_pct,
        'transaction_count_pct', case when v_prev_count > 0 then round(((v_curr_count - v_prev_count)::numeric / v_prev_count) * 100, 2) else 0 end
      )
    ),
    'categories', case when v_can_view_cost then v_categories else '[]'::jsonb end,
    'trends', jsonb_build_object(
      'daily', case when v_can_view_cost then v_daily_trends else '[]'::jsonb end
    ),
    'by_location', case when v_can_view_cost then v_locations else '[]'::jsonb end,
    'by_payee', case when v_can_view_cost then v_top_payees else '[]'::jsonb end,
    'recurring_expenses', case when v_can_view_cost then v_recurring else '[]'::jsonb end,
    'anomalies', v_anomalies
  );
end;
$$;

-- 4. Grants and Permissions
grant execute on function public.financial_intelligence_v830(uuid, uuid, int, text) to authenticated;
grant execute on function public.expense_intelligence_v830(uuid, uuid, int, text) to authenticated;

-- 5. Record Schema Release #711 (v8.3.5)
insert into public.thq_schema_releases (
  migration_no,
  schema_version,
  release_name,
  applied_at,
  notes
)
values (
  711,
  '8.3.5',
  'Operations Intelligence Phase 6: Financial, Accounting & Expense Intelligence',
  now(),
  'Ledger-backed double-entry P&L, cash flow, working capital, trial balance, GST/tax intelligence, and expense intelligence.'
)
on conflict (migration_no) do update set
  applied_at = excluded.applied_at,
  notes = excluded.notes;
