-- ============================================================================
-- THQ ERP: Phase 11.1 Release Verification & Final Sign-Off Test Suite
-- ============================================================================

do $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;  -- Owner
  v_foreign_tenant_id uuid := gen_random_uuid();
  v_location_id uuid;
  v_pricing_res jsonb;
  v_bulk_res jsonb;
  v_credit_res jsonb;
  v_staff_res jsonb;
  v_transfer_res jsonb;
  v_sales_res jsonb;
  v_cust_credit_count int;
  v_pred_res jsonb;
  v_finding_id uuid;
  v_ingest_res jsonb;
  v_trans_res jsonb;
  v_audit_count int;
  v_second_scan_count int;
  v_initial_occurrence int;
  v_updated_occurrence int;
  v_denied_err text;
begin
  select id into v_location_id from public.business_locations where tenant_id = v_tenant_id limit 1;

  raise notice '>>> Starting Phase 11.1 Release Verification Suite...';

  -- --------------------------------------------------------------------------
  -- SCOPE C (PART 1): TENANT ISOLATION BOUNDARY ENFORCEMENT (DENIED CASE)
  -- --------------------------------------------------------------------------
  -- Without setting auth context, invoking RPC on tenant must fail with Access denied
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.sales_intelligence_v830(v_tenant_id, v_location_id, 30);
    raise exception 'Security Gate Failed: sales_intelligence_v830 did not reject unauthenticated tenant call';
  exception when others then
    if sqlerrm not like '%Access denied%' then
      raise exception 'Security Gate Failed: Expected Access denied, got: %', sqlerrm;
    end if;
  end;

  -- Calling with a random non-existent foreign tenant ID must also fail with Access denied
  begin
    perform public.operations_intelligence_summary_v830(v_foreign_tenant_id, null, 30);
    raise exception 'Security Gate Failed: Foreign tenant was not rejected';
  exception when others then
    if sqlerrm not like '%Access denied%' then
      raise exception 'Security Gate Failed: Expected Access denied for foreign tenant, got: %', sqlerrm;
    end if;
  end;

  raise notice '✓ Scope C (Part 1): Unauthenticated & foreign tenant access strictly rejected with Access denied';

  -- Now set authenticated owner session context
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  -- --------------------------------------------------------------------------
  -- SCOPE A: SIMULATION CATEGORIES VERIFICATION
  -- --------------------------------------------------------------------------
  -- 1. Pricing Simulation
  v_pricing_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'pricing',
    jsonb_build_object('price_change_pct', 10.0, 'assumed_elasticity', -1.2)
  );
  assert (v_pricing_res ? 'simulation_results' and (v_pricing_res->'simulation_results' ? 'simulated_price')),
    'Scope A Failed: Pricing simulation failed';

  -- 2. Bulk Purchasing Simulation
  v_bulk_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'bulk_purchasing',
    jsonb_build_object('order_quantity', 1000, 'discount_pct', 10.0)
  );
  assert (v_bulk_res ? 'simulation_results' and (v_bulk_res->'simulation_results' ? 'net_financial_benefit')),
    'Scope A Failed: Bulk purchasing simulation failed';

  -- 3. Credit Policy Simulation
  v_credit_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'credit_policy',
    jsonb_build_object('terms_days_delta', 15, 'expected_sales_boost_pct', 8.0)
  );
  assert (v_credit_res ? 'simulation_results' and (v_credit_res->'simulation_results' ? 'simulated_dso_days')),
    'Scope A Failed: Credit policy simulation failed';

  -- 4. Staffing Simulation
  v_staff_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'staffing',
    jsonb_build_object('staff_count_delta', 2, 'avg_monthly_wage', 25000.0)
  );
  assert (v_staff_res ? 'simulation_results' and (v_staff_res->'simulation_results' ? 'simulated_staff_count')),
    'Scope A Failed: Staffing simulation failed';

  -- 5. Stock Transfer / Rebalancing Simulation
  v_transfer_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'stock_transfer',
    jsonb_build_object('quantity', 75.0, 'estimated_transfer_cost', 1200.0)
  );
  assert (v_transfer_res ? 'simulation_results' and (v_transfer_res->'simulation_results' ? 'stockout_days_averted_at_destination')),
    'Scope A Failed: Stock transfer simulation failed';

  -- 6. Unsupported Category Rejection (capex_investment)
  begin
    perform public.simulate_business_scenario_v830(
      v_tenant_id,
      'capex_investment',
      jsonb_build_object('capex_amount', 500000)
    );
    raise exception 'Scope A Failed: Unsupported simulation category was not rejected';
  exception when others then
    if sqlerrm not like '%Unsupported simulation category%' then
      raise exception 'Scope A Failed: Unexpected error on unsupported category: %', sqlerrm;
    end if;
  end;

  raise notice '✓ Scope A (Simulation Categories Reconciliation): All 5 categories verified + invalid rejection confirmed';

  -- --------------------------------------------------------------------------
  -- SCOPE B: CUSTOMER INTELLIGENCE ARCHITECTURE VERIFICATION
  -- --------------------------------------------------------------------------
  -- 1. Sales & Customer Purchasing Intelligence
  v_sales_res := public.sales_intelligence_v830(v_tenant_id, v_location_id, 30);
  assert (v_sales_res ? 'customer_intelligence' 
      and (v_sales_res->'customer_intelligence' ? 'segments') 
      and (v_sales_res->'customer_intelligence' ? 'top_customers')),
    'Scope B Failed: customer_intelligence missing from sales_intelligence_v830';

  -- 2. Customer Credit & Receivables
  select count(*) into v_cust_credit_count
  from public.customer_credit_intelligence_v480(v_tenant_id, v_location_id, '', 100);
  assert v_cust_credit_count is not null, 'Scope B Failed: customer_credit query failed';

  -- 3. Predictive Customer Churn
  v_pred_res := public.predictive_intelligence_v830(v_tenant_id, v_location_id, 30);
  assert (v_pred_res ? 'customer_churn_risk'),
    'Scope B Failed: customer_churn_risk missing from predictive_intelligence_v830';

  raise notice '✓ Scope B (Customer Intelligence Architecture): Distributed customer intelligence verified across Sales, Financial, and Predictive engines';

  -- --------------------------------------------------------------------------
  -- SCOPE C (PART 2): RLS POLICIES & PERMISSION SEPARATION
  -- --------------------------------------------------------------------------
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_insights' and rowsecurity = true),
    'Scope C Failed: erp_intelligence_insights RLS not enabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_finding_reviews' and rowsecurity = true),
    'Scope C Failed: erp_intelligence_finding_reviews RLS not enabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_simulations' and rowsecurity = true),
    'Scope C Failed: erp_intelligence_simulations RLS not enabled';

  raise notice '✓ Scope C (Part 2): RLS enabled on all intelligence persistence tables';

  -- --------------------------------------------------------------------------
  -- SCOPE D: ACTION CENTRE LIFECYCLE, CONCURRENCY & DEDUPLICATION
  -- --------------------------------------------------------------------------
  -- Clean up any lingering test finding
  delete from public.erp_intelligence_insights where dedup_key = 'test_dedup_key_phase11_1';

  -- 1. Ingest test finding
  v_ingest_res := public.erp_intelligence_ingest_findings_v830(
    v_tenant_id,
    jsonb_build_array(
      jsonb_build_object(
        'engine', 'sales',
        'rule_code', 'VERIF_TEST_CHURN_RISK',
        'severity', 'high',
        'title', 'Release Verification Churn Finding',
        'description', 'Automated verification test for Phase 11.1',
        'affected_entity_type', 'customer',
        'affected_entity_id', gen_random_uuid()::text,
        'impacted_amount', 45000.0,
        'confidence', 0.92,
        'dedup_key', 'test_dedup_key_phase11_1'
      )
    )
  );

  select id, occurrence_count into v_finding_id, v_initial_occurrence
  from public.erp_intelligence_insights
  where tenant_id = v_tenant_id and dedup_key = 'test_dedup_key_phase11_1';

  assert v_finding_id is not null, 'Scope D Failed: Finding ingestion failed';

  -- 2. Valid Transition: new -> under_review
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    v_tenant_id,
    v_finding_id,
    'under_review',
    'Reviewing test finding for Phase 11.1 sign-off'
  );
  assert (v_trans_res->>'to_status') = 'under_review', 'Scope D Failed: Transition to under_review failed';

  -- 3. Valid Transition: under_review -> accepted
  v_trans_res := public.erp_intelligence_finding_transition_v830(
    v_tenant_id,
    v_finding_id,
    'accepted',
    'Action plan accepted'
  );
  assert (v_trans_res->>'to_status') = 'accepted', 'Scope D Failed: Transition to accepted failed';

  -- 4. Illegal Transition Rejection: accepted -> new (must raise exception)
  begin
    perform public.erp_intelligence_finding_transition_v830(
      v_tenant_id,
      v_finding_id,
      'new',
      'Illegal leap backwards'
    );
    raise exception 'Scope D Failed: Illegal state transition was not rejected';
  exception when others then
    if sqlerrm not like '%Invalid lifecycle transition%' then
      raise exception 'Scope D Failed: Unexpected error on invalid transition: %', sqlerrm;
    end if;
  end;

  -- 5. Deduplication & Idempotent Re-scan: updates existing finding without creating duplicate
  v_ingest_res := public.erp_intelligence_ingest_findings_v830(
    v_tenant_id,
    jsonb_build_array(
      jsonb_build_object(
        'engine', 'sales',
        'rule_code', 'VERIF_TEST_CHURN_RISK',
        'severity', 'high',
        'title', 'Release Verification Churn Finding (Updated)',
        'description', 'Re-scan update test',
        'affected_entity_type', 'customer',
        'impacted_amount', 50000.0,
        'confidence', 0.95,
        'dedup_key', 'test_dedup_key_phase11_1'
      )
    )
  );

  select count(*), max(occurrence_count) into v_second_scan_count, v_updated_occurrence
  from public.erp_intelligence_insights
  where tenant_id = v_tenant_id and dedup_key = 'test_dedup_key_phase11_1';

  assert v_second_scan_count = 1, 'Scope D Failed: Duplicate row created instead of updating existing dedup_key';
  assert v_updated_occurrence > v_initial_occurrence, 'Scope D Failed: Occurrence count was not incremented on re-scan';

  -- 6. Audit Trail Check: Review history preserved
  select count(*) into v_audit_count
  from public.erp_intelligence_finding_reviews
  where finding_id = v_finding_id;

  assert v_audit_count >= 2, 'Scope D Failed: Audit review entries missing';

  -- Clean up test records
  delete from public.erp_intelligence_finding_reviews where finding_id = v_finding_id;
  delete from public.erp_intelligence_insights where id = v_finding_id;

  raise notice '✓ Scope D (Action Centre Lifecycle & Deduplication): State machine, rejection guards, dedup, and audit history verified';
  raise notice '>>> ALL 4 SCOPES VERIFIED WITH ZERO DEFECTS <<<';
end $$;
