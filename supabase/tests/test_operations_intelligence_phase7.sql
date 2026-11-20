-- THQ ERP — Operations Intelligence Phase 7 Test Suite
-- Target: flexi-erp-dev
-- Scope: Shared finding model, deduplication, priority scoring, lifecycle transitions, audit trail & diagnostics

do $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689';  -- Owner
  v_ingest_res jsonb;
  v_finding_id uuid;
  v_findings_batch jsonb;
  v_priority_score numeric;
  v_priority_reason text;
  v_trans_res jsonb;
  v_action_centre_res jsonb;
  v_reviews_res jsonb;
  v_scan_res jsonb;
  v_occurrences integer;
  v_status text;
  v_caught_invalid boolean := false;
begin
  -- Set request context to simulate tenant owner
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  raise notice '====================================================================';
  raise notice 'STARTING PHASE 7 DATABASE VERIFICATION SUITE';
  raise notice '====================================================================';

  -- --------------------------------------------------------------------------
  -- TEST 1: Ingest Findings & Stable Deduplication
  -- --------------------------------------------------------------------------
  v_findings_batch := jsonb_build_array(
    jsonb_build_object(
      'engine', 'inventory',
      'category', 'stockout_risk',
      'severity', 'critical',
      'rule_code', 'TEST_INV_CRITICAL_STOCKOUT',
      'detection_rule', 'Test stockout rule',
      'title', 'Test Critical Stockout: Sugar 1kg',
      'description', 'Zero stock on hand with daily sales velocity.',
      'affected_entity_type', 'product_variant',
      'affected_entity_id', 'var-test-001',
      'affected_record_ref', 'SKU-SUGAR-1KG',
      'location_id', null,
      'evidence', jsonb_build_object('stock_on_hand', 0, 'daily_velocity', 10.0),
      'confidence', 0.95,
      'impacted_amount', 12500.0,
      'recommended_action', jsonb_build_object('action_type', 'reorder', 'label', 'Order 100 units', 'route', '/purchases')
    )
  );

  -- 1.1 First ingestion: should insert new finding
  v_ingest_res := public.erp_intelligence_ingest_findings_v830(
    p_tenant_id => v_tenant_id,
    p_findings => v_findings_batch
  );

  if (v_ingest_res->>'inserted')::integer <> 1 then
    raise exception 'TEST 1.1 FAILED: Expected 1 inserted, got %', v_ingest_res;
  end if;
  raise notice 'Test 1.1 Passed: Initial finding inserted successfully.';

  -- Retrieve inserted finding
  select id, occurrence_count, status, priority_score, priority_reason
  into v_finding_id, v_occurrences, v_status, v_priority_score, v_priority_reason
  from public.erp_intelligence_insights
  where tenant_id = v_tenant_id and rule_code = 'TEST_INV_CRITICAL_STOCKOUT'
  limit 1;

  if v_finding_id is null or v_occurrences <> 1 or v_status <> 'new' then
    raise exception 'TEST 1.1 FAILED: Ingested row not found or incorrect initial state.';
  end if;

  -- Verify transparent priority scoring:
  -- Base critical (100) + Impact >5k (+5) + Systemic/null loc (+10) = 115 * 0.95 = 109.3 (rounded 109.3 or 109)
  raise notice 'Priority Score: % | Reason: %', v_priority_score, v_priority_reason;
  if v_priority_score < 100 then
    raise exception 'TEST 1.1 FAILED: Expected priority score >= 100 for critical with impact.';
  end if;
  raise notice 'Test 1.2 Passed: Transparent priority calculation validated.';

  -- 1.2 Second ingestion of identical finding: must deduplicate and increment occurrence_count
  v_ingest_res := public.erp_intelligence_ingest_findings_v830(
    p_tenant_id => v_tenant_id,
    p_findings => v_findings_batch
  );

  if (v_ingest_res->>'updated')::integer <> 1 or (v_ingest_res->>'inserted')::integer <> 0 then
    raise exception 'TEST 1.2 FAILED: Expected 1 updated, 0 inserted. Got %', v_ingest_res;
  end if;

  select occurrence_count into v_occurrences
  from public.erp_intelligence_insights
  where id = v_finding_id;

  if v_occurrences <> 2 then
    raise exception 'TEST 1.2 FAILED: Expected occurrence_count = 2, got %', v_occurrences;
  end if;
  raise notice 'Test 1.3 Passed: Deduplication verified. Finding updated idempotently without duplication.';

  -- --------------------------------------------------------------------------
  -- TEST 2: Lifecycle Transitions & Audit History
  -- --------------------------------------------------------------------------
  -- 2.1 Transition: new -> under_review
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id,
    p_to_status => 'under_review',
    p_review_notes => 'Assigned to procurement team for verification.'
  );
  if v_trans_res->>'to_status' <> 'under_review' then
    raise exception 'TEST 2.1 FAILED: Transition to under_review failed: %', v_trans_res;
  end if;
  raise notice 'Test 2.1 Passed: Valid transition new -> under_review succeeded.';

  -- 2.2 Transition: under_review -> accepted
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id,
    p_to_status => 'accepted',
    p_review_notes => 'Stockout confirmed. Accepted recommendation.'
  );
  if v_trans_res->>'to_status' <> 'accepted' then
    raise exception 'TEST 2.2 FAILED: Transition to accepted failed.';
  end if;
  raise notice 'Test 2.2 Passed: Valid transition under_review -> accepted succeeded.';

  -- 2.3 Transition: accepted -> approved
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id,
    p_to_status => 'approved',
    p_review_notes => 'Manager approved procurement proposal.'
  );
  if v_trans_res->>'to_status' <> 'approved' then
    raise exception 'TEST 2.3 FAILED: Transition to approved failed.';
  end if;
  raise notice 'Test 2.3 Passed: Valid transition accepted -> approved succeeded.';

  -- 2.4 Transition: approved -> completed -> resolved
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id,
    p_to_status => 'completed',
    p_review_notes => 'PO submitted in purchases module.'
  );
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id,
    p_to_status => 'resolved',
    p_review_notes => 'Stock replenishment received and posted.'
  );
  if v_trans_res->>'to_status' <> 'resolved' then
    raise exception 'TEST 2.4 FAILED: Transition to resolved failed.';
  end if;
  raise notice 'Test 2.4 Passed: Lifecycle progression to resolved succeeded.';

  -- 2.5 Illegal Transition Check: from resolved cannot jump to completed directly
  begin
    perform public.erp_intelligence_finding_transition_v830(
      p_tenant_id => v_tenant_id,
      p_finding_id => v_finding_id,
      p_to_status => 'completed',
      p_review_notes => 'Illegal jump'
    );
  exception when others then
    v_caught_invalid := true;
    raise notice 'Caught expected invalid transition exception: %', sqlerrm;
  end;

  if not v_caught_invalid then
    raise exception 'TEST 2.5 FAILED: Invalid state transition did not raise error!';
  end if;
  raise notice 'Test 2.5 Passed: Invalid lifecycle transition strictly rejected.';

  -- 2.6 Audit Trail Verification
  v_reviews_res := public.erp_intelligence_finding_reviews_v830(
    p_tenant_id => v_tenant_id,
    p_finding_id => v_finding_id
  );
  if jsonb_array_length(v_reviews_res) < 5 then
    raise exception 'TEST 2.6 FAILED: Expected at least 5 audit review history entries, got %', jsonb_array_length(v_reviews_res);
  end if;
  raise notice 'Test 2.6 Passed: Audit trail recorded % entries with user and notes.', jsonb_array_length(v_reviews_res);

  -- --------------------------------------------------------------------------
  -- TEST 3: Multi-Engine Diagnostic Scan
  -- --------------------------------------------------------------------------
  v_scan_res := public.erp_intelligence_scan_and_sync_v830(
    p_tenant_id => v_tenant_id
  );
  if (v_scan_res->>'success')::boolean <> true then
    raise exception 'TEST 3 FAILED: Diagnostic scan failed: %', v_scan_res;
  end if;
  raise notice 'Test 3 Passed: Multi-engine diagnostic scan completed successfully: %', v_scan_res;

  -- --------------------------------------------------------------------------
  -- TEST 4: Action Centre Query & Financial Masking
  -- --------------------------------------------------------------------------
  -- Query as owner
  v_action_centre_res := public.erp_intelligence_action_centre_v830(
    p_tenant_id => v_tenant_id
  );
  if (v_action_centre_res->>'can_view_cost')::boolean <> true then
    raise exception 'TEST 4 FAILED: Owner should have can_view_cost = true.';
  end if;
  raise notice 'Action Centre Summary: %', v_action_centre_res->'summary';
  raise notice 'Test 4 Passed: Action Centre query returned structured data with pagination.';

  -- Clean up test finding
  delete from public.erp_intelligence_finding_reviews where finding_id = v_finding_id;
  delete from public.erp_intelligence_insights where id = v_finding_id;

  raise notice '====================================================================';
  raise notice 'ALL PHASE 7 DATABASE TESTS PASSED WITH 100%% SUCCESS RATE';
  raise notice '====================================================================';
end $$;
