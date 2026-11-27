-- ============================================================================
-- THQ ERP Migration #719 / v8.3.13: Audit Center RPC Disambiguation & Integrity Fix
--
-- Root Cause:
-- 1. private.audit_workspace_v703 had two overloads:
--    a) (uuid, text, date, date, uuid, text, text, text, text, boolean, integer, integer) [12 params]
--    b) (uuid, text, date, date, uuid, text, text, text, text, boolean, integer, integer, text DEFAULT '') [13 params with default]
--    Because the 13th parameter had a default, callers passing 12 arguments with string literals ('accounts', '')
--    caused PostgreSQL error 42725 (ambiguous_function).
-- 2. In private.audit_workspace_v703, the accounts view referenced non-existent column a.type instead of a.account_type.
-- 3. In private.audit_checks_v704, Check #3 passed untyped literals to private.audit_workspace_v703.
--
-- Solution:
-- 1. Redefine the 13-parameter private.audit_workspace_v703 without default on source_type, and correct a.account_type.
-- 2. Redefine the 12-parameter private.audit_workspace_v703 to unambiguously delegate to the 13-parameter function with ''::text.
-- 3. Update private.audit_checks_v704 with explicit type casts.
-- 4. Preserve all security policies, search_path='', and tenant/location authorization.
-- ============================================================================

-- 1. Drop existing overloaded signatures to avoid parameter name/type conflicts
drop function if exists private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text);
drop function if exists private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer);

