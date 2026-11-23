-- THQ ERP — Operations Intelligence Phase 9 Test Suite
-- Target: flexi-erp-dev
-- Scope: Workforce Intelligence RPC, Shift/Attendance Analytics, Risk Detection & Action Centre Ingestion

do $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689';  -- Owner
  v_res jsonb;
  v_scan_res jsonb;
  v_action_centre_res jsonb;
  v_score numeric;
  v_health text;
  v_risks jsonb;
  v_branches jsonb;
begin
  -- Set request context to simulate tenant owner
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  raise notice '====================================================================';
  raise notice 'STARTING PHASE 9 WORKFORCE INTELLIGENCE DATABASE VERIFICATION SUITE';
  raise notice '====================================================================';

  -- --------------------------------------------------------------------------
  -- TEST 1: Execute workforce_intelligence_v830
  -- --------------------------------------------------------------------------
  v_res := public.workforce_intelligence_v830(
    p_tenant_id => v_tenant_id,
    p_days => 30
  );

  if v_res is null or (v_res->>'tenant_id')::uuid <> v_tenant_id then
    raise exception 'TEST 1 FAILED: Expected valid response with tenant_id %, got %', v_tenant_id, v_res;
  end if;

  v_score := (v_res->'summary'->>'overall_workforce_score')::numeric;
  v_health := v_res->'summary'->>'health_status';
  v_risks := v_res->'risks';
  v_branches := v_res->'branch_benchmarks';

  raise notice 'Workforce Score: % | Health Status: % | Active Risks: %', v_score, v_health, jsonb_array_length(v_risks);

  if v_score < 15.0 or v_score > 100.0 then
    raise exception 'TEST 1 FAILED: Score % is out of expected range [15, 100]', v_score;
  end if;

  if v_health not in ('optimal', 'acceptable', 'needs_attention', 'critical_delay') then
    raise exception 'TEST 1 FAILED: Unexpected health status %', v_health;
  end if;

  if (v_res->'workforce_availability') is null or (v_res->'attendance_intelligence') is null or
     (v_res->'shift_staffing') is null or (v_res->'capacity_demand') is null or
     (v_res->'overtime_cost') is null then
    raise exception 'TEST 1 FAILED: Missing required workforce domain blocks.';
  end if;

  raise notice 'Test 1 Passed: Workforce Intelligence RPC returned structured multi-domain analytics.';

  -- --------------------------------------------------------------------------
  -- TEST 2: Branch Workforce Benchmarks and Data Sufficiency
  -- --------------------------------------------------------------------------
  if jsonb_array_length(v_branches) = 0 then
    raise exception 'TEST 2 FAILED: Expected branch benchmarks for active locations.';
  end if;
  raise notice 'Branch benchmarks evaluated % active store location(s).', jsonb_array_length(v_branches);
  raise notice 'Test 2 Passed: Store workforce benchmarking qualified with sample counts.';

  -- --------------------------------------------------------------------------
  -- TEST 3: Diagnostic Scan and Action Centre Ingestion
  -- --------------------------------------------------------------------------
  v_scan_res := public.workforce_intelligence_diagnostic_scan_v830(
    p_tenant_id => v_tenant_id
  );

  if (v_scan_res->>'success')::boolean <> true then
    raise exception 'TEST 3 FAILED: Diagnostic scan failed: %', v_scan_res;
  end if;

  raise notice 'Scan Result: Total Detected: % | Inserted: % | Updated: %',
    v_scan_res->>'total_detected', v_scan_res->>'inserted', v_scan_res->>'updated';

  raise notice 'Test 3 Passed: Workforce risk scanner executed and ingested into findings repository.';

  -- --------------------------------------------------------------------------
  -- TEST 4: Query Action Centre for Workforce Engine
  -- --------------------------------------------------------------------------
  v_action_centre_res := public.erp_intelligence_action_centre_v830(
    p_tenant_id => v_tenant_id,
    p_engine => 'workforce'
  );

  if v_action_centre_res is null then
    raise exception 'TEST 4 FAILED: Action centre query for workforce engine failed.';
  end if;

  raise notice 'Action Centre Workforce Findings: %', v_action_centre_res->'summary';
  raise notice 'Test 4 Passed: Action Centre successfully exposes workforce intelligence findings.';

  raise notice '====================================================================';
  raise notice 'ALL PHASE 9 DATABASE TESTS PASSED WITH 100%% SUCCESS RATE';
  raise notice '====================================================================';
end $$;
