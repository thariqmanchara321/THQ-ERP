-- Phase B: Integrity & Reconciliation Center
-- Authoritative, read-only integrity engine for accounting, inventory, sales, purchases, banking, tax and operational consistency.
-- 1. Upgraded private.audit_checks_v704 with category filtering and 27 defensible domain checks.
-- 2. Added private.audit_check_records_v704 for evidence drill-down into specific affected records.
-- 3. Added public wrappers public.audit_checks_v704 and public.audit_check_records_v704.

create or replace function private.audit_checks_v704(t uuid, f date, z date, loc uuid, cat text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  rows jsonb:='[]';
  x record;
  n bigint;
  amt numeric;
  accounts jsonb;
  cash numeric;
  root record;
  verification jsonb;
  failed integer:=0;
  partial integer:=0;
  verified integer:=0;
  run_all boolean;
  run_acc boolean;
  run_inv boolean;
  run_sal boolean;
  run_bnk boolean;
  run_tax boolean;
  run_ops boolean;
begin
  perform private.audit_access_v703(t, loc);
  if f is null or z is null or f > z then
    raise exception 'Invalid audit period' using errcode='22023';
  end if;

  run_all := (cat is null or trim(cat) = '' or lower(trim(cat)) = 'all');
  run_acc := run_all or lower(trim(cat)) = 'accounting';
  run_inv := run_all or lower(trim(cat)) = 'inventory';
  run_sal := run_all or lower(trim(cat)) in ('sales_purchase', 'sales', 'purchases');
  run_bnk := run_all or lower(trim(cat)) in ('banking_payment', 'banking', 'payments');
  run_tax := run_all or lower(trim(cat)) in ('tax_gst', 'tax', 'gst');
  run_ops := run_all or lower(trim(cat)) in ('operational', 'system');

  -- =========================================================================
  -- A. ACCOUNTING INTEGRITY
  -- =========================================================================
  if run_acc then
    -- 1. Unbalanced Journals (Debits != Credits)
    select count(*), coalesce(sum(abs(diff)), 0)
    into n, amt
    from (
      select j.id, sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0)) as diff
      from public.journal_entries j
      join public.journal_lines l on l.journal_entry_id = j.id
      where j.tenant_id = t and j.entry_date between f and z
        and private.audit_record_allowed_v704(t, 'journal_entries', to_jsonb(j), loc)
      group by j.id
      having abs(sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0))) > 0.005
    ) d;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'accounting_unbalanced_journals',
      'category', 'accounting',
      'reference', 'Journal balance',
      'title', 'Unbalanced journal entries (Debits != Credits)',
      'count', n,
      'amount', amt,
      'difference', amt,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'critical',
      'dataset', 'journal_entries',
      'is_actionable', true,
      'basis', 'Double-entry rule: debits must equal credits for every posted journal entry (tolerance: 0.005).',
      'explanation', 'Every transaction journal must have zero net difference between total debits and total credits.'
    ));

    -- 2. Journal lines without valid account
    select count(*)
    into n
    from public.journal_lines l
    join public.journal_entries j on j.id = l.journal_entry_id
    where j.tenant_id = t and j.entry_date between f and z
      and private.audit_record_allowed_v704(t, 'journal_entries', to_jsonb(j), loc)
      and (l.account_id is null or not exists (
        select 1 from public.accounting_accounts a where a.id = l.account_id and a.tenant_id = t
      ));
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'accounting_orphaned_lines',
      'category', 'accounting',
      'reference', 'Chart of accounts',
      'title', 'Journal lines without valid accounts',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'journal_entries',
      'is_actionable', true,
      'basis', 'All journal debit/credit lines must resolve to an active tenant accounting account.',
      'explanation', 'Journal lines referencing null or missing account IDs break general ledger reporting and trial balance reconciliation.'
    ));

    -- 3. Trial Balance Difference
    accounts := private.audit_workspace_v703(t, 'accounts', f, z, loc, '', '', '', 'account_name', false, 0, 200);
    amt := coalesce((accounts#>>'{account_totals,difference}')::numeric, 0);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'trial_balance',
      'category', 'accounting',
      'reference', 'Trial balance',
      'title', 'Period debits minus credits variance',
      'amount', amt,
      'difference', amt,
      'count', case when abs(amt) > 0.005 then 1 else 0 end,
      'status', case when abs(amt) > 0.005 then 'Issue detected' else 'Passed' end,
      'severity', 'critical',
      'dataset', 'accounts',
      'is_actionable', true,
      'basis', 'Trial balance net variance across all active ledger accounts in period (tolerance: 0.005).',
      'explanation', 'Sum of all debit account balances must match sum of credit account balances.'
    ));

    -- 4. Negative Cash Closing Balance
    select coalesce(sum((a->>'debit')::numeric - (a->>'credit')::numeric), 0)
    into cash
    from private.accounting_lines_v702(t, z, loc) a
    where a->>'money_method' = 'cash';
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'negative_cash',
      'category', 'accounting',
      'reference', 'Cash on hand',
      'title', 'Cash closing balance negative review',
      'amount', cash,
      'count', case when cash < -0.005 then 1 else 0 end,
      'status', case when cash < -0.005 then 'Needs review' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'accounts',
      'is_actionable', true,
      'basis', 'Effective posted cash ledger through period end.',
      'explanation', 'A negative cash closing balance usually indicates missing cash receipts or unrecorded initial float.'
    ));

    -- 5. Posted Records Without Linked Journals
    for x in select * from (values
      ('sales', 'sale', 'sale_date', 'status=''posted'''),
      ('purchases', 'purchase', 'purchase_date', 'status=''posted'''),
      ('expenses', 'expense', 'expense_date', 'status=''posted'''),
      ('staff_earnings_v630', 'staff_earning', 'earning_date', 'true'),
      ('staff_payments_v630', 'staff_payment', 'payment_date', 'true'),
      ('purchase_invoices_v484', 'purchase_invoice_v484', 'invoice_date', 'status in (''posted'',''partially_paid'',''paid'')'),
      ('customer_receipts', 'customer_receipt', 'receipt_date', 'status=''posted'''),
      ('supplier_payments_v484', 'supplier_payment', 'payment_date', 'status=''posted''')
    ) v(dataset, source, datefield, condition) loop
      execute format(
        'select count(*) from public.%I d where d.tenant_id=$1 and d.%I between $2 and $3 and (%s) and private.audit_record_allowed_v704($1,$4,to_jsonb(d),$5) and not exists(select 1 from public.journal_entries j where j.tenant_id=$1 and j.source_id=d.id and j.source_type=$6 and j.status in(''posted'',''reversed''))',
        x.dataset, x.datefield, x.condition
      ) into n using t, f, z, x.dataset, loc, x.source;
      rows := rows || jsonb_build_array(jsonb_build_object(
        'id', 'posting_' || x.dataset,
        'category', 'accounting',
        'reference', replace(x.dataset, '_', ' '),
        'title', 'Posted ' || replace(x.dataset, '_', ' ') || ' without linked journals',
        'count', n,
        'status', case when n > 0 then 'Needs review' else 'Passed' end,
        'severity', 'medium',
        'dataset', x.dataset,
        'is_actionable', true,
        'basis', 'Source ID and source type match; posted or reversed journal required.',
        'explanation', 'Business transactions should generate double-entry financial journals upon posting.'
      ));
    end loop;
  end if;

  -- =========================================================================
  -- B. INVENTORY INTEGRITY
  -- =========================================================================
  if run_inv then
    -- 1. Stock balances vs movement ledger
    for x in select * from (values
      ('stock_balances', 'stock_movements', 'Stock balances'),
      ('location_stock_balances', 'location_stock_movements', 'Location stock balances')
    ) v(balances, movements, label) loop
      execute format(
        'with b as (select variant_id, location_id, quantity from public.%I x where tenant_id=$1 and private.audit_record_allowed_v704($1,$2,to_jsonb(x),$3)),
              m as (select variant_id, location_id, sum(quantity_delta) as qty from public.%I x where tenant_id=$1 and private.audit_record_allowed_v704($1,$4,to_jsonb(x),$3) group by variant_id, location_id)
         select count(*), coalesce(sum(abs(coalesce(b.quantity,0)-coalesce(m.qty,0))),0)
         from b full join m using(variant_id, location_id)
         where abs(coalesce(b.quantity,0)-coalesce(m.qty,0)) > 0.0001',
        x.balances, x.movements
      ) into n, amt using t, x.balances, loc, x.movements;
      rows := rows || jsonb_build_array(jsonb_build_object(
        'id', 'stock_' || x.balances,
        'category', 'inventory',
        'reference', x.label,
        'title', x.label || ' variance from movement ledger',
        'count', n,
        'difference', amt,
        'status', case when n > 0 then 'Needs review' else 'Passed' end,
        'severity', 'high',
        'dataset', x.balances,
        'is_actionable', true,
        'basis', 'Current balance table versus cumulative sum of all recorded stock movements.',
        'explanation', 'Saved on-hand balances must reconcile with the cumulative movement ledger history.'
      ));
    end loop;

    -- 2. Negative stock balances
    select count(*), coalesce(sum(abs(b.quantity)), 0)
    into n, amt
    from public.stock_balances b
    where b.tenant_id = t and b.quantity < -0.0001
      and private.audit_record_allowed_v704(t, 'stock_balances', to_jsonb(b), loc);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'inventory_negative_stock',
      'category', 'inventory',
      'reference', 'Negative inventory',
      'title', 'Negative stock balances on hand',
      'count', n,
      'difference', amt,
      'status', case when n > 0 then 'Needs review' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'stock_balances',
      'is_actionable', true,
      'basis', 'Items with recorded balance below zero (tolerance: 0.0001).',
      'explanation', 'Negative stock may reflect timing differences in receiving vs selling or misallocated stock batches.'
    ));

    -- 3. Orphaned stock movements (missing variant)
    select count(*)
    into n
    from public.stock_movements m
    where m.tenant_id = t
      and private.audit_record_allowed_v704(t, 'stock_movements', to_jsonb(m), loc)
      and not exists (select 1 from public.product_variants v where v.id = m.variant_id and v.tenant_id = t);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'inventory_orphaned_movements',
      'category', 'inventory',
      'reference', 'Stock movements',
      'title', 'Stock movements referencing missing product variants',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'stock_movements',
      'is_actionable', true,
      'basis', 'Every inventory movement must link to a valid product variant in the catalogue.',
      'explanation', 'Unlinked stock movements corrupt inventory valuation and SKU tracking.'
    ));
  end if;

  -- =========================================================================
  -- C. SALES & PURCHASE INTEGRITY
  -- =========================================================================
  if run_sal then
    -- 1. Sales invoice header vs line items
    select count(*), coalesce(sum(abs(s.grand_total - l.lines_sum)), 0)
    into n, amt
    from public.sales s
    cross join lateral (
      select coalesce(sum(si.line_total), 0) + coalesce(s.round_off, 0) + coalesce(s.additional_charges, 0) as lines_sum
      from public.sale_items si
      where si.sale_id = s.id
    ) l
    where s.tenant_id = t and s.sale_date between f and z and s.status = 'posted'
      and private.audit_record_allowed_v704(t, 'sales', to_jsonb(s), loc)
      and abs(s.grand_total - l.lines_sum) > 0.05;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'sales_header_vs_lines',
      'category', 'sales_purchase',
      'reference', 'Sales invoice totals',
      'title', 'Sale invoice total differs from sum of line items',
      'count', n,
      'difference', amt,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'sales',
      'is_actionable', true,
      'basis', 'Invoice grand_total must equal line totals + round off + additional charges (tolerance: 0.05).',
      'explanation', 'Header totals must match the exact mathematical sum of constituent lines.'
    ));

    -- 2. Purchases invoice header vs line items
    select count(*), coalesce(sum(abs(p.grand_total - l.lines_sum)), 0)
    into n, amt
    from public.purchases p
    cross join lateral (
      select coalesce(sum(pi.line_total), 0) + coalesce(p.round_off, 0) + coalesce(p.additional_charges, 0) as lines_sum
      from public.purchase_items pi
      where pi.purchase_id = p.id
    ) l
    where p.tenant_id = t and p.purchase_date between f and z and p.status = 'posted'
      and private.audit_record_allowed_v704(t, 'purchases', to_jsonb(p), loc)
      and abs(p.grand_total - l.lines_sum) > 0.05;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'purchases_header_vs_lines',
      'category', 'sales_purchase',
      'reference', 'Purchase invoice totals',
      'title', 'Purchase invoice total differs from sum of line items',
      'count', n,
      'difference', amt,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'purchases',
      'is_actionable', true,
      'basis', 'Purchase grand_total must equal line totals + round off + additional charges (tolerance: 0.05).',
      'explanation', 'Recorded purchase order or invoice headers must equal sum of line entries.'
    ));

    -- 3. Sales missing customer reference
    select count(*)
    into n
    from public.sales s
    where s.tenant_id = t and s.sale_date between f and z
      and s.customer_id is not null
      and private.audit_record_allowed_v704(t, 'sales', to_jsonb(s), loc)
      and not exists (select 1 from public.customers c where c.id = s.customer_id and c.tenant_id = t);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'sales_orphaned_customer',
      'category', 'sales_purchase',
      'reference', 'Customer references',
      'title', 'Sales invoices referencing non-existent customers',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'sales',
      'is_actionable', true,
      'basis', 'Every sale customer_id must exist in customers table.',
      'explanation', 'Orphaned customer references lead to incorrect receivables and ledger allocations.'
    ));

    -- 4. Purchases missing supplier reference
    select count(*)
    into n
    from public.purchases p
    where p.tenant_id = t and p.purchase_date between f and z
      and p.supplier_id is not null
      and private.audit_record_allowed_v704(t, 'purchases', to_jsonb(p), loc)
      and not exists (select 1 from public.suppliers s where s.id = p.supplier_id and s.tenant_id = t);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'purchases_orphaned_supplier',
      'category', 'sales_purchase',
      'reference', 'Supplier references',
      'title', 'Purchases referencing non-existent suppliers',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'purchases',
      'is_actionable', true,
      'basis', 'Every purchase supplier_id must exist in suppliers table.',
      'explanation', 'Orphaned supplier references break AP subsidiary ledger reconciliation.'
    ));
  end if;

  -- =========================================================================
  -- D. BANKING & PAYMENT INTEGRITY
  -- =========================================================================
  if run_bnk then
    -- 1. Unmatched bank statement lines
    select count(*)
    into n
    from public.bank_statement_lines_v500 b
    where b.tenant_id = t and b.transaction_date between f and z
      and (b.matched_journal_id is null or b.status <> 'matched')
      and private.audit_record_allowed_v704(t, 'bank_statement_lines_v500', to_jsonb(b), loc);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'bank_unmatched',
      'category', 'banking_payment',
      'reference', 'Bank statements',
      'title', 'Unmatched saved bank statement lines',
      'count', n,
      'status', case when n > 0 then 'Needs review' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'bank_statement_lines_v500',
      'is_actionable', true,
      'basis', 'Checks imported statement lines without matched journal entries.',
      'explanation', 'Unmatched bank statement transactions require reconciliation against receipts, payments or expenses.'
    ));

    -- 2. Bank evidence coverage
    select count(*)
    into n
    from public.bank_statement_lines_v500 b
    where b.tenant_id = t and b.transaction_date between f and z
      and private.audit_record_allowed_v704(t, 'bank_statement_lines_v500', to_jsonb(b), loc);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'bank_coverage',
      'category', 'banking_payment',
      'reference', 'Bank coverage',
      'title', 'Bank statement import coverage in period',
      'count', n,
      'status', case when n = 0 then 'Insufficient data' else 'Passed' end,
      'severity', 'informational',
      'dataset', 'bank_statement_lines_v500',
      'is_actionable', false,
      'basis', 'Total bank statement records imported during the audit period.',
      'explanation', case when n = 0 then 'No bank statements were imported for this period; bank reconciliation cannot be verified.' else 'Bank statement lines are recorded and available for reconciliation.' end
    ));

    -- 3. Customer receipts missing customer
    select count(*)
    into n
    from public.customer_receipts cr
    where cr.tenant_id = t and cr.receipt_date between f and z
      and cr.customer_id is not null
      and private.audit_record_allowed_v704(t, 'customer_receipts', to_jsonb(cr), loc)
      and not exists (select 1 from public.customers c where c.id = cr.customer_id and c.tenant_id = t);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'receipts_orphaned_customer',
      'category', 'banking_payment',
      'reference', 'Receipt customers',
      'title', 'Customer receipts referencing missing customers',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'customer_receipts',
      'is_actionable', true,
      'basis', 'Receipt customer_id must exist in customers table.',
      'explanation', 'Unlinked receipts cause discrepancies in debtor balances.'
    ));

    -- 4. Supplier payments missing supplier
    select count(*)
    into n
    from public.supplier_payments_v484 sp
    where sp.payment_date between f and z
      and sp.tenant_id = t
      and sp.supplier_id is not null
      and private.audit_record_allowed_v704(t, 'supplier_payments_v484', to_jsonb(sp), loc)
      and not exists (select 1 from public.suppliers s where s.id = sp.supplier_id and s.tenant_id = t);
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'payments_orphaned_supplier',
      'category', 'banking_payment',
      'reference', 'Payment suppliers',
      'title', 'Supplier payments referencing missing suppliers',
      'count', n,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'medium',
      'dataset', 'supplier_payments_v484',
      'is_actionable', true,
      'basis', 'Supplier payment supplier_id must exist in suppliers table.',
      'explanation', 'Unlinked supplier payments prevent proper settlement of creditor accounts.'
    ));
  end if;

  -- =========================================================================
  -- E. TAX & GST INTEGRITY
  -- =========================================================================
  if run_tax then
    -- 1. Sales invoice tax total vs sum of line taxes
    select count(*), coalesce(sum(abs(s.tax_total - l.lines_tax)), 0)
    into n, amt
    from public.sales s
    cross join lateral (
      select coalesce(sum(si.tax_amount), 0) as lines_tax
      from public.sale_items si
      where si.sale_id = s.id
    ) l
    where s.tenant_id = t and s.sale_date between f and z and s.status = 'posted'
      and private.audit_record_allowed_v704(t, 'sales', to_jsonb(s), loc)
      and abs(s.tax_total - l.lines_tax) > 0.05;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'tax_sales_tax_mismatch',
      'category', 'tax_gst',
      'reference', 'Sales tax calculation',
      'title', 'Sales tax total differs from sum of line tax amounts',
      'count', n,
      'difference', amt,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'sales',
      'is_actionable', true,
      'basis', 'Invoice tax_total must match sum of individual line tax_amount (tolerance: 0.05).',
      'explanation', 'Line-by-line tax computations must match invoice tax summaries to ensure statutory GST filing accuracy.'
    ));

    -- 2. Purchases tax total vs sum of line taxes
    select count(*), coalesce(sum(abs(p.tax_total - l.lines_tax)), 0)
    into n, amt
    from public.purchases p
    cross join lateral (
      select coalesce(sum(pi.tax_amount), 0) as lines_tax
      from public.purchase_items pi
      where pi.purchase_id = p.id
    ) l
    where p.tenant_id = t and p.purchase_date between f and z and p.status = 'posted'
      and private.audit_record_allowed_v704(t, 'purchases', to_jsonb(p), loc)
      and abs(p.tax_total - l.lines_tax) > 0.05;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'tax_purchases_tax_mismatch',
      'category', 'tax_gst',
      'reference', 'Purchase tax calculation',
      'title', 'Purchase tax total differs from sum of line tax amounts',
      'count', n,
      'difference', amt,
      'status', case when n > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'high',
      'dataset', 'purchases',
      'is_actionable', true,
      'basis', 'Purchase tax_total must match sum of individual line tax_amount (tolerance: 0.05).',
      'explanation', 'Purchase tax summaries must accurately reflect line item GST to substantiate input tax credit (ITC) claims.'
    ));
  end if;

  -- =========================================================================
  -- F. OPERATIONAL & SYSTEM INTEGRITY
  -- =========================================================================
  if run_ops then
    -- 1. Story history cryptographic verification
    for root in select distinct e.correlation_id, e.root_entity_type, e.root_entity_id
                from public.transaction_story_events_v600 e
                where e.tenant_id = t
                  and private.audit_record_allowed_v704(t, 'transaction_story_events_v600', to_jsonb(e), loc)
    loop
      if exists (select 1 from public.transaction_story_events_v600 e where e.tenant_id = t and e.correlation_id = root.correlation_id and not private.audit_record_allowed_v704(t, 'transaction_story_events_v600', to_jsonb(e), loc)) then
        partial := partial + 1;
        continue;
      end if;
      verification := public.transaction_story_verify_v600(t, root.root_entity_type, root.root_entity_id);
      if coalesce((verification->>'valid')::boolean, false) then
        verified := verified + 1;
      else
        failed := failed + 1;
      end if;
    end loop;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'story_integrity',
      'category', 'operational',
      'reference', 'Audit trail integrity',
      'title', 'Recorded audit story chains failing cryptographic hash verification',
      'count', failed,
      'status', case when failed > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'critical',
      'verified_chains', verified,
      'partial_scope_chains', partial,
      'dataset', 'transaction_story_events_v600',
      'is_actionable', true,
      'basis', 'Cryptographic SHA-256 chain verification of recorded transaction event sequences.',
      'explanation', 'Validates that recorded event logs have not suffered silent tampering, reordering, or metadata truncation.'
    ));

    -- 2. Cross-tenant FK link audit
    for x in
      select distinct cn.relname child, pn.relname parent, ca.attname col
      from pg_catalog.pg_constraint fk
      join pg_catalog.pg_class cn on cn.oid = fk.conrelid
      join pg_catalog.pg_class pn on pn.oid = fk.confrelid
      join pg_catalog.pg_attribute ca on ca.attrelid = cn.oid and ca.attnum = fk.conkey[1]
      join pg_catalog.pg_attribute pa on pa.attrelid = pn.oid and pa.attnum = fk.confkey[1]
      where fk.contype = 'f' and cardinality(fk.conkey) = 1 and fk.connamespace = 'public'::regnamespace and pa.attname = 'id'
        and exists (select 1 from jsonb_array_elements(private.audit_catalog_v704()) c where c->>'key' = cn.relname and (c->>'tenant_column')::boolean)
        and exists (select 1 from jsonb_array_elements(private.audit_catalog_v704()) c where c->>'key' = pn.relname and (c->>'tenant_column')::boolean)
    loop
      execute format(
        'select count(*) from public.%I c join public.%I p on p.id = c.%I where c.tenant_id = $1 and p.tenant_id <> $1 and private.audit_record_allowed_v704($1, $2, to_jsonb(c), $3)',
        x.child, x.parent, x.col
      ) into n using t, x.child, loc;
      if n > 0 then
        rows := rows || jsonb_build_array(jsonb_build_object(
          'id', 'tenant_link_' || x.child || '_' || x.col,
          'category', 'operational',
          'reference', replace(x.child, '_', ' '),
          'title', 'Linked ' || replace(x.child, '_', ' ') || ' records point to another tenant',
          'count', n,
          'status', 'Issue detected',
          'severity', 'critical',
          'dataset', x.child,
          'is_actionable', true,
          'basis', 'Multi-tenant isolation: Foreign keys must never reference foreign tenant records.',
          'explanation', 'Strict multi-tenant security assertion: foreign key reference crosses tenant boundary.'
        ));
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'rows', rows,
    'total_rows', jsonb_array_length(rows),
    'generated_at', statement_timestamp(),
    'basis', 'Authoritative ERP integrity engine. Evaluates mathematical, double-entry, subsidiary ledger, inventory movement, tax and cryptographic consistency.'
  );