-- 2. Primary 13-parameter private.audit_workspace_v703 (exact typed, no trailing default)
create or replace function private.audit_workspace_v703(
  t uuid,
  k text,
  f date,
  z date,
  loc uuid,
  q text,
  p_severity text,
  p_lifecycle text,
  sort_key text,
  descending boolean,
  page_offset integer,
  page_limit integer,
  source_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  tz text;
  lo timestamptz;
  hi timestamptz;
  raw jsonb;
  summary jsonb;
  totals jsonb;
  query_clean text;
begin
  perform private.audit_access_v703(t, loc);
  if f is null or z is null or page_offset is null or page_limit is null or f > z or page_offset < 0 or page_limit < 1 or page_limit > 200 then
    raise exception 'Invalid audit query' using errcode='22023';
  end if;
  if k not in ('findings', 'activity', 'accounts', 'journals') then
    raise exception 'Unknown audit view' using errcode='22023';
  end if;

  tz := coalesce((select timezone from public.tenant_settings where tenant_id = t), 'UTC');
  lo := f::timestamp at time zone tz;
  hi := (z + 1)::timestamp at time zone tz;
  query_clean := lower(trim(coalesce(q, '')));

  select jsonb_build_object(
    'high_risk', count(*) filter (where a.severity in ('high_risk', 'critical', 'high') and a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'needs_review', count(*) filter (where a.severity in ('needs_review', 'medium') and a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'open_attention', count(*) filter (where a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'unassigned', count(*) filter (where a.assigned_to is null and a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'overdue', count(*) filter (where a.due_date < current_date and a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'total_findings', count(*)
  ) into summary
  from public.audit_findings_v600 a
  where a.tenant_id = t and a.detected_at >= lo and a.detected_at < hi
    and private.reports_scope_v631(t, a.location_id, loc, 'view');

  if k = 'findings' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id,
      'finding_id', a.id,
      'date', a.detected_at,
      'reference', coalesce(a.entity_reference, e.entity_reference, 'N/A'),
      'title', a.title,
      'description', a.description,
      'severity', a.severity,
      'status', a.status,
      'priority', a.priority,
      'financial_exposure', a.financial_exposure,
      'risk_score', a.risk_score,
      'entity_type', a.entity_type,
      'entity_id', a.entity_id,
      'root_entity_type', e.root_entity_type,
      'root_entity_id', e.root_entity_id,
      'actor', e.actor_name,
      'location', b.name,
      'device', e.device_name,
      'rule', a.rule_code,
      'assigned_to', a.assigned_to,
      'assigned_name', coalesce(u.username, u.auth_email, 'Unassigned'),
      'due_date', a.due_date,
      'is_overdue', (a.due_date is not null and a.due_date < current_date and a.status not in ('resolved', 'dismissed')),
      'duplicate_group_id', a.duplicate_group_id,
      'is_duplicate', a.is_duplicate
    )), '[]'::jsonb) into raw
    from (
      select a.*
      from public.audit_findings_v600 a
      where a.tenant_id = t and a.detected_at >= lo and a.detected_at < hi
        and private.reports_scope_v631(t, a.location_id, loc, 'view')
        and (coalesce(p_severity, '') = '' or a.severity = p_severity or (p_severity = 'high_risk' and a.severity in ('high_risk', 'critical', 'high')))
        and (
          coalesce(p_lifecycle, '') = ''
          or (p_lifecycle = 'active' and a.status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated'))
          or (p_lifecycle = 'unassigned' and a.assigned_to is null and a.status not in ('resolved', 'dismissed'))
          or (p_lifecycle = 'overdue' and a.due_date < current_date and a.status not in ('resolved', 'dismissed'))
          or a.status = p_lifecycle
        )
        and (
          query_clean = ''
          or lower(coalesce(a.title, '')) like '%' || query_clean || '%'
          or lower(coalesce(a.entity_reference, '')) like '%' || query_clean || '%'
          or lower(coalesce(a.rule_code, '')) like '%' || query_clean || '%'
        )
      order by
        case when sort_key = 'priority' and descending then case a.priority when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end end desc,
        case when sort_key = 'priority' and not descending then case a.priority when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end end asc,
        case when sort_key = 'financial_exposure' and descending then a.financial_exposure end desc,
        case when sort_key = 'financial_exposure' and not descending then a.financial_exposure end asc,
        case when sort_key = 'due_date' and descending then a.due_date end desc nulls last,
        case when sort_key = 'due_date' and not descending then a.due_date end asc nulls last,
        case when sort_key = 'date' and descending then a.detected_at end desc,
        case when sort_key = 'date' and not descending then a.detected_at end asc,
        a.id desc
      offset page_offset limit page_limit
    ) a
    left join public.transaction_story_events_v600 e on e.tenant_id = t and e.id = a.source_event_id
    left join public.business_locations b on b.tenant_id = t and b.id = a.location_id
    left join public.user_login_names u on u.user_id = a.assigned_to and u.tenant_id = t;

    return jsonb_build_object(
      'rows', raw,
      'total_rows', coalesce((summary->>'total_findings')::int, 0),
      'summary', summary,
      'snapshot_token', md5(format('%s:%s:%s:%s:%s', t, f, z, summary->>'total_findings', lo))
    );

  elsif k = 'activity' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'date', e.event_time, 'reference', e.entity_reference,
      'title', initcap(replace(e.action, '_', ' ')),
      'entity_type', e.entity_type, 'entity_id', e.entity_id,
      'root_entity_type', e.root_entity_type, 'root_entity_id', e.root_entity_id,
      'actor', e.actor_name, 'location', b.name, 'device', e.device_name, 'reason', e.reason,
      'evidence_quality', case when coalesce((e.metadata->>'historical_reconstruction')::boolean, false) then 'Historical baseline' else 'Recorded event' end
    )), '[]'::jsonb) into raw
    from (
      select e.*
      from public.transaction_story_events_v600 e
      where e.tenant_id = t and e.event_time >= lo and e.event_time < hi
        and private.reports_scope_v631(t, e.location_id, loc, 'view')
        and (query_clean = '' or lower(coalesce(e.entity_reference, '')) like '%' || query_clean || '%' or lower(coalesce(e.action, '')) like '%' || query_clean || '%')
      order by e.event_time desc
      offset page_offset limit page_limit
    ) e
    left join public.business_locations b on b.tenant_id = t and b.id = e.location_id;

    return jsonb_build_object(
      'rows', raw,
      'total_rows', coalesce((select count(*) from public.transaction_story_events_v600 e where e.tenant_id = t and e.event_time >= lo and e.event_time < hi and private.reports_scope_v631(t, e.location_id, loc, 'view')), 0),
      'summary', summary,
      'snapshot_token', md5(format('act:%s:%s:%s', t, f, z))
    );

  elsif k = 'accounts' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', x.account_id, 'account_id', x.account_id, 'date', z, 'reference', x.account_code,
      'account_code', x.account_code, 'account_name', x.account_name, 'account_type', x.account_type,
      'debit', x.period_debit, 'credit', x.period_credit, 'balance', x.period_balance
    )), '[]'::jsonb) into raw
    from (
      select a.id as account_id, a.code as account_code, a.name as account_name, a.account_type as account_type,
             coalesce(sum(l.debit), 0) as period_debit,
             coalesce(sum(l.credit), 0) as period_credit,
             coalesce(sum(l.debit), 0) - coalesce(sum(l.credit), 0) as period_balance
      from public.accounting_accounts a
      left join public.journal_lines l on l.account_id = a.id
      left join public.journal_entries j on j.id = l.journal_entry_id and j.tenant_id = t and j.entry_date between f and z and j.status in ('posted', 'reversed')
      where a.tenant_id = t
        and (query_clean = '' or lower(coalesce(a.name, '')) like '%' || query_clean || '%' or lower(coalesce(a.code, '')) like '%' || query_clean || '%')
      group by a.id, a.code, a.name, a.account_type
      order by a.code asc
      offset page_offset limit page_limit
    ) x;

    select jsonb_build_object(
      'total_debit', coalesce(sum(l.debit), 0),
      'total_credit', coalesce(sum(l.credit), 0),
      'difference', coalesce(sum(l.debit), 0) - coalesce(sum(l.credit), 0)
    ) into totals
    from public.journal_lines l
    join public.journal_entries j on j.id = l.journal_entry_id and j.tenant_id = t and j.entry_date between f and z and j.status in ('posted', 'reversed');

    return jsonb_build_object(
      'rows', raw,
      'total_rows', (select count(*) from public.accounting_accounts a where a.tenant_id = t),
      'account_totals', totals,
      'snapshot_token', md5(format('acc:%s:%s:%s', t, f, z))
    );

  elsif k = 'journals' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', j.id, 'journal_id', j.id, 'date', j.entry_date, 'reference', j.entry_number,
      'party', j.party_name, 'amount', j.total_amount,
      'balance_status', case when abs(j.debit_sum - j.credit_sum) <= 0.005 then 'Balanced' else 'Unbalanced' end,
      'status', j.status, 'source_type', j.source_type, 'source_id', j.source_id
    )), '[]'::jsonb) into raw
    from (
      select j.id, j.entry_date, j.entry_number, j.status, j.source_type, j.source_id,
             (select l.party_type from public.journal_lines l where l.journal_entry_id = j.id limit 1) as party_name,
             coalesce(sum(l.debit), 0) as total_amount,
             coalesce(sum(l.debit), 0) as debit_sum,
             coalesce(sum(l.credit), 0) as credit_sum
      from public.journal_entries j
      left join public.journal_lines l on l.journal_entry_id = j.id
      where j.tenant_id = t and j.entry_date between f and z
        and (source_type is null or trim(source_type) = '' or j.source_type = source_type)
        and (query_clean = '' or lower(coalesce(j.entry_number, '')) like '%' || query_clean || '%')
      group by j.id, j.entry_date, j.entry_number, j.status, j.source_type, j.source_id
      order by j.entry_date desc, j.entry_number desc
      offset page_offset limit page_limit
    ) j;

    return jsonb_build_object(
      'rows', raw,
      'total_rows', (select count(*) from public.journal_entries j where j.tenant_id = t and j.entry_date between f and z and (source_type is null or trim(source_type) = '' or j.source_type = source_type)),
      'snapshot_token', md5(format('jrn:%s:%s:%s', t, f, z))
    );
  end if;

  return jsonb_build_object('rows', '[]'::jsonb, 'total_rows', 0);
