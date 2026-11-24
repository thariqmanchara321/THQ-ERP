# Test Suite: SEC-P1-02 Genuine Concurrent Database Quota Verification
# Tests race condition serialization for simultaneous location creation and terminal activation requests.

import ctypes
import ctypes.wintypes
import json
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

class CREDENTIAL(ctypes.Structure):
    _fields_ = [
        ('Flags', ctypes.wintypes.DWORD),
        ('Type', ctypes.wintypes.DWORD),
        ('TargetName', ctypes.c_wchar_p),
        ('Comment', ctypes.c_wchar_p),
        ('LastWritten', ctypes.wintypes.FILETIME),
        ('CredentialBlobSize', ctypes.wintypes.DWORD),
        ('CredentialBlob', ctypes.POINTER(ctypes.c_byte)),
        ('Persist', ctypes.wintypes.DWORD),
        ('AttributeCount', ctypes.wintypes.DWORD),
        ('Attributes', ctypes.c_void_p),
        ('TargetAlias', ctypes.c_wchar_p),
        ('UserName', ctypes.c_wchar_p),
    ]

Advapi32 = ctypes.WinDLL('Advapi32.dll')
CredReadW = Advapi32.CredReadW
CredReadW.argtypes = [ctypes.c_wchar_p, ctypes.wintypes.DWORD, ctypes.wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(CREDENTIAL))]
CredReadW.restype = ctypes.wintypes.BOOL

p_cred = ctypes.POINTER(CREDENTIAL)()
if not CredReadW('Supabase CLI:supabase', 1, 0, ctypes.byref(p_cred)):
    raise SystemExit('Could not read Supabase token from Windows Credential Manager')
cred = p_cred.contents
TOKEN = bytes(cred.CredentialBlob[:cred.CredentialBlobSize]).decode('utf-8')
QUERY_URL = 'https://api.supabase.com/v1/projects/yguzrxcdvyimjrfvtcvp/database/query'

