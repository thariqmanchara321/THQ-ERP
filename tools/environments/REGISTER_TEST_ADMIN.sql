-- Run only in THQ-ERP-MIGRATION-TEST, after creating a confirmed Auth user
-- in Dashboard > Authentication > Users > Add user.
-- Replace the email below with that test user's email. No password goes here.
do $test_setup$
declare
  v_email text := 'replace-with-your-test-email@example.com';
  v_user_id uuid;
begin
  if not exists (select 1 from private.thq_test_environment_identity
                 where singleton and project_ref='krejepenqgcmnsugbpmv') then
    raise exception 'This script requires the assigned THQ TEST database.';
  end if;
  select id into strict v_user_id from auth.users where lower(email)=lower(v_email);
  insert into public.profiles(id,display_name) values(v_user_id,'THQ Test Admin')
    on conflict(id) do nothing;
  insert into public.user_login_names(user_id,username,auth_email)
    values(v_user_id,'thq_test_admin',v_email)
    on conflict(user_id) do update set username=excluded.username,auth_email=excluded.auth_email;
  insert into private.platform_admins(user_id,role,status)
    values(v_user_id,'super_admin','active')
    on conflict(user_id) do update set role=excluded.role,status=excluded.status;
  insert into private.platform_admin_role_assignments(user_id,role_key,active)
    values(v_user_id,'super_admin',true)
    on conflict(user_id) do update set role_key=excluded.role_key,active=true;
end
$test_setup$;
