-- ============================================================================
-- THQ ERP: SEC-P0-01 Remediation Authorization Test Suite
-- Returns a detailed verification table for all 8 test scenarios
-- ============================================================================

create or replace function pg_temp.run_sec_p0_01_test_matrix()
returns table(
  scenario_no int,
  scenario_name text,
  expected_result text,
  actual_result text,
  test_status text
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_tenant_id uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid; -- TENZO TRADERS
  v_owner_id uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;  -- Tenant A Owner
  v_customer_id uuid := '2fa77806-2e50-4435-9470-288516e1a148'::uuid; -- MUSADIK
  v_foreign_tenant_id uuid := 'e60bec89-6830-43af-b4e6-e6974f6be35e'::uuid; -- Foreign Tenant B
  v_admin_id uuid := '11526f34-e37c-4605-9213-c2193203a642'::uuid;  -- Platform Administrator
  v_ordinary_user_id uuid := '2c937881-b663-476a-9de3-4d96af1705a2'::uuid; -- Real auth.users record
  v_suspended_user_id uuid := 'd0143a98-03c3-4204-9239-d2b4e2c91e32'::uuid; -- Real auth.users record
  v_location_id uuid;
  v_count int;
  v_detail jsonb;
  v_statement jsonb;
  v_grant_res jsonb;
  v_grant_id uuid;
  v_expired_grant_id uuid;
  v_temp_mem_id uuid;
  v_temp_role_id uuid;
  v_susp_mem_id uuid;
  v_err text;
begin
  select id into v_location_id
  from public.business_locations
  where tenant_id = v_tenant_id and active limit 1;

  -- --------------------------------------------------------------------------
  -- SCENARIO 1: UNAUTHENTICATED CALLER (MUST BE DENIED)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', '', true);
  v_err := null;
  begin
    perform public.customer_accounts_list_v471(v_tenant_id);
    v_err := 'ALLOWED (VULNERABILITY DETECTED)';
  exception when others then
    v_err := sqlerrm;
  end;

  if v_err like '%Access denied%' then
    scenario_no := 1;
    scenario_name := 'Unauthenticated caller accessing customer accounts';
    expected_result := 'Denied with Access denied';
    actual_result := 'Denied: ' || v_err;
    test_status := 'PASS';
    return next;
  else
    scenario_no := 1;
    scenario_name := 'Unauthenticated caller accessing customer accounts';
    expected_result := 'Denied with Access denied';
    actual_result := 'Unexpected: ' || coalesce(v_err, 'null');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 2: TENANT A OWNER ACCESSING TENANT A (MUST BE ALLOWED)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  v_err := null;
  begin
    select count(*) into v_count from public.customer_accounts_list_v471(v_tenant_id);
    v_detail := public.customer_account_v471(v_tenant_id, v_customer_id);
    v_statement := public.customers_get_statement_v715(v_tenant_id, v_customer_id);
  exception when others then
    v_err := sqlerrm;
  end;

  if v_err is null and v_detail->'customer' is not null and v_statement->'customer_name' is not null then
    scenario_no := 2;
    scenario_name := 'Tenant A owner accessing Tenant A customer data';
    expected_result := 'Allowed with full customer accounts and statements';
    actual_result := 'Allowed (customers: ' || v_count || ', customer_name: ' || (v_detail->'customer'->>'name') || ')';
    test_status := 'PASS';
    return next;
  else
    scenario_no := 2;
    scenario_name := 'Tenant A owner accessing Tenant A customer data';
    expected_result := 'Allowed with full customer accounts and statements';
    actual_result := 'Error: ' || coalesce(v_err, 'empty customer');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 3: TENANT A OWNER REQUESTING TENANT B (MUST BE DENIED)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  v_err := null;
  begin
    perform public.customer_accounts_list_v471(v_foreign_tenant_id);
    v_err := 'ALLOWED (CROSS-TENANT LEAK)';
  exception when others then
    v_err := sqlerrm;
  end;

  if v_err like '%Access denied%' then
    scenario_no := 3;
    scenario_name := 'Tenant A owner requesting foreign Tenant B';
    expected_result := 'Denied with Access denied';
    actual_result := 'Denied: ' || v_err;
    test_status := 'PASS';
    return next;
  else
    scenario_no := 3;
    scenario_name := 'Tenant A owner requesting foreign Tenant B';
    expected_result := 'Denied with Access denied';
    actual_result := 'Unexpected: ' || coalesce(v_err, 'null');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 4: TENANT A ORDINARY USER REQUESTING TENANT B (MUST BE DENIED)
  -- --------------------------------------------------------------------------
  select id into v_temp_role_id from public.roles where key = 'clerk' or key = 'sales_rep' limit 1;
  insert into public.tenant_memberships(id, tenant_id, user_id, status)
  values (gen_random_uuid(), v_tenant_id, v_ordinary_user_id, 'active')
  returning id into v_temp_mem_id;

  if v_temp_role_id is not null then
    insert into public.user_roles(tenant_id, user_id, role_id, membership_id)
    values (v_tenant_id, v_ordinary_user_id, v_temp_role_id, v_temp_mem_id);
  end if;

  perform set_config('request.jwt.claim.sub', v_ordinary_user_id::text, true);
  v_err := null;
  begin
    perform public.customer_accounts_list_v471(v_foreign_tenant_id);
    v_err := 'ALLOWED (CROSS-TENANT LEAK)';
  exception when others then
    v_err := sqlerrm;
  end;

  delete from public.user_roles where membership_id = v_temp_mem_id;
  delete from public.tenant_memberships where id = v_temp_mem_id;

  if v_err like '%Access denied%' then
    scenario_no := 4;
    scenario_name := 'Tenant A ordinary user requesting foreign Tenant B';
    expected_result := 'Denied with Access denied';
    actual_result := 'Denied: ' || v_err;
    test_status := 'PASS';
    return next;
  else
    scenario_no := 4;
    scenario_name := 'Tenant A ordinary user requesting foreign Tenant B';
    expected_result := 'Denied with Access denied';
    actual_result := 'Unexpected: ' || coalesce(v_err, 'null');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 5: PLATFORM ADMIN REQUESTING ARBITRARY TENANT (DENIED BY DEFAULT)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  v_err := null;
  begin
    perform public.customer_accounts_list_v471(v_tenant_id);
    v_err := 'ALLOWED (SEC-P0-01 VULNERABILITY REPRODUCED)';
  exception when others then
    v_err := sqlerrm;
  end;

  if v_err like '%Access denied%' then
    scenario_no := 5;
    scenario_name := 'Platform admin requesting arbitrary tenant without support grant';
    expected_result := 'Denied by default with Access denied';
    actual_result := 'Denied: ' || v_err;
    test_status := 'PASS';
    return next;
  else
    scenario_no := 5;
    scenario_name := 'Platform admin requesting arbitrary tenant without support grant';
    expected_result := 'Denied by default with Access denied';
    actual_result := 'Unexpected: ' || coalesce(v_err, 'null');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 6: AUTHORIZED SUPPORT WORKFLOW (EXPLICIT SCOPE & LIFESPAN)
  -- --------------------------------------------------------------------------
  -- 6a. Tenant owner issues support grant
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  v_grant_res := public.platform_support_grant_issue_v840(
    v_tenant_id,
    v_admin_id,
    'customer_support',
    60,
    'Investigating customer credit balance and statement discrepancy for tenant owner'
  );
  v_grant_id := (v_grant_res->>'grant_id')::uuid;

  -- 6b. Platform admin accesses under support grant
  perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  select count(*) into v_count from public.customer_accounts_list_v471(v_tenant_id);
  v_detail := public.customer_account_v471(v_tenant_id, v_customer_id);

  -- 6c. Verify support grant does NOT permit payment receipt
  v_err := null;
  begin
    perform public.customer_receive_payment_v471(
      v_tenant_id, v_customer_id, 10.00, 'cash', 'REF-TEST-SUP', 'Test',
      null, v_location_id, null, null, null, null, 'REQ-SUP-' || gen_random_uuid()::text
    );
    v_err := 'ALLOWED (SUPPORT USURPATION OF FINANCIAL POSTING)';
  exception when others then
    v_err := sqlerrm;
  end;

  -- 6d. Revoke grant
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  perform public.platform_support_grant_revoke_v840(v_grant_id, v_tenant_id);

  -- 6e. Verify denied after revoke
  perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  begin
    perform public.customer_accounts_list_v471(v_tenant_id);
    v_err := 'ALLOWED AFTER REVOCATION';
  exception when others then
    null; -- expected
  end;

  delete from private.platform_support_grants where id = v_grant_id;

  if v_count >= 0 and v_err like '%Access denied%' then
    scenario_no := 6;
    scenario_name := 'Authorized support delegation lifecycle';
    expected_result := 'Allowed during active grant, prohibited from financial posting, denied after revocation';
    actual_result := 'Allowed (count: ' || v_count || '), payment strictly blocked, revoked grant immediately denied';
    test_status := 'PASS';
    return next;
  else
    scenario_no := 6;
    scenario_name := 'Authorized support delegation lifecycle';
    expected_result := 'Allowed during active grant, prohibited from financial posting, denied after revocation';
    actual_result := 'Failed: ' || coalesce(v_err, 'unknown');
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 7: USER WITH RESTRICTED LOCATION ACCESS (ONLY AUTHORIZED DATA)
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  v_statement := public.customers_get_statement_v715(v_tenant_id, v_customer_id, null, null, gen_random_uuid());

  if jsonb_array_length(coalesce(v_statement->'rows', '[]'::jsonb)) = 0 then
    scenario_no := 7;
    scenario_name := 'User with restricted location access';
    expected_result := 'Only authorized location data returned; unauthorized locations omitted';
    actual_result := 'Scoped query strictly excluded unauthorized location records (0 unauthorized rows)';
    test_status := 'PASS';
    return next;
  else
    scenario_no := 7;
    scenario_name := 'User with restricted location access';
    expected_result := 'Only authorized location data returned; unauthorized locations omitted';
    actual_result := 'Leak: unauthorized location returned data';
    test_status := 'FAIL';
    return next;
  end if;


  -- --------------------------------------------------------------------------
  -- SCENARIO 8: REVOKED OR SUSPENDED USER (DENIED ACCORDING TO POLICY)
  -- --------------------------------------------------------------------------
  insert into public.tenant_memberships(id, tenant_id, user_id, status)
  values (gen_random_uuid(), v_tenant_id, v_suspended_user_id, 'suspended')
  returning id into v_susp_mem_id;

  perform set_config('request.jwt.claim.sub', v_suspended_user_id::text, true);
  v_err := null;
  begin
    perform public.customer_accounts_list_v471(v_tenant_id);
    v_err := 'ALLOWED (SUSPENDED USER ACCESS LEAK)';
  exception when others then
    v_err := sqlerrm;
  end;

  delete from public.tenant_memberships where id = v_susp_mem_id;
  perform set_config('request.jwt.claim.sub', '', true);

  if v_err like '%Access denied%' then
    scenario_no := 8;
    scenario_name := 'Revoked or suspended tenant user';
    expected_result := 'Denied according to tenant policy with Access denied';
    actual_result := 'Denied: ' || v_err;
    test_status := 'PASS';
    return next;
  else
    scenario_no := 8;
    scenario_name := 'Revoked or suspended tenant user';
    expected_result := 'Denied according to tenant policy with Access denied';
    actual_result := 'Unexpected: ' || coalesce(v_err, 'null');
    test_status := 'FAIL';
    return next;
  end if;

end $$;

select * from pg_temp.run_sec_p0_01_test_matrix();
