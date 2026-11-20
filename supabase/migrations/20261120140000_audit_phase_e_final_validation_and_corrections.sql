-- =============================================================================
-- THQ ERP: AUDIT CENTER PHASE E - FINAL VALIDATION & TARGETED CORRECTIONS
-- Migration: 20261120140000_audit_phase_e_final_validation_and_corrections.sql
-- 
-- 1. Corrects note_type check constraint on public.audit_finding_notes_v704 to include
--    all valid investigation note types supported by the UI:
--    ('investigation', 'observation', 'evidence_link', 'resolution', 'reassignment',
--     'escalation', 'evidence_request', 'client_explanation', 'internal_note', 'auditor_conclusion')
-- 2. Hardens public.audit_risk_scan_period_v704 for 100% idempotent scans:
--    - Replaces volatile gen_random_uuid() fallback with deterministic entity-derived UUID
--      so that repeated scans of the same period do not generate duplicate findings.
--    - Adds proactive existence check before insertion.
-- 3. Corrects column references for purchases and sales headers:
--    - public.purchases and public.sales do not possess direct location_id columns;
--      safely passes null::uuid as location_id to prevent column not found errors.
-- 4. Adds Rule E: IRREGULAR_POSTING_DATE detection in audit_risk_scan_period_v704
--    for backdated (>60 days prior to creation) or future-dated (>1 day in future) records.
-- 5. Extends RPC return payload to include 'detected_count' and 'scanned_period' to
--    satisfy client UI notifications without breaking existing consumers.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. UPDATE NOTE_TYPE CHECK CONSTRAINT ON public.audit_finding_notes_v704
-- -----------------------------------------------------------------------------
alter table public.audit_finding_notes_v704 drop constraint if exists audit_finding_notes_v704_note_type_check;
alter table public.audit_finding_notes_v704 add constraint audit_finding_notes_v704_note_type_check
  check (note_type in (
    'investigation',
    'observation',
    'evidence_link',
    'resolution',
    'reassignment',
    'escalation',
    'evidence_request',
    'client_explanation',
    'internal_note',
    'auditor_conclusion'
  ));

