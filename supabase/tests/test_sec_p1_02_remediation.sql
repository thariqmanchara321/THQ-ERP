-- Test Suite: SEC-P1-02 Subscription Quota Enforcement Verification
-- Tests all matrix scenarios for Location and Terminal quotas under migration 717 / v8.3.11.

do $test_suite$
declare
  v_test_tenant uuid;
  v_user_owner uuid;
  v_user_stranger uuid;
  v_mem_owner uuid;
  v_loc1 uuid;
  v_loc2 uuid;
  v_loc3 uuid;
  v_dev1 uuid;
  v_dev2 uuid;
  v_dev3 uuid;
  v_err_caught boolean;
  v_err_code text;
  v_err_msg text;
  v_starter_plan_id uuid;
  v_business_plan_id uuid;
  v_enterprise_plan_id uuid;
  v_res jsonb;
  v_results jsonb := '{}'::jsonb;
begin
  begin -- Inner test transaction block for clean automatic rollback

    -- Select reference plans
    select id into v_starter_plan_id from public.subscription_plans where key = 'starter';
    select id into v_business_plan_id from public.subscription_plans where key = 'business';
    select id into v_enterprise_plan_id from public.subscription_plans where key = 'enterprise';

    -- Pick valid users from auth.users
    select id into v_user_owner from auth.users order by created_at asc limit 1;
    select id into v_user_stranger from auth.users where id <> v_user_owner order by created_at desc limit 1;
    if v_user_stranger is null then
      v_user_stranger := gen_random_uuid();
    end if;

    -- Create isolated test tenant
    v_test_tenant := gen_random_uuid();
    insert into public.tenants (id, name, slug, business_code, business_type, status)
    values (v_test_tenant, 'SEC-P1-02 Test Biz', 'sec-p1-test-' || substr(v_test_tenant::text, 1, 8), 'BIZ-SECP1TEST', 'retail', 'active');

    -- Seed default roles for tenant
    perform private.seed_default_roles(v_test_tenant);

    -- Assign owner membership
    v_mem_owner := gen_random_uuid();
    insert into public.tenant_memberships (id, tenant_id, user_id, status)
    values (v_mem_owner, v_test_tenant, v_user_owner, 'active');

    insert into public.user_roles (tenant_id, membership_id, role_id)
    select v_test_tenant, v_mem_owner, r.id from public.roles r where r.tenant_id = v_test_tenant and r.key = 'owner';

    -- -------------------------------------------------------------------------
    -- Scenario 1: Default fallback to Trial plan when no subscription row exists
    -- -------------------------------------------------------------------------
    v_res := private.subscription_effective_limits(v_test_tenant);
    assert (v_res->>'status') = 'trial', 'Test 1.1 failed: Expected trial status';
    assert (v_res->>'max_locations')::int = 1, 'Test 1.2 failed: Expected max_locations = 1';
    assert (v_res->>'max_terminals')::int = 2, 'Test 1.3 failed: Expected max_terminals = 2';
    v_results := v_results || jsonb_build_object('scenario_1_trial_fallback', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 2: Starter Plan (1 location, 2 terminals)
    -- -------------------------------------------------------------------------
    insert into public.tenant_subscriptions (tenant_id, plan_id, status, billing_cycle, starts_at)
    values (v_test_tenant, v_starter_plan_id, 'active', 'monthly', now())
    on conflict (tenant_id) do update set plan_id = v_starter_plan_id, status = 'active', limit_overrides = '{}'::jsonb;

    -- Create Primary Location (1 of 1)
    v_loc1 := gen_random_uuid();
    insert into public.business_locations (id, tenant_id, location_code, name, hierarchy_role, active)
    values (v_loc1, v_test_tenant, 'MAIN', 'Main Store', 'main_store', true);

    -- Pre-provision 2 devices (2 of 2)
    v_dev1 := gen_random_uuid();
    insert into public.business_devices (id, tenant_id, location_id, device_code, name, app_type, status, activation_expires_at)
    values (v_dev1, v_test_tenant, v_loc1, 'CLIENT-001', 'PC 1', 'client', 'active', null);

    v_dev2 := gen_random_uuid();
    insert into public.business_devices (id, tenant_id, location_id, device_code, name, app_type, status, activation_expires_at)
    values (v_dev2, v_test_tenant, v_loc1, 'POS-001', 'POS 1', 'pos', 'active', null);
    v_results := v_results || jsonb_build_object('scenario_2_starter_baseline', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 3: At Quota - Attempting to create 2nd location via platform_location_create_v709 must fail
    -- -------------------------------------------------------------------------
    v_err_caught := false;
    begin
      perform public.platform_location_create_v709(v_test_tenant, 'Branch 2', 'BR2', 'store');
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 3 failed: Expected platform_location_create_v709 to fail at quota';
    assert v_err_msg like '%Location limit exceeded%', 'Test 3 failed: Unexpected error message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_3_at_quota_location_rejected', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 4: At Quota - Attempting to issue a 3rd new terminal must fail
    -- -------------------------------------------------------------------------
    v_err_caught := false;
    begin
      perform public.platform_device_issue_activation_v709(v_test_tenant, v_loc1, 'Extra POS', 'pos', null, null);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 4 failed: Expected platform_device_issue_activation_v709 to fail at quota';
    assert v_err_msg like '%Terminal limit exceeded%', 'Test 4 failed: Unexpected error message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_4_at_quota_terminal_rejected', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 5: Re-activation of an existing active/pending device must succeed without extra slot
    -- -------------------------------------------------------------------------
    v_err_caught := false;
    begin
      v_res := public.platform_device_issue_activation_v709(v_test_tenant, v_loc1, 'PC 1 Renamed', 'client', null, v_dev1);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert not v_err_caught, 'Test 5 failed: Re-activation of existing device should not consume extra quota: ' || coalesce(v_err_msg, '');
    assert (v_res->>'success')::boolean = true, 'Test 5 failed: Expected success';
    v_results := v_results || jsonb_build_object('scenario_5_terminal_reactivation_permitted', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 6: Revoked device frees up quota slot for new terminal
    -- -------------------------------------------------------------------------
    update public.business_devices set status = 'revoked' where id = v_dev2;

    v_err_caught := false;
    begin
      v_res := public.platform_device_issue_activation_v709(v_test_tenant, v_loc1, 'Replacement POS', 'pos', null, null);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert not v_err_caught, 'Test 6 failed: Slot freed by revoked device should allow new activation: ' || coalesce(v_err_msg, '');
    v_dev3 := (v_res->>'device_id')::uuid;
    assert v_dev3 is not null, 'Test 6 failed: Device ID was null';
    v_results := v_results || jsonb_build_object('scenario_6_revoked_device_frees_slot', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 7: Inactive location excluded from active location count & deactivation/reactivation lifecycle
    -- -------------------------------------------------------------------------
    -- Temporarily grant limit of 2 locations to test branch lifecycle
    update public.tenant_subscriptions
    set limit_overrides = '{"max_locations": 2, "max_terminals": 10}'::jsonb
    where tenant_id = v_test_tenant;

    -- Create branch location v_loc2 (now 2 of 2 active)
    v_loc2 := public.platform_business_location_save(
      v_test_tenant, null, null, 'BR2', 'Second Location', 'store',
      null, null, null, null, null, null, null, null, 'India', 'BR2', true
    );

    -- Trying to create a 3rd active location must fail (at quota 2 of 2)
    v_err_caught := false;
    begin
      perform public.platform_business_location_save(
        v_test_tenant, null, null, 'BR3', 'Third Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR3', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 7.1 failed: Expected 3rd location to fail at quota';

    -- Deactivate v_loc2 (has no active devices, so guard allows deactivation)
    perform public.platform_business_location_save(
      v_test_tenant, v_loc2, null, 'BR2', 'Second Location', 'store',
      null, null, null, null, null, null, null, null, 'India', 'BR2', false
    );
    assert (select active from public.business_locations where id = v_loc2) = false,
      'Test 7.2 failed: Expected v_loc2 to be inactive';

    -- Active count is now 1 again. Creating v_loc3 should now SUCCEED!
    v_err_caught := false;
    begin
      v_loc3 := public.platform_business_location_save(
        v_test_tenant, null, null, 'BR3', 'Third Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR3', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert not v_err_caught, 'Test 7.3 failed: Inactive location should free quota slot: ' || coalesce(v_err_msg, '');

    -- Now tenant has v_loc1 (active) and v_loc3 (active), and v_loc2 (inactive).
    -- Attempting to re-activate v_loc2 should FAIL because limit is 2 and we already have 2 active!
    v_err_caught := false;
    begin
      perform public.platform_business_location_save(
        v_test_tenant, v_loc2, null, 'BR2', 'Second Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR2', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 7.4 failed: Re-activating inactive location when at quota should fail';
    assert v_err_msg like '%Location limit exceeded%', 'Test 7.4 failed: Unexpected message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_7_inactive_exclusion_and_reactivation', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 8: Above Quota (e.g. after downgrade) - Existing intact, further creation blocked
    -- -------------------------------------------------------------------------
    -- Downgrade to starter plan (max_locations: 1), removing overrides
    update public.tenant_subscriptions
    set plan_id = v_starter_plan_id, limit_overrides = '{}'::jsonb
    where tenant_id = v_test_tenant;

    -- Tenant currently has 2 active locations (v_loc1 and v_loc3) on starter plan (limit 1)
    -- Verify existing records are intact:
    assert (select count(*) from public.business_locations where tenant_id = v_test_tenant and active = true) = 2,
      'Test 8.1 failed: Non-destructive requirement violated, existing locations modified!';

    -- Verify creating another location is blocked
    v_err_caught := false;
    begin
      perform public.platform_business_location_save(
        v_test_tenant, null, null, 'BR4', 'Fourth Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR4', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 8.2 failed: Expected creation to fail when above quota';
    assert v_err_msg like '%Location limit exceeded%', 'Test 8.2 failed: Unexpected message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_8_above_quota_downgrade_safety', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 9: Plan Upgrade to Business (3 locations, 6 terminals)
    -- -------------------------------------------------------------------------
    update public.tenant_subscriptions
    set plan_id = v_business_plan_id, updated_at = now()
    where tenant_id = v_test_tenant;

    -- Now tenant has 2 active locations, limit is 3. Adding 3rd location via save should succeed!
    v_err_caught := false;
    begin
      perform public.platform_business_location_save(
        v_test_tenant, null, null, 'BR4', 'Fourth Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR4', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert not v_err_caught, 'Test 9 failed: Upgraded plan should permit 3rd location: ' || coalesce(v_err_msg, '');
    v_results := v_results || jsonb_build_object('scenario_9_plan_upgrade_expansion', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 10: Zero Quota via limit_overrides strictly forbids creation
    -- -------------------------------------------------------------------------
    update public.tenant_subscriptions
    set limit_overrides = '{"max_locations": 0}'::jsonb
    where tenant_id = v_test_tenant;

    v_err_caught := false;
    begin
      perform public.platform_business_location_save(
        v_test_tenant, null, null, 'BR5', 'Fifth Location', 'store',
        null, null, null, null, null, null, null, null, 'India', 'BR5', true
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 10 failed: Zero quota should forbid location creation';
    assert v_err_msg like '%Location limit exceeded%', 'Test 10 failed: Unexpected message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_10_zero_quota_enforced', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 11: Suspended subscription status disables provisioning
    -- -------------------------------------------------------------------------
    update public.tenant_subscriptions
    set status = 'suspended', limit_overrides = '{}'::jsonb
    where tenant_id = v_test_tenant;

    v_err_caught := false;
    begin
      perform private.subscription_check_quota(v_test_tenant, 'locations', 1);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 11.1 failed: Suspended status must disable quota check';
    assert v_err_msg like '%Subscription suspended%', 'Test 11.1 failed: Unexpected error: ' || v_err_msg;

    v_err_caught := false;
    begin
      perform private.subscription_check_quota(v_test_tenant, 'terminals', 1);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 11.2 failed: Suspended status must disable terminal check';
    v_results := v_results || jsonb_build_object('scenario_11_suspended_subscription_guard', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 12: Enterprise Unlimited Plan
    -- -------------------------------------------------------------------------
    update public.tenant_subscriptions
    set status = 'active', plan_id = v_enterprise_plan_id, limit_overrides = '{}'::jsonb
    where tenant_id = v_test_tenant;

    v_err_caught := false;
    begin
      perform private.subscription_check_quota(v_test_tenant, 'locations', 100);
      perform private.subscription_check_quota(v_test_tenant, 'terminals', 100);
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert not v_err_caught, 'Test 12 failed: Enterprise plan should permit unlimited resources: ' || coalesce(v_err_msg, '');
    v_results := v_results || jsonb_build_object('scenario_12_enterprise_unlimited', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 13: Tenant System Create V471 quota check
    -- -------------------------------------------------------------------------
    -- Set plan back to starter (max 2 terminals), with 2 active devices
    update public.tenant_subscriptions
    set plan_id = v_starter_plan_id, limit_overrides = '{}'::jsonb
    where tenant_id = v_test_tenant;

    -- Ensure active devices count is at limit (2)
    update public.business_devices set status = 'active' where id in (v_dev1, v_dev3);

    v_err_caught := false;
    begin
      perform public.tenant_system_create_v471(
        v_test_tenant, v_loc1, 'Extra System', 'client', 'desktop', '{}'::text[], null, 'office'
      );
    exception when others then
      v_err_caught := true;
      v_err_msg := SQLERRM;
    end;
    assert v_err_caught, 'Test 13 failed: tenant_system_create_v471 should be rejected at terminal quota';
    assert v_err_msg like '%Terminal limit exceeded%', 'Test 13 failed: Unexpected message: ' || v_err_msg;
    v_results := v_results || jsonb_build_object('scenario_13_tenant_system_create_v471_quota', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 14: Unauthorized caller rejected in platform_location_create_v709
    -- -------------------------------------------------------------------------
    -- Emulate stranger user session (non-service-role, non-platform-admin, non-owner)
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_user_stranger::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);

    v_err_caught := false;
    begin
      perform public.platform_location_create_v709(v_test_tenant, 'Unauthorized Loc', 'UNAUTH', 'store');
    exception when others then
      v_err_caught := true;
      v_err_code := SQLSTATE;
    end;
    assert v_err_caught, 'Test 14 failed: Expected unauthorized caller to be rejected';
    assert v_err_code = '42501', 'Test 14 failed: Expected SQLSTATE 42501, got ' || v_err_code;
    v_results := v_results || jsonb_build_object('scenario_14_unauthorized_location_create_42501', 'PASS');

    -- -------------------------------------------------------------------------
    -- Scenario 15: Unauthorized caller rejected in platform_device_issue_activation_v709
    -- -------------------------------------------------------------------------
    v_err_caught := false;
    begin
      perform public.platform_device_issue_activation_v709(v_test_tenant, v_loc1, 'Unauthorized POS', 'pos', null, null);
    exception when others then
      v_err_caught := true;
      v_err_code := SQLSTATE;
    end;
    assert v_err_caught, 'Test 15 failed: Expected unauthorized caller to be rejected';
    assert v_err_code = '42501', 'Test 15 failed: Expected SQLSTATE 42501, got ' || v_err_code;
    v_results := v_results || jsonb_build_object('scenario_15_unauthorized_device_issue_42501', 'PASS');

    -- Reset session role
    perform set_config('role', 'postgres', true);

    -- Clean rollback of test data
    raise exception using errcode = 'ZT001', message = 'Rollback test suite';
  exception when sqlstate 'ZT001' then
    null;
  end;

  perform set_config('sec_p1_02.result', v_results::text, false);
end $test_suite$;

select current_setting('sec_p1_02.result')::jsonb as test_results;
