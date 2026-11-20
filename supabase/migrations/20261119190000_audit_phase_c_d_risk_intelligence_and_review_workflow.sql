-- Phase C & D: Advanced Risk Intelligence & Professional Audit Review Workflow
-- Cohesive Audit Center enhancement:
-- 1. Schema extensions on public.audit_findings_v600 (assignment, due dates, priority, financial exposure, duplicate grouping).
-- 2. New table public.audit_finding_notes_v704 for persistent, traceable investigation notes and evidence references.
-- 3. New table public.audit_finding_history_v704 for immutable workflow audit activity history.
-- 4. Advanced risk intelligence scanning engine with duplicate reference detection, payment reference collisions,
--    rapid return/adjustment patterns, and Phase B integrity bridge.
-- 5. Professional review workflow RPCs: assignment, lifecycle status transitions, notes, detail view, dashboard metrics,
--    and assignable users with strict tenant isolation and permission checks.

-- -----------------------------------------------------------------------------
-- 1. EXTEND public.audit_findings_v600
-- -----------------------------------------------------------------------------
alter table public.audit_findings_v600
  add column if not exists assigned_to uuid,
  add column if not exists assigned_at timestamptz,
  add column if not exists assigned_by uuid,
  add column if not exists due_date date,
  add column if not exists priority text not null default 'medium',
  add column if not exists financial_exposure numeric not null default 0.0,
  add column if not exists duplicate_group_id text,
  add column if not exists is_duplicate boolean not null default false,
  add column if not exists rule_version text not null default '7.4';

-- Update check constraints on audit_findings_v600
alter table public.audit_findings_v600 drop constraint if exists audit_findings_v600_severity_chk;
alter table public.audit_findings_v600 add constraint audit_findings_v600_severity_chk
  check (severity in ('critical', 'high_risk', 'needs_review', 'low_risk', 'high', 'medium', 'low'));

