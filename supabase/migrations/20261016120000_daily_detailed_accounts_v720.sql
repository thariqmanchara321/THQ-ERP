-- THQ ERP v7.2.0
-- Daily Detailed Accounts Report Engine
-- Consolidated reporting infrastructure for authoritative daily financial statements

create or replace function public.daily_detailed_accounts_v720(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_zone text;
  v_cash_opening numeric := 0;
  v_cash_received numeric := 0;
  v_cash_paid numeric := 0;
  v_cash_closing numeric := 0;

  v_bank_opening numeric := 0;
  v_bank_received numeric := 0;
  v_bank_paid numeric := 0;
  v_bank_closing numeric := 0;

  v_sales_count bigint := 0;
  v_sales_total numeric := 0;
  v_sales_tax numeric := 0;
  v_sales_cash numeric := 0;
  v_sales_bank numeric := 0;
  v_sales_credit numeric := 0;

  v_purchases_count bigint := 0;
  v_purchases_total numeric := 0;
  v_purchases_tax numeric := 0;
  v_purchases_cash numeric := 0;
  v_purchases_bank numeric := 0;
  v_purchases_credit numeric := 0;

  v_customer_receipts numeric := 0;
  v_supplier_payments numeric := 0;
  v_expenses_total numeric := 0;
  v_transfers_total numeric := 0;

  v_sales_returns_count bigint := 0;
  v_sales_returns_total numeric := 0;
  v_purchase_returns_count bigint := 0;
  v_purchase_returns_total numeric := 0;

  v_ar_opening numeric := 0;
  v_ar_closing numeric := 0;
  v_ap_opening numeric := 0;
  v_ap_closing numeric := 0;

  v_day_journals jsonb := '[]'::jsonb;
  v_exceptions jsonb := '[]'::jsonb;
  v_closing_statement text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access denied' using errcode = '42501';
  end if;

  select coalesce(timezone, 'Asia/Kolkata') into v_zone
  from public.tenant_settings
  where tenant_id = p_tenant_id;

  -- 1. Cash Balances
  select coalesce(sum(jl.debit - jl.credit), 0) into v_cash_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or j.location_id = p_location_id);

  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
    into v_cash_received, v_cash_paid
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or j.location_id = p_location_id);

  v_cash_closing := v_cash_opening + v_cash_received - v_cash_paid;

  -- 2. Bank Balances
  select coalesce(sum(jl.debit - jl.credit), 0) into v_bank_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and (a.system_key in ('bank_account', 'undeposited_funds', 'clearing_account') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'upi', 'card'))
    and (p_location_id is null or j.location_id = p_location_id);

  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
    into v_bank_received, v_bank_paid
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and (a.system_key in ('bank_account', 'undeposited_funds', 'clearing_account') or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'upi', 'card'))
    and (p_location_id is null or j.location_id = p_location_id);

  v_bank_closing := v_bank_opening + v_bank_received - v_bank_paid;

  -- 3. Sales Activity
  select
    count(*),
    coalesce(sum(grand_total), 0),
    coalesce(sum(tax_total), 0)
    into v_sales_count, v_sales_total, v_sales_tax
  from public.sales s
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('draft', 'void', 'cancelled')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, os.location_id, p_location_id, 'view'));

  select coalesce(sum(p.amount), 0) into v_sales_cash
  from public.sale_payments p
  join public.sales s on s.id = p.sale_id and s.tenant_id = p.tenant_id
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where p.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('draft', 'void', 'cancelled')
    and lower(coalesce(p.payment_method, 'cash')) = 'cash'
    and (p_location_id is null or os.location_id = p_location_id);

  select coalesce(sum(p.amount), 0) into v_sales_bank
  from public.sale_payments p
  join public.sales s on s.id = p.sale_id and s.tenant_id = p.tenant_id
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where p.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('draft', 'void', 'cancelled')
    and lower(coalesce(p.payment_method, 'cash')) in ('bank', 'upi', 'card', 'online', 'cheque')
    and (p_location_id is null or os.location_id = p_location_id);

  v_sales_credit := greatest(0, v_sales_total - v_sales_cash - v_sales_bank);

  -- 4. Purchases Activity
  select
    count(*),
    coalesce(sum(grand_total), 0),
    coalesce(sum(tax_total), 0)
    into v_purchases_count, v_purchases_total, v_purchases_tax
  from public.purchases p
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where p.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('draft', 'void', 'cancelled')
    and (p_location_id is null or private.reports_scope_v631(p_tenant_id, op.location_id, p_location_id, 'view'));

  select coalesce(sum(x.amount), 0) into v_purchases_cash
  from public.purchase_payments x
  join public.purchases p on p.id = x.purchase_id and p.tenant_id = x.tenant_id
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where x.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('draft', 'void', 'cancelled')
    and lower(coalesce(x.payment_method, 'cash')) = 'cash'
    and (p_location_id is null or op.location_id = p_location_id);

  select coalesce(sum(x.amount), 0) into v_purchases_bank
  from public.purchase_payments x
  join public.purchases p on p.id = x.purchase_id and p.tenant_id = x.tenant_id
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where x.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('draft', 'void', 'cancelled')
    and lower(coalesce(x.payment_method, 'cash')) in ('bank', 'upi', 'card', 'online', 'cheque')
    and (p_location_id is null or op.location_id = p_location_id);

  v_purchases_credit := greatest(0, v_purchases_total - v_purchases_cash - v_purchases_bank);

  -- 5. Customer Receipts & Supplier Payments
  select coalesce(sum(p.amount), 0) into v_customer_receipts
  from public.sale_payments p
  left join public.document_origins os on os.tenant_id = p.tenant_id and os.entity_type = 'sale' and os.entity_id = p.sale_id
  where p.tenant_id = p_tenant_id
    and (p.paid_at at time zone v_zone)::date between p_from and p_to
    and (p_location_id is null or os.location_id = p_location_id);

  select coalesce(sum(p.amount), 0) into v_supplier_payments
  from public.purchase_payments p
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.purchase_id
  where p.tenant_id = p_tenant_id
    and (p.paid_at at time zone v_zone)::date between p_from and p_to
    and (p_location_id is null or op.location_id = p_location_id);

  -- 6. Operating Expenses
  select coalesce(sum(total_amount), 0) into v_expenses_total
  from public.expenses e
  left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between p_from and p_to
    and coalesce(e.status, 'posted') = 'posted'
    and (p_location_id is null or oe.location_id = p_location_id);

  -- 7. Account Transfers (Contra)
  select coalesce(sum(jl.debit), 0) into v_transfers_total
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and j.source_type in ('contra', 'transfer')
    and (p_location_id is null or j.location_id = p_location_id);

  -- 8. Returns
  select count(*), coalesce(sum(grand_total), 0)
  into v_sales_returns_count, v_sales_returns_total
  from public.sales_returns sr
  where sr.tenant_id = p_tenant_id
    and sr.return_date between p_from and p_to
    and sr.refund_status <> 'waived'
    and (p_location_id is null or sr.location_id = p_location_id);

  select count(*), coalesce(sum(grand_total), 0)
  into v_purchase_returns_count, v_purchase_returns_total
  from public.purchase_returns pr
  where pr.tenant_id = p_tenant_id
    and pr.return_date between p_from and p_to
    and pr.credit_status <> 'waived'
    and (p_location_id is null or pr.location_id = p_location_id);

  -- 9. AR / AP Balances
  select coalesce(sum(jl.debit - jl.credit), 0) into v_ar_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and a.system_key in ('accounts_receivable', 'customer_credits')
    and (p_location_id is null or j.location_id = p_location_id);

  select coalesce(sum(jl.debit - jl.credit), 0) into v_ar_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date <= p_to
    and a.system_key in ('accounts_receivable', 'customer_credits')
    and (p_location_id is null or j.location_id = p_location_id);

  select coalesce(sum(jl.credit - jl.debit), 0) into v_ap_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and a.system_key in ('accounts_payable', 'supplier_credits')
    and (p_location_id is null or j.location_id = p_location_id);

  select coalesce(sum(jl.credit - jl.debit), 0) into v_ap_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date <= p_to
    and a.system_key in ('accounts_payable', 'supplier_credits')
    and (p_location_id is null or j.location_id = p_location_id);

  -- 10. Day Journals
  select coalesce(jsonb_agg(jsonb_build_object(
    'journal_id', j.id,
    'entry_number', j.entry_number,
    'entry_date', j.entry_date,
    'source_type', j.source_type,
    'source_id', j.source_id,
    'reference', j.source_reference,
    'description', j.description,
    'status', j.status,
    'debit_total', coalesce(tot.debit_total, 0),
    'credit_total', coalesce(tot.credit_total, 0),
    'is_balanced', abs(coalesce(tot.debit_total, 0) - coalesce(tot.credit_total, 0)) < 0.01,
    'lines_count', coalesce(tot.lines_count, 0)
  ) order by j.entry_date desc, j.created_at desc), '[]'::jsonb)
  into v_day_journals
  from public.journal_entries j
  left join lateral (
    select
      sum(jl.debit) as debit_total,
      sum(jl.credit) as credit_total,
      count(*) as lines_count
    from public.journal_lines jl
    where jl.journal_entry_id = j.id
  ) tot on true
  where j.tenant_id = p_tenant_id
    and j.entry_date between p_from and p_to
    and (p_location_id is null or j.location_id = p_location_id)
  limit 200;

  -- 11. Accounting Exceptions
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', 'unbalanced_journal',
    'id', j.id,
    'reference', j.entry_number,
    'note', 'Journal entry debits (' || coalesce(tot.debit_total, 0) || ') do not equal credits (' || coalesce(tot.credit_total, 0) || ')'
  )), '[]'::jsonb)
  into v_exceptions
  from public.journal_entries j
  left join lateral (
    select
      sum(jl.debit) as debit_total,
      sum(jl.credit) as credit_total
    from public.journal_lines jl
    where jl.journal_entry_id = j.id
  ) tot on true
  where j.tenant_id = p_tenant_id
    and j.entry_date between p_from and p_to
    and abs(coalesce(tot.debit_total, 0) - coalesce(tot.credit_total, 0)) >= 0.01;

  if v_cash_closing < 0 then
    v_exceptions := v_exceptions || jsonb_build_array(jsonb_build_object(
      'type', 'negative_cash',
      'reference', 'Cash Account',
      'note', 'Closing cash balance is negative: ' || v_cash_closing
    ));
  end if;

  -- 12. Closing Statement
  v_closing_statement := format(
    'Daily Closing Statement: On %s to %s, total sales reached %s across %s invoices (%s cash, %s credit). Purchases totaled %s across %s bills. Customer receipts were %s and supplier payments %s. Cash closed at %s (movement %s); Bank closed at %s (movement %s). Total operating expenses recognized: %s. Receivables moved by %s; Payables moved by %s. Status: %s.',
    p_from, p_to, v_sales_total, v_sales_count, v_sales_cash, v_sales_credit,
    v_purchases_total, v_purchases_count, v_customer_receipts, v_supplier_payments,
    v_cash_closing, (v_cash_closing - v_cash_opening),
    v_bank_closing, (v_bank_closing - v_bank_opening),
    v_expenses_total, (v_ar_closing - v_ar_opening), (v_ap_closing - v_ap_opening),
    case when jsonb_array_length(v_exceptions) = 0 then 'Reconciled (Passed)' else 'Exceptions Flagged' end
  );

  return jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to),
    'currency', coalesce((select currency_code from public.tenant_settings where tenant_id = p_tenant_id), 'INR'),
    'cash', jsonb_build_object(
      'opening', v_cash_opening,
      'received', v_cash_received,
      'paid', v_cash_paid,
      'closing', v_cash_closing,
      'net_movement', v_cash_closing - v_cash_opening
    ),
    'bank', jsonb_build_object(
      'opening', v_bank_opening,
      'received', v_bank_received,
      'paid', v_bank_paid,
      'closing', v_bank_closing,
      'net_movement', v_bank_closing - v_bank_opening
    ),
    'sales', jsonb_build_object(
      'count', v_sales_count,
      'total', v_sales_total,
      'tax', v_sales_tax,
      'cash', v_sales_cash,
      'bank', v_sales_bank,
      'credit', v_sales_credit
    ),
    'purchases', jsonb_build_object(
      'count', v_purchases_count,
      'total', v_purchases_total,
      'tax', v_purchases_tax,
      'cash', v_purchases_cash,
      'bank', v_purchases_bank,
      'credit', v_purchases_credit
    ),
    'receipts', jsonb_build_object(
      'customer_receipts', v_customer_receipts
    ),
    'payments', jsonb_build_object(
      'supplier_payments', v_supplier_payments,
      'operating_expenses', v_expenses_total,
      'transfers', v_transfers_total
    ),
    'returns', jsonb_build_object(
      'sales_count', v_sales_returns_count,
      'sales_total', v_sales_returns_total,
      'purchase_count', v_purchase_returns_count,
      'purchase_total', v_purchase_returns_total
    ),
    'receivables', jsonb_build_object(
      'opening', v_ar_opening,
      'closing', v_ar_closing,
      'net_movement', v_ar_closing - v_ar_opening
    ),
    'payables', jsonb_build_object(
      'opening', v_ap_opening,
      'closing', v_ap_closing,
      'net_movement', v_ap_closing - v_ap_opening
    ),
    'day_journals', v_day_journals,
    'exceptions', v_exceptions,
    'reconciliation_status', case when jsonb_array_length(v_exceptions) = 0 then 'Passed' else 'Mismatch' end,
    'closing_statement', v_closing_statement
  );
end;
$$;

revoke all on function public.daily_detailed_accounts_v720(uuid, date, date, uuid) from public, anon;
grant execute on function public.daily_detailed_accounts_v720(uuid, date, date, uuid) to authenticated;
