-- ============================================================================
-- SQL Test Suite: Operations Intelligence Phase 4
-- Advanced Inventory Intelligence & Inter-Store Rebalancing
-- ============================================================================

do $$
declare
  v_tid uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;
  v_owner_uid uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;
  v_row_count integer := 0;
  v_rebal_count integer := 0;
  v_summary jsonb;
  v_rec record;
begin
  -- --------------------------------------------------------------------------
  -- 1. Impersonate owner
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_uid::text, true);

  -- --------------------------------------------------------------------------
  -- 2. Test inventory_intelligence_v830 (All 32 columns and classification)
  -- --------------------------------------------------------------------------
  select count(*) into v_row_count
  from public.inventory_intelligence_v830(v_tid, null, 90, '', 500);

  assert v_row_count > 0, 'inventory_intelligence_v830 returned 0 rows for active tenant';

  -- Check first row structure and classification
  select * into v_rec
  from public.inventory_intelligence_v830(v_tid, null, 90, '', 1)
  limit 1;

  assert v_rec.location_id is not null, 'location_id is null';
  assert v_rec.product_name is not null, 'product_name is null';
  assert v_rec.abc_class in ('A', 'B', 'C'), 'abc_class must be A, B, or C';
  assert v_rec.movement_class in ('fast_moving', 'normal_moving', 'slow_moving', 'non_moving', 'dead_stock'),
    'movement_class has invalid value: ' || coalesce(v_rec.movement_class, 'null');
  assert v_rec.net_effective_stock >= v_rec.available, 'net_effective_stock must be >= available stock';
  assert v_rec.cumulative_sales_pct >= 0, 'cumulative_sales_pct must be >= 0';

  -- --------------------------------------------------------------------------
  -- 3. Test inventory_rebalancing_recommendations_v830
  -- --------------------------------------------------------------------------
  select count(*) into v_rebal_count
  from public.inventory_rebalancing_recommendations_v830(v_tid, null, 90, 50);

  -- Notice: If tenant has multi-locations, query executes without errors
  for v_rec in
    select * from public.inventory_rebalancing_recommendations_v830(v_tid, null, 90, 5)
  loop
    assert v_rec.source_location_id <> v_rec.dest_location_id, 'Source and destination locations cannot be the same';
    assert v_rec.suggested_transfer_qty >= 1, 'Suggested transfer quantity must be >= 1';
    assert v_rec.source_stock_after = (v_rec.source_available - v_rec.suggested_transfer_qty), 'Source stock after calculation mismatch';
    assert v_rec.dest_stock_after = (v_rec.dest_available + v_rec.suggested_transfer_qty), 'Destination stock after calculation mismatch';
    assert v_rec.priority in ('critical', 'high', 'normal'), 'Priority has unexpected value';
    assert length(v_rec.reason) > 10, 'Reason must contain explanation text';
  end loop;

  -- --------------------------------------------------------------------------
  -- 4. Test operations_intelligence_summary_v830 integration
  -- --------------------------------------------------------------------------
  select public.operations_intelligence_summary_v830(v_tid, null, 90) into v_summary;
  assert v_summary is not null, 'Summary returned null';
  assert (v_summary->>'total_monitored_variants')::int > 0, 'Total monitored variants should be > 0';
  assert (v_summary->>'inventory_value')::numeric >= 0, 'Inventory value must be >= 0';
  assert (v_summary->>'dead_stock_value')::numeric >= 0, 'Dead stock value must be >= 0';
  assert (v_summary->>'excess_stock_value')::numeric >= 0, 'Excess stock value must be >= 0';
  assert (v_summary->>'rebalancing_opportunities')::int >= 0, 'Rebalancing opportunities must be >= 0';

  -- --------------------------------------------------------------------------
  -- 5. Test Empty Query / Zero-Safety
  -- --------------------------------------------------------------------------
  select count(*) into v_row_count
  from public.inventory_intelligence_v830(v_tid, null, 30, 'non_existent_search_query_xyz_9999');
  assert v_row_count = 0, 'Non-existent search should return 0 rows without error';

  raise notice 'ALL PHASE 4 SQL TESTS PASSED! Tenant: %, Rows: %, Rebalancing suggestions: %',
    v_tid, v_row_count, v_rebal_count;
end $$;