alter table public.audit_findings_v600 drop constraint if exists audit_findings_v600_status_chk;
alter table public.audit_findings_v600 add constraint audit_findings_v600_status_chk
  check (status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated', 'resolved', 'dismissed', 'explained'));

alter table public.audit_findings_v600 drop constraint if exists audit_findings_v600_priority_chk;
alter table public.audit_findings_v600 add constraint audit_findings_v600_priority_chk
  check (priority in ('critical', 'high', 'medium', 'low'));

-- Indexes for review dashboard & filtering
create index if not exists idx_audit_findings_tenant_status on public.audit_findings_v600(tenant_id, status);
create index if not exists idx_audit_findings_tenant_priority on public.audit_findings_v600(tenant_id, priority);
create index if not exists idx_audit_findings_tenant_assigned on public.audit_findings_v600(tenant_id, assigned_to);
create index if not exists idx_audit_findings_tenant_due_date on public.audit_findings_v600(tenant_id, due_date);
create index if not exists idx_audit_findings_tenant_dup_group on public.audit_findings_v600(tenant_id, duplicate_group_id);

-- Update evidence immutability trigger to allow review workflow fields
create or replace function private.v600_guard_finding_evidence()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  if old.tenant_id is distinct from new.tenant_id
    or old.source_event_id is distinct from new.source_event_id
    or old.correlation_id is distinct from new.correlation_id
    or old.rule_code is distinct from new.rule_code
    or old.entity_type is distinct from new.entity_type
    or old.entity_id is distinct from new.entity_id
    or old.location_id is distinct from new.location_id
    or old.device_id is distinct from new.device_id
    or old.actor_user_id is distinct from new.actor_user_id
    or old.detected_at is distinct from new.detected_at
    or old.evidence is distinct from new.evidence then
      raise exception 'Audit finding evidence is immutable; only review workflow fields may change' using errcode='55000';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. INVESTIGATION NOTES TABLE (public.audit_finding_notes_v704)
-- -----------------------------------------------------------------------------
create table if not exists public.audit_finding_notes_v704 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  finding_id uuid not null references public.audit_findings_v600(id) on delete cascade,
  author_id uuid not null,
  author_name text,
  note_type text not null default 'investigation' check (note_type in ('investigation', 'observation', 'evidence_link', 'resolution', 'reassignment', 'escalation')),
  note text not null check (length(trim(note)) > 0),
  evidence_references jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_notes_finding on public.audit_finding_notes_v704(tenant_id, finding_id, created_at asc);

alter table public.audit_finding_notes_v704 enable row level security;

drop policy if exists audit_finding_notes_tenant_policy on public.audit_finding_notes_v704;
create policy audit_finding_notes_tenant_policy on public.audit_finding_notes_v704
  for all using (tenant_id = (select tenant_id from public.tenant_memberships where user_id = auth.uid() and status = 'active' limit 1));

-- Immutability guard for notes
create or replace function private.audit_guard_notes_immutable_v704()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception 'Audit investigation notes are immutable and cannot be modified or deleted' using errcode='55000';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_notes_immutable on public.audit_finding_notes_v704;
create trigger trg_audit_notes_immutable
before update or delete on public.audit_finding_notes_v704
for each row execute function private.audit_guard_notes_immutable_v704();

-- -----------------------------------------------------------------------------
-- 3. ACTIVITY HISTORY TABLE (public.audit_finding_history_v704)
-- -----------------------------------------------------------------------------
create table if not exists public.audit_finding_history_v704 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  finding_id uuid not null references public.audit_findings_v600(id) on delete cascade,
  action text not null,
  actor_id uuid not null,
  actor_name text,
  before_state jsonb,
  after_state jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_history_finding on public.audit_finding_history_v704(tenant_id, finding_id, created_at asc);

alter table public.audit_finding_history_v704 enable row level security;

drop policy if exists audit_finding_history_tenant_policy on public.audit_finding_history_v704;
create policy audit_finding_history_tenant_policy on public.audit_finding_history_v704
  for all using (tenant_id = (select tenant_id from public.tenant_memberships where user_id = auth.uid() and status = 'active' limit 1));

-- Immutability guard for history
create or replace function private.audit_guard_history_immutable_v704()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception 'Audit activity history is append-only and cannot be altered or removed' using errcode='55000';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_history_immutable on public.audit_finding_history_v704;
create trigger trg_audit_history_immutable
before update or delete on public.audit_finding_history_v704
for each row execute function private.audit_guard_history_immutable_v704();

-- -----------------------------------------------------------------------------
-- 4. ADVANCED RISK SCAN ENGINE (public.audit_risk_scan_period_v704)
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
  v_inserted integer := 0;
  v_skipped integer := 0;
  v_actor_id uuid := auth.uid();
  v_actor_name text := 'System Auditor';
  r record;
  v_exposure numeric;
  v_priority text;
  v_evidence jsonb;
  v_event_id uuid;
  v_finding_id uuid;
  v_group_id text;
  v_is_dup boolean;
begin
  perform private.audit_access_v703(p_tenant_id, p_location_id);
  if not private.has_permission(p_tenant_id, 'audit_center.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  select coalesce(u.username, u.auth_email, 'Auditor') into v_actor_name
  from public.user_login_names u
  where u.user_id = v_actor_id limit 1;

  -- A. DETECT DUPLICATE PURCHASE INVOICE REFERENCES (Same external invoice number reused across purchases/suppliers)
  for r in
    select p.id, p.purchase_number, p.supplier_id, s.name as supplier_name,
           coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF') as inv_ref,
           p.grand_total, p.purchase_date, null::uuid as location_id,
           count(*) over (partition by lower(trim(coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF')))) as ref_count,
           row_number() over (partition by lower(trim(coalesce(nullif(trim(p.supplier_invoice_number), ''), nullif(trim(p.purchase_number), ''), 'REF'))) order by p.purchase_date asc, p.created_at asc) as row_seq
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
        v_event_id := gen_random_uuid();
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
        v_event_id := gen_random_uuid();
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
      v_event_id := gen_random_uuid();
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
      v_event_id := gen_random_uuid();
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

  return jsonb_build_object(
    'new_findings', v_inserted,
    'existing_skipped', v_skipped,
    'from', p_from,
    'to', p_to,
    'scanned_at', now()
  );
end;
$$;
revoke all on function public.audit_risk_scan_period_v704(uuid,date,date,uuid) from public,anon;
grant execute on function public.audit_risk_scan_period_v704(uuid,date,date,uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. PROFESSIONAL REVIEW WORKFLOW RPCS
-- -----------------------------------------------------------------------------

-- A. List eligible assignable users in tenant
create or replace function public.audit_assignable_users_v704(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform private.audit_access_v703(p_tenant_id, null);
  if not private.has_permission(p_tenant_id, 'audit_center.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id,
      'username', coalesce(u.username, u.auth_email, 'Team Member'),
      'email', u.auth_email,
      'joined_at', m.joined_at
    ) order by coalesce(u.username, u.auth_email)), '[]'::jsonb)
    from public.tenant_memberships m
    left join public.user_login_names u on u.user_id = m.user_id and u.tenant_id = p_tenant_id
    where m.tenant_id = p_tenant_id and m.status = 'active'
  );
end;
$$;
revoke all on function public.audit_assignable_users_v704(uuid) from public,anon;
grant execute on function public.audit_assignable_users_v704(uuid) to authenticated;

-- B. Assign / Reassign Finding
create or replace function public.audit_finding_assign_v704(
  p_tenant_id uuid,
  p_finding_id uuid,
  p_assign_to uuid,
  p_priority text default null,
  p_due_date date default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f public.audit_findings_v600%rowtype;
  v_before jsonb;
  v_actor_id uuid := auth.uid();
  v_actor_name text := 'Reviewer';
  v_assignee_name text := 'Assignee';
begin
  perform private.audit_access_v703(p_tenant_id, null);
  if not private.has_permission(p_tenant_id, 'audit_center.review') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  -- Validate assignee belongs to tenant if not unassigning
  if p_assign_to is not null then
    if not exists (select 1 from public.tenant_memberships where tenant_id = p_tenant_id and user_id = p_assign_to and status = 'active') then
      raise exception 'Assignee is not an active member of this business' using errcode='22023';
    end if;
    select coalesce(username, auth_email, 'Team Member') into v_assignee_name
    from public.user_login_names where user_id = p_assign_to and tenant_id = p_tenant_id limit 1;
  else
    v_assignee_name := 'Unassigned';
  end if;

  select coalesce(username, auth_email, 'Reviewer') into v_actor_name
  from public.user_login_names where user_id = v_actor_id and tenant_id = p_tenant_id limit 1;

  select to_jsonb(x) into v_before
  from public.audit_findings_v600 x
  where x.tenant_id = p_tenant_id and x.id = p_finding_id
    and private.audit_record_allowed_v704(p_tenant_id, 'audit_findings_v600', to_jsonb(x), null);

  if v_before is null then
    raise exception 'Audit finding not found' using errcode='P0002';
  end if;

  update public.audit_findings_v600
  set assigned_to = p_assign_to,
      assigned_at = case when p_assign_to is not null then now() else null end,
      assigned_by = case when p_assign_to is not null then v_actor_id else null end,
      due_date = coalesce(p_due_date, due_date),
      priority = coalesce(p_priority, priority),
      status = case when status = 'open' and p_assign_to is not null then 'assigned' else status end,
      updated_at = now()
  where tenant_id = p_tenant_id and id = p_finding_id
  returning * into f;

  -- Log immutable history record
  insert into public.audit_finding_history_v704 (
    tenant_id, finding_id, action, actor_id, actor_name, before_state, after_state, reason
  ) values (
    p_tenant_id, p_finding_id,
    case when (v_before->>'assigned_to') is distinct from p_assign_to::text then
      case when p_assign_to is null then 'finding_unassigned' else 'finding_assigned' end
    else 'finding_updated' end,
    coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_actor_name,
    jsonb_build_object('assigned_to', v_before->>'assigned_to', 'priority', v_before->>'priority', 'due_date', v_before->>'due_date', 'status', v_before->>'status'),
    jsonb_build_object('assigned_to', f.assigned_to, 'assignee_name', v_assignee_name, 'priority', f.priority, 'due_date', f.due_date, 'status', f.status),
    coalesce(nullif(trim(p_reason), ''), 'Assignment updated in audit workspace')
  );

  return to_jsonb(f);
end;
$$;
revoke all on function public.audit_finding_assign_v704(uuid,uuid,uuid,text,date,text) from public,anon;
grant execute on function public.audit_finding_assign_v704(uuid,uuid,uuid,text,date,text) to authenticated;

-- C. Lifecycle Status Transition
create or replace function public.audit_finding_status_v704(
  p_tenant_id uuid,
  p_finding_id uuid,
  p_status text,
  p_note text,
  p_resolution_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f public.audit_findings_v600%rowtype;
  v_before jsonb;
  v_resolve boolean;
  v_actor_id uuid := auth.uid();
  v_actor_name text := 'Reviewer';
begin
  perform private.audit_access_v703(p_tenant_id, null);
  if nullif(trim(p_note), '') is null then
    raise exception 'A review explanation note is required for all lifecycle changes' using errcode='22023';
  end if;

  if p_status not in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated', 'resolved', 'dismissed', 'explained') then
    raise exception 'Invalid audit finding status: %', p_status using errcode='22023';
  end if;

  v_resolve := p_status in ('resolved', 'escalated', 'dismissed');
  if v_resolve then
    if not private.has_permission(p_tenant_id, 'audit_center.resolve') then
      raise exception 'Permission denied (audit_center.resolve required)' using errcode='42501';
    end if;
  else
    if not private.has_permission(p_tenant_id, 'audit_center.review') then
      raise exception 'Permission denied (audit_center.review required)' using errcode='42501';
    end if;
  end if;

  select coalesce(username, auth_email, 'Reviewer') into v_actor_name
  from public.user_login_names where user_id = v_actor_id and tenant_id = p_tenant_id limit 1;

  select to_jsonb(x) into v_before
  from public.audit_findings_v600 x
  where x.tenant_id = p_tenant_id and x.id = p_finding_id
    and private.audit_record_allowed_v704(p_tenant_id, 'audit_findings_v600', to_jsonb(x), null);

  if v_before is null then
    raise exception 'Audit finding not found' using errcode='P0002';
  end if;

  update public.audit_findings_v600
  set status = p_status,
      reviewer_id = v_actor_id,
      reviewed_at = now(),
      review_note = case when v_resolve then review_note else coalesce(nullif(trim(p_note), ''), review_note) end,
      resolution_note = case when v_resolve then coalesce(nullif(trim(p_resolution_note), ''), nullif(trim(p_note), ''), resolution_note) else resolution_note end,
      updated_at = now()
  where tenant_id = p_tenant_id and id = p_finding_id
  returning * into f;

  -- Add note to notes table
  insert into public.audit_finding_notes_v704 (
    tenant_id, finding_id, author_id, author_name, note_type, note
  ) values (
    p_tenant_id, p_finding_id, coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_actor_name, case when v_resolve then 'resolution' else 'investigation' end, trim(p_note)
  );

  -- Log immutable activity history
  insert into public.audit_finding_history_v704 (
    tenant_id, finding_id, action, actor_id, actor_name, before_state, after_state, reason
  ) values (
    p_tenant_id, p_finding_id, 'status_changed',
    coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_actor_name,
    jsonb_build_object('status', v_before->>'status'),
    jsonb_build_object('status', f.status),
    trim(p_note)
  );

  -- Maintain backward compatibility with business_audit_log
  perform private.business_audit_write(
    p_tenant_id, 'audit_finding_reviewed', 'audit_finding', p_finding_id, f.entity_reference, v_before, to_jsonb(f)
  );

  return to_jsonb(f);
end;
$$;
revoke all on function public.audit_finding_status_v704(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.audit_finding_status_v704(uuid,uuid,text,text,text) to authenticated;

-- D. Add Investigation Note & Evidence References
create or replace function public.audit_finding_add_note_v704(
  p_tenant_id uuid,
  p_finding_id uuid,
  p_note text,
  p_note_type text default 'investigation',
  p_evidence_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_note_id uuid;
  v_actor_id uuid := auth.uid();
  v_actor_name text := 'Reviewer';
  v_result jsonb;
begin
  perform private.audit_access_v703(p_tenant_id, null);
  if not private.has_permission(p_tenant_id, 'audit_center.review') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  if nullif(trim(p_note), '') is null then
    raise exception 'Note text cannot be empty' using errcode='22023';
  end if;

  select coalesce(username, auth_email, 'Reviewer') into v_actor_name
  from public.user_login_names where user_id = v_actor_id and tenant_id = p_tenant_id limit 1;

  if not exists (select 1 from public.audit_findings_v600 where tenant_id = p_tenant_id and id = p_finding_id) then
    raise exception 'Audit finding not found' using errcode='P0002';
  end if;

  insert into public.audit_finding_notes_v704 (
    tenant_id, finding_id, author_id, author_name, note_type, note, evidence_references
  ) values (
    p_tenant_id, p_finding_id, coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_actor_name, coalesce(p_note_type, 'investigation'), trim(p_note), coalesce(p_evidence_refs, '[]'::jsonb)
  ) returning id into v_note_id;

  -- Append to activity history
  insert into public.audit_finding_history_v704 (
    tenant_id, finding_id, action, actor_id, actor_name, after_state, reason
  ) values (
    p_tenant_id, p_finding_id, 'note_added',
    coalesce(v_actor_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_actor_name,
    jsonb_build_object('note_id', v_note_id, 'note_type', p_note_type, 'refs_count', jsonb_array_length(coalesce(p_evidence_refs, '[]'::jsonb))),
    trim(p_note)
  );

  select to_jsonb(n) into v_result
  from public.audit_finding_notes_v704 n
  where n.id = v_note_id;

  return v_result;
end;
$$;
revoke all on function public.audit_finding_add_note_v704(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.audit_finding_add_note_v704(uuid,uuid,text,text,jsonb) to authenticated;

-- E. Comprehensive Finding Detail RPC
create or replace function public.audit_finding_detail_v704(
  p_tenant_id uuid,
  p_finding_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  f public.audit_findings_v600%rowtype;
  v_sensitive boolean;
  v_events jsonb;
  v_notes jsonb;
  v_history jsonb;
  v_duplicates jsonb;
  v_assignee jsonb;
begin
  perform private.audit_access_v703(p_tenant_id, null);
  if not private.has_permission(p_tenant_id, 'audit_center.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  select * into f
  from public.audit_findings_v600
  where tenant_id = p_tenant_id and id = p_finding_id
    and private.audit_record_allowed_v704(p_tenant_id, 'audit_findings_v600', to_jsonb(audit_findings_v600), null);

  if not found then
    raise exception 'Audit finding not found' using errcode='P0002';
  end if;

  v_sensitive := private.has_permission(p_tenant_id, 'audit_history.view_sensitive');

  -- Assignee info
  if f.assigned_to is not null then
    select jsonb_build_object('user_id', u.user_id, 'username', coalesce(u.username, u.auth_email, 'Reviewer'), 'email', u.auth_email)
    into v_assignee
    from public.user_login_names u
    where u.user_id = f.assigned_to and u.tenant_id = p_tenant_id limit 1;
  end if;

  -- Transaction Story Events
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence', e.event_sequence, 'id', e.id, 'action', e.action, 'event_time', e.event_time,
    'entity_type', e.entity_type, 'entity_id', e.entity_id, 'entity_reference', e.entity_reference,
    'actor', jsonb_build_object('user_id', e.actor_user_id, 'name', e.actor_name, 'roles', e.actor_role_keys),
    'device', jsonb_build_object('id', e.device_id, 'name', e.device_name, 'code', e.device_code, 'app', e.source_app),
    'location_id', e.location_id, 'changed_fields', e.changed_fields,
    'before', case when v_sensitive then e.before_data else null end,
    'after', case when v_sensitive then e.after_data else null end,
    'reason', e.reason,
    'approval', jsonb_build_object('request_id', e.approval_request_id, 'approved_by', e.approved_by, 'approved_at', e.approved_at, 'note', e.approval_note),
    'related_entities', e.related_entities, 'event_hash', e.event_hash
  ) order by e.event_sequence), '[]'::jsonb) into v_events
  from public.transaction_story_events_v600 e
  where e.tenant_id = p_tenant_id and e.correlation_id = f.correlation_id
    and private.audit_record_allowed_v704(p_tenant_id, 'transaction_story_events_v600', to_jsonb(e), null);

  -- Investigation Notes
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'author_id', n.author_id, 'author_name', n.author_name,
    'note_type', n.note_type, 'note', n.note, 'evidence_references', n.evidence_references,
    'created_at', n.created_at
  ) order by n.created_at desc), '[]'::jsonb) into v_notes
  from public.audit_finding_notes_v704 n
  where n.tenant_id = p_tenant_id and n.finding_id = p_finding_id;

  -- Activity History
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'action', h.action, 'actor_id', h.actor_id, 'actor_name', h.actor_name,
    'before_state', h.before_state, 'after_state', h.after_state, 'reason', h.reason,
    'created_at', h.created_at
  ) order by h.created_at desc), '[]'::jsonb) into v_history
  from public.audit_finding_history_v704 h
  where h.tenant_id = p_tenant_id and h.finding_id = p_finding_id;

  -- Related / Duplicate Findings
  if f.duplicate_group_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id, 'reference', d.entity_reference, 'title', d.title, 'status', d.status,
      'priority', d.priority, 'financial_exposure', d.financial_exposure, 'detected_at', d.detected_at
    ) order by d.detected_at asc), '[]'::jsonb) into v_duplicates
    from public.audit_findings_v600 d
    where d.tenant_id = p_tenant_id and d.duplicate_group_id = f.duplicate_group_id and d.id <> f.id;
  else
    v_duplicates := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'finding', to_jsonb(f),
    'assignee', v_assignee,
    'notes', v_notes,
    'history', v_history,
    'duplicates', v_duplicates,
    'transaction_story', v_events,
    'sensitive_values_visible', v_sensitive
  );
