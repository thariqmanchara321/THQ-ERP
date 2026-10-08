-- ============================================================================
-- REGISTER TEST USER / STAFF SCRIPT
-- Project Target: krejepenqgcmnsugbpmv (THQ TEST DATABASE ONLY)
-- Run after creating a test user under Supabase Dashboard > Authentication > Users
-- ============================================================================

do $test_user_setup$
declare
  v_email text := 'test-cashier@example.com'; -- Replace with the test user's email created in Auth
  v_username text := 'thq_test_cashier';       -- Test login username (min 4 chars)
  v_user_id uuid;
  v_tenant_id uuid := '11111111-1111-1111-1111-111111111111'::uuid; -- THQTEST tenant
  v_location_id uuid := '22222222-2222-2222-2222-222222222222'::uuid; -- Main Test Branch
  v_membership_id uuid;
  v_owner_role_id uuid;
begin
  -- ABSOLUTE SAFETY GUARD: Reject execution if NOT running on the test database!
  if not exists (select 1 from private.thq_test_environment_identity
                 where singleton and project_ref = 'krejepenqgcmnsugbpmv') then
    raise exception 'FATAL SAFETY ABORT: This script can ONLY run on the TEST database (krejepenqgcmnsugbpmv).';
  end if;

  -- 1. Find the Auth user
  select id into v_user_id from auth.users where lower(email) = lower(trim(v_email));
  if v_user_id is null then
    raise exception 'User with email % not found in auth.users. Please create it in Supabase Auth first.', v_email;
  end if;

  -- 2. Create / Update Profile
  insert into public.profiles (id, display_name)
  values (v_user_id, 'THQ Test Staff')
  on conflict (id) do update set display_name = 'THQ Test Staff';

  -- 3. Create / Update Username Mapping
  insert into public.user_login_names (user_id, username, auth_email)
  values (v_user_id, lower(trim(v_username)), lower(trim(v_email)))
  on conflict (user_id) do update set
    username = excluded.username,
    auth_email = excluded.auth_email;

  -- 4. Create / Update Tenant Membership
  insert into public.tenant_memberships (tenant_id, user_id, status)
  values (v_tenant_id, v_user_id, 'active')
  on conflict (tenant_id, user_id) do update set status = 'active'
  returning id into v_membership_id;

  if v_membership_id is null then
    select id into v_membership_id from public.tenant_memberships
    where tenant_id = v_tenant_id and user_id = v_user_id;
  end if;

  -- 5. Assign Owner/Admin Role
  select id into v_owner_role_id from public.roles where key = 'owner' limit 1;
  if v_owner_role_id is not null then
    insert into public.user_roles (tenant_id, membership_id, role_id)
    values (v_tenant_id, v_membership_id, v_owner_role_id)
    on conflict do nothing;
  end if;

  -- 6. Grant Location Access
  insert into public.business_user_location_access (tenant_id, user_id, location_id, access_level)
  values (v_tenant_id, v_user_id, v_location_id, 'manage')
  on conflict (tenant_id, user_id, location_id) do update set access_level = 'manage';

  raise notice 'Test user % (username: %) configured for THQTEST with full permissions.', v_email, v_username;
end
$test_user_setup$;