end;
$$;

revoke all on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text) from public,anon;
grant execute on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text) to authenticated;

-- 3. Backward-compatible 12-parameter private.audit_workspace_v703 delegating unambiguously
create or replace function private.audit_workspace_v703(
  t uuid,
  k text,
  f date,
  z date,
  loc uuid,
  q text,
  p_severity text,
  p_lifecycle text,
  sort_key text,
  descending boolean,
  page_offset integer,
  page_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  return private.audit_workspace_v703(
    t,
    k,
    f,
    z,
    loc,
    q,
    p_severity,
    p_lifecycle,
    sort_key,
    descending,
    page_offset,
    page_limit,
    ''::text
  );
end;
$$;

revoke all on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) from public,anon;
grant execute on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) to authenticated;

-- 4. Update private.audit_checks_v704 with explicit type casts at line 108
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
  total_cross_tenant_leaks integer:=0;
  total_fk_checked integer:=0;
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
    -- Excludes drafts; catches posted and reversed entries with debits != credits or zero lines.
    select count(*), coalesce(sum(abs(diff)), 0)
    into n, amt
    from (
      select j.id, sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0)) as diff
      from public.journal_entries j
      left join public.journal_lines l on l.journal_entry_id = j.id
      where j.tenant_id = t and j.entry_date between f and z
        and j.status in ('posted', 'reversed')
        and private.audit_record_allowed_v704(t, 'journal_entries', to_jsonb(j), loc)
      group by j.id
      having abs(sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0))) > 0.005
         or count(l.id) = 0
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
      'basis', 'Double-entry rule: debits must equal credits for every posted/reversed journal entry (tolerance: 0.005).',
      'explanation', 'Every transaction journal must have zero net difference between total debits and total credits, and cannot be posted with zero lines.'
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
    accounts := private.audit_workspace_v703(t, 'accounts'::text, f, z, loc, ''::text, ''::text, ''::text, 'account_name'::text, false, 0, 200, ''::text);
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
      'explanation', 'Sum of all debit account balances must match sum of credit account balances across the chart of accounts.'
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
      'explanation', 'A negative cash closing balance usually indicates missing cash receipts, unrecorded initial float, or timing differences.'
    ));

    -- 5-12. Posted Records Without Linked Journals
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
        'select count(*) from public.%I d where d.tenant_id=$1 and d.%I between $2 and $3 and (%s) and private.audit_record_allowed_v704($1,$4,to_jsonb(d),$5) and not exists(select 1 from public.journal_entries j where j.tenant_id=$1 and (j.source_id=d.id and j.source_type=$6) and j.status in(''posted'',''reversed''))',
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
    -- 1. Stock balances vs movement ledger (Stock balances and Location stock balances)
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
      'basis', 'Every sale customer_id must exist in customers table for the tenant.',
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
      'basis', 'Every purchase supplier_id must exist in suppliers table for the tenant.',
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
      'basis', 'Receipt customer_id must exist in customers table for the tenant.',
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
      'basis', 'Supplier payment supplier_id must exist in suppliers table for the tenant.',
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
      'explanation', 'Line-by-line tax computations must match invoice tax summaries to ensure internal sales register consistency before statutory GST returns are compiled. This evaluates internal ERP records, not actual portal filings.'
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
      'explanation', 'Purchase tax summaries must accurately reflect line item GST to substantiate input tax credit (ITC) claims in internal registers.'
    ));
  end if;

  -- =========================================================================
  -- F. OPERATIONAL & SYSTEM INTEGRITY
  -- =========================================================================
  if run_ops then
    -- 1. Story history cryptographic verification
    -- Period-scoped: only verifies story events created within the audit window.
    for root in select distinct e.correlation_id, e.root_entity_type, e.root_entity_id
                from public.transaction_story_events_v600 e
                where e.tenant_id = t and e.event_time::date between f and z
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
      'status', case
        when failed > 0 then 'Issue detected'
        when verified = 0 and partial = 0 then 'Insufficient data'
        else 'Passed'
      end,
      'severity', 'critical',
      'verified_chains', verified,
      'partial_scope_chains', partial,
      'dataset', 'transaction_story_events_v600',
      'is_actionable', true,
      'basis', 'Cryptographic SHA-256 chain verification of recorded transaction event sequences in period.',
      'explanation', case
        when verified = 0 and partial = 0 and failed = 0 then 'No transaction story events recorded in the selected period to evaluate.'
        when failed > 0 then format('%s audit story chains failed cryptographic hash integrity verification.', failed)
        else 'Validates that recorded event logs have not suffered silent tampering, reordering, or metadata truncation.'
      end
    ));

    -- 2. Cross-tenant FK link audit
    -- Systematically scans relational foreign keys across registered catalog tables with tenant columns.
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
      total_fk_checked := total_fk_checked + 1;
      execute format(
        'select count(*) from public.%I c join public.%I p on p.id = c.%I where c.tenant_id = $1 and p.tenant_id <> $1 and private.audit_record_allowed_v704($1, $2, to_jsonb(c), $3)',
        x.child, x.parent, x.col
      ) into n using t, x.child, loc;
      if n > 0 then
        total_cross_tenant_leaks := total_cross_tenant_leaks + n;
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

    -- Authoritative baseline multi-tenant isolation check (always emitted)
    rows := rows || jsonb_build_array(jsonb_build_object(
      'id', 'ops_cross_tenant_references',
      'category', 'operational',
      'reference', 'Tenant boundary',
      'title', 'Foreign key references crossing tenant boundary',
      'count', total_cross_tenant_leaks,
      'status', case when total_cross_tenant_leaks > 0 then 'Issue detected' else 'Passed' end,
      'severity', 'critical',
      'dataset', 'tenants',
      'is_actionable', true,
      'basis', format('Verified %s relational foreign key constraints across catalog tables with tenant columns.', total_fk_checked),
      'explanation', case
        when total_cross_tenant_leaks = 0 then format('No cross-tenant foreign key violations detected across %s scanned relational table relationships.', total_fk_checked)
        else format('%s cross-tenant references detected across database tables. Strict tenant isolation boundary compromised.', total_cross_tenant_leaks)
      end
    ));
  end if;

  return jsonb_build_object(
    'rows', rows,
    'total_rows', jsonb_array_length(rows),
    'generated_at', statement_timestamp(),
    'basis', 'Authoritative ERP integrity engine. Evaluates mathematical, double-entry, subsidiary ledger, inventory movement, tax and cryptographic consistency.'
  );