end;
$$;
revoke all on function public.audit_finding_detail_v704(uuid,uuid) from public,anon;
grant execute on function public.audit_finding_detail_v704(uuid,uuid) to authenticated;

-- F. Review Dashboard Summary RPC (Section 4.E)
create or replace function public.audit_review_dashboard_v704(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_tz text;
  v_lo timestamptz;
  v_hi timestamptz;
  v_summary jsonb;
  v_workload jsonb;
begin
  perform private.audit_access_v703(p_tenant_id, p_location_id);
  if not private.has_permission(p_tenant_id, 'audit_center.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  v_tz := coalesce((select timezone from public.tenant_settings where tenant_id = p_tenant_id), 'UTC');
  v_lo := p_from::timestamp at time zone v_tz;
  v_hi := (p_to + 1)::timestamp at time zone v_tz;

  select jsonb_build_object(
    'total_open', count(*) filter (where status in ('open', 'assigned', 'under_review', 'awaiting_info', 'escalated')),
    'critical_priority', count(*) filter (where priority = 'critical' and status not in ('resolved', 'dismissed')),
    'high_priority', count(*) filter (where priority = 'high' and status not in ('resolved', 'dismissed')),
    'medium_priority', count(*) filter (where priority = 'medium' and status not in ('resolved', 'dismissed')),
    'low_priority', count(*) filter (where priority = 'low' and status not in ('resolved', 'dismissed')),
    'unassigned', count(*) filter (where assigned_to is null and status not in ('resolved', 'dismissed')),
    'awaiting_info', count(*) filter (where status = 'awaiting_info'),
    'under_review', count(*) filter (where status = 'under_review'),
    'escalated', count(*) filter (where status = 'escalated'),
    'overdue', count(*) filter (where due_date < current_date and status not in ('resolved', 'dismissed')),
    'resolved_in_period', count(*) filter (where status in ('resolved', 'explained') and reviewed_at >= v_lo and reviewed_at < v_hi),
    'dismissed_in_period', count(*) filter (where status = 'dismissed' and reviewed_at >= v_lo and reviewed_at < v_hi),
    'total_exposure', coalesce(sum(financial_exposure) filter (where status not in ('resolved', 'dismissed')), 0.0)
  ) into v_summary
  from public.audit_findings_v600 a
  where a.tenant_id = p_tenant_id and a.detected_at >= v_lo and a.detected_at < v_hi
    and private.reports_scope_v631(p_tenant_id, a.location_id, p_location_id, 'view');

  select coalesce(jsonb_agg(w.data), '[]'::jsonb) into v_workload
  from (
    select jsonb_build_object(
      'user_id', a.assigned_to,
      'username', coalesce(u.username, u.auth_email, 'Unassigned'),
      'active_count', count(*),
      'critical_count', count(*) filter (where a.priority = 'critical'),
      'overdue_count', count(*) filter (where a.due_date < current_date)
    ) as data
    from public.audit_findings_v600 a
    left join public.user_login_names u on u.user_id = a.assigned_to and u.tenant_id = p_tenant_id
    where a.tenant_id = p_tenant_id and a.detected_at >= v_lo and a.detected_at < v_hi
      and a.status not in ('resolved', 'dismissed')
      and private.reports_scope_v631(p_tenant_id, a.location_id, p_location_id, 'view')
    group by a.assigned_to, coalesce(u.username, u.auth_email, 'Unassigned')
    order by count(*) desc
  ) w;

  return jsonb_build_object(
    'metrics', v_summary,
    'workload_by_reviewer', v_workload,
    'generated_at', statement_timestamp()
  );
end;
$$;
revoke all on function public.audit_review_dashboard_v704(uuid,date,date,uuid) from public,anon;
grant execute on function public.audit_review_dashboard_v704(uuid,date,date,uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. ENHANCE private.audit_workspace_v703 FOR FINDINGS VIEW
-- -----------------------------------------------------------------------------
drop function if exists private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text);
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
  source_type text default ''
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
      select a.id as account_id, a.code as account_code, a.name as account_name, a.type as account_type,
             coalesce(sum(l.debit), 0) as period_debit,
             coalesce(sum(l.credit), 0) as period_credit,
             coalesce(sum(l.debit), 0) - coalesce(sum(l.credit), 0) as period_balance
      from public.accounting_accounts a
      left join public.journal_lines l on l.account_id = a.id
      left join public.journal_entries j on j.id = l.journal_entry_id and j.tenant_id = t and j.entry_date between f and z and j.status in ('posted', 'reversed')
      where a.tenant_id = t
        and (query_clean = '' or lower(coalesce(a.name, '')) like '%' || query_clean || '%' or lower(coalesce(a.code, '')) like '%' || query_clean || '%')
      group by a.id, a.code, a.name, a.type
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
