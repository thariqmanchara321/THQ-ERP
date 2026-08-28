-- FLEXI ERP V3.2
-- Admin-selectable POS modules, client-visible branch/system directory,
-- owner-managed locations and app/location access.
begin;

-- Replace issue activation with a V3.2 version that stores terminal modules and prefix.
create or replace function public.platform_device_issue_activation_v32(
  p_tenant_id uuid,
  p_location_id uuid,
  p_name text,
  p_app_type text,
  p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,extensions,pg_temp
as $$ declare
  v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  if p_app_type not in ('client','pos') then raise exception 'Invalid app type';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid location';end if;

  if p_app_type='pos' then
    select coalesce(array_agg(distinct x), '{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in ('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else
    v_modules:='{}'::text[];
  end if;

  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
    select 1 from public.business_devices d
    where d.tenant_id=p_tenant_id and d.status<>'revoked'
      and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))
  ) then raise exception 'Terminal invoice prefix is already in use'; end if;

  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
  v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix)
  values(v_id,p_tenant_id,p_location_id,v_device_code,trim(p_name),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,nullif(upper(trim(p_invoice_prefix)),''));
  perform private.platform_audit_write('device.activation_issue','business_device',v_id::text,p_tenant_id,jsonb_build_object('device_code',v_device_code,'app_type',p_app_type,'location_id',p_location_id,'modules',v_modules));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules);
end $$;
grant execute on function public.platform_device_issue_activation_v32(uuid,uuid,text,text,text,text[],text) to authenticated;

create or replace function public.platform_device_settings_update(
  p_tenant_id uuid,p_device_id uuid,p_module_keys text[],p_invoice_prefix text,p_name text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_type text;v_modules text[];begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select app_type into v_type from public.business_devices where id=p_device_id and tenant_id=p_tenant_id;
  if v_type is null then raise exception 'Device not found';end if;
  if v_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in ('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
    select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.id<>p_device_id and d.status<>'revoked'
      and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))
  ) then raise exception 'Terminal invoice prefix is already in use'; end if;
  update public.business_devices set allowed_modules=v_modules,invoice_prefix=nullif(upper(trim(p_invoice_prefix)),''),name=coalesce(nullif(trim(p_name),''),name),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id;
  perform private.platform_audit_write('device.settings_update','business_device',p_device_id::text,p_tenant_id,jsonb_build_object('modules',v_modules,'invoice_prefix',p_invoice_prefix));
end $$;
grant execute on function public.platform_device_settings_update(uuid,uuid,text[],text,text) to authenticated;

drop function if exists public.platform_business_devices_list(uuid);
create or replace function public.platform_business_devices_list(p_tenant_id uuid)
returns table(
  id uuid,tenant_id uuid,location_id uuid,location_name text,device_code text,tracking_code text,name text,app_type text,platform_hint text,status text,
  allowed_modules text[],invoice_prefix text,activated_at timestamptz,last_seen_at timestamptz,created_at timestamptz
) language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select d.id,d.tenant_id,d.location_id,l.name,d.device_code,d.tracking_code,d.name,d.app_type,d.platform_hint,d.status,d.allowed_modules,d.invoice_prefix,d.activated_at,d.last_seen_at,d.created_at
  from public.business_devices d join public.business_locations l on l.id=d.location_id where d.tenant_id=p_tenant_id order by d.created_at desc;
end $$;
grant execute on function public.platform_business_devices_list(uuid) to authenticated;

-- Client runtime context. Device module list limits POS independently from tenant modules.
create or replace function public.client_runtime_context(p_tenant_id uuid,p_device_id uuid,p_app_key text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_all boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_app_allowed(p_tenant_id,p_app_key) then raise exception 'This user is not enabled for this application';end if;
  if not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.app_type=p_app_key and d.status='active') then raise exception 'Device is not active';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  select jsonb_build_object(
    'device_id',d.id,'device_code',d.device_code,'device_name',d.name,'device_modules',coalesce(to_jsonb(d.allowed_modules),'[]'::jsonb),
    'location_id',d.location_id,'location_code',l.location_code,'location_name',l.name,
    'can_view_all_locations',v_all,
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'code',x.location_code,'name',x.name,'type',x.location_type,'tracking_code',x.tracking_code,'access_level',case when v_all then 'manage' else a.access_level end) order by x.name)
      from public.business_locations x
      left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=x.id
      where x.tenant_id=p_tenant_id and x.active and (v_all or a.user_id is not null)),'[]'::jsonb)
  ) into v
  from public.business_devices d join public.business_locations l on l.id=d.location_id
  where d.id=p_device_id and d.tenant_id=p_tenant_id;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.client_runtime_context(uuid,uuid,text) to authenticated;

-- Tenant side directory for owner/authorized managers.
create or replace function public.tenant_locations_devices_list(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_all boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage');
  return jsonb_build_object(
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'parent_location_id',l.parent_location_id,'location_code',l.location_code,'tracking_code',l.tracking_code,'name',l.name,'location_type',l.location_type,'phone',l.phone,'email',l.email,'gstin',l.gstin,'invoice_prefix',l.invoice_prefix,'active',l.active) order by l.name)
      from public.business_locations l left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id
      where l.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'location_id',d.location_id,'device_code',d.device_code,'tracking_code',d.tracking_code,'name',d.name,'app_type',d.app_type,'status',d.status,'allowed_modules',d.allowed_modules,'invoice_prefix',d.invoice_prefix,'last_seen_at',d.last_seen_at) order by d.created_at desc)
      from public.business_devices d join public.business_locations l on l.id=d.location_id left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id
      where d.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb)
  );