def exec_sql(sql):
    req = urllib.request.Request(
        QUERY_URL,
        data=json.dumps({'query': sql}).encode('utf-8'),
        headers={'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read().decode('utf-8')
            return True, json.loads(data) if data.strip() else None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode('utf-8')
        try:
            err_json = json.loads(err_body)
            msg = err_json.get('message', err_body)
        except Exception:
            msg = err_body
        return False, msg

def run_concurrent_test():
    print('======================================================================')
    print('THQ ERP - Phase 12.2.1: Genuine Concurrent Quota Database Verification')
    print('======================================================================\n')

    # 1. Setup isolated test tenant
    setup_sql = """
    do $$
    declare
      v_tenant uuid := 'd0000000-0000-4000-8000-000000000001'::uuid;
      v_starter_id uuid;
      v_user uuid;
      v_mem uuid;
      v_loc uuid;
      v_dev uuid;
    begin
      set session_replication_role = 'replica';
      delete from public.business_devices where tenant_id = v_tenant;
      delete from public.business_locations where tenant_id = v_tenant;
      delete from public.tenant_subscriptions where tenant_id = v_tenant;
      delete from public.user_roles where tenant_id = v_tenant;
      delete from public.tenant_memberships where tenant_id = v_tenant;
      delete from public.roles where tenant_id = v_tenant;
      delete from public.thq_sync_state_v480 where tenant_id = v_tenant;
      delete from public.tenants where id = v_tenant;
      set session_replication_role = 'origin';

      -- Create tenant
      insert into public.tenants (id, name, slug, business_code, business_type, status)
      values (v_tenant, 'Concurrent Quota Test Corp', 'conc-quota-test', 'BIZ-CONCTEST', 'retail', 'active');

      -- Roles
      perform private.seed_default_roles(v_tenant);

      -- Owner
      select id into v_user from auth.users order by created_at asc limit 1;
      v_mem := gen_random_uuid();
      insert into public.tenant_memberships (id, tenant_id, user_id, status)
      values (v_mem, v_tenant, v_user, 'active');
      insert into public.user_roles (tenant_id, membership_id, role_id)
      select v_tenant, v_mem, r.id from public.roles r where r.tenant_id = v_tenant and r.key = 'owner';

      -- Subscription: Starter plan with max_locations = 2, max_terminals = 10
      select id into v_starter_id from public.subscription_plans where key = 'starter';
      insert into public.tenant_subscriptions (tenant_id, plan_id, status, limit_overrides, starts_at)
      values (v_tenant, v_starter_id, 'active', '{"max_locations": 2, "max_terminals": 10}'::jsonb, now());

      -- Baseline: 1 active location. (1 slot remaining out of 2)
      v_loc := gen_random_uuid();
      insert into public.business_locations (id, tenant_id, location_code, name, location_type, hierarchy_role, active)
      values (v_loc, v_tenant, 'MAIN', 'Main Branch', 'store', 'main_store', true);
    end $$;
    """
    ok, res = exec_sql(setup_sql)
    if not ok:
        raise SystemExit(f'Setup failed: {res}')
    print('[SETUP] Test tenant created: d0000000-0000-4000-8000-000000000001')
    print('[SETUP] Baseline configured: max_locations = 2, active locations = 1 (1 slot remaining)\n')

    # 2. Test 1: Concurrent Location Creation
    print('--- TEST 1: Two simultaneous location-creation requests when 1 slot remains ---')
    req1_sql = """
    do $$
    begin
      -- Request 1: Creates location 'BRANCH-A' and holds advisory transaction lock for 1.2 seconds
      perform public.platform_location_create_v709(
        'd0000000-0000-4000-8000-000000000001'::uuid,
        'Branch A',
        'BR-A'
      );
      perform pg_sleep(1.2);
    end $$;
    """

    req2_sql = """
    do $$
    begin
      -- Request 2: Attempts to create location 'BRANCH-B' concurrently
      perform public.platform_location_create_v709(
        'd0000000-0000-4000-8000-000000000001'::uuid,
        'Branch B',
        'BR-B'
      );
    end $$;
    """

    def run_worker(name, sql):
        t0 = time.time()
        print(f'[{time.strftime("%H:%M:%S")}] Dispatching {name}...')
        ok, res = exec_sql(sql)
        dt = time.time() - t0
        print(f'[{time.strftime("%H:%M:%S")}] {name} completed in {dt:.2f}s (Success: {ok})')
        return name, ok, res, dt

    t_start = time.time()
    with ThreadPoolExecutor(max_workers=2) as executor:
        fut1 = executor.submit(run_worker, 'Location-Req-1', req1_sql)
        fut2 = executor.submit(run_worker, 'Location-Req-2', req2_sql)
        r1 = fut1.result()
        r2 = fut2.result()
    total_loc_time = time.time() - t_start

    print(f'\nLocation Concurrency Total Time: {total_loc_time:.2f}s')
    print(f'Result 1: Success={r1[1]}, Duration={r1[3]:.2f}s, Output={str(r1[2])[:120]}')
    print(f'Result 2: Success={r2[1]}, Duration={r2[3]:.2f}s, Output={str(r2[2])[:120]}')

    # Verify exactly 1 succeeded and 1 failed
    loc_success_count = (1 if r1[1] else 0) + (1 if r2[1] else 0)
    failed_result = r2 if not r2[1] else r1
    assert loc_success_count == 1, f'Expected exactly 1 request to succeed, but {loc_success_count} succeeded'
    assert 'Location limit exceeded' in str(failed_result[2]), f'Expected "Location limit exceeded" in error, got: {failed_result[2]}'
    print('>>> TEST 1 VERIFICATION: Exactly 1 request succeeded, and 1 request failed with "Location limit exceeded" quota error!\n')

    # Check database active locations count
    ok, count_res = exec_sql("select count(*)::int as active_locations from public.business_locations where tenant_id = 'd0000000-0000-4000-8000-000000000001' and active = true;")
    assert count_res[0]['active_locations'] == 2, f'Expected active_locations = 2, got {count_res}'
    print(f'[DB ASSERTION] Active locations in database = {count_res[0]["active_locations"]} (strictly matches limit of 2, never breached)\n')

    # 3. Test 2: Concurrent Terminal Activation
    print('--- TEST 2: Two simultaneous terminal-activation requests when 1 slot remains ---')
    prep_terminal_sql = """
    do $$
    declare
      v_tenant uuid := 'd0000000-0000-4000-8000-000000000001'::uuid;
      v_loc uuid;
    begin
      -- Set subscription limit_overrides: max_terminals = 2
      update public.tenant_subscriptions
      set limit_overrides = '{"max_locations": 10, "max_terminals": 2}'::jsonb
      where tenant_id = v_tenant;

      -- Clean all devices for this tenant
      delete from public.business_devices where tenant_id = v_tenant;

      -- Get Main location
      select id into v_loc from public.business_locations where tenant_id = v_tenant and location_code = 'MAIN';

      -- Baseline: 1 active terminal. (1 slot remaining out of 2)
      insert into public.business_devices (
        tenant_id, location_id, device_code, name, app_type, status, activation_expires_at
      ) values (
        v_tenant, v_loc, 'CLIENT-MAIN-001', 'Primary Office PC', 'client', 'active', null
      );
    end $$;
    """
    ok, res = exec_sql(prep_terminal_sql)
    if not ok:
        raise SystemExit(f'Terminal setup failed: {res}')
    print('[SETUP] Configured: max_terminals = 2, active terminals = 1 (1 slot remaining)\n')

    term_req1_sql = """
    do $$
    declare
      v_tenant uuid := 'd0000000-0000-4000-8000-000000000001'::uuid;
      v_loc uuid;
    begin
      select id into v_loc from public.business_locations where tenant_id = v_tenant and location_code = 'MAIN';
      -- Request 1: Issues terminal 'POS-1' and holds transaction lock for 1.2s
      perform public.platform_device_issue_activation_v709(
        v_tenant, v_loc, 'POS Terminal Alpha', 'pos', 'POS-ALPHA', null
      );
      perform pg_sleep(1.2);
    end $$;
    """

    term_req2_sql = """
    do $$
    declare
      v_tenant uuid := 'd0000000-0000-4000-8000-000000000001'::uuid;
      v_loc uuid;
    begin
      select id into v_loc from public.business_locations where tenant_id = v_tenant and location_code = 'MAIN';
      -- Request 2: Concurrently attempts to issue terminal 'POS-2'
      perform public.platform_device_issue_activation_v709(
        v_tenant, v_loc, 'POS Terminal Beta', 'pos', 'POS-BETA', null
      );
    end $$;
    """

    t_start = time.time()
    with ThreadPoolExecutor(max_workers=2) as executor:
        fut1 = executor.submit(run_worker, 'Terminal-Req-1', term_req1_sql)
        fut2 = executor.submit(run_worker, 'Terminal-Req-2', term_req2_sql)
        r1 = fut1.result()
        r2 = fut2.result()
    total_term_time = time.time() - t_start

    print(f'\nTerminal Concurrency Total Time: {total_term_time:.2f}s')
    print(f'Result 1: Success={r1[1]}, Duration={r1[3]:.2f}s, Output={str(r1[2])[:120]}')
    print(f'Result 2: Success={r2[1]}, Duration={r2[3]:.2f}s, Output={str(r2[2])[:120]}')

    # Verify exactly 1 succeeded and 1 failed
    term_success_count = (1 if r1[1] else 0) + (1 if r2[1] else 0)
    failed_term_result = r2 if not r2[1] else r1
    assert term_success_count == 1, f'Expected exactly 1 request to succeed, but {term_success_count} succeeded'
    assert 'Terminal limit exceeded' in str(failed_term_result[2]), f'Expected "Terminal limit exceeded" in error, got: {failed_term_result[2]}'
    print('>>> TEST 2 VERIFICATION: Exactly 1 request succeeded, and 1 request failed with "Terminal limit exceeded" quota error!\n')

    # Check database active terminals count
    ok, count_term_res = exec_sql("select count(*)::int as active_terminals from public.business_devices where tenant_id = 'd0000000-0000-4000-8000-000000000001' and status in ('active', 'pending');")
    assert count_term_res[0]['active_terminals'] == 2, f'Expected active_terminals = 2, got {count_term_res}'
    print(f'[DB ASSERTION] Active/pending terminals in database = {count_term_res[0]["active_terminals"]} (strictly matches limit of 2, never breached)\n')

    # 4. Teardown
    teardown_sql = """
    do $$
    declare
      v_tenant uuid := 'd0000000-0000-4000-8000-000000000001'::uuid;
    begin
      set session_replication_role = 'replica';
      delete from public.business_devices where tenant_id = v_tenant;
      delete from public.business_locations where tenant_id = v_tenant;
      delete from public.tenant_subscriptions where tenant_id = v_tenant;
      delete from public.user_roles where tenant_id = v_tenant;
      delete from public.tenant_memberships where tenant_id = v_tenant;
      delete from public.roles where tenant_id = v_tenant;
      delete from public.thq_sync_state_v480 where tenant_id = v_tenant;
      delete from public.tenants where id = v_tenant;
      set session_replication_role = 'origin';
    end $$;
    """
    ok, res = exec_sql(teardown_sql)
    assert ok, f'Teardown failed: {res}'
    print('[TEARDOWN] Test tenant d0000000-0000-4000-8000-000000000001 completely cleaned up.')
    print('\n======================================================================')
    print('ALL GENUINE CONCURRENT QUOTA TESTS PASSED PERFECTLY!')
    print('======================================================================')

if __name__ == '__main__':
    run_concurrent_test()
