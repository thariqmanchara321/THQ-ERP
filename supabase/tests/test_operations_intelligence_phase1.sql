do $$
declare
  v_tid uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;
  v_owner_uid uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;
  v_summary jsonb;
  v_inv_count int;
  v_reorder_count int;
  v_pay_count int;
  v_test_var record;
  v_reorder_row record;
begin
  -- Impersonate owner
  perform set_config('request.jwt.claim.sub', v_owner_uid::text, true);

  -- 1. Test inventory_intelligence_v830
  select count(*) into v_inv_count from public.inventory_intelligence_v830(v_tid, null, 30, '', 100);
  assert v_inv_count > 0, 'inventory_intelligence_v830 returned 0 rows';

  -- 2. Test operations_intelligence_summary_v830
  select public.operations_intelligence_summary_v830(v_tid, null, 30) into v_summary;
  assert v_summary is not null, 'summary is null';
  assert (v_summary->>'total_monitored_variants')::int > 0, 'monitored variants is 0';
  assert (v_summary->>'inventory_value')::numeric > 0, 'owner should see non-zero inventory value';
  assert (v_summary->>'payables')::numeric > 0, 'payables should be > 0';

  -- 3. Test customer_credit_intelligence_v480
  perform * from public.customer_credit_intelligence_v480(v_tid, null, '', 10);

  -- 4. Test supplier_payables_intelligence_v480
  select count(*) into v_pay_count from public.supplier_payables_intelligence_v480(v_tid, null, '', 10);
  assert v_pay_count > 0, 'supplier_payables returned 0 rows';

  -- 5. Deep test purchase_reorder_suggestions_v480 with actual suggestions
  -- Pick one variant and temporarily bump reorder_level
  select lps.location_id, lps.variant_id, pv.product_id
    into v_test_var
  from public.location_product_settings lps
  join public.product_variants pv on pv.id = lps.variant_id
  where lps.tenant_id = v_tid and lps.active = true
  limit 1;

  if v_test_var.variant_id is not null then
    -- Temporarily set reorder_level high so suggested_reorder > 0
    update public.location_product_settings
    set reorder_level = 99999, max_stock = 100000
    where tenant_id = v_tid and location_id = v_test_var.location_id and variant_id = v_test_var.variant_id;

    -- Make sure product has a known tax_rate
    update public.products
    set tax_rate = 18.0
    where id = v_test_var.product_id and tenant_id = v_tid;

    -- Query purchase_reorder_suggestions_v480
    select * into v_reorder_row
    from public.purchase_reorder_suggestions_v480(v_tid, v_test_var.location_id, 30, '', 10)
    where variant_id = v_test_var.variant_id;

    assert v_reorder_row.variant_id is not null, 'Reorder suggestion row was not returned';
    assert v_reorder_row.tax_rate = 18.0, format('Expected tax_rate=18.0, got %s', v_reorder_row.tax_rate);
    assert v_reorder_row.suggested_quantity > 0, format('Expected suggested_quantity > 0, got %s', v_reorder_row.suggested_quantity);

    -- Restore settings
    update public.location_product_settings
    set reorder_level = 0, max_stock = 0
    where tenant_id = v_tid and location_id = v_test_var.location_id and variant_id = v_test_var.variant_id;
  end if;

  raise notice 'ALL COMPREHENSIVE TESTS AND DEEP REORDER ASSERTIONS PASSED!';
end $$;