end $$;
grant execute on function public.tenant_locations_devices_list(uuid) to authenticated;

create or replace function public.tenant_business_location_save(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,p_phone text,p_email text,p_gstin text,p_invoice_prefix text,p_active boolean
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Location name required';end if;
  if p_location_id is null then
    insert into public.business_locations(tenant_id,parent_location_id,location_code,name,location_type,phone,email,gstin,invoice_prefix,active)
    values(p_tenant_id,p_parent_location_id,upper(trim(p_location_code)),trim(p_name),p_location_type,nullif(trim(p_phone),''),nullif(trim(p_email),''),nullif(trim(p_gstin),''),nullif(upper(trim(p_invoice_prefix)),''),coalesce(p_active,true)) returning id into v_id;
  else
    if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
    update public.business_locations set parent_location_id=p_parent_location_id,location_code=upper(trim(p_location_code)),name=trim(p_name),location_type=p_location_type,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),gstin=nullif(trim(p_gstin),''),invoice_prefix=nullif(upper(trim(p_invoice_prefix)),''),active=coalesce(p_active,true),updated_at=now()
    where id=p_location_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function public.tenant_business_location_save(uuid,uuid,uuid,text,text,text,text,text,text,text,boolean) to authenticated;

-- Permissions/module for Client team and richer branch scope.
insert into public.modules(key,name,description,is_core,category,sort_order,is_active,is_beta,requires_configuration)
values('users','Team & Access','Business users, POS access and store scope',false,'administration',905,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,sort_order=excluded.sort_order,is_active=true;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select id,'users',true from public.tenants on conflict(tenant_id,module_key) do update set enabled=true;

-- Locations/Stores are a V3.2 platform foundation for every tenant. A business can
-- still choose whether to create child stores; MAIN remains the default store.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select id,'locations',true from public.tenants
on conflict(tenant_id,module_key) do update set enabled=true;

do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description) values
      ('users.view','View Team','users','View business users and access'),
      ('users.manage','Manage Team','users','Create/edit users, POS access and location scope'),
      ('locations.view_all','View All Locations','locations','View merged/all store data'),
      ('locations.manage_all','Manage All Locations','locations','Operate and manage all stores')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
      ('users.view','View Team','users'),('users.manage','Manage Team','users'),('locations.view_all','View All Locations','locations'),('locations.manage_all','Manage All Locations','locations')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r cross join (values('users.view'),('users.manage'),('locations.view_all'),('locations.manage_all')) p(key)
where r.key='owner' on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.permissions p on p.module_key in ('locations','users')
where r.key='owner'
on conflict do nothing;


-- Tenant owner/authorized manager can add/revoke systems under their own business.
create or replace function public.tenant_device_issue_activation(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null
)
returns jsonb language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
  if p_app_type not in ('client','pos') then raise exception 'Invalid app type';end if;
  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in ('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
    select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked'
      and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))
  ) then raise exception 'Terminal invoice prefix is already in use'; end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
  v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix)
  values(v_id,p_tenant_id,p_location_id,v_device_code,trim(p_name),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,nullif(upper(trim(p_invoice_prefix)),''));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules);
end $$;
grant execute on function public.tenant_device_issue_activation(uuid,uuid,text,text,text,text[],text) to authenticated;

create or replace function public.tenant_device_settings_update(p_tenant_id uuid,p_device_id uuid,p_module_keys text[],p_invoice_prefix text,p_name text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_type text;v_modules text[];begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  select location_id,app_type into v_loc,v_type from public.business_devices where tenant_id=p_tenant_id and id=p_device_id;
  if v_loc is null then raise exception 'Device not found';end if;
  if not private.erp_user_location_allowed(p_tenant_id,v_loc,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
  if v_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in ('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
    select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.id<>p_device_id and d.status<>'revoked'
      and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))
  ) then raise exception 'Terminal invoice prefix is already in use'; end if;
  update public.business_devices set allowed_modules=v_modules,invoice_prefix=nullif(upper(trim(p_invoice_prefix)),''),name=coalesce(nullif(trim(p_name),''),name),updated_at=now() where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.tenant_device_settings_update(uuid,uuid,text[],text,text) to authenticated;

create or replace function public.tenant_device_revoke(p_tenant_id uuid,p_device_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  select location_id into v_loc from public.business_devices where tenant_id=p_tenant_id and id=p_device_id;
  if v_loc is null then raise exception 'Device not found';end if;
  if not private.erp_user_location_allowed(p_tenant_id,v_loc,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
  update public.business_devices set status='revoked',activation_hash=null,device_secret_hash=null,updated_at=now() where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.tenant_device_revoke(uuid,uuid) to authenticated;


commit;
select 'V3.2 device modules/location access ready' as status;
