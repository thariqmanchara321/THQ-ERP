-- Comprehensive 20-Scenario Verification Matrix for THQ ERP GST / Non-GST Separation (v716)
-- Scenarios A through T as mandated by Master Task

do $matrix$
declare
  t uuid := gen_random_uuid();
  t2 uuid := gen_random_uuid();
  usr uuid := gen_random_uuid();
  membership uuid := gen_random_uuid();
  owner_role uuid;
  clerk_usr uuid := gen_random_uuid();
  clerk_membership uuid := gen_random_uuid();
  clerk_role uuid;
  loc1 uuid := gen_random_uuid();
  loc2 uuid := gen_random_uuid();
  dev1 uuid := gen_random_uuid();
  dev2 uuid := gen_random_uuid();
  cust1 uuid := gen_random_uuid();
  cust_interstate uuid := gen_random_uuid();
  sup1 uuid := gen_random_uuid();
  sup_gst uuid := gen_random_uuid();
  unit uuid := gen_random_uuid();
  prod_goods uuid := gen_random_uuid();
  var_goods uuid := gen_random_uuid();
  prod_exempt uuid := gen_random_uuid();
  var_exempt uuid := gen_random_uuid();
  reg1 uuid := gen_random_uuid();
  profile1 uuid := gen_random_uuid();
  profile_exempt uuid := gen_random_uuid();
  prod_rcm uuid := gen_random_uuid();
  var_rcm uuid := gen_random_uuid();
  profile_rcm uuid := gen_random_uuid();
  load_id uuid := gen_random_uuid();

  -- Execution tracking
  results jsonb := '{}'::jsonb;
  r jsonb;
  q jsonb;
  sale_a uuid;
  sale_b uuid;
  sale_g uuid;
  sale_h uuid;
  purch_c uuid;
  purch_i uuid;
  s_return_d uuid;
  p_return_e uuid;
  load_sale_f uuid;
  offline_sale_o uuid;
  req_id text;
  again jsonb;
  chk_count int;
  bad boolean;
  j_id uuid;
  imbalance numeric;
  detail jsonb;
