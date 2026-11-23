-- ============================================================================
-- Migration: 20261123110000_operations_intelligence_phase9_workforce.sql
-- Module: Operations Intelligence
-- Phase: Phase 9 — Workforce Intelligence Engine
--
-- Features:
-- 1. workforce_intelligence_v830:
--    - Evaluates workforce availability, attendance patterns, shift execution,
--      workload distribution, overtime ratios, and workforce cost trends.
--    - Algorithm-first, 100% deterministic, zero external AI dependencies.
--    - Zero employee surveillance, no individual productivity rankings.
--    - Strict tenant isolation and role-based payroll permission masking.
--    - Fair store-to-store benchmarking qualified with sample sufficiency.
-- 2. workforce_intelligence_diagnostic_scan_v830:
--    - Ingests detected workforce risks into erp_intelligence_insights
--      under engine = 'workforce'.
-- 3. Registers Release #714 (v8.3.8) in public.thq_schema_releases.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. workforce_intelligence_v830
-- ----------------------------------------------------------------------------
create or replace function public.workforce_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_can_view_payroll boolean := false;
  v_period_days integer := coalesce(p_days, 30);
  v_from_ts timestamp with time zone;
  v_prev_from_ts timestamp with time zone;
  v_from_date date;
  v_to_date date := current_date;

  -- Workforce Availability
  v_total_staff integer := 0;
  v_active_staff integer := 0;
  v_inactive_staff integer := 0;
  v_staff_by_role jsonb := '[]'::jsonb;
  v_staff_by_branch jsonb := '[]'::jsonb;

  -- Attendance & Leave Intelligence
  v_total_attendance_records integer := 0;
  v_present_count integer := 0;
  v_half_day_count integer := 0;
  v_absent_count integer := 0;
  v_paid_leave_count integer := 0;
  v_unpaid_leave_count integer := 0;
  v_total_regular_hours numeric := 0.0;
  v_total_overtime_hours numeric := 0.0;
  v_attendance_rate_pct numeric := 100.0;
  v_absence_rate_pct numeric := 0.0;
  v_leave_rate_pct numeric := 0.0;
  v_overtime_ratio_pct numeric := 0.0;
  v_daily_attendance_trends jsonb := '[]'::jsonb;

  -- Shift & Cashier Staffing
  v_total_shifts integer := 0;
  v_open_shifts integer := 0;
  v_closed_shifts integer := 0;
  v_avg_shift_hours numeric := 0.0;
  v_shift_discrepancy_count integer := 0;
  v_daily_shifts jsonb := '[]'::jsonb;

  -- Demand & Capacity Indicators
  v_total_sales integer := 0;
  v_avg_txns_per_staff_day numeric := 0.0;
  v_peak_demand_hours jsonb := '[]'::jsonb;
  v_total_pos integer := 0;
  v_total_transfers integer := 0;

  -- Overtime & Workforce Cost Intelligence
  v_gross_workforce_earnings numeric := 0.0;
  v_net_workforce_earnings numeric := 0.0;
  v_total_payments_disbursed numeric := 0.0;
  v_earnings_by_kind jsonb := '[]'::jsonb;

  -- Branch Benchmarks & Risks
  v_branch_benchmarks jsonb := '[]'::jsonb;
  v_risks jsonb := '[]'::jsonb;
  v_workforce_score numeric := 100.0;
  v_health_status text := 'optimal';
  v_data_freshness jsonb;