end $$;

revoke all on function private.audit_checks_v704(uuid,date,date,uuid,text) from public,anon;
grant execute on function private.audit_checks_v704(uuid,date,date,uuid,text) to authenticated;

-- 5. Backward-compatible 4-parameter private.audit_checks_v704 delegating unambiguously
create or replace function private.audit_checks_v704(t uuid, f date, z date, loc uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select private.audit_checks_v704(t, f, z, loc, null::text);
$$;

revoke all on function private.audit_checks_v704(uuid,date,date,uuid) from public,anon;
grant execute on function private.audit_checks_v704(uuid,date,date,uuid) to authenticated;

-- 6. Ensure public wrappers delegate cleanly
create or replace function public.audit_checks_v704(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_category text default null
)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
  select private.audit_checks_v704(p_tenant_id, p_from, p_to, p_location_id, p_category);
$$;

revoke all on function public.audit_checks_v704(uuid,date,date,uuid,text) from public,anon;
grant execute on function public.audit_checks_v704(uuid,date,date,uuid,text) to authenticated;

create or replace function public.audit_workspace_v703(
  p_tenant_id uuid,
  p_view text,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_query text default '',
  p_severity text default '',
  p_status text default '',
  p_sort_key text default 'date',
  p_sort_desc boolean default true,
  p_offset integer default 0,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
  select private.audit_workspace_v703(
    p_tenant_id,
    p_view,
    p_from,
    p_to,
    p_location_id,
    p_query,
    p_severity,
    p_status,
    p_sort_key,
    p_sort_desc,
    p_offset,
    p_limit,
    ''::text
  );
$$;

revoke all on function public.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) from public,anon;
grant execute on function public.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) to authenticated;

