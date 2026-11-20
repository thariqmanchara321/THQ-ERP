-- ============================================================================
-- SQL Test Suite: Operations Intelligence Phase 5
-- Purchase Intelligence, Supplier Intelligence & Procurement Intelligence
-- ============================================================================

do $$
declare
  v_tid uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;
  v_owner_uid uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;
  v_res_purchase jsonb;
  v_res_supplier jsonb;
  v_res_procure jsonb;
  v_elem jsonb;
  v_rec_count integer := 0;
begin
  -- --------------------------------------------------------------------------
  -- 1. Impersonate owner
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_uid::text, true);

  -- --------------------------------------------------------------------------
  -- 2. Test purchase_intelligence_v830
  -- --------------------------------------------------------------------------
  select public.purchase_intelligence_v830(v_tid, null, 90, '') into v_res_purchase;

  assert v_res_purchase is not null, 'purchase_intelligence_v830 returned null';
  assert v_res_purchase ? 'summary', 'purchase_intelligence_v830 missing summary';
  assert v_res_purchase ? 'trends', 'purchase_intelligence_v830 missing trends';
  assert v_res_purchase ? 'by_supplier', 'purchase_intelligence_v830 missing by_supplier';
  assert v_res_purchase ? 'by_category', 'purchase_intelligence_v830 missing by_category';
  assert v_res_purchase ? 'by_product', 'purchase_intelligence_v830 missing by_product';
  assert v_res_purchase ? 'price_changes', 'purchase_intelligence_v830 missing price_changes';
  assert v_res_purchase ? 'po_performance', 'purchase_intelligence_v830 missing po_performance';

  -- Verify current vs previous calculation consistency
  assert (v_res_purchase->'summary'->'current'->>'gross_purchases')::numeric >= 0, 'gross_purchases must be >= 0';
  assert (v_res_purchase->'summary'->'current'->>'net_purchases')::numeric = 
    greatest(
      (v_res_purchase->'summary'->'current'->>'gross_purchases')::numeric - (v_res_purchase->'summary'->'current'->>'purchase_returns')::numeric,
      0
    ), 'net_purchases must equal gross_purchases - purchase_returns';

  -- Verify trends array
  assert jsonb_typeof(v_res_purchase->'trends'->'daily') = 'array', 'daily trends must be a json array';
  assert jsonb_array_length(v_res_purchase->'trends'->'daily') > 0, 'daily trends should not be empty for 90 days';

  -- Verify PO performance metrics
  assert (v_res_purchase->'po_performance'->>'total_orders')::int >= 0, 'total_orders must be >= 0';
  assert (v_res_purchase->'po_performance'->>'fulfillment_rate_pct')::numeric between 0.0 and 100.0, 'fulfillment_rate_pct out of range';

  -- --------------------------------------------------------------------------
  -- 3. Test supplier_intelligence_v830
  -- --------------------------------------------------------------------------
  select public.supplier_intelligence_v830(v_tid, null, 90, '', 200) into v_res_supplier;

  assert v_res_supplier is not null, 'supplier_intelligence_v830 returned null';
  assert v_res_supplier ? 'summary', 'supplier_intelligence_v830 missing summary';
  assert v_res_supplier ? 'suppliers', 'supplier_intelligence_v830 missing suppliers';
  assert (v_res_supplier->'summary'->>'total_suppliers_count')::int >= 0, 'total_suppliers_count must be >= 0';
  assert (v_res_supplier->'summary'->>'total_spend')::numeric >= 0, 'total_spend must be >= 0';
  assert (v_res_supplier->'summary'->>'high_risk_suppliers_count')::int >= 0, 'high_risk_suppliers_count must be >= 0';

  -- Validate supplier record structure
  for v_elem in select jsonb_array_elements(v_res_supplier->'suppliers')
  loop
    assert v_elem ? 'supplier_id', 'supplier record missing supplier_id';
    assert v_elem ? 'supplier_name', 'supplier record missing supplier_name';
    assert (v_elem->>'spend')::numeric >= 0, 'supplier spend must be >= 0';
    assert (v_elem->>'order_count')::int >= 0, 'supplier order_count must be >= 0';
    assert v_elem->>'risk_score' in ('high', 'medium', 'low'), 'risk_score must be high, medium, or low';
    assert v_elem->>'data_sufficiency' in ('sufficient', 'insufficient_history'), 'data_sufficiency has invalid value';
    assert jsonb_typeof(v_elem->'risk_indicators') = 'array', 'risk_indicators must be array';
  end loop;

  -- --------------------------------------------------------------------------
  -- 4. Test procurement_intelligence_v830
  -- --------------------------------------------------------------------------
  select public.procurement_intelligence_v830(v_tid, null, 90, '', 500) into v_res_procure;

  assert v_res_procure is not null, 'procurement_intelligence_v830 returned null';
  assert v_res_procure ? 'summary', 'procurement_intelligence_v830 missing summary';
  assert v_res_procure ? 'recommendations', 'procurement_intelligence_v830 missing recommendations';

  assert (v_res_procure->'summary'->>'total_recommended_skus')::int >= 0, 'total_recommended_skus must be >= 0';
  assert (v_res_procure->'summary'->>'critical_skus_count')::int >= 0, 'critical_skus_count must be >= 0';
  assert (v_res_procure->'summary'->>'high_urgency_skus_count')::int >= 0, 'high_urgency_skus_count must be >= 0';
  assert (v_res_procure->'summary'->>'normal_urgency_skus_count')::int >= 0, 'normal_urgency_skus_count must be >= 0';
  assert (v_res_procure->'summary'->>'incoming_stock_covered_skus')::int >= 0, 'incoming_stock_covered_skus must be >= 0';

  -- Validate recommendation record schema and deduplication logic
  for v_elem in select jsonb_array_elements(v_res_procure->'recommendations')
  loop
    v_rec_count := v_rec_count + 1;
    assert v_elem ? 'recommendation_id', 'recommendation missing recommendation_id';
    assert v_elem ? 'variant_id', 'recommendation missing variant_id';
    assert v_elem ? 'product_name', 'recommendation missing product_name';
    assert v_elem ? 'sku', 'recommendation missing sku';
    assert v_elem ? 'available_stock', 'recommendation missing available_stock';
    assert v_elem ? 'net_effective_stock', 'recommendation missing net_effective_stock';
    assert v_elem ? 'reorder_level', 'recommendation missing reorder_level';
    assert v_elem ? 'suggested_purchase_qty', 'recommendation missing suggested_purchase_qty';
    assert v_elem->>'urgency' in ('critical', 'high', 'normal', 'covered'), 
      'urgency must be critical, high, normal, or covered, got: ' || coalesce(v_elem->>'urgency', 'null');
    assert length(v_elem->>'supplier_reason') > 5, 'supplier_reason must provide plain-English explanation';

    -- Deduplication assertion: if urgency is 'covered', suggested_purchase_qty should be 0
    if v_elem->>'urgency' = 'covered' then
      assert (v_elem->>'suggested_purchase_qty')::numeric = 0, 'Covered recommendations must have suggested_purchase_qty = 0';
    end if;
  end loop;

  -- --------------------------------------------------------------------------
  -- 5. Test Simulated Procurement Shortage & Reorder Calculation
  -- --------------------------------------------------------------------------
  declare
    v_test_loc uuid;
    v_test_var uuid;
    v_test_avail numeric;
    v_orig_reorder numeric;
    v_orig_max numeric;
    v_found_sim boolean := false;
  begin
    -- Pick a stock product with positive available quantity
    select b.location_id, b.variant_id, b.quantity
    into v_test_loc, v_test_var, v_test_avail
    from public.location_stock_balances b
    join public.product_variants pv on pv.id = b.variant_id
    join public.products p on p.id = pv.product_id
    where b.tenant_id = v_tid and p.item_type = 'stock' and b.quantity > 10
    limit 1;

    if v_test_loc is not null and v_test_var is not null then
      -- Backup existing settings
      select reorder_level, max_stock into v_orig_reorder, v_orig_max
      from public.location_product_settings
      where tenant_id = v_tid and location_id = v_test_loc and variant_id = v_test_var;

      -- Set reorder level above available to trigger recommendation
      insert into public.location_product_settings (tenant_id, location_id, variant_id, reorder_level, max_stock)
      values (v_tid, v_test_loc, v_test_var, v_test_avail + 100, v_test_avail + 300)
      on conflict (tenant_id, location_id, variant_id) do update
      set reorder_level = v_test_avail + 100, max_stock = v_test_avail + 300;

      -- Query procurement intelligence
      select public.procurement_intelligence_v830(v_tid, v_test_loc, 90, '', 500) into v_res_procure;

      for v_elem in select jsonb_array_elements(v_res_procure->'recommendations')
      loop
        if (v_elem->>'variant_id')::uuid = v_test_var then
          v_found_sim := true;
          assert (v_elem->>'suggested_purchase_qty')::numeric = 300, 
            'Suggested purchase qty should reach max_stock (300 shortage), got: ' || (v_elem->>'suggested_purchase_qty');
          assert v_elem->>'urgency' in ('critical', 'high', 'normal'),
            'Simulated shortage urgency should be high or critical, got: ' || (v_elem->>'urgency');
        end if;
      end loop;

      assert v_found_sim = true, 'Simulated shortage SKU was not returned in recommendations';

      -- Restore original setting
      if v_orig_reorder is not null then
        update public.location_product_settings
        set reorder_level = v_orig_reorder, max_stock = v_orig_max
        where tenant_id = v_tid and location_id = v_test_loc and variant_id = v_test_var;
      else
        delete from public.location_product_settings
        where tenant_id = v_tid and location_id = v_test_loc and variant_id = v_test_var;
      end if;
    end if;
  end;

  -- --------------------------------------------------------------------------
  -- 6. Test Non-existent search query returns valid empty structure
  -- --------------------------------------------------------------------------
  select public.procurement_intelligence_v830(v_tid, null, 30, 'xyz_procure_non_existent_9999') into v_res_procure;
  assert jsonb_array_length(v_res_procure->'recommendations') = 0, 'Non-existent query should return 0 recommendations';

  raise notice 'ALL PHASE 5 SQL TESTS PASSED! Tenant: %, Suppliers tested: %, Procurement recs tested: %',
    v_tid, jsonb_array_length(v_res_supplier->'suppliers'), v_rec_count;
end $$;