end $$;

create or replace function private.audit_check_records_v704(t uuid, check_id text, f date, z date, loc uuid, lim integer default 50) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  records jsonb := '[]'::jsonb;
  target_dataset text;
  check_title text;
  rule_text text;
  src text;
begin
  perform private.audit_access_v703(t, loc);
  if f is null or z is null or f > z or lim is null or lim < 1 or lim > 200 then
    raise exception 'Invalid drilldown parameters' using errcode='22023';
  end if;

  case
    -- 1. Unbalanced journals
    when check_id = 'accounting_unbalanced_journals' then
      target_dataset := 'journal_entries';
      check_title := 'Unbalanced journal entries';
      rule_text := 'Debits must equal credits for every journal entry.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          j.id::text,
          j.entry_number as reference,
          j.entry_date::text as date,
          'journal_entries' as dataset,
          sum(coalesce(l.debit, 0)) as expected_value,
          sum(coalesce(l.credit, 0)) as actual_value,
          sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0)) as difference,
          format('Journal debits (%s) do not equal credits (%s)', sum(coalesce(l.debit, 0)), sum(coalesce(l.credit, 0))) as description
        from public.journal_entries j
        join public.journal_lines l on l.journal_entry_id = j.id
        where j.tenant_id = t and j.entry_date between f and z
          and private.audit_record_allowed_v704(t, 'journal_entries', to_jsonb(j), loc)
        group by j.id, j.entry_number, j.entry_date
        having abs(sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0))) > 0.005
        order by j.entry_date desc, j.entry_number desc
        limit lim
      ) r;

    -- 2. Orphaned journal lines
    when check_id = 'accounting_orphaned_lines' then
      target_dataset := 'journal_entries';
      check_title := 'Journal lines without valid account';
      rule_text := 'Journal lines must reference an existing active account.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          j.id::text,
          j.entry_number as reference,
          j.entry_date::text as date,
          'journal_entries' as dataset,
          'Valid account' as expected_value,
          coalesce(l.account_id::text, 'NULL') as actual_value,
          null::numeric as difference,
          format('Journal line %s has missing or invalid account ID %s', l.id, coalesce(l.account_id::text, 'NULL')) as description
        from public.journal_lines l
        join public.journal_entries j on j.id = l.journal_entry_id
        where j.tenant_id = t and j.entry_date between f and z
          and private.audit_record_allowed_v704(t, 'journal_entries', to_jsonb(j), loc)
          and (l.account_id is null or not exists (
            select 1 from public.accounting_accounts a where a.id = l.account_id and a.tenant_id = t
          ))
        order by j.entry_date desc
        limit lim
      ) r;

    -- 3. Sales header vs line totals
    when check_id = 'sales_header_vs_lines' then
      target_dataset := 'sales';
      check_title := 'Sales invoice total mismatch';
      rule_text := 'Invoice grand total must equal the sum of line totals + round off + charges.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          s.id::text,
          s.sale_number as reference,
          s.sale_date::text as date,
          'sales' as dataset,
          l.lines_sum as expected_value,
          s.grand_total as actual_value,
          (s.grand_total - l.lines_sum) as difference,
          format('Invoice total (%s) differs from lines sum (%s)', s.grand_total, l.lines_sum) as description
        from public.sales s
        cross join lateral (
          select coalesce(sum(si.line_total), 0) + coalesce(s.round_off, 0) + coalesce(s.additional_charges, 0) as lines_sum
          from public.sale_items si
          where si.sale_id = s.id
        ) l
        where s.tenant_id = t and s.sale_date between f and z and s.status = 'posted'
          and private.audit_record_allowed_v704(t, 'sales', to_jsonb(s), loc)
          and abs(s.grand_total - l.lines_sum) > 0.05
        order by s.sale_date desc, s.sale_number desc
        limit lim
      ) r;

    -- 4. Purchases header vs line totals
    when check_id = 'purchases_header_vs_lines' then
      target_dataset := 'purchases';
      check_title := 'Purchase invoice total mismatch';
      rule_text := 'Purchase grand total must equal the sum of line totals + round off + charges.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          p.id::text,
          p.purchase_number as reference,
          p.purchase_date::text as date,
          'purchases' as dataset,
          l.lines_sum as expected_value,
          p.grand_total as actual_value,
          (p.grand_total - l.lines_sum) as difference,
          format('Purchase total (%s) differs from lines sum (%s)', p.grand_total, l.lines_sum) as description
        from public.purchases p
        cross join lateral (
          select coalesce(sum(pi.line_total), 0) + coalesce(p.round_off, 0) + coalesce(p.additional_charges, 0) as lines_sum
          from public.purchase_items pi
          where pi.purchase_id = p.id
        ) l
        where p.tenant_id = t and p.purchase_date between f and z and p.status = 'posted'
          and private.audit_record_allowed_v704(t, 'purchases', to_jsonb(p), loc)
          and abs(p.grand_total - l.lines_sum) > 0.05
        order by p.purchase_date desc, p.purchase_number desc
        limit lim
      ) r;

    -- 5. Sales tax mismatch
    when check_id = 'tax_sales_tax_mismatch' then
      target_dataset := 'sales';
      check_title := 'Sales tax calculation mismatch';
      rule_text := 'Invoice tax_total must match the sum of individual line tax_amount.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          s.id::text,
          s.sale_number as reference,
          s.sale_date::text as date,
          'sales' as dataset,
          l.lines_tax as expected_value,
          s.tax_total as actual_value,
          (s.tax_total - l.lines_tax) as difference,
          format('Invoice tax (%s) differs from lines tax sum (%s)', s.tax_total, l.lines_tax) as description
        from public.sales s
        cross join lateral (
          select coalesce(sum(si.tax_amount), 0) as lines_tax
          from public.sale_items si
          where si.sale_id = s.id
        ) l
        where s.tenant_id = t and s.sale_date between f and z and s.status = 'posted'
          and private.audit_record_allowed_v704(t, 'sales', to_jsonb(s), loc)
          and abs(s.tax_total - l.lines_tax) > 0.05
        order by s.sale_date desc, s.sale_number desc
        limit lim
      ) r;

    -- 6. Purchases tax mismatch
    when check_id = 'tax_purchases_tax_mismatch' then
      target_dataset := 'purchases';
      check_title := 'Purchase tax calculation mismatch';
      rule_text := 'Purchase tax_total must match the sum of individual line tax_amount.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          p.id::text,
          p.purchase_number as reference,
          p.purchase_date::text as date,
          'purchases' as dataset,
          l.lines_tax as expected_value,
          p.tax_total as actual_value,
          (p.tax_total - l.lines_tax) as difference,
          format('Purchase tax (%s) differs from lines tax sum (%s)', p.tax_total, l.lines_tax) as description
        from public.purchases p
        cross join lateral (
          select coalesce(sum(pi.tax_amount), 0) as lines_tax
          from public.purchase_items pi
          where pi.purchase_id = p.id
        ) l
        where p.tenant_id = t and p.purchase_date between f and z and p.status = 'posted'
          and private.audit_record_allowed_v704(t, 'purchases', to_jsonb(p), loc)
          and abs(p.tax_total - l.lines_tax) > 0.05
        order by p.purchase_date desc, p.purchase_number desc
        limit lim
      ) r;

    -- 7. Stock balances vs movement ledger
    when check_id in ('stock_stock_balances', 'stock_location_stock_balances') then
      target_dataset := 'stock_balances';
      check_title := 'Stock balance vs movement ledger variance';
      rule_text := 'Recorded stock quantity must equal the net sum of stock movement deltas.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        with b as (
          select variant_id, location_id, quantity
          from public.stock_balances x
          where tenant_id = t and private.audit_record_allowed_v704(t, 'stock_balances', to_jsonb(x), loc)
        ),
        m as (
          select variant_id, location_id, sum(quantity_delta) as qty
          from public.stock_movements x
          where tenant_id = t and private.audit_record_allowed_v704(t, 'stock_movements', to_jsonb(x), loc)
          group by variant_id, location_id
        )
        select
          coalesce(b.variant_id, m.variant_id)::text as id,
          coalesce(v.sku, v.name, 'Variant') as reference,
          current_date::text as date,
          'stock_balances' as dataset,
          coalesce(m.qty, 0) as expected_value,
          coalesce(b.quantity, 0) as actual_value,
          (coalesce(b.quantity, 0) - coalesce(m.qty, 0)) as difference,
          format('Stock balance (%s) differs from movement sum (%s)', coalesce(b.quantity, 0), coalesce(m.qty, 0)) as description
        from b
        full join m using(variant_id, location_id)
        left join public.product_variants v on v.id = coalesce(b.variant_id, m.variant_id)
        where abs(coalesce(b.quantity, 0) - coalesce(m.qty, 0)) > 0.0001
        limit lim
      ) r;

    -- 8. Negative stock balances
    when check_id = 'inventory_negative_stock' then
      target_dataset := 'stock_balances';
      check_title := 'Negative stock on hand';
      rule_text := 'Inventory on hand should not fall below zero.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          b.variant_id::text as id,
          coalesce(v.sku, v.name, 'Variant') as reference,
          current_date::text as date,
          'stock_balances' as dataset,
          0.0 as expected_value,
          b.quantity as actual_value,
          b.quantity as difference,
          format('Recorded stock quantity is negative (%s)', b.quantity) as description
        from public.stock_balances b
        left join public.product_variants v on v.id = b.variant_id
        where b.tenant_id = t and b.quantity < -0.0001
          and private.audit_record_allowed_v704(t, 'stock_balances', to_jsonb(b), loc)
        order by b.quantity asc
        limit lim
      ) r;

    -- 9. Orphaned stock movements
    when check_id = 'inventory_orphaned_movements' then
      target_dataset := 'stock_movements';
      check_title := 'Stock movements without valid variant';
      rule_text := 'Every movement must link to a valid variant in catalogue.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          m.id::text,
          coalesce(m.reference_number, m.movement_type, 'Movement') as reference,
          m.occurred_at::date::text as date,
          'stock_movements' as dataset,
          'Existing variant' as expected_value,
          m.variant_id::text as actual_value,
          m.quantity_delta as difference,
          format('Movement references missing variant ID %s', m.variant_id) as description
        from public.stock_movements m
        where m.tenant_id = t
          and private.audit_record_allowed_v704(t, 'stock_movements', to_jsonb(m), loc)
          and not exists (select 1 from public.product_variants v where v.id = m.variant_id and v.tenant_id = t)
        order by m.occurred_at desc
        limit lim
      ) r;

    -- 10. Unmatched bank statement lines
    when check_id = 'bank_unmatched' then
      target_dataset := 'bank_statement_lines_v500';
      check_title := 'Unmatched bank statement lines';
      rule_text := 'Bank statement lines should be reconciled against ERP transaction journals.';
      select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      into records
      from (
        select
          b.id::text,
          coalesce(b.reference, 'Statement line') as reference,
          b.transaction_date::text as date,
          'bank_statement_lines_v500' as dataset,
          'Matched journal' as expected_value,
          coalesce(b.status, 'unmatched') as actual_value,
          b.amount as difference,
          format('Bank transaction of %s has no matching journal entry (%s)', b.amount, coalesce(b.description, '')) as description
        from public.bank_statement_lines_v500 b
        where b.tenant_id = t and b.transaction_date between f and z
          and (b.matched_journal_id is null or b.status <> 'matched')
          and private.audit_record_allowed_v704(t, 'bank_statement_lines_v500', to_jsonb(b), loc)
        order by b.transaction_date desc
        limit lim
      ) r;

    -- 11. Missing journals for posted transactions (posting_*)
    when check_id like 'posting_%' then
      target_dataset := substring(check_id from 9);
      check_title := 'Posted records without linked journals';
      rule_text := 'Posted business transactions must create double-entry journal entries.';

      select v.source into src from (values
        ('sales', 'sale'), ('purchases', 'purchase'), ('expenses', 'expense'),
        ('staff_earnings_v630', 'staff_earning'), ('staff_payments_v630', 'staff_payment'),
        ('purchase_invoices_v484', 'purchase_invoice_v484'), ('customer_receipts', 'customer_receipt'),
        ('supplier_payments_v484', 'supplier_payment')
      ) v(dataset, source) where v.dataset = target_dataset;

      if src is not null then
        execute format(
          'select coalesce(jsonb_agg(row_to_json(r)), ''[]''::jsonb) from (
             select d.id::text,
                    coalesce(d.id::text, ''Transaction'') as reference,
                    current_date::text as date,
                    $2 as dataset,
                    ''Linked journal entry'' as expected_value,
                    ''No journal entry'' as actual_value,
                    0::numeric as difference,
                    ''Transaction is posted but has no corresponding journal entry in journal_entries'' as description
             from public.%I d
             where d.tenant_id = $1
               and private.audit_record_allowed_v704($1, $2, to_jsonb(d), $4)
               and not exists (
                 select 1 from public.journal_entries j
                 where j.tenant_id = $1 and j.source_id = d.id and j.source_type = $5
                   and j.status in (''posted'', ''reversed'')
               )
             limit $3
           ) r',
          target_dataset
        ) into records using t, target_dataset, lim, loc, src;
      end if;

    -- Default fallback
    else
      target_dataset := 'audit';
      check_title := check_id;
      rule_text := 'Integrity audit check rule.';
      records := '[]'::jsonb;
  end case;

  return jsonb_build_object(
    'check_id', check_id,
    'dataset', coalesce(target_dataset, 'audit'),
    'title', coalesce(check_title, check_id),
    'rule', coalesce(rule_text, ''),
    'total_records', jsonb_array_length(records),
    'records', records
  );
end $$;

-- Public wrappers
create or replace function public.audit_checks_v704(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_category text default null
) returns jsonb
language sql stable security invoker set search_path='' as $$
  select private.audit_checks_v704(p_tenant_id, p_from, p_to, p_location_id, p_category);
$$;

revoke all on function public.audit_checks_v704(uuid, date, date, uuid, text) from public, anon;
grant execute on function public.audit_checks_v704(uuid, date, date, uuid, text) to authenticated;

create or replace function public.audit_check_records_v704(
  p_tenant_id uuid,
  p_check_id text,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_limit integer default 50
) returns jsonb
language sql stable security invoker set search_path='' as $$
  select private.audit_check_records_v704(p_tenant_id, p_check_id, p_from, p_to, p_location_id, p_limit);
$$;

revoke all on function public.audit_check_records_v704(uuid, text, date, date, uuid, integer) from public, anon;
grant execute on function public.audit_check_records_v704(uuid, text, date, date, uuid, integer) to authenticated;