create or replace function public.audit_workspace_page_v703(
  p_tenant_id uuid,
  p_view text,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_query text default '',
  p_severity text default '',
  p_status text default '',
  p_sort_key text default 'date',
  p_sort_desc boolean default true,
  p_offset integer default 0,
  p_limit integer default 50,
  p_source_type text default ''
)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
  select private.audit_workspace_v703(
    p_tenant_id,
    p_view,
    p_from,
    p_to,
    p_location_id,
    p_query,
    p_severity,
    p_status,
    p_sort_key,
    p_sort_desc,
    p_offset,
    p_limit,
    p_source_type
  );
$$;

revoke all on function public.audit_workspace_page_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text) from public,anon;
grant execute on function public.audit_workspace_page_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text) to authenticated;

-- ----------------------------------------------------------------------------
-- Register Schema Release #719 (v8.3.13)
-- ----------------------------------------------------------------------------
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  719,
  'v8.3.13',
  'audit_integrity_eval_ambiguity_fix_v8313',
  'Audit Center integrity evaluation ambiguity fix: resolve 12/13 parameter overload ambiguity on private.audit_workspace_v703, correct accounting_accounts column reference, and wrap with explicit parameter typing in private.audit_checks_v704.'
)
on conflict do nothing;

notify pgrst, 'reload schema';