begin
  -- 1. Tenant Access Verification
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied: caller does not belong to tenant %.', p_tenant_id
      using errcode = '42501';
  end if;

  -- 2. Role-Based Payroll / Compensation Permission Verification
  v_can_view_payroll := private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'staff.payroll')
    or private.erp_has_permission(p_tenant_id, 'accounting.view')
    or private.erp_has_permission(p_tenant_id, 'reports.view');

  -- 3. Date Windows
  if v_period_days <= 0 then v_period_days := 30; end if;
  v_from_ts := now() - (v_period_days || ' days')::interval;
  v_prev_from_ts := now() - ((v_period_days * 2) || ' days')::interval;
  v_from_date := v_to_date - (v_period_days || ' days')::interval;

  -- --------------------------------------------------------------------------
  -- 4. Workforce Availability Intelligence
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where sm.active = true and (sm.left_on is null or sm.left_on >= current_date)),
    count(*) filter (where sm.active = false or (sm.left_on is not null and sm.left_on < current_date))
  into v_total_staff, v_active_staff, v_inactive_staff
  from public.staff_members_v630 sm
  where sm.tenant_id = p_tenant_id
    and (p_location_id is null or sm.location_id = p_location_id);

  -- Role breakdown
  select coalesce(jsonb_agg(r), '[]'::jsonb)
  into v_staff_by_role
  from (
    select
      coalesce(sm.job_role, 'staff') as job_role,
      count(*) as count,
      count(*) filter (where sm.active = true) as active_count,
      sm.wage_basis
    from public.staff_members_v630 sm
    where sm.tenant_id = p_tenant_id
      and (p_location_id is null or sm.location_id = p_location_id)
    group by sm.job_role, sm.wage_basis
    order by count(*) desc
  ) r;

  -- --------------------------------------------------------------------------
  -- 5. Attendance & Leave Intelligence
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where att.status = 'present'),
    count(*) filter (where att.status = 'half_day'),
    count(*) filter (where att.status = 'absent'),
    count(*) filter (where att.status = 'paid_leave'),
    count(*) filter (where att.status = 'unpaid_leave'),
    coalesce(round(sum(att.hours), 1), 0.0),
    coalesce(round(sum(att.overtime_hours), 1), 0.0)
  into
    v_total_attendance_records,
    v_present_count,
    v_half_day_count,
    v_absent_count,
    v_paid_leave_count,
    v_unpaid_leave_count,
    v_total_regular_hours,
    v_total_overtime_hours
  from public.staff_attendance_v630 att
  where att.tenant_id = p_tenant_id
    and (p_location_id is null or att.location_id = p_location_id)
    and att.work_date >= v_from_date;

  if v_total_attendance_records > 0 then
    v_attendance_rate_pct := round(
      ((v_present_count + (0.5 * v_half_day_count)) / v_total_attendance_records::numeric) * 100.0,
      1
    );
    v_absence_rate_pct := round((v_absent_count::numeric / v_total_attendance_records::numeric) * 100.0, 1);
    v_leave_rate_pct := round(
      ((v_paid_leave_count + v_unpaid_leave_count)::numeric / v_total_attendance_records::numeric) * 100.0,
      1
    );
  else
    v_attendance_rate_pct := 100.0;
    v_absence_rate_pct := 0.0;
    v_leave_rate_pct := 0.0;
  end if;

  if v_total_regular_hours > 0 then
    v_overtime_ratio_pct := round((v_total_overtime_hours / v_total_regular_hours) * 100.0, 1);
  else
    v_overtime_ratio_pct := 0.0;
  end if;

  -- Daily attendance trends
  select coalesce(jsonb_agg(d), '[]'::jsonb)
  into v_daily_attendance_trends
  from (
    select
      att.work_date,
      count(*) filter (where att.status = 'present') as present,
      count(*) filter (where att.status = 'half_day') as half_day,
      count(*) filter (where att.status = 'absent') as absent,
      count(*) filter (where att.status in ('paid_leave', 'unpaid_leave')) as on_leave,
      coalesce(round(sum(att.hours), 1), 0.0) as regular_hours,
      coalesce(round(sum(att.overtime_hours), 1), 0.0) as overtime_hours
    from public.staff_attendance_v630 att
    where att.tenant_id = p_tenant_id
      and (p_location_id is null or att.location_id = p_location_id)
      and att.work_date >= v_from_date
    group by att.work_date
    order by att.work_date asc
    limit 30
  ) d;

  -- --------------------------------------------------------------------------
  -- 6. Shift & Cashier Staffing Intelligence
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where cs.status = 'open'),
    count(*) filter (where cs.status = 'closed'),
    coalesce(round(avg(extract(epoch from (coalesce(cs.closed_at, now()) - cs.opened_at))) / 3600.0, 1), 0.0),
    count(*) filter (where abs(coalesce(cs.difference, 0)) > 50.0)
  into
    v_total_shifts,
    v_open_shifts,
    v_closed_shifts,
    v_avg_shift_hours,
    v_shift_discrepancy_count
  from public.cashier_shifts cs
  where cs.tenant_id = p_tenant_id
    and (p_location_id is null or cs.location_id = p_location_id)
    and cs.opened_at >= v_from_ts;

  -- Daily shift breakdown
  select coalesce(jsonb_agg(s), '[]'::jsonb)
  into v_daily_shifts
  from (
    select
      cs.opened_at::date as shift_date,
      count(*) as shift_count,
      count(distinct cs.user_id) as active_cashiers,
      coalesce(round(avg(extract(epoch from (coalesce(cs.closed_at, now()) - cs.opened_at))) / 3600.0, 1), 0.0) as avg_duration_hours,
      count(*) filter (where abs(coalesce(cs.difference, 0)) > 50.0) as discrepancies
    from public.cashier_shifts cs
    where cs.tenant_id = p_tenant_id
      and (p_location_id is null or cs.location_id = p_location_id)
      and cs.opened_at >= v_from_ts
    group by cs.opened_at::date
    order by cs.opened_at::date asc
    limit 30
  ) s;

  -- --------------------------------------------------------------------------
  -- 7. Workforce Demand & Capacity Intelligence
  -- --------------------------------------------------------------------------
  -- Total sales transactions in window
  select count(*)
  into v_total_sales
  from public.sales s
  where s.tenant_id = p_tenant_id
    and s.created_at >= v_from_ts
    and s.status in ('completed', 'posted');

  -- Total purchase orders in window
  select count(*)
  into v_total_pos
  from public.purchase_orders_v480 po
  where po.tenant_id = p_tenant_id
    and (p_location_id is null or po.location_id = p_location_id)
    and po.created_at >= v_from_ts;

  -- Total stock transfers in window
  select count(*)
  into v_total_transfers
  from public.stock_transfers st
  where st.tenant_id = p_tenant_id
    and (p_location_id is null or st.from_location_id = p_location_id or st.to_location_id = p_location_id)
    and st.created_at >= v_from_ts;

  if v_active_staff > 0 and v_period_days > 0 then
    v_avg_txns_per_staff_day := round(v_total_sales::numeric / (v_active_staff * v_period_days)::numeric, 1);
  else
    v_avg_txns_per_staff_day := 0.0;
  end if;

  -- Peak sales demand hours
  select coalesce(jsonb_agg(ph), '[]'::jsonb)
  into v_peak_demand_hours
  from (
    select
      extract(hour from s.created_at)::integer as hour_of_day,
      count(*) as sales_transactions
    from public.sales s
    where s.tenant_id = p_tenant_id
      and s.created_at >= v_from_ts
      and s.status in ('completed', 'posted')
    group by extract(hour from s.created_at)
    order by count(*) desc
    limit 6
  ) ph;

  -- --------------------------------------------------------------------------
  -- 8. Overtime & Workforce Cost Intelligence (Permission-Protected)
  -- --------------------------------------------------------------------------
  if v_can_view_payroll then
    select
      coalesce(round(sum(se.gross_amount), 2), 0.0),
      coalesce(round(sum(se.amount), 2), 0.0)
    into v_gross_workforce_earnings, v_net_workforce_earnings
    from public.staff_earnings_v630 se
    where se.tenant_id = p_tenant_id
      and (p_location_id is null or se.location_id = p_location_id)
      and se.earning_date >= v_from_date;

    select coalesce(round(sum(sp.amount), 2), 0.0)
    into v_total_payments_disbursed
    from public.staff_payments_v630 sp
    where sp.tenant_id = p_tenant_id
      and (p_location_id is null or sp.location_id = p_location_id)
      and sp.payment_date >= v_from_date;

    select coalesce(jsonb_agg(k), '[]'::jsonb)
    into v_earnings_by_kind
    from (
      select
        se.kind,
        count(*) as count,
        coalesce(round(sum(se.gross_amount), 2), 0.0) as gross_amount,
        coalesce(round(sum(se.amount), 2), 0.0) as net_amount
      from public.staff_earnings_v630 se
      where se.tenant_id = p_tenant_id
        and (p_location_id is null or se.location_id = p_location_id)
        and se.earning_date >= v_from_date
      group by se.kind
      order by sum(se.gross_amount) desc
    ) k;
  else
    v_gross_workforce_earnings := 0.0;
    v_net_workforce_earnings := 0.0;
    v_total_payments_disbursed := 0.0;
    v_earnings_by_kind := '[]'::jsonb;
  end if;

  -- --------------------------------------------------------------------------
  -- 9. Fair Branch Workforce Benchmarking
  -- --------------------------------------------------------------------------
  select coalesce(jsonb_agg(bb), '[]'::jsonb)
  into v_branch_benchmarks
  from (
    select
      loc.id as location_id,
      loc.name as location_name,
      loc.location_code as location_code,
      count(distinct sm.id) filter (where sm.active = true) as staff_count,
      count(distinct att.id) as attendance_records,
      case
        when count(distinct att.id) > 0 then
          round(((count(distinct att.id) filter (where att.status = 'present') + 0.5 * count(distinct att.id) filter (where att.status = 'half_day')) / count(distinct att.id)::numeric) * 100.0, 1)
        else 100.0
      end as attendance_rate_pct,
      coalesce(round(sum(att.hours), 1), 0.0) as regular_hours,
      coalesce(round(sum(att.overtime_hours), 1), 0.0) as overtime_hours,
      count(distinct cs.id) as cashier_shifts_count,
      case
        when (count(distinct att.id) + count(distinct cs.id)) >= 5 then 'sufficient'
        else 'low_volume'
      end as data_sufficiency
    from public.business_locations loc
    left join public.staff_members_v630 sm on sm.location_id = loc.id
    left join public.staff_attendance_v630 att on att.location_id = loc.id and att.work_date >= v_from_date
    left join public.cashier_shifts cs on cs.location_id = loc.id and cs.opened_at >= v_from_ts
    where loc.tenant_id = p_tenant_id and loc.active = true
    group by loc.id, loc.name, loc.location_code
    order by loc.name asc
  ) bb;

  -- --------------------------------------------------------------------------
  -- 10. Deterministic Workforce Risk & Anomaly Detection Rules
  -- --------------------------------------------------------------------------
  -- Rule 1: WF_ATTENDANCE_COVERAGE_DROP
  if v_active_staff > 0 and v_total_attendance_records >= 5 and (v_attendance_rate_pct < 75.0 or v_absence_rate_pct > 20.0) then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_ATTENDANCE_COVERAGE_DROP',
      'affected_process', 'workforce_attendance',
      'severity', case when v_attendance_rate_pct < 60.0 then 'critical' else 'warning' end,
      'title', 'Significant Drop in Workforce Attendance Coverage',
      'description', 'Attendance coverage rate contracted to ' || v_attendance_rate_pct || '% (Absence rate: ' || v_absence_rate_pct || '%).',
      'recommendation', 'Review branch staffing coverage, examine root causes of absences, and arrange relief coverage if required.',
      'route', '/staff',
      'evidence', jsonb_build_object(
        'attendance_rate_pct', v_attendance_rate_pct,
        'absence_rate_pct', v_absence_rate_pct,
        'absent_count', v_absent_count,
        'total_attendance_records', v_total_attendance_records
      )
    );
  end if;

  -- Rule 2: WF_OVERTIME_SPIKE
  if v_total_regular_hours >= 40.0 and v_overtime_ratio_pct > 25.0 then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_OVERTIME_SPIKE',
      'affected_process', 'workforce_overtime',
      'severity', 'warning',
      'title', 'Unusual Growth in Recorded Overtime Hours',
      'description', 'Overtime hours reached ' || v_total_overtime_hours || ' hrs (' || v_overtime_ratio_pct || '% of regular operating hours).',
      'recommendation', 'Investigate operational workload drivers and evaluate whether additional permanent staffing is more sustainable than ongoing overtime.',
      'route', '/staff',
      'evidence', jsonb_build_object(
        'total_overtime_hours', v_total_overtime_hours,
        'total_regular_hours', v_total_regular_hours,
        'overtime_ratio_pct', v_overtime_ratio_pct
      )
    );
  end if;

  -- Rule 3: WF_SHIFT_COVERAGE_GAP
  if v_total_sales >= 50 and v_total_shifts = 0 then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_SHIFT_COVERAGE_GAP',
      'affected_process', 'shift_management',
      'severity', 'critical',
      'title', 'Operating High Sales Volume Without Recorded Cashier Shifts',
      'description', v_total_sales || ' sales transactions were completed during the window, but 0 cashier shifts were logged.',
      'recommendation', 'Enforce cashier shift opening and closing protocols on POS terminals for complete cash and drawer accountability.',
      'route', '/pos',
      'evidence', jsonb_build_object(
        'completed_sales', v_total_sales,
        'recorded_shifts', v_total_shifts
      )
    );
  elsif v_shift_discrepancy_count >= 3 then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_SHIFT_COVERAGE_GAP',
      'affected_process', 'shift_management',
      'severity', 'warning',
      'title', 'Recurring Shift Cash Discrepancies Detected',
      'description', v_shift_discrepancy_count || ' closed cashier shift(s) exhibited drawer cash discrepancies > 50.',
      'recommendation', 'Audit shift closing declarations, cash drop compliance, and cashier handover protocols.',
      'route', '/pos',
      'evidence', jsonb_build_object(
        'discrepancy_count', v_shift_discrepancy_count,
        'total_shifts', v_total_shifts
      )
    );
  end if;

  -- Rule 4: WF_PEAK_DEMAND_UNDERSTAFFING
  if v_active_staff < 2 and (v_total_sales / v_period_days::numeric) >= 100.0 then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_PEAK_DEMAND_UNDERSTAFFING',
      'affected_process', 'workforce_capacity',
      'severity', 'warning',
      'title', 'High Transaction Volume Handled by Limited Staffing',
      'description', 'Daily sales velocity exceeds 100 txns/day with only ' || v_active_staff || ' active staff member(s) assigned.',
      'recommendation', 'Review staffing allocation against operating customer traffic to prevent cashier exhaustion and transaction processing delays.',
      'route', '/staff',
      'evidence', jsonb_build_object(
        'active_staff', v_active_staff,
        'daily_sales_txns', round(v_total_sales / v_period_days::numeric, 1)
      )
    );
  end if;

  -- Rule 5: WF_MISSING_ATTENDANCE_LOGS
  if v_active_staff >= 2 and v_total_attendance_records = 0 and v_period_days >= 7 then
    v_risks := v_risks || jsonb_build_object(
      'rule_code', 'WF_MISSING_ATTENDANCE_LOGS',
      'affected_process', 'workforce_compliance',
      'severity', 'info',
      'title', 'Missing Workforce Attendance Logging',
      'description', v_active_staff || ' staff members are active, but zero daily attendance records have been registered in the last ' || v_period_days || ' days.',
      'recommendation', 'Ensure store and branch managers log daily attendance in the Staff & Wages module.',
      'route', '/staff',
      'evidence', jsonb_build_object(
        'active_staff', v_active_staff,
        'evaluated_days', v_period_days,
        'attendance_records', v_total_attendance_records
      )
    );
  end if;

  -- --------------------------------------------------------------------------
  -- 11. Deterministic Overall Workforce Health & Score Calculation
  -- --------------------------------------------------------------------------
  v_workforce_score := 100.0;

  if v_active_staff > 0 and v_total_attendance_records >= 5 and v_attendance_rate_pct < 85.0 then
    v_workforce_score := v_workforce_score - least(25.0, (85.0 - v_attendance_rate_pct) * 0.8);
  end if;

  if v_overtime_ratio_pct > 20.0 then
    v_workforce_score := v_workforce_score - least(15.0, (v_overtime_ratio_pct - 20.0) * 0.5);
  end if;

  if v_active_staff >= 2 and v_total_attendance_records = 0 and v_period_days >= 7 then
    v_workforce_score := v_workforce_score - 15.0;
  end if;

  if v_total_sales >= 50 and v_total_shifts = 0 then
    v_workforce_score := v_workforce_score - 20.0;
  elsif v_shift_discrepancy_count > 0 then
    v_workforce_score := v_workforce_score - least(15.0, v_shift_discrepancy_count * 3.0);
  end if;

  -- Clamped bounded score [15.0, 100.0]
  v_workforce_score := round(least(100.0, greatest(15.0, v_workforce_score)), 1);

  if v_workforce_score >= 90.0 then
    v_health_status := 'optimal';
  elsif v_workforce_score >= 75.0 then
    v_health_status := 'acceptable';
  elsif v_workforce_score >= 50.0 then
    v_health_status := 'needs_attention';
  else
    v_health_status := 'critical_delay';
  end if;

  -- Data Freshness Metadata
  v_data_freshness := jsonb_build_object(
    'as_of', now(),
    'evaluated_days', v_period_days,
    'total_staff_evaluated', v_total_staff,
    'total_attendance_evaluated', v_total_attendance_records,
    'total_shifts_evaluated', v_total_shifts,
    'total_sales_evaluated', v_total_sales
  );

  -- Return Structured Intelligence Payload
  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'can_view_payroll', v_can_view_payroll,
    'summary', jsonb_build_object(
      'overall_workforce_score', v_workforce_score,
      'health_status', v_health_status,
      'active_workforce_count', v_active_staff,
      'attendance_rate_pct', v_attendance_rate_pct,
      'total_recorded_hours', v_total_regular_hours,
      'total_overtime_hours', v_total_overtime_hours,
      'overtime_ratio_pct', v_overtime_ratio_pct,
      'active_risks_count', jsonb_array_length(v_risks)
    ),
    'workforce_availability', jsonb_build_object(
      'total_staff', v_total_staff,
      'active_staff', v_active_staff,
      'inactive_staff', v_inactive_staff,
      'by_role', v_staff_by_role
    ),
    'attendance_intelligence', jsonb_build_object(
      'total_records', v_total_attendance_records,
      'present_count', v_present_count,
      'half_day_count', v_half_day_count,
      'absent_count', v_absent_count,
      'paid_leave_count', v_paid_leave_count,
      'unpaid_leave_count', v_unpaid_leave_count,
      'attendance_rate_pct', v_attendance_rate_pct,
      'absence_rate_pct', v_absence_rate_pct,
      'leave_rate_pct', v_leave_rate_pct,
      'daily_trends', v_daily_attendance_trends
    ),
    'shift_staffing', jsonb_build_object(
      'total_shifts', v_total_shifts,
      'open_shifts', v_open_shifts,
      'closed_shifts', v_closed_shifts,
      'avg_shift_hours', v_avg_shift_hours,
      'discrepancy_count', v_shift_discrepancy_count,
      'daily_shifts', v_daily_shifts
    ),
    'capacity_demand', jsonb_build_object(
      'avg_txns_per_staff_day', v_avg_txns_per_staff_day,
      'peak_demand_hours', v_peak_demand_hours,
      'workload_distribution', jsonb_build_object(
        'sales_transactions', v_total_sales,
        'purchase_orders', v_total_pos,
        'stock_transfers', v_total_transfers
      )
    ),
    'overtime_cost', jsonb_build_object(
      'can_view_payroll', v_can_view_payroll,
      'total_regular_hours', v_total_regular_hours,
      'total_overtime_hours', v_total_overtime_hours,
      'overtime_ratio_pct', v_overtime_ratio_pct,
      'gross_workforce_earnings', v_gross_workforce_earnings,
      'net_workforce_earnings', v_net_workforce_earnings,
      'total_payments_disbursed', v_total_payments_disbursed,
      'earnings_by_kind', v_earnings_by_kind
    ),
    'branch_benchmarks', v_branch_benchmarks,
    'risks', v_risks,
    'data_freshness', v_data_freshness
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. workforce_intelligence_diagnostic_scan_v830
-- ----------------------------------------------------------------------------
create or replace function public.workforce_intelligence_diagnostic_scan_v830(
  p_tenant_id uuid,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_wf_data jsonb;
  v_risks jsonb;
  v_findings_batch jsonb := '[]'::jsonb;
  v_r jsonb;
  v_ingest_res jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
begin
  -- Run workforce intelligence
  v_wf_data := public.workforce_intelligence_v830(
    p_tenant_id => p_tenant_id,
    p_location_id => p_location_id,
    p_days => 30
  );

  v_risks := v_wf_data->'risks';

  if v_risks is not null and jsonb_array_length(v_risks) > 0 then
    for v_r in select * from jsonb_array_elements(v_risks) loop
      v_findings_batch := v_findings_batch || jsonb_build_object(
        'engine', 'workforce',
        'category', 'workforce_risk',
        'severity', v_r->>'severity',
        'rule_code', v_r->>'rule_code',
        'detection_rule', 'Workforce Operational Intelligence: ' || (v_r->>'affected_process'),
        'title', v_r->>'title',
        'description', v_r->>'description',
        'affected_entity_type', 'workforce_process',
        'affected_entity_id', v_r->>'affected_process',
        'affected_record_ref', coalesce(v_r->>'affected_process', 'Workforce'),
        'location_id', p_location_id,
        'evidence', v_r->'evidence',
        'confidence', 0.95,
        'impacted_amount', 0.0,
        'recommended_action', jsonb_build_object(
          'action_type', 'workforce_review',
          'label', v_r->>'recommendation',
          'route', v_r->>'route'
        )
      );
    end loop;

    v_ingest_res := public.erp_intelligence_ingest_findings_v830(
      p_tenant_id => p_tenant_id,
      p_findings => v_findings_batch
    );

    v_inserted := coalesce((v_ingest_res->>'inserted')::integer, 0);
    v_updated := coalesce((v_ingest_res->>'updated')::integer, 0);
  end if;

  return jsonb_build_object(
    'success', true,
    'total_detected', coalesce(jsonb_array_length(v_risks), 0),
    'inserted', v_inserted,
    'updated', v_updated,
    'workforce_score', v_wf_data->'summary'->>'overall_workforce_score',
    'health_status', v_wf_data->'summary'->>'health_status'
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Register Release #714 (v8.3.8) in thq_schema_releases
-- ----------------------------------------------------------------------------
insert into public.thq_schema_releases (
  migration_no,
  schema_version,
  release_name,
  applied_at,
  notes
) values (
  714,
  'v8.3.8',
  'operations_intelligence_phase9_workforce',
  now(),
  'Phase 9 Workforce Intelligence Engine, attendance coverage, shift tracking, overtime ratios, payroll privacy, and Action Centre integration.'
)
on conflict (migration_no) do update set
  applied_at = now(),
  notes = excluded.notes;
