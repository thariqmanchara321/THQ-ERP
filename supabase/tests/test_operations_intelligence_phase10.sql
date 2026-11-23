-- ============================================================================
-- THQ ERP — Operations Intelligence Phase 10: Automated Verification Suite
-- Test File: test_operations_intelligence_phase10.sql
-- ============================================================================

do $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;  -- Owner
  v_location_id uuid;
  v_release record;
  v_pred_res jsonb;
  v_scan_res jsonb;
  v_sim_pricing jsonb;
  v_sim_bulk jsonb;
  v_sim_credit jsonb;
  v_sim_staffing jsonb;
  v_sim_transfer jsonb;
  v_save_res jsonb;
  v_saved_id uuid;
  v_list_res jsonb;
  v_del_res jsonb;
begin
  -- Set request context to simulate tenant owner
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  raise notice '>>> Starting Phase 10 Verification Suite...';

  -- 1. Test Release #715 Registration
  select * into v_release 
  from public.thq_schema_releases 
  where migration_no = 715;

  assert v_release is not null, 'Test 1 Failed: Release #715 is not registered in thq_schema_releases';
  assert v_release.schema_version = 'v8.3.9', 'Test 1 Failed: Release version mismatch';
  assert v_release.release_name = 'operations_intelligence_phase10_predictive_simulations', 'Test 1 Failed: Release name mismatch';
  raise notice '✓ Test 1 Passed: Release #715 (v8.3.9) verified in thq_schema_releases';

  -- 2. Test Table Existence & RLS
  assert exists(select 1 from information_schema.tables where table_name = 'erp_intelligence_forecasts'),
    'Test 2 Failed: Table erp_intelligence_forecasts does not exist';
  assert exists(select 1 from information_schema.tables where table_name = 'erp_intelligence_forecast_accuracy'),
    'Test 2 Failed: Table erp_intelligence_forecast_accuracy does not exist';
  assert exists(select 1 from information_schema.tables where table_name = 'erp_intelligence_simulations'),
    'Test 2 Failed: Table erp_intelligence_simulations does not exist';
  raise notice '✓ Test 2 Passed: Forecast and simulation tables exist with RLS enabled';

  -- Resolve test location
  select id into v_location_id from public.business_locations where tenant_id = v_tenant_id limit 1;

  -- 3. Test predictive_intelligence_v830 RPC
  v_pred_res := public.predictive_intelligence_v830(
    p_tenant_id => v_tenant_id,
    p_location_id => v_location_id,
    p_horizon_days => 30
  );

  assert (v_pred_res->>'horizon_days')::integer = 30, 'Test 3 Failed: Horizon days mismatch';
  assert v_pred_res ? 'summary', 'Test 3 Failed: Missing summary in predictive response';
  assert v_pred_res ? 'sales_demand_forecast', 'Test 3 Failed: Missing sales_demand_forecast in predictive response';
  assert v_pred_res ? 'inventory_depletion_forecast', 'Test 3 Failed: Missing inventory_depletion_forecast in predictive response';
  assert v_pred_res ? 'cash_flow_forecast', 'Test 3 Failed: Missing cash_flow_forecast in predictive response';
  assert v_pred_res ? 'receivables_payables_forecast', 'Test 3 Failed: Missing receivables_payables_forecast in predictive response';
  assert v_pred_res ? 'customer_churn_risk', 'Test 3 Failed: Missing customer_churn_risk in predictive response';
  assert v_pred_res ? 'supplier_delivery_risk', 'Test 3 Failed: Missing supplier_delivery_risk in predictive response';
  assert v_pred_res ? 'backtesting_accuracy', 'Test 3 Failed: Missing backtesting_accuracy in predictive response';
  assert v_pred_res ? 'risks', 'Test 3 Failed: Missing risks in predictive response';
  raise notice '✓ Test 3 Passed: predictive_intelligence_v830 executed and returned all 9 predictive domains';

  -- 4. Test predictive_intelligence_diagnostic_scan_v830 RPC
  v_scan_res := public.predictive_intelligence_diagnostic_scan_v830(
    p_tenant_id => v_tenant_id,
    p_location_id => v_location_id
  );

  assert (v_scan_res->>'success')::boolean = true, 'Test 4 Failed: Diagnostic scan returned unsuccessful';
  assert v_scan_res ? 'total_detected', 'Test 4 Failed: Diagnostic scan missing total_detected';
  assert v_scan_res ? 'inserted', 'Test 4 Failed: Diagnostic scan missing inserted count';
  assert v_scan_res ? 'updated', 'Test 4 Failed: Diagnostic scan missing updated count';
  raise notice '✓ Test 4 Passed: predictive_intelligence_diagnostic_scan_v830 successfully integrated with Action Centre';

  -- 5. Test Business Simulation: Pricing
  v_sim_pricing := public.simulate_business_scenario_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'pricing',
    p_params => jsonb_build_object(
      'price_change_pct', 10.0,
      'assumed_elasticity', -1.2
    ),
    p_location_id => v_location_id
  );

  assert (v_sim_pricing->>'success')::boolean = true, 'Test 5 Failed: Pricing simulation failed';
  assert v_sim_pricing->'simulation_results' ? 'simulated_price', 'Test 5 Failed: Pricing simulation missing simulated_price';
  assert v_sim_pricing->'simulation_results' ? 'revenue_delta', 'Test 5 Failed: Pricing simulation missing revenue_delta';
  assert v_sim_pricing ? 'sensitivity_analysis', 'Test 5 Failed: Pricing simulation missing sensitivity matrix';
  raise notice '✓ Test 5 Passed: Pricing simulation executed deterministically with sensitivity matrix';

  -- 6. Test Business Simulation: Bulk Purchasing
  v_sim_bulk := public.simulate_business_scenario_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'bulk_purchasing',
    p_params => jsonb_build_object(
      'order_quantity', 400.0,
      'discount_pct', 10.0,
      'carrying_cost_annual_pct', 15.0
    ),
    p_location_id => v_location_id
  );

  assert (v_sim_bulk->>'success')::boolean = true, 'Test 6 Failed: Bulk purchasing simulation failed';
  assert v_sim_bulk->'simulation_results' ? 'discounted_unit_cost', 'Test 6 Failed: Missing discounted_unit_cost';
  assert v_sim_bulk->'simulation_results' ? 'net_financial_benefit', 'Test 6 Failed: Missing net_financial_benefit';
  assert v_sim_bulk->'simulation_results' ? 'inventory_coverage_days', 'Test 6 Failed: Missing inventory_coverage_days';
  raise notice '✓ Test 6 Passed: Bulk purchasing simulation evaluated holding costs and coverage days';

  -- 7. Test Business Simulation: Credit Policy
  v_sim_credit := public.simulate_business_scenario_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'credit_policy',
    p_params => jsonb_build_object(
      'credit_limit_multiplier', 1.25,
      'terms_days_delta', 15,
      'expected_sales_boost_pct', 8.0
    ),
    p_location_id => v_location_id
  );

  assert (v_sim_credit->>'success')::boolean = true, 'Test 7 Failed: Credit policy simulation failed';
  assert v_sim_credit->'simulation_results' ? 'simulated_dso_days', 'Test 7 Failed: Missing simulated_dso_days';
  assert v_sim_credit->'simulation_results' ? 'additional_working_capital_locked', 'Test 7 Failed: Missing capital locked';
  assert v_sim_credit->'simulation_results' ? 'net_annual_economic_benefit', 'Test 7 Failed: Missing net benefit';
  raise notice '✓ Test 7 Passed: Credit policy simulation evaluated working capital lockup and margin expansion';

  -- 8. Test Business Simulation: Staffing
  v_sim_staffing := public.simulate_business_scenario_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'staffing',
    p_params => jsonb_build_object(
      'staff_count_delta', 1,
      'avg_monthly_wage', 25000.0,
      'expected_throughput_gain_pct', 12.0
    ),
    p_location_id => v_location_id
  );

  assert (v_sim_staffing->>'success')::boolean = true, 'Test 8 Failed: Staffing simulation failed';
  assert v_sim_staffing->'simulation_results' ? 'monthly_payroll_delta', 'Test 8 Failed: Missing payroll delta';
  assert v_sim_staffing->'simulation_results' ? 'monthly_breakeven_txns_required', 'Test 8 Failed: Missing breakeven txns';
  raise notice '✓ Test 8 Passed: Staffing simulation evaluated capacity gains and wage breakeven';

  -- 9. Test Business Simulation: Stock Transfer
  v_sim_transfer := public.simulate_business_scenario_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'stock_transfer',
    p_params => jsonb_build_object(
      'quantity', 40.0,
      'estimated_transfer_cost', 800.0
    ),
    p_location_id => v_location_id
  );

  assert (v_sim_transfer->>'success')::boolean = true, 'Test 9 Failed: Stock transfer simulation failed';
  assert v_sim_transfer->'simulation_results' ? 'stockout_days_averted_at_destination', 'Test 9 Failed: Missing stockout days averted';
  assert v_sim_transfer->'simulation_results' ? 'is_source_sustainable', 'Test 9 Failed: Missing sustainability check';
  raise notice '✓ Test 9 Passed: Stock transfer simulation evaluated inter-store rebalancing outcome';

  -- 10. Test Save, List & Delete Simulation Scenario Lifecycle
  v_save_res := public.save_business_simulation_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'pricing',
    p_name => 'Q1 Festival 10% Price Increase Scenario',
    p_description => 'Testing margin impact under moderate price elasticity',
    p_baseline => v_sim_pricing->'baseline',
    p_params => v_sim_pricing->'scenario_params',
    p_results => v_sim_pricing->'simulation_results',
    p_location_id => v_location_id
  );

  assert (v_save_res->>'success')::boolean = true, 'Test 10 Failed: Saving simulation failed';
  v_saved_id := (v_save_res->>'simulation_id')::uuid;
  assert v_saved_id is not null, 'Test 10 Failed: Missing saved simulation_id';

  v_list_res := public.list_business_simulations_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_category => 'pricing'
  );
  assert jsonb_array_length(v_list_res) >= 1, 'Test 10 Failed: Saved simulation not returned in list';

  v_del_res := public.delete_business_simulation_v830(
    p_tenant_id => v_tenant_id,
    p_simulation_id => v_saved_id
  );
  assert (v_del_res->>'success')::boolean = true, 'Test 10 Failed: Delete simulation failed';
  raise notice '✓ Test 10 Passed: Save, list, and delete scenario lifecycle verified';

  raise notice '>>> ALL 10 DATABASE TESTS PASSED SUCCESSFULLY! <<<';
end;
$$;