-- -----------------------------------------------------------------------------
-- 2. HARDEN AND ENHANCE public.audit_risk_scan_period_v704
-- -----------------------------------------------------------------------------
create or replace function public.audit_risk_scan_period_v704(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_event_id uuid;
  v_finding_id uuid;
  v_group_id text;
  v_is_dup boolean;
  v_exposure numeric;
  v_priority text;
  v_evidence jsonb;
  v_inserted integer := 0;
  v_skipped integer := 0;
  v_actor_id uuid := auth.uid();
  v_actor_name text := 'System Risk Scanner';
begin
  perform private.audit_access_v703(p_tenant_id, p_location_id);
  if not private.has_permission(p_tenant_id, 'audit_center.review') then
    raise exception 'Permission denied (audit_center.review required)' using errcode='42501';
  end if;

  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'Invalid scan period date range' using errcode='22023';
  end if;

  select coalesce(username, auth_email, 'System Risk Scanner') into v_actor_name
  from public.user_login_names where user_id = v_actor_id and tenant_id = p_tenant_id limit 1;

  -- A. DETECT DUPLICATE PURCHASE INVOICES (Same supplier invoice ref across multiple purchases)
  for r in
    select p.id, p.purchase_number, p.supplier_invoice_number, p.supplier_id, p.grand_total,
           p.purchase_date, p.created_at, null::uuid as location_id, s.name as supplier_name,
           coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF') as inv_ref,
           count(*) over (partition by p.supplier_id, lower(trim(coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF')))) as ref_count,
           row_number() over (partition by p.supplier_id, lower(trim(coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF'))) order by p.purchase_date asc, p.created_at asc) as row_seq
    from public.purchases p
    left join public.suppliers s on s.id = p.supplier_id
    where p.tenant_id = p_tenant_id
      and p.purchase_date between p_from and p_to
      and p.supplier_id is not null
      and length(trim(coalesce(p.supplier_invoice_number, p.purchase_number, ''))) > 2
      and private.audit_record_allowed_v704(p_tenant_id, 'purchases', to_jsonb(p), p_location_id)
  loop
    if r.ref_count > 1 then
      v_group_id := 'dup_inv_' || md5(lower(trim(r.inv_ref)));
      v_is_dup := (r.row_seq > 1);
      v_exposure := coalesce(r.grand_total, 0.0);
      v_priority := case when v_exposure >= 50000 then 'critical' when v_exposure >= 10000 then 'high' else 'medium' end;

      select id into v_event_id
      from public.transaction_story_events_v600 e
      where e.tenant_id = p_tenant_id and e.entity_type = 'purchase' and e.entity_id = r.id
      order by e.event_sequence asc limit 1;

      if v_event_id is null then
        v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, 'purchase', r.id))::uuid;
      end if;

      if exists (
        select 1 from public.audit_findings_v600
        where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'DUPLICATE_PURCHASE_REFERENCE'
      ) then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_evidence := jsonb_build_object(
        'what_happened', format('Purchase invoice reference %s appears %s times for supplier %s.', r.inv_ref, r.ref_count, coalesce(r.supplier_name, 'Unknown')),
        'why_detected', 'Duplicate invoice reference detected across multiple purchase headers for the same vendor.',
        'rule_name', 'DUPLICATE_PURCHASE_REFERENCE',
        'financial_impact', v_exposure,
        'is_confirmed', true,
        'investigation_steps', 'Cross-check physical vendor bill, delivery note, and supplier statement to verify whether this is an accidental double-entry or duplicate billing.',
        'supplier_id', r.supplier_id,
        'supplier_name', r.supplier_name,
        'reference_number', r.inv_ref,
        'total_occurrences', r.ref_count
      );

      insert into public.audit_findings_v600 (
        id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
        risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
        detected_at, evidence, status, priority, financial_exposure, duplicate_group_id, is_duplicate
      ) values (
        gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'high_risk',
        'DUPLICATE_PURCHASE_REFERENCE',
        'Duplicate purchase invoice reference',
        format('Supplier bill %s recorded %s times with total value %s', r.inv_ref, r.ref_count, v_exposure),
        case when v_priority = 'critical' then 94 else 82 end,
        'purchase', r.id, r.purchase_number, r.location_id, v_actor_id,
        now(), v_evidence, 'open', v_priority, v_exposure, v_group_id, v_is_dup
      )
      on conflict (tenant_id, source_event_id, rule_code) do nothing
      returning id into v_finding_id;

      if v_finding_id is not null then
        v_inserted := v_inserted + 1;
        insert into public.audit_finding_history_v704 (
          tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
        ) values (
          p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
          v_actor_name, jsonb_build_object('rule_code', 'DUPLICATE_PURCHASE_REFERENCE', 'priority', v_priority, 'exposure', v_exposure),
          'Detected by Advanced Risk Intelligence scan'
        );
      else
        v_skipped := v_skipped + 1;
      end if;
    end if;
  end loop;

  -- B. DETECT DUPLICATE PAYMENT REFERENCES (Reused bank UTR, check, or payment reference across receipts)
  for r in
    select cr.id, cr.receipt_number, cr.payment_method, cr.amount, cr.receipt_date, cr.location_id,
           nullif(trim(cr.reference_number), '') as pay_ref,
           count(*) over (partition by lower(trim(nullif(trim(cr.reference_number), '')))) as ref_count,
           row_number() over (partition by lower(trim(nullif(trim(cr.reference_number), ''))) order by cr.receipt_date asc, cr.created_at asc) as row_seq
    from public.customer_receipts cr
    where cr.tenant_id = p_tenant_id
      and cr.receipt_date between p_from and p_to
      and length(trim(coalesce(cr.reference_number, ''))) > 3
      and private.audit_record_allowed_v704(p_tenant_id, 'customer_receipts', to_jsonb(cr), p_location_id)
  loop
    if r.ref_count > 1 then
      v_group_id := 'dup_payref_' || md5(lower(trim(r.pay_ref)));
      v_is_dup := (r.row_seq > 1);
      v_exposure := coalesce(r.amount, 0.0);
      v_priority := case when v_exposure >= 25000 then 'critical' when v_exposure >= 5000 then 'high' else 'medium' end;

      select id into v_event_id
      from public.transaction_story_events_v600 e
      where e.tenant_id = p_tenant_id and e.entity_type = 'customer_receipt' and e.entity_id = r.id
      order by e.event_sequence asc limit 1;

      if v_event_id is null then
        v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, 'customer_receipt', r.id))::uuid;
      end if;

      if exists (
        select 1 from public.audit_findings_v600
        where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'DUPLICATE_PAYMENT_REFERENCE'
      ) then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_evidence := jsonb_build_object(
        'what_happened', format('Payment transaction reference %s was used across %s different receipts.', r.pay_ref, r.ref_count),
        'why_detected', 'Payment reference collision: same bank UTR, check or transaction ID submitted multiple times.',
        'rule_name', 'DUPLICATE_PAYMENT_REFERENCE',
        'financial_impact', v_exposure,
        'is_confirmed', true,
        'investigation_steps', 'Log in to banking portal to verify if bank credit was received multiple times or if a single deposit reference was erroneously applied to several receipts.',
        'reference_number', r.pay_ref,
        'payment_method', r.payment_method,
        'total_occurrences', r.ref_count
      );

      insert into public.audit_findings_v600 (
        id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
        risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
        detected_at, evidence, status, priority, financial_exposure, duplicate_group_id, is_duplicate
      ) values (
        gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'high_risk',
        'DUPLICATE_PAYMENT_REFERENCE',
        'Duplicate payment reference across receipts',
        format('Payment reference %s submitted across %s receipts with value %s', r.pay_ref, r.ref_count, v_exposure),
        case when v_priority = 'critical' then 95 else 85 end,
        'customer_receipt', r.id, r.receipt_number, r.location_id, v_actor_id,
        now(), v_evidence, 'open', v_priority, v_exposure, v_group_id, v_is_dup
      )
      on conflict (tenant_id, source_event_id, rule_code) do nothing
      returning id into v_finding_id;

      if v_finding_id is not null then
        v_inserted := v_inserted + 1;
        insert into public.audit_finding_history_v704 (
          tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
        ) values (
          p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
          v_actor_name, jsonb_build_object('rule_code', 'DUPLICATE_PAYMENT_REFERENCE', 'priority', v_priority, 'exposure', v_exposure),
          'Detected by Advanced Risk Intelligence scan'
        );
      else
        v_skipped := v_skipped + 1;
      end if;
    end if;
  end loop;

  -- C. DETECT RAPID RETURNS (Sales return logged within 15 minutes of sale)
  for r in
    select sr.id, sr.return_number, sr.sale_id, s.sale_number, sr.grand_total as return_total,
           sr.created_at as return_time, s.created_at as sale_time, sr.location_id,
           extract(epoch from (sr.created_at - s.created_at)) / 60.0 as minutes_diff
    from public.sales_returns sr
    join public.sales s on s.id = sr.sale_id and s.tenant_id = p_tenant_id
    where sr.tenant_id = p_tenant_id
      and sr.return_date between p_from and p_to
      and sr.created_at >= s.created_at
      and (sr.created_at - s.created_at) < interval '15 minutes'
      and private.audit_record_allowed_v704(p_tenant_id, 'sales_returns', to_jsonb(sr), p_location_id)
  loop
    v_exposure := coalesce(r.return_total, 0.0);
    v_priority := case when v_exposure >= 20000 then 'critical' when v_exposure >= 5000 then 'high' else 'medium' end;

    select id into v_event_id
    from public.transaction_story_events_v600 e
    where e.tenant_id = p_tenant_id and e.entity_type = 'sales_return' and e.entity_id = r.id
    order by e.event_sequence asc limit 1;

    if v_event_id is null then
      v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, 'sales_return', r.id))::uuid;
    end if;

    if exists (
      select 1 from public.audit_findings_v600
      where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'RAPID_RETURN_AFTER_SALE'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_evidence := jsonb_build_object(
      'what_happened', format('Sale %s was returned (%s) just %s minutes after creation.', r.sale_number, r.return_number, round(r.minutes_diff::numeric, 1)),
      'why_detected', 'Rapid turnaround return: transaction returned almost immediately after billing.',
      'rule_name', 'RAPID_RETURN_AFTER_SALE',
      'financial_impact', v_exposure,
      'is_confirmed', false,
      'investigation_steps', 'Inspect return reason, original payment mode (cash vs card), customer presence, and physical restocking to verify return validity.',
      'sale_number', r.sale_number,
      'minutes_difference', round(r.minutes_diff::numeric, 1)
    );

    insert into public.audit_findings_v600 (
      id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
      risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
      detected_at, evidence, status, priority, financial_exposure
    ) values (
      gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'needs_review',
      'RAPID_RETURN_AFTER_SALE',
      'Rapid sale cancellation or return',
      format('Return %s processed within %s minutes of sale %s', r.return_number, round(r.minutes_diff::numeric, 1), r.sale_number),
      70, 'sales_return', r.id, r.return_number, r.location_id, v_actor_id,
      now(), v_evidence, 'open', v_priority, v_exposure
    )
    on conflict (tenant_id, source_event_id, rule_code) do nothing
    returning id into v_finding_id;

    if v_finding_id is not null then
      v_inserted := v_inserted + 1;
      insert into public.audit_finding_history_v704 (
        tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
      ) values (
        p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
        v_actor_name, jsonb_build_object('rule_code', 'RAPID_RETURN_AFTER_SALE', 'priority', v_priority, 'exposure', v_exposure),
        'Detected by Advanced Risk Intelligence scan'
      );
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  -- D. BRIDGE PHASE B INTEGRITY DISCREPANCIES (Unbalanced journals into actionable findings)
  for r in
    select j.id, j.entry_number, j.entry_date, j.location_id,
           abs(sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0))) as diff,
           sum(coalesce(l.debit, 0)) as total_debit,
           sum(coalesce(l.credit, 0)) as total_credit,
           count(l.id) as line_count
    from public.journal_entries j
    left join public.journal_lines l on l.journal_entry_id = j.id
    where j.tenant_id = p_tenant_id and j.entry_date between p_from and p_to
      and j.status in ('posted', 'reversed')
      and private.audit_record_allowed_v704(p_tenant_id, 'journal_entries', to_jsonb(j), p_location_id)
    group by j.id, j.entry_number, j.entry_date, j.location_id
    having abs(sum(coalesce(l.debit, 0)) - sum(coalesce(l.credit, 0))) > 0.005 or count(l.id) = 0
  loop
    v_exposure := coalesce(r.diff, r.total_debit, 0.0);
    v_priority := 'critical';

    select id into v_event_id
    from public.transaction_story_events_v600 e
    where e.tenant_id = p_tenant_id and e.entity_type = 'journal_entry' and e.entity_id = r.id
    order by e.event_sequence asc limit 1;

    if v_event_id is null then
      v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, 'journal_entry', r.id))::uuid;
    end if;

    if exists (
      select 1 from public.audit_findings_v600
      where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'UNBALANCED_JOURNAL_ENTRY'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_evidence := jsonb_build_object(
      'what_happened', case when r.line_count = 0 then format('Journal %s was posted with zero lines.', r.entry_number) else format('Journal %s debits (%s) do not equal credits (%s). Variance: %s', r.entry_number, r.total_debit, r.total_credit, r.diff) end,
      'why_detected', 'Double-entry accounting violation: posted financial entry is out of balance.',
      'rule_name', 'UNBALANCED_JOURNAL_ENTRY',
      'financial_impact', v_exposure,
      'is_confirmed', true,
      'investigation_steps', 'Audit journal vouchers and source documents. Review line amounts to identify missing debit or credit posting.',
      'entry_number', r.entry_number,
      'entry_date', r.entry_date,
      'difference', r.diff
    );

    insert into public.audit_findings_v600 (
      id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
      risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
      detected_at, evidence, status, priority, financial_exposure
    ) values (
      gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'critical',
      'UNBALANCED_JOURNAL_ENTRY',
      'Unbalanced financial journal entry',
      format('Posted journal %s is out of balance by %s', r.entry_number, v_exposure),
      99, 'journal_entry', r.id, r.entry_number, r.location_id, v_actor_id,
      now(), v_evidence, 'open', 'critical', v_exposure
    )
    on conflict (tenant_id, source_event_id, rule_code) do nothing
    returning id into v_finding_id;

    if v_finding_id is not null then
      v_inserted := v_inserted + 1;
      insert into public.audit_finding_history_v704 (
        tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
      ) values (
        p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
        v_actor_name, jsonb_build_object('rule_code', 'UNBALANCED_JOURNAL_ENTRY', 'priority', 'critical', 'exposure', v_exposure),
        'Bridge from Phase B Integrity Engine'
      );
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  -- E. DETECT IRREGULAR OR BACKDATED POSTING DATES (Sales, Purchases, Journals)
  -- 1) Sales with date > current_date + 1 OR date < (created_at::date - 60)
  for r in
    select s.id, s.sale_number as doc_number, s.sale_date as doc_date, s.created_at, s.grand_total, null::uuid as location_id,
           'sale'::text as entity_type,
           case
             when s.sale_date > current_date + 1 then format('Future-dated sale (%s days ahead of today)', (s.sale_date - current_date))
             else format('Severely backdated sale (%s days prior to system creation)', (s.created_at::date - s.sale_date))
           end as reason_desc,
           case
             when s.sale_date > current_date + 1 then (s.sale_date - current_date)
             else (s.created_at::date - s.sale_date)
           end as days_variance
    from public.sales s
    where s.tenant_id = p_tenant_id
      and s.sale_date between p_from and p_to
      and (s.sale_date > current_date + 1 or s.sale_date < (s.created_at::date - 60))
      and private.audit_record_allowed_v704(p_tenant_id, 'sales', to_jsonb(s), p_location_id)
  loop
    v_exposure := coalesce(r.grand_total, 0.0);
    v_priority := case when v_exposure >= 25000 then 'high' else 'medium' end;

    select id into v_event_id
    from public.transaction_story_events_v600 e
    where e.tenant_id = p_tenant_id and e.entity_type = r.entity_type and e.entity_id = r.id
    order by e.event_sequence asc limit 1;

    if v_event_id is null then
      v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, r.entity_type, r.id))::uuid;
    end if;

    if exists (
      select 1 from public.audit_findings_v600
      where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'IRREGULAR_POSTING_DATE'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_evidence := jsonb_build_object(
      'what_happened', r.reason_desc,
      'why_detected', 'Posting date anomaly: transaction date is either in the future or backdated more than 60 days prior to creation.',
      'rule_name', 'IRREGULAR_POSTING_DATE',
      'financial_impact', v_exposure,
      'is_confirmed', true,
      'investigation_steps', 'Inspect source voucher, verify if the date was mistyped, verify whether the fiscal period was already closed, and ensure approvals exist.',
      'document_number', r.doc_number,
      'document_date', r.doc_date,
      'creation_date', r.created_at,
      'days_variance', r.days_variance
    );

    insert into public.audit_findings_v600 (
      id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
      risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
      detected_at, evidence, status, priority, financial_exposure
    ) values (
      gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'needs_review',
      'IRREGULAR_POSTING_DATE',
      'Irregular or backdated transaction posting date',
      format('Sale %s has abnormal posting date %s (%s)', r.doc_number, r.doc_date, r.reason_desc),
      75, r.entity_type, r.id, r.doc_number, r.location_id, v_actor_id,
      now(), v_evidence, 'open', v_priority, v_exposure
    )
    on conflict (tenant_id, source_event_id, rule_code) do nothing
    returning id into v_finding_id;

    if v_finding_id is not null then
      v_inserted := v_inserted + 1;
      insert into public.audit_finding_history_v704 (
        tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
      ) values (
        p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
        v_actor_name, jsonb_build_object('rule_code', 'IRREGULAR_POSTING_DATE', 'priority', v_priority, 'exposure', v_exposure),
        'Detected by Advanced Risk Intelligence scan'
      );
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  -- 2) Purchases with date > current_date + 1 OR date < (created_at::date - 60)
  for r in
    select p.id, p.purchase_number as doc_number, p.purchase_date as doc_date, p.created_at, p.grand_total, null::uuid as location_id,
           'purchase'::text as entity_type,
           case
             when p.purchase_date > current_date + 1 then format('Future-dated purchase (%s days ahead of today)', (p.purchase_date - current_date))
             else format('Severely backdated purchase (%s days prior to system creation)', (p.created_at::date - p.purchase_date))
           end as reason_desc,
           case
             when p.purchase_date > current_date + 1 then (p.purchase_date - current_date)
             else (p.created_at::date - p.purchase_date)
           end as days_variance
    from public.purchases p
    where p.tenant_id = p_tenant_id
      and p.purchase_date between p_from and p_to
      and (p.purchase_date > current_date + 1 or p.purchase_date < (p.created_at::date - 60))
      and private.audit_record_allowed_v704(p_tenant_id, 'purchases', to_jsonb(p), p_location_id)
  loop
    v_exposure := coalesce(r.grand_total, 0.0);
    v_priority := case when v_exposure >= 25000 then 'high' else 'medium' end;

    select id into v_event_id
    from public.transaction_story_events_v600 e
    where e.tenant_id = p_tenant_id and e.entity_type = r.entity_type and e.entity_id = r.id
    order by e.event_sequence asc limit 1;

    if v_event_id is null then
      v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, r.entity_type, r.id))::uuid;
    end if;

    if exists (
      select 1 from public.audit_findings_v600
      where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'IRREGULAR_POSTING_DATE'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_evidence := jsonb_build_object(
      'what_happened', r.reason_desc,
      'why_detected', 'Posting date anomaly: transaction date is either in the future or backdated more than 60 days prior to creation.',
      'rule_name', 'IRREGULAR_POSTING_DATE',
      'financial_impact', v_exposure,
      'is_confirmed', true,
      'investigation_steps', 'Inspect vendor bill, delivery note, and approvals to verify why purchase was entered with this abnormal date.',
      'document_number', r.doc_number,
      'document_date', r.doc_date,
      'creation_date', r.created_at,
      'days_variance', r.days_variance
    );

    insert into public.audit_findings_v600 (
      id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
      risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
      detected_at, evidence, status, priority, financial_exposure
    ) values (
      gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'needs_review',
      'IRREGULAR_POSTING_DATE',
      'Irregular or backdated transaction posting date',
      format('Purchase %s has abnormal posting date %s (%s)', r.doc_number, r.doc_date, r.reason_desc),
      75, r.entity_type, r.id, r.doc_number, r.location_id, v_actor_id,
      now(), v_evidence, 'open', v_priority, v_exposure
    )
    on conflict (tenant_id, source_event_id, rule_code) do nothing
    returning id into v_finding_id;

    if v_finding_id is not null then
      v_inserted := v_inserted + 1;
      insert into public.audit_finding_history_v704 (
        tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
      ) values (
        p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
        v_actor_name, jsonb_build_object('rule_code', 'IRREGULAR_POSTING_DATE', 'priority', v_priority, 'exposure', v_exposure),
        'Detected by Advanced Risk Intelligence scan'
      );
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  -- 3) Journal entries with date > current_date + 1 OR date < (created_at::date - 60)
  for r in
    select j.id, j.entry_number as doc_number, j.entry_date as doc_date, j.created_at, j.location_id,
           'journal_entry'::text as entity_type,
           (select coalesce(sum(l.debit), 0) from public.journal_lines l where l.journal_entry_id = j.id) as total_amount,
           case
             when j.entry_date > current_date + 1 then format('Future-dated journal entry (%s days ahead of today)', (j.entry_date - current_date))
             else format('Severely backdated journal entry (%s days prior to system creation)', (j.created_at::date - j.entry_date))
           end as reason_desc,
           case
             when j.entry_date > current_date + 1 then (j.entry_date - current_date)
             else (j.created_at::date - j.entry_date)
           end as days_variance
    from public.journal_entries j
    where j.tenant_id = p_tenant_id
      and j.entry_date between p_from and p_to
      and j.status in ('posted', 'reversed')
      and (j.entry_date > current_date + 1 or j.entry_date < (j.created_at::date - 60))
      and private.audit_record_allowed_v704(p_tenant_id, 'journal_entries', to_jsonb(j), p_location_id)
  loop
    v_exposure := coalesce(r.total_amount, 0.0);
    v_priority := case when v_exposure >= 25000 then 'high' else 'medium' end;

    select id into v_event_id
    from public.transaction_story_events_v600 e
    where e.tenant_id = p_tenant_id and e.entity_type = r.entity_type and e.entity_id = r.id
    order by e.event_sequence asc limit 1;

    if v_event_id is null then
      v_event_id := md5(format('audit_event:%s:%s:%s', p_tenant_id, r.entity_type, r.id))::uuid;
    end if;

    if exists (
      select 1 from public.audit_findings_v600
      where tenant_id = p_tenant_id and source_event_id = v_event_id and rule_code = 'IRREGULAR_POSTING_DATE'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_evidence := jsonb_build_object(
      'what_happened', r.reason_desc,
      'why_detected', 'Posting date anomaly: journal entry date is either in the future or backdated more than 60 days prior to creation.',
      'rule_name', 'IRREGULAR_POSTING_DATE',
      'financial_impact', v_exposure,
      'is_confirmed', true,
      'investigation_steps', 'Inspect journal voucher and approval trail. Ensure backdated adjustments into closed financial periods are accompanied by management sign-off.',
      'document_number', r.doc_number,
      'document_date', r.doc_date,
      'creation_date', r.created_at,
      'days_variance', r.days_variance
    );

    insert into public.audit_findings_v600 (
      id, tenant_id, source_event_id, correlation_id, severity, rule_code, title, description,
      risk_score, entity_type, entity_id, entity_reference, location_id, actor_user_id,
      detected_at, evidence, status, priority, financial_exposure
    ) values (
      gen_random_uuid(), p_tenant_id, v_event_id, gen_random_uuid(), 'needs_review',
      'IRREGULAR_POSTING_DATE',
      'Irregular or backdated transaction posting date',
      format('Journal %s has abnormal posting date %s (%s)', r.doc_number, r.doc_date, r.reason_desc),
      75, r.entity_type, r.id, r.doc_number, r.location_id, v_actor_id,
      now(), v_evidence, 'open', v_priority, v_exposure
    )
    on conflict (tenant_id, source_event_id, rule_code) do nothing
    returning id into v_finding_id;

    if v_finding_id is not null then
      v_inserted := v_inserted + 1;
      insert into public.audit_finding_history_v704 (
        tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
      ) values (
        p_tenant_id, v_finding_id, 'finding_created', coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
        v_actor_name, jsonb_build_object('rule_code', 'IRREGULAR_POSTING_DATE', 'priority', v_priority, 'exposure', v_exposure),
        'Detected by Advanced Risk Intelligence scan'
      );
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'detected_count', v_inserted,
    'new_findings', v_inserted,
    'existing_skipped', v_skipped,
    'scanned_period', format('%s to %s', p_from, p_to),
    'from', p_from,
    'to', p_to,
    'scanned_at', now()
  );
end;
$$;

revoke all on function public.audit_risk_scan_period_v704(uuid, date, date, uuid) from public, anon;
grant execute on function public.audit_risk_scan_period_v704(uuid, date, date, uuid) to authenticated;
