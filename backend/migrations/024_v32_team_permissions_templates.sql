-- FLEXI ERP V3.2
-- Client-managed team support and template/plan defaults.
begin;

create or replace function public.tenant_user_management_context(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_manage boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_manage:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'users.manage');
  return jsonb_build_object(
    'can_manage',v_manage,
    'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'key',r.key,'name',r.name,'is_system',coalesce(r.is_system,false)) order by r.name) from public.roles r where r.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or r.key<>'owner')),'[]'::jsonb),
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'code',l.location_code,'name',l.name) order by l.name) from public.business_locations l where l.tenant_id=p_tenant_id and l.active and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,l.id,'manage'))),'[]'::jsonb)
  );
end $$;
grant execute on function public.tenant_user_management_context(uuid) to authenticated;

create or replace function public.tenant_user_access_get(p_tenant_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'users.manage') then raise exception 'Permission denied';end if;
  return jsonb_build_object(
    'client_enabled',coalesce((select enabled from public.business_user_app_access where tenant_id=p_tenant_id and user_id=p_user_id and app_key='client'),true),
    'pos_enabled',coalesce((select enabled from public.business_user_app_access where tenant_id=p_tenant_id and user_id=p_user_id and app_key='pos'),false),
    'locations',coalesce((select jsonb_agg(jsonb_build_object('location_id',a.location_id,'access_level',a.access_level)) from public.business_user_location_access a where a.tenant_id=p_tenant_id and a.user_id=p_user_id),'[]'::jsonb)
  );
end $$;
grant execute on function public.tenant_user_access_get(uuid,uuid) to authenticated;

create or replace function public.tenant_user_access_set(
  p_tenant_id uuid,p_user_id uuid,p_client_enabled boolean,p_pos_enabled boolean,p_location_ids uuid[],p_access_level text default 'operate'
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'users.manage') then raise exception 'Permission denied';end if;
  if p_access_level not in ('view','operate','manage') then raise exception 'Invalid access level';end if;
  if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_user_id and status='active') then raise exception 'User is not an active member';end if;
  if private.erp_user_is_owner(p_tenant_id,p_user_id) and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Only an owner can alter owner access';end if;

  insert into public.business_user_app_access(tenant_id,user_id,app_key,enabled) values(p_tenant_id,p_user_id,'client',coalesce(p_client_enabled,true))
  on conflict(tenant_id,user_id,app_key) do update set enabled=excluded.enabled,updated_at=now();
  insert into public.business_user_app_access(tenant_id,user_id,app_key,enabled) values(p_tenant_id,p_user_id,'pos',coalesce(p_pos_enabled,false))
  on conflict(tenant_id,user_id,app_key) do update set enabled=excluded.enabled,updated_at=now();

  delete from public.business_user_location_access where tenant_id=p_tenant_id and user_id=p_user_id;
  insert into public.business_user_location_access(tenant_id,user_id,location_id,access_level)
  select p_tenant_id,p_user_id,l.id,p_access_level from public.business_locations l
  where l.tenant_id=p_tenant_id and l.active and l.id=any(coalesce(p_location_ids,'{}'::uuid[]))
  on conflict do update set access_level=excluded.access_level,updated_at=now();
end $$;
grant execute on function public.tenant_user_access_set(uuid,uuid,boolean,boolean,uuid[],text) to authenticated;

-- App access checker is callable by authenticated clients and by Edge Functions with a user token.
create or replace function public.current_user_app_access(p_tenant_id uuid,p_app_key text)
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$ select private.erp_user_has_tenant_access(p_tenant_id) and private.erp_user_app_allowed(p_tenant_id,p_app_key); $$;
grant execute on function public.current_user_app_access(uuid,text) to authenticated;

-- SKU check for editable automatic SKU field.
create or replace function public.inventory_sku_available(p_tenant_id uuid,p_sku text,p_variant_id uuid default null)
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select private.erp_user_has_tenant_access(p_tenant_id) and not exists(
    select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and upper(pv.sku)=upper(trim(p_sku)) and (p_variant_id is null or pv.id<>p_variant_id)
  );
$$;
grant execute on function public.inventory_sku_available(uuid,text,uuid) to authenticated;

-- Team module is enabled by default in templates/plans; POS contents still depend on terminal config.
insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key from public.business_templates bt cross join (values('users'),('locations')) x(module_key)
on conflict do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select sp.id,x.module_key from public.subscription_plans sp cross join (values('users'),('locations')) x(module_key)
on conflict do nothing;

-- Owner receives user permissions for enabled user module.
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key='users' and tm.enabled
join public.permissions p on p.module_key='users' where r.key='owner'
on conflict do nothing;

commit;
select 'V3.2 team/defaults ready' as status;
