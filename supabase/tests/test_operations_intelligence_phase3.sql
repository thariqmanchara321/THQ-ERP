do $$
declare
  v_tid uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;
  v_owner_uid uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;
  v_staff_uid uuid := '00000000-0000-0000-0000-000000000002'::uuid;
  v_res jsonb;
  v_perf jsonb;
  v_trends jsonb;
  v_products jsonb;
  v_categories jsonb;
  v_cust jsonb;
  v_anomalies jsonb;
begin
  -- --------------------------------------------------------------------------
  -- Test 1: Impersonate Owner with Cost Visibility (90 days to encompass data)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_uid::text, true);

  select public.sales_intelligence_v830(v_tid, null, 90, '') into v_res;
  assert v_res is not null, 'sales_intelligence_v830 returned null for owner';
  assert (v_res->>'can_view_cost')::boolean = true, 'owner should have can_view_cost = true';

  v_perf := v_res->'performance';
  assert v_perf is not null, 'performance object is null';
  assert (v_perf->'current'->>'gross_sales')::numeric > 0, 'current gross sales should be > 0 for 90d';
  assert (v_perf->'current'->>'net_sales')::numeric > 0, 'current net sales should be > 0';
  assert (v_perf->'current'->>'order_count')::int > 0, 'current order count should be > 0';
  assert (v_perf->'current'->>'gross_profit')::numeric > 0, 'owner should see gross profit > 0';

  v_trends := v_res->'trends';
  assert jsonb_array_length(v_trends->'daily') = 90, 'daily trends should have 90 entries for 90d window';
  assert jsonb_array_length(v_trends->'weekly') > 0, 'weekly trends should have entries';
  assert jsonb_array_length(v_trends->'monthly') > 0, 'monthly trends should have entries';

  v_products := v_res->'products';
  assert jsonb_array_length(v_products->'best_selling') > 0, 'best_selling products should not be empty';
  assert jsonb_array_length(v_products->'highest_volume') > 0, 'highest_volume products should not be empty';

  v_categories := v_res->'categories';
  assert jsonb_array_length(v_categories) > 0, 'categories should not be empty';

  v_cust := v_res->'customer_intelligence';
  assert (v_cust->'summary'->>'total_active_customers')::int > 0, 'active customers should be > 0';
  assert jsonb_array_length(v_cust->'segments') > 0, 'customer segments should not be empty';
  assert jsonb_array_length(v_cust->'top_customers') > 0, 'top customers should not be empty';

  v_anomalies := v_res->'anomalies';
  assert v_anomalies is not null, 'anomalies array should not be null';

  -- --------------------------------------------------------------------------
  -- Test 2: Test Empty Dataset (0-day or future window) - verify zero-safety
  -- --------------------------------------------------------------------------
  select public.sales_intelligence_v830(v_tid, null, 1, 'non_existent_search_query_xyz') into v_res;
  assert v_res is not null, 'empty dataset returned null';
  assert (v_res->'performance'->'current'->>'net_sales')::numeric = 0, 'net sales should be 0';
  assert (v_res->'performance'->'current'->>'aov')::numeric = 0, 'aov should be 0 without divide by zero';
  assert jsonb_array_length(v_res->'products'->'best_selling') = 0, 'best selling should be empty';
  assert (v_res->'customer_intelligence'->'summary'->>'total_active_customers')::int = 0, 'active customers should be 0';

  -- --------------------------------------------------------------------------
  -- Test 3: Location Filtering
  -- --------------------------------------------------------------------------
  -- Query a location id from business locations
  declare
    v_loc_id uuid;
  begin
    select id into v_loc_id from public.business_locations where tenant_id = v_tid and active = true limit 1;
    if v_loc_id is not null then
      select public.sales_intelligence_v830(v_tid, v_loc_id, 90, '') into v_res;
      assert v_res is not null, 'location-filtered query returned null';
    end if;
  end;

  raise notice 'ALL SALES INTELLIGENCE SQL TESTS PASSED! Current net sales: %, Active customers: %, Categories: %',
    v_perf->'current'->>'net_sales',
    v_cust->'summary'->>'total_active_customers',
    jsonb_array_length(v_categories);
end $$;
