-- ============================================================================
-- THQ ERP — LIVE VERIFICATION SUITE: PRE-POSTING FULL EDITABILITY & FLOWS
-- Target Business: butterfly portal (a659b6de-885d-44ed-9fa7-93eefa7d47d2)
-- Zero-Touch Constraint: Tenzo Traders (0af96a25-2f04-44e2-a00f-5c4688f34238)
-- ============================================================================

create temp table if not exists test_results (
  step_num integer,
  test_name text,
  passed boolean,
  details text
);

truncate table test_results;

do $$
declare
  v_tenant_id uuid := 'a659b6de-885d-44ed-9fa7-93eefa7d47d2'::uuid; -- Butterfly Portal
  v_tenzo_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;  -- Tenzo Traders (ZERO-TOUCH)
  v_owner_id uuid := '2a2d0129-8756-4ad7-9998-a18844965670'::uuid;  -- Butterfly Owner UID
  v_location_id uuid := '296a7a42-067d-4213-9b1a-d1492458df6c'::uuid; -- bfly01
  v_variant_id uuid := '68d70e81-5468-4776-b62a-9f5fd292dcc6'::uuid;  -- m-sand
  v_cft_unit_id uuid := 'd762e0b2-041c-4916-9631-446cfe60785b'::uuid; -- CFT
  v_supplier_1 uuid := 'e96180f2-5aa6-4da3-8590-8d1b6289aab1'::uuid;  -- supplier-1
  v_supplier_2 uuid := 'cb03862d-94cb-4697-9bbb-76ac9648499e'::uuid;  -- supplier-2 (for divergence)
  v_vehicle_id uuid := '62c12367-cd0d-4152-bb80-10f26190aec3'::uuid;  -- KL9853A342
  v_device_id uuid := '91616e91-93a3-4b59-81b5-1e82794ba42c'::uuid;   -- Active registered client system

  -- Tenzo baseline counters
  v_tenzo_loads_pre integer;
  v_tenzo_purchases_pre integer;
  v_tenzo_sales_pre integer;
  v_tenzo_journals_pre integer;
  v_tenzo_stock_pre integer;
  v_tenzo_costs_pre integer;
  v_tenzo_events_pre integer;

  -- Tenzo post counters
  v_tenzo_loads_post integer;
  v_tenzo_purchases_post integer;
  v_tenzo_sales_post integer;
  v_tenzo_journals_post integer;
  v_tenzo_stock_post integer;
  v_tenzo_costs_post integer;
  v_tenzo_events_post integer;

  -- Workflow variables
  v_res jsonb;
  v_load_1_id uuid;
  v_load_1 public.aggregate_loads_v617%rowtype;
  v_load_1_t1 timestamptz;
  v_load_1_t2 timestamptz;
  v_purchase_id uuid;
  v_event_count integer;
  v_journal_balance numeric;
  v_stock_qty numeric;

  -- Concurrency test variables
  v_load_2_id uuid;
  v_load_2_t1 timestamptz;
  v_concurrency_caught boolean := false;
  v_immutable_edit_caught boolean := false;
  v_immutable_reopen_caught boolean := false;
  v_duplicate_post_caught boolean := false;

  -- Report test variables
  v_daily_report jsonb;
  v_ws_report jsonb;
  v_expense_report jsonb;