begin
  begin -- Protected block for transaction isolation
    ----------------------------------------------------------------------------
    -- SETUP: Primary Tenant (Unregistered / Non-GST baseline)
    ----------------------------------------------------------------------------
    insert into public.tenants(id, name, slug, business_type)
    values(t, 'Matrix Test Store', 'matrix-' || t, 'material_yard');

    insert into auth.users(id, aud, role, email)
    values(usr, 'authenticated', 'authenticated', 'matrix-owner-' || usr || '@test.invalid');

    insert into public.tenant_memberships(id, tenant_id, user_id)
    values(membership, t, usr);

    select id into owner_role from public.roles where tenant_id = t and key = 'owner' limit 1;
    if owner_role is null then
      insert into public.roles(tenant_id, key, name) values(t, 'owner', 'Owner') returning id into owner_role;
    end if;
    insert into public.role_permissions(role_id, permission_key)
    select owner_role, key from public.permissions on conflict do nothing;
    insert into public.user_roles(tenant_id, membership_id, role_id)
    values(t, membership, owner_role);

    perform set_config('request.jwt.claim.sub', usr::text, true);
    perform private.v47_ensure_accounting_for_tenant(t);
    perform private.v491_ensure_financial_mappings(t);
    perform private.v628_seed_payment_methods(t);

    -- Setup Locations & Devices
    insert into public.business_locations(id, tenant_id, location_code, name, invoice_prefix, state, address_line1)
    values(loc1, t, 'LOC1-' || loc1, 'Main Location MH', 'MTH', 'Maharashtra', '100 Test Road, Mumbai');

    insert into public.business_locations(id, tenant_id, location_code, name, invoice_prefix, state, address_line1)
    values(loc2, t, 'LOC2-' || loc2, 'Branch Location GA', 'GAH', 'Goa', '200 Coastal Road, Panaji');

    insert into public.business_devices(id, tenant_id, location_id, device_code, name, app_type, status, invoice_prefix, allowed_modules)
    values(dev1, t, loc1, 'DEV1-' || dev1, 'POS Terminal 1', 'pos', 'active', 'MTH', '{sales,purchases}');

    insert into public.business_devices(id, tenant_id, location_id, device_code, name, app_type, status, invoice_prefix, allowed_modules)
    values(dev2, t, loc2, 'DEV2-' || dev2, 'Client Terminal 2', 'client', 'active', 'GAH', '{sales,purchases}');

    insert into public.business_user_app_access(tenant_id, user_id, app_key, enabled)
    values(t, usr, 'pos', true), (t, usr, 'client', true);
    insert into public.business_user_location_access(tenant_id, user_id, location_id, access_level)
    values(t, usr, loc1, 'manage'), (t, usr, loc2, 'manage');

    -- Setup Clerk (non-owner with operational sales & purchase permissions, NO GST permissions)
    insert into auth.users(id, aud, role, email)
    values(clerk_usr, 'authenticated', 'authenticated', 'matrix-clerk-' || clerk_usr || '@test.invalid');
    insert into public.tenant_memberships(id, tenant_id, user_id)
    values(clerk_membership, t, clerk_usr);
    insert into public.roles(tenant_id, key, name)
    values(t, 'op_clerk', 'Operational Clerk') returning id into clerk_role;
    insert into public.role_permissions(role_id, permission_key)
    values
      (clerk_role, 'sales.manage'), (clerk_role, 'sales.view'), (clerk_role, 'sales.return'),
      (clerk_role, 'purchases.manage'), (clerk_role, 'purchases.view'), (clerk_role, 'purchases.return'),
      (clerk_role, 'inventory.manage'), (clerk_role, 'inventory.view'),
      (clerk_role, 'aggregate_yard.manage'), (clerk_role, 'aggregate_yard.view'),
      (clerk_role, 'payments.receive');
    insert into public.user_roles(tenant_id, membership_id, role_id)
    values(t, clerk_membership, clerk_role);
    insert into public.business_user_app_access(tenant_id, user_id, app_key, enabled)
    values(t, clerk_usr, 'client', true), (t, clerk_usr, 'pos', true);
    insert into public.business_user_location_access(tenant_id, user_id, location_id, access_level)
    values(t, clerk_usr, loc1, 'manage');

    -- Setup Customers & Suppliers
    insert into public.customers(id, tenant_id, name, state, is_walk_in)
    values(cust1, t, 'Local Customer MH', 'Maharashtra', false);

    insert into public.customers(id, tenant_id, name, state, is_walk_in)
    values(cust_interstate, t, 'Interstate Customer KA', 'Karnataka', false);

    insert into public.suppliers(id, tenant_id, name, state)
    values(sup1, t, 'Local Non-GST Supplier', 'Maharashtra');

    insert into public.suppliers(id, tenant_id, name, state, tax_number)
    values(sup_gst, t, 'Registered GST Supplier', 'Maharashtra', '27ABCDE1234F1Z0');

    -- Setup Units & Products
    insert into public.inventory_units(id, tenant_id, code, name) values(unit, t, 'MTXUNIT', 'Matrix Unit');
    insert into public.inventory_units_v481(id, tenant_id, code, name) values(unit, t, 'MTXUNIT', 'Matrix Unit');

    -- Product 1: Standard Goods (catalogue tax_rate = 18%)
    insert into public.products(id, tenant_id, name, item_type, base_unit_id, tax_rate)
    values(prod_goods, t, 'Crushed Stone 20mm', 'stock', unit, 18);
    insert into public.product_variants(id, tenant_id, product_id, name, sku, cost_price, selling_price)
    values(var_goods, t, prod_goods, 'Standard 20mm', 'SKU-CS-20MM-' || var_goods, 40, 100);
    insert into public.product_units_v481(tenant_id, variant_id, unit_id, is_base, is_default_sale, is_default_purchase, allow_sale, allow_purchase)
    values(t, var_goods, unit, true, true, true, true, true);

    -- Product 2: Exempt Goods (0%)
    insert into public.products(id, tenant_id, name, item_type, base_unit_id, tax_rate)
    values(prod_exempt, t, 'Natural Soil Fill', 'stock', unit, 0);
    insert into public.product_variants(id, tenant_id, product_id, name, sku, cost_price, selling_price)
    values(var_exempt, t, prod_exempt, 'Standard Soil', 'SKU-SOIL-' || var_exempt, 20, 50);
    insert into public.product_units_v481(tenant_id, variant_id, unit_id, is_base, is_default_sale, is_default_purchase, allow_sale, allow_purchase)
    values(t, var_exempt, unit, true, true, true, true, true);

    -- Product 3: RCM Legal Service
    insert into public.products(id, tenant_id, name, item_type, base_unit_id, tax_rate)
    values(prod_rcm, t, 'Advocate Legal Service', 'service', unit, 18);
    insert into public.product_variants(id, tenant_id, product_id, name, sku, cost_price, selling_price)
    values(var_rcm, t, prod_rcm, 'Legal Advisory', 'SKU-RCM-' || var_rcm, 500, 500);
    insert into public.product_units_v481(tenant_id, variant_id, unit_id, is_base, is_default_purchase, allow_purchase)
    values(t, var_rcm, unit, true, true, true);

    perform public.inventory_location_assign_v4(t, loc1, var_goods, true, 100, 0, null);
    perform public.inventory_location_assign_v4(t, loc1, var_exempt, true, 50, 0, null);
    perform public.inventory_location_assign_v4(t, loc2, var_goods, true, 100, 0, null);

    perform public.inventory_adjust_stock(t, var_goods, 1000, 'Opening stock goods');
    insert into public.location_stock_balances(tenant_id, location_id, variant_id, quantity, average_cost)
    values(t, loc1, var_goods, 1000, 40)
    on conflict(tenant_id, location_id, variant_id) do update set quantity = 1000, average_cost = 40;

    perform public.inventory_adjust_stock(t, var_exempt, 1000, 'Opening stock exempt');
    insert into public.location_stock_balances(tenant_id, location_id, variant_id, quantity, average_cost)
    values(t, loc1, var_exempt, 1000, 20)
    on conflict(tenant_id, location_id, variant_id) do update set quantity = 1000, average_cost = 20;

    ----------------------------------------------------------------------------
    -- SCENARIO A: Non-GST Cash Sale
    ----------------------------------------------------------------------------
    -- Store is unregistered. Clerk executes cash sale for 10 units @ 100.
    perform set_config('request.jwt.claim.sub', clerk_usr::text, true);
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 10, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18)),
      '[{"method_code":"cash","amount":1000}]',
      'Scenario A Non-GST Cash Sale', loc1, dev1, req_id, null, null, '[]'
    );
    sale_a := (r->>'sale_id')::uuid;
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 1000 or abs(imbalance) > 0.005 then
      raise exception 'Scenario A Failed: tax_total=% grand_total=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
    end if;
    results := results || jsonb_build_object('scenario_A_nongst_cash_sale', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO B: Non-GST Credit Sale
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date + 30,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 5, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18)),
      '[{"method_code":"credit","amount":500}]',
      'Scenario B Non-GST Credit Sale', loc1, dev1, req_id, null, null, '[]'
    );
    sale_b := (r->>'sale_id')::uuid;
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 500 or abs(imbalance) > 0.005 then
      raise exception 'Scenario B Failed: tax_total=% grand_total=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
    end if;
    results := results || jsonb_build_object('scenario_B_nongst_credit_sale', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO C: Non-GST Purchase
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_purchase_create_v520(
      t, sup1, 'INV-SUP-001', current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 20, 'unit_cost', 40, 'discount_amount', 0, 'tax_rate', 0)),
      0, 0, 800, 'cash', null, 'Scenario C Purchase', loc1, dev1, req_id
    );
    purch_c := (r->>'purchase_id')::uuid;
    j_id := (select id from public.journal_entries where tenant_id = t and source_id = purch_c limit 1);

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_amount')::numeric <> 0 or (r->>'total_amount')::numeric <> 800 or abs(imbalance) > 0.005 then
      raise exception 'Scenario C Failed: tax_amount=% total_amount=% imbalance=%', r->>'tax_amount', r->>'total_amount', imbalance;
    end if;
    results := results || jsonb_build_object('scenario_C_nongst_purchase', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO D: Non-GST Sale Return
    ----------------------------------------------------------------------------
    declare
      si_id uuid;
    begin
      select id into si_id from public.sale_items where tenant_id = t and sale_id = sale_a limit 1;
      req_id := gen_random_uuid()::text;
      r := public.gst_sales_return_create_v520(
        t, sale_a, current_date,
        jsonb_build_array(jsonb_build_object('sale_item_id', si_id, 'quantity', 2, 'unit_price', 100, 'discount', 0)),
        'Damaged delivery', loc1, dev1, req_id
      );
      s_return_d := (r->>'sales_return_id')::uuid;
      j_id := (select id from public.journal_entries where tenant_id = t and source_id = s_return_d limit 1);

      select coalesce(sum(debit - credit), 0) into imbalance
      from public.journal_lines where journal_entry_id = j_id;

      if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 200 or abs(imbalance) > 0.005 then
        raise exception 'Scenario D Failed: tax_total=% grand_total=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
      end if;
      results := results || jsonb_build_object('scenario_D_nongst_sale_return', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO E: Non-GST Purchase Return
    ----------------------------------------------------------------------------
    declare
      pi_id uuid;
    begin
      select id into pi_id from public.purchase_items where tenant_id = t and purchase_id = purch_c limit 1;
      req_id := gen_random_uuid()::text;
      r := public.gst_purchase_return_create_v520(
        t, purch_c, current_date,
        jsonb_build_array(jsonb_build_object('purchase_item_id', pi_id, 'quantity', 5, 'unit_price', 40, 'discount', 0)),
        'Excess delivery return', loc1, dev1, req_id
      );
      p_return_e := (r->>'purchase_return_id')::uuid;
      j_id := (select id from public.journal_entries where tenant_id = t and source_id = p_return_e limit 1);

      select coalesce(sum(debit - credit), 0) into imbalance
      from public.journal_lines where journal_entry_id = j_id;

      if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 200 or abs(imbalance) > 0.005 then
        raise exception 'Scenario E Failed: tax_total=% grand_total=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
      end if;
      results := results || jsonb_build_object('scenario_E_nongst_purchase_return', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO F: Non-GST Material-Yard Load and Invoice
    ----------------------------------------------------------------------------
    insert into public.tenant_modules(tenant_id, module_key, enabled)
    values(t, 'aggregate_yard', true) on conflict(tenant_id, module_key) do update set enabled = true;

    insert into public.aggregate_loads_v617(
      id, tenant_id, load_number, direction, status, location_id, variant_id,
      product_name_snapshot, unit_code, quantity, customer_id, vehicle_registration_snapshot, driver_name_snapshot
    ) values(
      load_id, t, 'LOAD-TEST-' || load_id, 'outbound', 'completed', loc1, var_goods,
      'Crushed Stone 20mm', 'MTXUNIT', 15, cust1, 'MH-04-AB-1234', 'Ramesh Driver'
    );

    req_id := gen_random_uuid()::text;
    r := public.aggregate_load_sale_create_v630(
      t, load_id, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 15, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18)),
      '[{"method_code":"cash","amount":1500}]',
      'Scenario F Yard Load Invoice', loc1, dev1, req_id, null, null, '[]'
    );
    load_sale_f := (r->>'sale_id')::uuid;
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 1500 or abs(imbalance) > 0.005 then
      raise exception 'Scenario F Failed: tax_total=% grand_total=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
    end if;
    results := results || jsonb_build_object('scenario_F_nongst_material_yard_load', 'PASS');

    ----------------------------------------------------------------------------
    -- CONFIGURE GST REGISTRATION FOR GST SCENARIOS (G through L)
    ----------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', usr::text, true); -- Owner role
    insert into public.gst_tenant_tax_modes_v520(tenant_id, tax_mode, effective_from, reason)
    values(t, 'gst_registered', current_date, 'Matrix GST Testing')
    on conflict (tenant_id, effective_from) do update set tax_mode = 'gst_registered';

    perform private.gst_v520_ensure_accounts(t);

    insert into public.gst_registrations_v520(id, tenant_id, gstin, legal_name, state_code, address_line1)
    values(reg1, t, '27AAPFU0939F1ZV', 'Matrix Infotech & Stones LLP', '27', '100 Industrial Area, Mumbai');

    insert into public.gst_registration_versions_v520(tenant_id, registration_id, legal_name, registration_type, address_line1, effective_from, validation_status)
    values(t, reg1, 'Matrix Infotech & Stones LLP', 'regular', '100 Industrial Area, Mumbai', current_date, 'local_validated');

    insert into public.gst_location_registrations_v520(tenant_id, location_id, registration_id, effective_from)
    values(t, loc1, reg1, current_date);

    insert into public.gst_product_tax_profiles_v520(id, tenant_id, variant_id, supply_kind, hsn_sac, gst_rate, validation_status, effective_from)
    values(profile1, t, var_goods, 'goods', '25171010', 18, 'locally_validated', current_date);

    insert into public.gst_product_tax_profiles_v520(id, tenant_id, variant_id, supply_kind, hsn_sac, gst_rate, validation_status, effective_from)
    values(profile_exempt, t, var_exempt, 'goods', '25051000', 0, 'locally_validated', current_date);

    insert into public.gst_product_tax_profiles_v520(id, tenant_id, variant_id, supply_kind, hsn_sac, gst_rate, reverse_charge, validation_status, effective_from)
    values(profile_rcm, t, var_rcm, 'service', '998211', 18, true, 'locally_validated', current_date);

    insert into public.gst_party_registrations_v520(
      tenant_id, party_type, party_id, registration_type, gstin, state_code,
      legal_name, address_line1, validation_status, active, effective_from
    ) values(
      t, 'supplier', sup_gst, 'registered', '27ABCDE1234F1Z0', '27',
      'Registered GST Supplier', 'Supplier Address', 'local_validated', true, current_date
    );

    ----------------------------------------------------------------------------
    -- SCENARIO G: GST Intra-State Sale (CGST 9% + SGST 9%)
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 10, 'unit_price', 100, 'discount_amount', 0)),
      '[{"method_code":"cash","amount":1180}]',
      'Scenario G Intra-State Sale', loc1, dev1, req_id, 'B2C', '27', '[]'
    );
    sale_g := (r->>'sale_id')::uuid;
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 180 or (r->>'cgst')::numeric <> 90 or (r->>'sgst')::numeric <> 90 or (r->>'igst')::numeric <> 0 or (r->>'grand_total')::numeric <> 1180 or abs(imbalance) > 0.005 then
      raise exception 'Scenario G Failed: tax=% cgst=% sgst=% grand=%', r->>'tax_total', r->>'cgst', r->>'sgst', r->>'grand_total';
    end if;
    results := results || jsonb_build_object('scenario_G_gst_intra_state_sale', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO H: GST Inter-State Sale (IGST 18%)
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust_interstate, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 10, 'unit_price', 100, 'discount_amount', 0)),
      '[{"method_code":"cash","amount":1180}]',
      'Scenario H Inter-State Sale', loc1, dev1, req_id, 'B2C', '29', '[]'
    );
    sale_h := (r->>'sale_id')::uuid;
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 180 or (r->>'cgst')::numeric <> 0 or (r->>'sgst')::numeric <> 0 or (r->>'igst')::numeric <> 180 or (r->>'grand_total')::numeric <> 1180 or abs(imbalance) > 0.005 then
      raise exception 'Scenario H Failed: tax=% igst=% grand=%', r->>'tax_total', r->>'igst', r->>'grand_total';
    end if;
    results := results || jsonb_build_object('scenario_H_gst_inter_state_sale', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO I: GST Purchase with Eligible Input Tax
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_purchase_create_v520(
      t, sup_gst, 'GST-INV-889', current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 10, 'unit_cost', 40, 'discount_amount', 0)),
      0, 0, 472, 'cash', null, 'Scenario I GST Purchase', loc1, dev1, req_id, 'B2B', '27'
    );
    purch_i := (r->>'purchase_id')::uuid;
    j_id := (select id from public.journal_entries where tenant_id = t and source_id = purch_i limit 1);

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_amount')::numeric <> 72 or (r->>'total_amount')::numeric <> 472 or abs(imbalance) > 0.005 then
      raise exception 'Scenario I Failed: tax=% total=% imbalance=%', r->>'tax_amount', r->>'total_amount', imbalance;
    end if;
    results := results || jsonb_build_object('scenario_I_gst_eligible_input_tax_purchase', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO J: GST Credit / Debit Note (Sales Return under GST)
    ----------------------------------------------------------------------------
    declare
      si_g uuid;
    begin
      select id into si_g from public.sale_items where tenant_id = t and sale_id = sale_g limit 1;
      req_id := gen_random_uuid()::text;
      r := public.gst_sales_return_create_v520(
        t, sale_g, current_date,
        jsonb_build_array(jsonb_build_object('sale_item_id', si_g, 'quantity', 2, 'unit_price', 100, 'discount', 0)),
        'GST Credit Note Reversal', loc1, dev1, req_id
      );
      j_id := (select id from public.journal_entries where tenant_id = t and source_id = (r->>'sales_return_id')::uuid limit 1);

      select coalesce(sum(debit - credit), 0) into imbalance
      from public.journal_lines where journal_entry_id = j_id;

      if (r->>'tax_total')::numeric <> 36 or (r->>'cgst')::numeric <> 18 or (r->>'sgst')::numeric <> 18 or (r->>'grand_total')::numeric <> 236 or abs(imbalance) > 0.005 then
        raise exception 'Scenario J Failed: tax=% grand=% imbalance=%', r->>'tax_total', r->>'grand_total', imbalance;
      end if;
      results := results || jsonb_build_object('scenario_J_gst_credit_note', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO K: GST Reverse Charge (RCM Verification)
    ----------------------------------------------------------------------------
    -- Quote verification for RCM liability
    q := public.gst_document_quote_v520(
      t, 'purchase', loc1, sup_gst, current_date,
      'B2B', '27',
      jsonb_build_array(jsonb_build_object('variant_id', var_rcm, 'unit_id', unit, 'quantity', 1, 'unit_price', 1000, 'discount_amount', 0)),
      0, 0
    );
    if coalesce((q->'totals'->>'thq_rcm_tax_payable_total')::numeric, 0) <> 180
       or coalesce((q->'totals'->>'tax_collected_total')::numeric, 0) <> 0
       or (q->'totals'->>'grand_total')::numeric <> 1000 then
      raise exception 'Scenario K Failed: RCM quote expected 180 thq_rcm, 0 collected, 1000 total. Got: %', q->'totals';
    end if;
    results := results || jsonb_build_object('scenario_K_gst_reverse_charge', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO L: GST Exempt / Zero-Rated Transaction
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_exempt, 'unit_id', unit, 'quantity', 10, 'unit_price', 50, 'discount_amount', 0)),
      '[{"method_code":"cash","amount":500}]',
      'Scenario L Exempt Supply', loc1, dev1, req_id, 'B2C', '27', '[]'
    );
    j_id := (r->>'journal_id')::uuid;

    select coalesce(sum(debit - credit), 0) into imbalance
    from public.journal_lines where journal_entry_id = j_id;

    if (r->>'tax_total')::numeric <> 0 or (r->>'grand_total')::numeric <> 500 or abs(imbalance) > 0.005 then
      raise exception 'Scenario L Failed: tax_total=% grand_total=%', r->>'tax_total', r->>'grand_total';
    end if;
    results := results || jsonb_build_object('scenario_L_gst_exempt_zero_rated', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO M: GST Switch Transition with Historical Transactions
    ----------------------------------------------------------------------------
    insert into public.gst_tenant_tax_modes_v520(tenant_id, tax_mode, effective_from, effective_to, reason)
    values(t, 'non_gst', current_date - 30, current_date - 1, 'Historical unregistered operation');

    if private.gst_tax_mode_resolve_v520(t, current_date - 1) <> 'non_gst' then
      raise exception 'Scenario M Failed: Historical date before effective_from did not resolve non_gst';
    end if;
    detail := public.sales_get_detail_v630(t, sale_a);
    if detail->'gst'->>'tax_mode' <> 'non_gst' or (detail->'gst'->>'tax_collected_total')::numeric <> 0 then
      raise exception 'Scenario M Failed: Historical sale mutated after GST registration';
    end if;
    results := results || jsonb_build_object('scenario_M_gst_switch_transition', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO N: Multi-Location Business Isolation
    ----------------------------------------------------------------------------
    -- Location 1 has registration reg1 in Maharashtra.
    -- Location 2 is in Goa without mapping in gst_location_registrations_v520.
    q := public.sales_invoice_context_v632(t, loc2, dev2, current_date, null);
    if q->>'tax_mode' = 'gst_registered' and (q->>'gstin') is not null and q->>'gstin' = '27AAPFU0939F1ZV' then
      raise exception 'Scenario N Failed: Goa location improperly inherited Maharashtra location registration';
    end if;
    results := results || jsonb_build_object('scenario_N_multi_location_isolation', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO O: Offline POS Sync and Retry
    ----------------------------------------------------------------------------
    -- In Non-GST store, offline POS sync with 0 tax should never be rejected with TAX_CHANGED
    declare
      t_offline uuid := gen_random_uuid();
      loc_off uuid := gen_random_uuid();
      dev_off uuid := gen_random_uuid();
      cust_off uuid := gen_random_uuid();
      var_off uuid := gen_random_uuid();
      prod_off uuid := gen_random_uuid();
      unit_off uuid := gen_random_uuid();
      sync_res jsonb;
    begin
      insert into public.tenants(id, name, slug) values(t_offline, 'Offline Sync Store', 'offline-' || t_offline);
      perform private.v47_ensure_accounting_for_tenant(t_offline);
      perform private.v491_ensure_financial_mappings(t_offline);
      perform private.v628_seed_payment_methods(t_offline);
      insert into public.tenant_memberships(id, tenant_id, user_id) values(gen_random_uuid(), t_offline, usr);
      select id into owner_role from public.roles where tenant_id = t_offline and key = 'owner' limit 1;
      if owner_role is null then insert into public.roles(tenant_id, key, name) values(t_offline, 'owner', 'Owner') returning id into owner_role; end if;
      insert into public.role_permissions(role_id, permission_key) select owner_role, key from public.permissions on conflict do nothing;
      insert into public.user_roles(tenant_id, membership_id, role_id) select t_offline, tm.id, owner_role from public.tenant_memberships tm where tm.tenant_id = t_offline and tm.user_id = usr;
      insert into public.business_locations(id, tenant_id, location_code, name, invoice_prefix, state, address_line1) values(loc_off, t_offline, 'OFF-LOC', 'Offline Loc', 'OFF', 'Maharashtra', 'Addr');
      insert into public.business_devices(id, tenant_id, location_id, device_code, name, app_type, status, invoice_prefix, allowed_modules) values(dev_off, t_offline, loc_off, 'OFF-DEV', 'Offline POS', 'pos', 'active', 'OFF', '{sales,purchases}');
      select id into cust_off from public.customers where tenant_id = t_offline and is_walk_in = true limit 1;
      if cust_off is null then
        insert into public.customers(id, tenant_id, name, state, is_walk_in) values(gen_random_uuid(), t_offline, 'Offline Cust', 'Maharashtra', true) returning id into cust_off;
      end if;
      insert into public.inventory_units(id, tenant_id, code, name) values(unit_off, t_offline, 'UOFF', 'Unit Off');
      insert into public.inventory_units_v481(id, tenant_id, code, name) values(unit_off, t_offline, 'UOFF', 'Unit Off');
      insert into public.products(id, tenant_id, name, item_type, base_unit_id, tax_rate) values(prod_off, t_offline, 'Prod Off', 'stock', unit_off, 18);
      insert into public.product_variants(id, tenant_id, product_id, name, sku, selling_price) values(var_off, t_offline, prod_off, 'Def', 'SKU-OFF-' || var_off, 100);
      insert into public.product_units_v481(tenant_id, variant_id, unit_id, is_base, is_default_sale, allow_sale) values(t_offline, var_off, unit_off, true, true, true);
      perform public.inventory_location_assign_v4(t_offline, loc_off, var_off, true, 100, 0, null);
      perform public.inventory_adjust_stock(t_offline, var_off, 100, 'Opening stock offline');
      insert into public.location_stock_balances(tenant_id, location_id, variant_id, quantity, average_cost)
      values(t_offline, loc_off, var_off, 100, 40)
      on conflict(tenant_id, location_id, variant_id) do update set quantity = 100, average_cost = 40;

      sync_res := public.gst_pos_offline_sale_sync_v522(
        t_offline, dev_off, loc_off,
        'OFF-REQ-' || gen_random_uuid()::text,
        jsonb_build_object(
          'local_invoice_number', 'OFF-LOCAL-001',
          'sale_date', current_date,
          'customer_id', cust_off,
          'items', jsonb_build_array(
            jsonb_build_object(
              'variant_id', var_off,
              'unit_id', unit_off,
              'quantity', 1,
              'unit_price', 100,
              'discount_amount', 0,
              'tax_rate', 0,
              'line_total', 100
            )
          ),
          'payment_allocations', jsonb_build_array(
            jsonb_build_object('method_code', 'cash', 'amount', 100)
          )
        )
      );

      if coalesce((sync_res->>'success')::boolean, false) is not true or (sync_res->>'tax_total')::numeric <> 0 then
        raise exception 'Scenario O Failed: Offline sync rejected or collected tax in non-GST store: %', sync_res;
      end if;
      results := results || jsonb_build_object('scenario_O_offline_pos_sync', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO P: Duplicate Transaction Submission (Idempotency)
    ----------------------------------------------------------------------------
    req_id := gen_random_uuid()::text;
    r := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 1, 'unit_price', 100, 'discount_amount', 0)),
      '[{"method_code":"cash","amount":118}]',
      'Scenario P Duplicate Test', loc1, dev1, req_id, 'B2C', '27', '[]'
    );
    again := public.gst_client_sale_create_v630(
      t, cust1, current_date, current_date,
      jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 1, 'unit_price', 100, 'discount_amount', 0)),
      '[{"method_code":"cash","amount":118}]',
      'Scenario P Duplicate Test', loc1, dev1, req_id, 'B2C', '27', '[]'
    );
    if (r->>'sale_id') <> (again->>'sale_id') then
      raise exception 'Scenario P Failed: Duplicate submission produced new sale_id';
    end if;
    select count(*) into chk_count from public.transaction_requests_v47 where tenant_id = t and request_id = req_id;
    if chk_count <> 1 then
      raise exception 'Scenario P Failed: transaction_requests_v47 count <> 1';
    end if;
    select count(*) into chk_count from public.sales where tenant_id = t and id = (r->>'sale_id')::uuid;
    if chk_count <> 1 then
      raise exception 'Scenario P Failed: More than 1 sale stored for sale_id';
    end if;
    results := results || jsonb_build_object('scenario_P_idempotent_duplicate_submission', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO Q: Payment Allocation and Journal Reconciliation
    ----------------------------------------------------------------------------
    -- Credit sale B was 500 outstanding. Record customer payment against it.
    declare
      pay_res jsonb;
      pay_id uuid;
    begin
      pay_res := public.customer_receive_payment_v471(
        t, cust1, 500, 'cash', 'REC-001', 'Customer payment settlement',
        sale_b, loc1, dev1, gen_random_uuid()::text
      );
      pay_id := (pay_res->>'receipt_id')::uuid;
      j_id := (select id from public.journal_entries where tenant_id = t and source_id = pay_id limit 1);

      select coalesce(sum(debit - credit), 0) into imbalance
      from public.journal_lines where journal_entry_id = j_id;

      if abs(imbalance) > 0.005 then
        raise exception 'Scenario Q Failed: Payment journal imbalanced: %', imbalance;
      end if;
      results := results || jsonb_build_object('scenario_Q_payment_reconciliation', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO R: GST versus Non-GST Invoices
    ----------------------------------------------------------------------------
    -- Verify detail structure of Non-GST sale A vs GST sale G
    declare
      det_a jsonb := public.sales_get_detail_v630(t, sale_a);
      det_g jsonb := public.sales_get_detail_v630(t, sale_g);
    begin
      if det_a->'gst'->>'document_class' <> 'commercial_invoice' or (det_a->'gst'->>'tax_collected_total')::numeric <> 0 then
        raise exception 'Scenario R Failed: Non-GST invoice metadata incorrect: %', det_a->'gst';
      end if;
      if det_g->'gst'->>'document_class' <> 'tax_invoice' or (det_g->'gst'->>'cgst_total')::numeric <> 90 or det_g->'gst'->>'supplier_gstin' <> '27AAPFU0939F1ZV' then
        raise exception 'Scenario R Failed: GST tax invoice metadata incorrect: %', det_g->'gst';
      end if;
      if length(det_g->>'invoice_number') > 16 then
        raise exception 'Scenario R Failed: Legal invoice number exceeds 16 chars: %', det_g->>'invoice_number';
      end if;
      results := results || jsonb_build_object('scenario_R_gst_vs_nongst_invoices', 'PASS');
    end;

    ----------------------------------------------------------------------------
    -- SCENARIO S: Cross-Business Isolation
    ----------------------------------------------------------------------------
    insert into public.tenants(id, name, slug) values(t2, 'Foreign Tenant', 'foreign-' || t2);
    bad := false;
    begin
      perform public.sales_invoice_context_v632(t2, loc1, dev1, current_date, null);
    exception when others then
      bad := true;
    end;
    if not bad then
      raise exception 'Scenario S Failed: User accessed another tenant invoice context';
    end if;

    bad := false;
    begin
      perform public.gst_client_sale_create_v630(
        t2, cust1, current_date, current_date,
        jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 1, 'unit_price', 100)),
        '[{"method_code":"cash","amount":100}]', 'Cross tenant attack', loc1, dev1, gen_random_uuid()::text, null, null, '[]'
      );
    exception when others then
      bad := true;
    end;
    if not bad then
      raise exception 'Scenario S Failed: User created transaction in foreign tenant';
    end if;
    results := results || jsonb_build_object('scenario_S_cross_business_isolation', 'PASS');

    ----------------------------------------------------------------------------
    -- SCENARIO T: Incorrect or Missing Tax Configuration Handling
    ----------------------------------------------------------------------------
    -- Setting an unreviewed profile should block GST creation
    update public.gst_product_tax_profiles_v520 set validation_status = 'review_required' where id = profile1;
    bad := false;
    begin
      perform public.gst_client_sale_create_v630(
        t, cust1, current_date, current_date,
        jsonb_build_array(jsonb_build_object('variant_id', var_goods, 'unit_id', unit, 'quantity', 1, 'unit_price', 100)),
        '[{"method_code":"cash","amount":118}]', 'Unreviewed tax profile', loc1, dev1, gen_random_uuid()::text, 'B2C', '27', '[]'
      );
    exception when others then
      bad := true;
    end;
    if not bad then
      raise exception 'Scenario T Failed: Sale succeeded despite review_required tax profile';
    end if;
    update public.gst_product_tax_profiles_v520 set validation_status = 'locally_validated' where id = profile1;
    results := results || jsonb_build_object('scenario_T_missing_tax_config_guard', 'PASS');

    -- Roll back all test rows cleanly
    raise exception using errcode = 'ZT001', message = 'Rollback matrix test';
  exception when sqlstate 'ZT001' then
    null;
  end;

  perform set_config('thq_matrix_v716.result', results::text, false);
end $matrix$;

select current_setting('thq_matrix_v716.result')::jsonb as matrix_results;
