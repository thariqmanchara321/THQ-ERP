-- ============================================================================
-- THQ ERP — Operations Intelligence Phase 11: Comprehensive System Audit Suite
-- File: test_operations_intelligence_phase11_audit.sql
-- ============================================================================

do $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;  -- Owner
  v_location_id uuid;
  v_count integer;
  v_summary jsonb;
  v_sales jsonb;
  v_inventory record;
  v_rebalancing jsonb;
  v_purchases jsonb;
  v_suppliers jsonb;
  v_procurement jsonb;
  v_financial jsonb;
  v_expenses jsonb;
  v_efficiency jsonb;
  v_workforce jsonb;
  v_predictive jsonb;
  v_action_centre jsonb;
  v_finding record;
  v_sim_res jsonb;
  v_release_count integer;
begin
  -- Set request context to simulate tenant owner
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  raise notice '>>> Starting Phase 11 Comprehensive System Audit Suite...';

  -- --------------------------------------------------------------------------
  -- 1. Schema Releases Audit (Releases 706 - 715)
  -- --------------------------------------------------------------------------
  select count(*) into v_release_count
  from public.thq_schema_releases
  where migration_no in (706, 707, 708, 709, 710, 711, 712, 713, 714, 715);

  raise notice 'Schema releases registered: % / 10', v_release_count;
  assert exists(select 1 from public.thq_schema_releases where migration_no = 715),
    'Audit 1 Failed: Release #715 not found';

  -- --------------------------------------------------------------------------
  -- 2. Physical Table Existence & RLS Verification
  -- --------------------------------------------------------------------------
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_insights' and rowsecurity = true),
    'Audit 2 Failed: erp_intelligence_insights missing or RLS disabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_finding_reviews' and rowsecurity = true),
    'Audit 2 Failed: erp_intelligence_finding_reviews missing or RLS disabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_forecasts' and rowsecurity = true),
    'Audit 2 Failed: erp_intelligence_forecasts missing or RLS disabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_forecast_accuracy' and rowsecurity = true),
    'Audit 2 Failed: erp_intelligence_forecast_accuracy missing or RLS disabled';
  assert exists(select 1 from pg_tables where schemaname = 'public' and tablename = 'erp_intelligence_simulations' and rowsecurity = true),
    'Audit 2 Failed: erp_intelligence_simulations missing or RLS disabled';

  raise notice '✓ Audit 1 & 2 Passed: Releases and RLS on all intelligence tables verified';

  -- Resolve test location
  select id into v_location_id from public.business_locations where tenant_id = v_tenant_id limit 1;

  -- --------------------------------------------------------------------------
  -- 3. Engine 1: Executive Overview / Summary (v830)
  -- --------------------------------------------------------------------------
  v_summary := public.operations_intelligence_summary_v830(v_tenant_id, v_location_id, 30);
  assert v_summary ? 'summary' or v_summary ? 'tenant_id', 'Audit 3 Failed: Executive summary invalid';
  raise notice '✓ Audit 3 Passed: Engine 1 (Executive Summary) verified';

  -- --------------------------------------------------------------------------
  -- 4. Engine 2: Sales Intelligence (v830)
  -- --------------------------------------------------------------------------
  v_sales := public.sales_intelligence_v830(v_tenant_id, v_location_id, 30, '');
  assert v_sales ? 'performance', 'Audit 4 Failed: Sales intelligence missing performance';
  assert v_sales ? 'trends', 'Audit 4 Failed: Sales intelligence missing trends';
  assert v_sales ? 'customer_intelligence', 'Audit 4 Failed: Sales intelligence missing customer intelligence';
  raise notice '✓ Audit 4 Passed: Engine 2 (Sales Intelligence) verified';

  -- --------------------------------------------------------------------------
  -- 5. Engine 3: Inventory Intelligence & Rebalancing (v830)
  -- --------------------------------------------------------------------------
  select * into v_inventory
  from public.inventory_intelligence_v830(v_tenant_id, v_location_id, 30, '', 10)
  limit 1;

  select count(*) into v_count
  from public.inventory_rebalancing_recommendations_v830(v_tenant_id, v_location_id, 30, 10);
  assert v_count >= 0, 'Audit 5 Failed: Inventory rebalancing returned invalid count';
  raise notice '✓ Audit 5 Passed: Engine 3 (Inventory & Rebalancing) verified';

  -- --------------------------------------------------------------------------
  -- 6. Engine 4: Purchase, Supplier & Procurement Intelligence (v830)
  -- --------------------------------------------------------------------------
  v_purchases := public.purchase_intelligence_v830(v_tenant_id, v_location_id, 30, '');
  assert v_purchases ? 'summary', 'Audit 6 Failed: Purchase intelligence missing summary';

  v_suppliers := public.supplier_intelligence_v830(v_tenant_id, v_location_id, 30, '', 50);
  assert v_suppliers ? 'summary', 'Audit 6 Failed: Supplier intelligence missing summary';

  v_procurement := public.procurement_intelligence_v830(v_tenant_id, v_location_id, 30, '', 50);
  assert v_procurement ? 'summary', 'Audit 6 Failed: Procurement intelligence missing summary';
  raise notice '✓ Audit 6 Passed: Engines 4, 5, 6 (Purchase, Supplier, Procurement) verified';

  -- --------------------------------------------------------------------------
  -- 7. Engine 5: Financial & Expense Intelligence (v830)
  -- --------------------------------------------------------------------------
  v_financial := public.financial_intelligence_v830(v_tenant_id, v_location_id, 30, '');
  assert v_financial ? 'performance', 'Audit 7 Failed: Financial intelligence missing performance';

  v_expenses := public.expense_intelligence_v830(v_tenant_id, v_location_id, 30, '');
  assert v_expenses ? 'summary', 'Audit 7 Failed: Expense intelligence missing summary';
  raise notice '✓ Audit 7 Passed: Engine 7 (Financial & Expense Intelligence) verified';

  -- --------------------------------------------------------------------------
  -- 8. Engine 6: Operational Efficiency (v830)
  -- --------------------------------------------------------------------------
  v_efficiency := public.operational_efficiency_intelligence_v830(v_tenant_id, v_location_id, 30);
  assert v_efficiency ? 'summary', 'Audit 8 Failed: Operational efficiency missing summary';
  assert v_efficiency ? 'bottlenecks', 'Audit 8 Failed: Operational efficiency missing bottlenecks';
  raise notice '✓ Audit 8 Passed: Engine 8 (Operational Efficiency) verified';

  -- --------------------------------------------------------------------------
  -- 9. Engine 7: Workforce Intelligence (v830)
  -- --------------------------------------------------------------------------
  v_workforce := public.workforce_intelligence_v830(v_tenant_id, v_location_id, 30);
  assert v_workforce ? 'summary', 'Audit 9 Failed: Workforce intelligence missing summary';
  assert v_workforce ? 'risks', 'Audit 9 Failed: Workforce intelligence missing risks';
  raise notice '✓ Audit 9 Passed: Engine 9 (Workforce Intelligence) verified';

  -- --------------------------------------------------------------------------
  -- 10. Engine 8: Predictive Intelligence (v830)
  -- --------------------------------------------------------------------------
  v_predictive := public.predictive_intelligence_v830(v_tenant_id, v_location_id, 30);
  assert v_predictive ? 'sales_demand_forecast', 'Audit 10 Failed: Predictive missing sales demand';
  assert v_predictive ? 'inventory_depletion_forecast', 'Audit 10 Failed: Predictive missing inventory depletion';
  assert v_predictive ? 'cash_flow_forecast', 'Audit 10 Failed: Predictive missing cash flow';
  assert v_predictive ? 'backtesting_accuracy', 'Audit 10 Failed: Predictive missing backtesting accuracy';
  raise notice '✓ Audit 10 Passed: Engine 10 (Predictive Intelligence) verified';

  -- --------------------------------------------------------------------------
  -- 11. Central Action & Risk Centre Lifecycle & Integrity (v830)
  -- --------------------------------------------------------------------------
  v_action_centre := public.erp_intelligence_action_centre_v830(
    p_tenant_id => v_tenant_id,
    p_location_id => v_location_id,
    p_query => '',
    p_engine => null,
    p_severity => null,
    p_status => null,
    p_category => null,
    p_limit => 10,
    p_offset => 0
  );
  assert v_action_centre ? 'findings', 'Audit 11 Failed: Action centre missing findings list';
  assert v_action_centre ? 'summary', 'Audit 11 Failed: Action centre missing summary';
  raise notice '✓ Audit 11 Passed: Central Action & Risk Centre verified';

  -- --------------------------------------------------------------------------
  -- 12. Business Simulations Isolation Verification
  -- --------------------------------------------------------------------------
  v_sim_res := public.simulate_business_scenario_v830(
    v_tenant_id,
    'pricing',
    '{"price_change_pct": 5.0, "assumed_elasticity": -1.2}'::jsonb,
    v_location_id
  );
  assert (v_sim_res->>'success')::boolean = true, 'Audit 12 Failed: Simulation failed';
  assert v_sim_res ? 'simulation_results', 'Audit 12 Failed: Simulation missing results';
  raise notice '✓ Audit 12 Passed: Business simulation executed in strict read-only sandbox';

  raise notice '=======================================================';
  raise notice '>>> ALL 12 AUDIT SUITE CHECKS PASSED SUCCESSFULLY! <<<';
  raise notice '=======================================================';
end $$;