begin
  -- Snapshot Tenzo Traders baseline using database session role
  select count(*) into v_tenzo_loads_pre from public.aggregate_loads_v617 where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_purchases_pre from public.purchases where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_sales_pre from public.sales where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_journals_pre from public.journal_entries where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_stock_pre from public.stock_movements where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_costs_pre from public.material_load_costs_v630 where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_events_pre from public.aggregate_load_events_v617 where tenant_id = v_tenzo_id;

  -- --------------------------------------------------------------------------
  -- STEP 0: Set Authenticated Session to Butterfly Portal Owner
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);

  insert into test_results values (0, 'Tenzo Traders Baseline Guard', true,
    format('Tenzo records snapshotted: Loads=%s, Purchases=%s, Sales=%s, Journals=%s',
      v_tenzo_loads_pre, v_tenzo_purchases_pre, v_tenzo_sales_pre, v_tenzo_journals_pre));

  -- --------------------------------------------------------------------------
  -- Setup: Ensure product unit CFT and GST profile are attached in Butterfly Portal
  -- --------------------------------------------------------------------------
  insert into public.product_units_v481 (
    tenant_id, variant_id, unit_id, is_base, allow_purchase, allow_sale,
    is_default_purchase, is_default_sale, conversion_to_base, quantity_step,
    cutting_allowed, cutting_charge, active, settings
  ) values (
    v_tenant_id, v_variant_id, v_cft_unit_id,
    false, true, true, false, false, 1, 1, false, 0, true, '{}'::jsonb
  ) on conflict (tenant_id, variant_id, unit_id) do update set
    active = true, allow_purchase = true, allow_sale = true;

  perform public.gst_product_profile_save_v520(
    v_tenant_id, v_variant_id, 'goods', '2505', 'taxable', 5.0, 0, 0, false, false,
    'M-Sand test profile', current_date
  );

  -- --------------------------------------------------------------------------
  -- STEP 1: Inward Load Creation with Dimensional / Volumetric Calculation
  -- Dimensions: 12ft x 6ft x 4ft = 288 CFT (2.88 Brass).
  -- Weights: Gross 15,500 kg, Tare 5,500 kg, Net 10,000 kg.
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'create',
    p_data => jsonb_build_object(
      'request_id', 'req-live-test-' || gen_random_uuid()::text,
      'p_direction', 'inbound',
      'p_location_id', v_location_id,
      'p_variant_id', v_variant_id,
      'p_quantity', 288,
      'p_unit_code', 'CFT',
      'p_measurement_method', 'dimensions',
      'p_body_length_ft', 12,
      'p_body_width_ft', 6,
      'p_body_height_ft', 4,
      'p_calculated_cft', 288,
      'p_gross_weight_kg', 15500,
      'p_tare_weight_kg', 5500,
      'p_net_weight_kg', 10000,
      'p_vehicle_id', v_vehicle_id,
      'p_supplier_id', v_supplier_1,
      'p_source_name', 'Mukkam Quarry',
      'p_source_reference', 'DC-LIVE-001',
      'p_notes', 'Initial live verification load'
    )
  );

  v_load_1_id := (v_res->>'load_id')::uuid;
  if v_load_1_id is null then
    raise exception 'Step 1 Failed: Load creation returned null load_id';
  end if;

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.status <> 'draft' or v_load_1.quantity <> 288 or v_load_1.calculated_cft <> 288 then
    raise exception 'Step 1 Failed: Load properties mismatch (status=%s, qty=%s, cft=%s)',
      v_load_1.status, v_load_1.quantity, v_load_1.calculated_cft;
  end if;

  insert into test_results values (1, 'Inward Load Creation & Volumetric Calculation', true,
    format('Load %s created in draft. Qty=%s CFT (12x6x4), Net Weight=%s kg',
      v_load_1.load_number, v_load_1.quantity, v_load_1.net_weight_kg));

  -- --------------------------------------------------------------------------
  -- STEP 2: Draft Load Direct Edit & Recalculation
  -- Change Height to 5ft -> 12 x 6 x 5 = 360 CFT.
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'edit',
    p_data => jsonb_build_object(
      'load_id', v_load_1_id,
      'p_direction', 'inbound',
      'p_location_id', v_location_id,
      'p_variant_id', v_variant_id,
      'p_quantity', 360,
      'p_unit_code', 'CFT',
      'p_measurement_method', 'dimensions',
      'p_body_length_ft', 12,
      'p_body_width_ft', 6,
      'p_body_height_ft', 5,
      'p_calculated_cft', 360,
      'p_gross_weight_kg', 18000,
      'p_tare_weight_kg', 5500,
      'p_net_weight_kg', 12500,
      'p_vehicle_id', v_vehicle_id,
      'p_supplier_id', v_supplier_1,
      'p_source_name', 'Mukkam Quarry',
      'p_source_reference', 'DC-LIVE-001-REV',
      'p_notes', 'Draft load edited to 5ft height (360 CFT)'
    )
  );

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.quantity <> 360 or v_load_1.calculated_cft <> 360 or v_load_1.status <> 'draft' then
    raise exception 'Step 2 Failed: Draft edit did not persist (qty=%s, cft=%s, status=%s)',
      v_load_1.quantity, v_load_1.calculated_cft, v_load_1.status;
  end if;

  insert into test_results values (2, 'Draft Direct Edit & Dimensional Recalculation', true,
    format('Draft load updated: Qty=360 CFT, Net Weight=%s kg, Ref=%s',
      v_load_1.net_weight_kg, v_load_1.source_reference));

  -- --------------------------------------------------------------------------
  -- STEP 3: Load Confirmation (Transitions to Confirmed-Unbilled)
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'confirm',
    p_data => jsonb_build_object('load_id', v_load_1_id)
  );

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.status <> 'completed' or v_load_1.purchase_id is not null then
    raise exception 'Step 3 Failed: Load confirmation status mismatch (status=%s, purchase_id=%s)',
      v_load_1.status, v_load_1.purchase_id;
  end if;

  insert into test_results values (3, 'Load Confirmation to Confirmed-Unbilled', true,
    format('Load %s confirmed successfully. Status=completed, Unbilled (purchase_id=NULL)',
      v_load_1.load_number));

  -- --------------------------------------------------------------------------
  -- STEP 4: Confirmed-Unbilled Direct Editing (v722 Core Feature)
  -- Edit load while in 'completed' status BEFORE purchase billing is created.
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'edit',
    p_data => jsonb_build_object(
      'load_id', v_load_1_id,
      'p_direction', 'inbound',
      'p_location_id', v_location_id,
      'p_variant_id', v_variant_id,
      'p_quantity', 360,
      'p_unit_code', 'CFT',
      'p_measurement_method', 'dimensions',
      'p_body_length_ft', 12,
      'p_body_width_ft', 6,
      'p_body_height_ft', 5,
      'p_calculated_cft', 360,
      'p_gross_weight_kg', 18000,
      'p_tare_weight_kg', 5500,
      'p_net_weight_kg', 12500,
      'p_vehicle_id', v_vehicle_id,
      'p_supplier_id', v_supplier_1,
      'p_source_name', 'Mukkam North Pit',
      'p_source_reference', 'DC-CONFIRMED-EDIT-722',
      'p_notes', 'Confirmed load direct edit test'
    )
  );

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.source_reference <> 'DC-CONFIRMED-EDIT-722' or v_load_1.source_name <> 'Mukkam North Pit' then
    raise exception 'Step 4 Failed: Confirmed-unbilled direct edit did not persist fields';
  end if;

  -- Verify audit event 'edited_confirmed' was recorded
  select count(*) into v_event_count from public.aggregate_load_events_v617
  where tenant_id = v_tenant_id and load_id = v_load_1_id and event_type = 'edited_confirmed';
  if v_event_count = 0 then
    raise exception 'Step 4 Failed: edited_confirmed event was not audited in aggregate_load_events_v617';
  end if;

  insert into test_results values (4, 'Confirmed-Unbilled Direct Editing (v722)', true,
    format('Confirmed load edited directly before billing. Source=%s, Ref=%s, Audit event recorded',
      v_load_1.source_name, v_load_1.source_reference));

  -- --------------------------------------------------------------------------
  -- STEP 5: Explicit Reopen Flow (aggregate_load_reopen_v722)
  -- Reverts load back to 'draft', preserves audit trail with reason.
  -- --------------------------------------------------------------------------
  v_res := public.aggregate_load_reopen_v722(
    p_tenant_id => v_tenant_id,
    p_load_id => v_load_1_id,
    p_reason => 'Need to adjust driver allocation and measurement notes prior to billing'
  );

  if coalesce((v_res->>'reopened')::boolean, false) <> true then
    raise exception 'Step 5 Failed: aggregate_load_reopen_v722 did not return reopened=true';
  end if;

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.status <> 'draft' then
    raise exception 'Step 5 Failed: Load status was not reverted to draft (current: %s)', v_load_1.status;
  end if;

  -- Verify audit event 'reopened' was recorded
  select count(*) into v_event_count from public.aggregate_load_events_v617
  where tenant_id = v_tenant_id and load_id = v_load_1_id and event_type = 'reopened';
  if v_event_count = 0 then
    raise exception 'Step 5 Failed: reopened event was not audited in aggregate_load_events_v617';
  end if;

  insert into test_results values (5, 'Explicit Load Reopen Flow (v722)', true,
    format('Load %s reverted to draft with full audit trail and reason preservation', v_load_1.load_number));

  -- --------------------------------------------------------------------------
  -- STEP 6: Re-confirm Load for Billing
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'confirm',
    p_data => jsonb_build_object('load_id', v_load_1_id)
  );

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.status <> 'completed' then
    raise exception 'Step 6 Failed: Re-confirmation failed';
  end if;

  insert into test_results values (6, 'Load Re-confirmation', true,
    format('Load %s re-confirmed to completed status', v_load_1.load_number));

  -- --------------------------------------------------------------------------
  -- STEP 7: Authoritative Purchase Posting with Supplier Divergence & Quantity Tolerance
  -- Physical load was 360 CFT from supplier-1.
  -- Inward Bill is issued by supplier-2 for 350 CFT @ Rs 50/CFT (moisture tolerance).
  -- --------------------------------------------------------------------------
  v_load_1_t1 := v_load_1.updated_at;

  v_res := public.aggregate_load_purchase_create_v629(
    p_tenant_id => v_tenant_id,
    p_load_id => v_load_1_id,
    p_supplier_id => v_supplier_2, -- Divergent supplier
    p_supplier_invoice_number => 'BILL-LIVE-722-' || substr(gen_random_uuid()::text, 1, 6),
    p_purchase_date => current_date,
    p_due_date => current_date + 15,
    p_items => jsonb_build_array(
      jsonb_build_object(
        'variant_id', v_variant_id,
        'quantity', 350, -- Divergent billed quantity (350 vs physical 360)
        'unit_cost', 50.00,
        'unit_price', 50.00,
        'discount_amount', 0,
        'tax_rate', 5.0,
        'unit_id', v_cft_unit_id,
        'unit_code', 'CFT',
        'entered_unit_code', 'CFT',
        'invoice_description', 'M-Sand 350 CFT Divergent Bill'
      )
    ),
    p_additional_charges => 0,
    p_round_off => 0,
    p_initial_payment => 0,
    p_payment_method => 'cash',
    p_location_id => v_location_id,
    p_device_id => v_device_id,
    p_request_id => 'req-live-purchase-' || gen_random_uuid()::text,
    p_load_updated_at => v_load_1_t1 -- Fresh concurrency token
  );

  v_purchase_id := nullif(v_res->>'purchase_id', '')::uuid;
  if v_purchase_id is null then
    raise exception 'Step 7 Failed: Purchase posting failed: %', v_res::text;
  end if;

  select * into v_load_1 from public.aggregate_loads_v617 where id = v_load_1_id and tenant_id = v_tenant_id;
  if v_load_1.purchase_id is distinct from v_purchase_id or v_load_1.status <> 'completed' then
    raise exception 'Step 7 Failed: Purchase linkage mismatch on load';
  end if;

  -- Physical measurements MUST remain 360 CFT intact
  if v_load_1.quantity <> 360 or v_load_1.calculated_cft <> 360 then
    raise exception 'Step 7 Failed: Physical load measurements were altered by purchase billing';
  end if;

  -- Supplier divergence audit event must exist
  select count(*) into v_event_count from public.aggregate_load_events_v617
  where tenant_id = v_tenant_id and load_id = v_load_1_id and event_type = 'billing_supplier_divergence';
  if v_event_count = 0 then
    raise exception 'Step 7 Failed: billing_supplier_divergence was not audited';
  end if;

  -- Double-entry journal balance check: Debits must equal Credits
  select coalesce(sum(l.debit - l.credit), 0) into v_journal_balance
  from public.journal_lines l
  join public.journal_entries j on j.id = l.journal_entry_id
  where j.tenant_id = v_tenant_id and j.source_type = 'purchase' and j.source_id = v_purchase_id;

  if abs(v_journal_balance) > 0.001 then
    raise exception 'Step 7 Failed: Double-entry journal is unbalanced (delta=%s)', v_journal_balance;
  end if;

  -- Stock movements check
  select coalesce(sum(quantity_delta), 0) into v_stock_qty
  from public.stock_movements
  where tenant_id = v_tenant_id and reference_type = 'purchase' and reference_id = v_purchase_id;

  if v_stock_qty <= 0 then
    raise exception 'Step 7 Failed: Stock ledger movement not created';
  end if;

  insert into test_results values (7, 'Authoritative Purchase Posting with Divergence & Journals', true,
    format('Purchase %s created. Physical load (360 CFT) preserved, Billed 350 CFT to Supplier-2. Journal Balanced (delta=%s), Stock Inflow=%s',
      v_purchase_id, v_journal_balance, v_stock_qty));

  -- --------------------------------------------------------------------------
  -- STEP 8: Post-Posting Strict Immutability Guard
  -- Load is now posted and linked to a finalized Purchase.
  -- ALL edits and reopens MUST be strictly blocked.
  -- --------------------------------------------------------------------------
  -- 8a: Attempt Direct Edit
  begin
    perform public.aggregate_load_edit_v628(
      p_tenant_id => v_tenant_id,
      p_load_id => v_load_1_id,
      p_direction => 'inbound',
      p_location_id => v_location_id,
      p_variant_id => v_variant_id,
      p_quantity => 400,
      p_unit_code => 'CFT',
      p_measurement_method => 'manual',
      p_body_length_ft => null, p_body_width_ft => null, p_body_height_ft => null,
      p_gross_weight_kg => null, p_tare_weight_kg => null, p_net_weight_kg => null,
      p_vehicle_id => null, p_driver_id => null, p_supplier_id => null, p_customer_id => null,
      p_source_name => null, p_destination_name => null, p_source_reference => null,
      p_freight_mode => 'none', p_freight_amount => 0, p_capacity_override => false,
      p_capacity_override_reason => null, p_notes => 'Illegal edit attempt'
    );
  exception when others then
    v_immutable_edit_caught := true;
  end;

  if not v_immutable_edit_caught then
    raise exception 'Step 8a Failed: Post-posting edit was allowed!';
  end if;

  -- 8b: Attempt Reopen
  begin
    perform public.aggregate_load_reopen_v722(
      p_tenant_id => v_tenant_id,
      p_load_id => v_load_1_id,
      p_reason => 'Illegal reopen attempt'
    );
  exception when others then
    v_immutable_reopen_caught := true;
  end;

  if not v_immutable_reopen_caught then
    raise exception 'Step 8b Failed: Post-posting reopen was allowed!';
  end if;

  -- 8c: Attempt Duplicate Purchase Posting
  begin
    perform public.aggregate_load_purchase_create_v629(
      p_tenant_id => v_tenant_id,
      p_load_id => v_load_1_id,
      p_supplier_id => v_supplier_1,
      p_supplier_invoice_number => 'DUPLICATE-BILL',
      p_purchase_date => current_date,
      p_due_date => current_date + 15,
      p_items => jsonb_build_array(
        jsonb_build_object(
          'variant_id', v_variant_id, 'quantity', 350, 'unit_cost', 50.00, 'unit_price', 50.00,
          'discount_amount', 0, 'tax_rate', 5.0, 'unit_id', v_cft_unit_id, 'unit_code', 'CFT'
        )
      ),
      p_additional_charges => 0, p_round_off => 0, p_initial_payment => 0,
      p_payment_method => 'cash', p_location_id => v_location_id, p_device_id => v_device_id,
      p_request_id => 'req-dup-' || gen_random_uuid()::text
    );
  exception when others then
    v_duplicate_post_caught := true;
  end;

  if not v_duplicate_post_caught then
    raise exception 'Step 8c Failed: Duplicate purchase posting was allowed!';
  end if;

  insert into test_results values (8, 'Strict Post-Posting Immutability Enforced', true,
    'All illegal post-posting operations strictly blocked: Direct Edit (BLOCKED), Reopen (BLOCKED), Duplicate Purchase (BLOCKED)');

  -- --------------------------------------------------------------------------
  -- STEP 9: Concurrency Conflict Protection (v722 Token Detection)
  -- --------------------------------------------------------------------------
  v_res := public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'create',
    p_data => jsonb_build_object(
      'request_id', 'req-concur-' || gen_random_uuid()::text,
      'p_direction', 'inbound',
      'p_location_id', v_location_id,
      'p_variant_id', v_variant_id,
      'p_quantity', 100,
      'p_unit_code', 'CFT',
      'p_measurement_method', 'manual',
      'p_notes', 'Concurrency test load'
    )
  );
  v_load_2_id := (v_res->>'load_id')::uuid;

  -- Record timestamp t1
  select updated_at into v_load_2_t1 from public.aggregate_loads_v617 where id = v_load_2_id;

  -- Confirm the load
  perform public.material_load_workspace_v630(
    p_tenant_id => v_tenant_id,
    p_action => 'confirm',
    p_data => jsonb_build_object('load_id', v_load_2_id)
  );

  -- Now touch/edit the load behind the scenes (advancing updated_at > t1)
  perform pg_sleep(0.05);
  update public.aggregate_loads_v617
  set notes = 'Modified behind the scenes', updated_at = clock_timestamp()
  where id = v_load_2_id and tenant_id = v_tenant_id;

  -- Attempt to post purchase using the stale v_load_2_t1 token
  begin
    perform public.aggregate_load_purchase_create_v629(
      p_tenant_id => v_tenant_id,
      p_load_id => v_load_2_id,
      p_supplier_id => v_supplier_1,
      p_supplier_invoice_number => 'BILL-CONCURRENCY-TEST',
      p_purchase_date => current_date,
      p_due_date => current_date + 15,
      p_items => jsonb_build_array(
        jsonb_build_object(
          'variant_id', v_variant_id, 'quantity', 100, 'unit_cost', 50.00, 'unit_price', 50.00,
          'discount_amount', 0, 'tax_rate', 5.0, 'unit_id', v_cft_unit_id, 'unit_code', 'CFT'
        )
      ),
      p_additional_charges => 0, p_round_off => 0, p_initial_payment => 0,
      p_payment_method => 'cash', p_location_id => v_location_id, p_device_id => v_device_id,
      p_request_id => 'req-concur-post-' || gen_random_uuid()::text,
      p_load_updated_at => v_load_2_t1 -- Stale timestamp!
    );
  exception when others then
    if sqlerrm like '%modified in Material Yard after this purchase draft was opened%' then
      v_concurrency_caught := true;
    else
      raise exception 'Step 9 Unexpected Error: %', sqlerrm;
    end if;
  end;

  if not v_concurrency_caught then
    raise exception 'Step 9 Failed: Concurrency conflict with stale timestamp was not detected!';
  end if;

  insert into test_results values (9, 'Concurrency Conflict Detection (v722 Token Guard)', true,
    'Stale load_updated_at correctly triggered conflict exception preventing race condition');

  -- --------------------------------------------------------------------------
  -- STEP 10: Historical Paid/Due Accuracy & Reports Verification (v721, v720, v719)
  -- --------------------------------------------------------------------------
  -- Daily Detailed Accounts Report (v720)
  v_daily_report := public.daily_detailed_accounts_v720(
    p_tenant_id => v_tenant_id,
    p_from => current_date,
    p_to => current_date,
    p_location_id => v_location_id
  );

  if v_daily_report is null or not (v_daily_report ? 'reconciliation_status') or not (v_daily_report ? 'cash') then
    raise exception 'Step 10a Failed: Daily detailed report returned invalid payload';
  end if;

  -- Workspace General Ledger & Cash Rollup (v721 / v702)
  v_ws_report := public.accounting_workspace_v702(
    p_tenant_id => v_tenant_id,
    p_report => 'general_ledger',
    p_from => current_date - 30,
    p_to => current_date,
    p_location_id => null
  );

  if v_ws_report is null or not (v_ws_report ? 'rows') then
    raise exception 'Step 10b Failed: Accounting workspace general ledger returned invalid payload';
  end if;

  -- Advanced Expense Report (v719)
  v_expense_report := public.expenses_advanced_report_dataset_v719(
    p_tenant_id => v_tenant_id,
    p_from => current_date - 30,
    p_to => current_date,
    p_location_id => null
  );

  if v_expense_report is null or not (v_expense_report ? 'expenses') then
    raise exception 'Step 10c Failed: Expense advanced report returned invalid payload';
  end if;

  insert into test_results values (10, 'Accounting & Expense Reporting Execution (v719-v721)', true,
    format('All reports verified: Daily Detailed Accounts (v720), Accounting GL Workspace (v721), Advanced Expense Dataset (v719)'));

  -- --------------------------------------------------------------------------
  -- STEP 11: Tenzo Traders Zero-Touch Strict Verification
  -- --------------------------------------------------------------------------
  select count(*) into v_tenzo_loads_post from public.aggregate_loads_v617 where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_purchases_post from public.purchases where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_sales_post from public.sales where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_journals_post from public.journal_entries where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_stock_post from public.stock_movements where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_costs_post from public.material_load_costs_v630 where tenant_id = v_tenzo_id;
  select count(*) into v_tenzo_events_post from public.aggregate_load_events_v617 where tenant_id = v_tenzo_id;

  if v_tenzo_loads_pre <> v_tenzo_loads_post
     or v_tenzo_purchases_pre <> v_tenzo_purchases_post
     or v_tenzo_sales_pre <> v_tenzo_sales_post
     or v_tenzo_journals_pre <> v_tenzo_journals_post
     or v_tenzo_stock_pre <> v_tenzo_stock_post
     or v_tenzo_costs_pre <> v_tenzo_costs_post
     or v_tenzo_events_pre <> v_tenzo_events_post then
    raise exception 'CRITICAL SAFETY VIOLATION: Tenzo Traders was touched during verification! (Pre vs Post mismatch)';
  end if;

  insert into test_results values (11, 'Tenzo Traders Zero-Touch Absolute Invariance', true,
    format('ZERO CHANGES on Tenzo Traders: Loads delta=0 (%s), Purchases delta=0 (%s), Sales delta=0 (%s), Journals delta=0 (%s)',
      v_tenzo_loads_post, v_tenzo_purchases_post, v_tenzo_sales_post, v_tenzo_journals_post));

end $$;

select step_num, test_name, passed, details from test_results order by step_num;
