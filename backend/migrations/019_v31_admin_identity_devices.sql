-- Flexi ERP V3.1 - platform identity/device helper RPCs
begin;

create or replace function public.platform_username_lookup(p_username text)
returns table(user_id uuid, username text, display_name text)
language plpgsql security definer set search_path=''
as $$ begin
  if not public.current_user_is_platform_admin() then raise exception 'Platform admin required'; end if;
  return query select n.user_id,n.username,null::text as display_name
  from public.user_login_names n
  where n.username=lower(trim(p_username));
end $$;

create or replace function public.platform_business_identity(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare r jsonb; begin
  if not public.current_user_is_platform_admin() then raise exception 'Platform admin required'; end if;
  select jsonb_build_object('tenant_id',t.id,'business_code',t.business_code,'name',t.name,'slug',t.slug,'status',t.status)
  into r from public.tenants t where t.id=p_tenant_id;
  return coalesce(r,'{}'::jsonb);
end $$;

create or replace function public.platform_usernames_list(p_tenant_id uuid default null)
returns table(user_id uuid, username text, display_name text, tenant_id uuid, tenant_name text)
language plpgsql security definer set search_path=''
as $$ begin
  if not public.current_user_is_platform_admin() then raise exception 'Platform admin required'; end if;
  return query
  select distinct n.user_id,n.username,null::text as display_name,tm.tenant_id,t.name
  from public.user_login_names n
  left join public.tenant_memberships tm on tm.user_id=n.user_id and tm.status='active'
  left join public.tenants t on t.id=tm.tenant_id
  where p_tenant_id is null or tm.tenant_id=p_tenant_id
  order by n.username;
end $$;

revoke all on function public.platform_username_lookup(text) from public,anon,authenticated;
revoke all on function public.platform_business_identity(uuid) from public,anon,authenticated;
revoke all on function public.platform_usernames_list(uuid) from public,anon,authenticated;
grant execute on function public.platform_username_lookup(text) to authenticated;
grant execute on function public.platform_business_identity(uuid) to authenticated;
grant execute on function public.platform_usernames_list(uuid) to authenticated;


create or replace function public.platform_admins_v3_list()
returns table(user_id uuid,username text,email text,role_key text,active boolean,created_at timestamptz)
language plpgsql security definer set search_path=public,private,auth,pg_temp
as $$ begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin access required'; end if;
  return query select a.user_id,coalesce(n.username,''),u.email::text,a.role_key,a.active,a.created_at
  from private.platform_admin_role_assignments a join auth.users u on u.id=a.user_id left join public.user_login_names n on n.user_id=a.user_id
  order by coalesce(n.username,u.email::text);
end $$;
grant execute on function public.platform_admins_v3_list() to authenticated;

create or replace function public.platform_admin_v3_grant(p_username text,p_role_key text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_user uuid;begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin access required'; end if;
  if p_role_key not in ('super_admin','support_admin','billing_admin','sales_admin','technical_admin','auditor') then raise exception 'Invalid platform role'; end if;
  select user_id into v_user from public.user_login_names where username=lower(trim(p_username));
  if v_user is null then raise exception 'No Flexi ERP user exists with this username';end if;
  insert into private.platform_admin_role_assignments(user_id,role_key,active,created_by) values(v_user,p_role_key,true,auth.uid())
  on conflict(user_id) do update set role_key=excluded.role_key,active=true,updated_at=now();
  perform private.platform_audit_write('platform_admin.grant','platform_admin',v_user::text,null,jsonb_build_object('username',lower(trim(p_username)),'role_key',p_role_key));
end $$;
grant execute on function public.platform_admin_v3_grant(text,text) to authenticated;

commit;
