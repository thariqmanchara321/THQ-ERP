-- THQ ERP V4.7.1 — system/store administration fixes and hierarchy cleanup.
begin;

alter table public.business_devices
  add column if not exists system_role text;

update public.business_devices
set system_role = case when app_type='pos' then 'pos' else 'office' end
where system_role is null or trim(system_role)='';

alter table public.business_devices
  alter column system_role set default 'office';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='business_devices_system_role_check') then
    alter table public.business_devices add constraint business_devices_system_role_check
      check(system_role in('pos','back_office','office','inventory'));
  end if;
end $$;

-- Existing V4 updater omitted terminal_day. Keep its public name compatible and correct it.
create or replace function public.platform_device_settings_update(
  p_tenant_id uuid,p_device_id uuid,p_module_keys text[],p_invoice_prefix text,p_name text default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_type text;v_modules text[];begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select app_type into v_type from public.business_devices where id=p_device_id and tenant_id=p_tenant_id;
  if v_type is null then raise exception 'System not found';end if;
  if v_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
    select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.id<>p_device_id and d.status<>'revoked'
      and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))
  ) then raise exception 'Terminal invoice prefix is already in use';end if;
  update public.business_devices
  set allowed_modules=v_modules,invoice_prefix=case when v_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else invoice_prefix end,
      name=coalesce(nullif(trim(p_name),''),name),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.platform_device_settings_update(uuid,uuid,text[],text,text) to authenticated;

create or replace function public.platform_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],
  p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_modules text[];v_role text;v_old_location uuid;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;
  v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;

  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then
      raise exception 'Close the cashier shift before moving this system to another store';
    end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then
      raise exception 'Resume or remove held invoices before moving this POS to another store';
    end if;
  end if;

  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
      select 1 from public.business_devices x where x.tenant_id=p_tenant_id and x.id<>p_system_id and x.status<>'revoked'
       and upper(coalesce(x.invoice_prefix,''))=upper(trim(p_invoice_prefix))
    ) then raise exception 'Terminal invoice prefix is already in use';end if;
  else
    v_modules:='{}'::text[];
  end if;

  update public.business_devices
  set location_id=p_location_id,name=coalesce(nullif(trim(p_name),''),name),allowed_modules=v_modules,
      invoice_prefix=case when d.app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else invoice_prefix end,
      system_role=v_role,updated_at=now()
  where id=p_system_id;

  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null,
    jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules);
end $$;
grant execute on function public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

create or replace function public.platform_system_delete_v471(p_tenant_id uuid,p_system_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_has_history boolean:=false;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;

  select exists(select 1 from public.document_origins where tenant_id=p_tenant_id and device_id=p_system_id)
      or exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id)
      or exists(select 1 from public.system_installations where tenant_id=p_tenant_id and system_id=p_system_id)
  into v_has_history;

  delete from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id;
  update public.system_installations set status='revoked',deactivated_at=coalesce(deactivated_at,now()),
    deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'System removed from Admin')
  where tenant_id=p_tenant_id and system_id=p_system_id and status<>'revoked';

  if v_has_history then
    update public.business_devices set status='revoked',installation_id=null,device_secret_hash=null,activation_hash=null,
      activation_expires_at=null,last_seen_at=null,deactivated_at=coalesce(deactivated_at,now()),deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'System removed from Admin'),updated_at=now()
    where id=p_system_id;
    perform private.business_audit_write(p_tenant_id,'system.archive','business_device',p_system_id,d.device_code,null,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','system_id',p_system_id,'message','System has transaction/installation history and was safely archived.');
  end if;

  delete from public.business_devices where id=p_system_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'system.delete','business_device',p_system_id,d.device_code,null,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','system_id',p_system_id,'message','Unused system permanently deleted.');
end $$;
grant execute on function public.platform_system_delete_v471(uuid,uuid,text) to authenticated;

create or replace function public.platform_location_delete_v471(p_tenant_id uuid,p_location_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare l public.business_locations%rowtype;v_has_history boolean:=false;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into l from public.business_locations where id=p_location_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Store/location not found';end if;
  if coalesce(l.hierarchy_role,'')='main_store' or upper(coalesce(l.location_code,''))='MAIN' then
    raise exception 'MAIN STORE cannot be deleted. Rename/edit it instead.';
  end if;
  if exists(select 1 from public.business_devices where tenant_id=p_tenant_id and location_id=p_location_id and status<>'revoked') then
    raise exception 'Move or delete the systems assigned to this store before deleting it';
  end if;
  if exists(select 1 from public.business_locations where tenant_id=p_tenant_id and parent_location_id=p_location_id and active) then
    raise exception 'Move/archive child locations before deleting this store';
  end if;
  select exists(select 1 from public.document_origins where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id)
  into v_has_history;

  if v_has_history then
    update public.business_locations set active=false,updated_at=now() where id=p_location_id;
    perform private.business_audit_write(p_tenant_id,'location.archive','business_location',p_location_id,l.location_code,null,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','location_id',p_location_id,'message','Store has business history and was safely archived.');
  end if;

  delete from public.business_locations where id=p_location_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'location.delete','business_location',p_location_id,l.location_code,null,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','location_id',p_location_id,'message','Unused store permanently deleted.');
end $$;
grant execute on function public.platform_location_delete_v471(uuid,uuid,text) to authenticated;

-- Include system_role in the Admin system list.
drop function if exists public.platform_systems_list_v471(uuid);
create function public.platform_systems_list_v471(p_tenant_id uuid)
returns table(
  id uuid,location_id uuid,location_name text,location_code text,device_code text,tracking_code text,
  name text,app_type text,system_role text,platform_hint text,status text,allowed_modules text[],invoice_prefix text,
  installation_id text,activated_at timestamptz,activation_issued_at timestamptz,last_seen_at timestamptz,
  deactivated_at timestamptz,deactivation_reason text,created_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select d.id,d.location_id,l.name,l.location_code,d.device_code,d.tracking_code,d.name,d.app_type,
    coalesce(d.system_role,case when d.app_type='pos' then 'pos' else 'office' end),d.platform_hint,d.status,d.allowed_modules,d.invoice_prefix,
    d.installation_id,d.activated_at,d.activation_issued_at,d.last_seen_at,d.deactivated_at,d.deactivation_reason,d.created_at
  from public.business_devices d join public.business_locations l on l.id=d.location_id
  where d.tenant_id=p_tenant_id order by l.sort_order,l.name,d.app_type,d.created_at;
end $$;
grant execute on function public.platform_systems_list_v471(uuid) to authenticated;


-- Business-owner/delegated-manager system lifecycle. This mirrors the v4.7.1 logical
-- system model without granting Platform Admin privileges to business users.
create or replace function public.tenant_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$
declare v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];v_role text;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') then raise exception 'Location manage access denied';end if;
  if p_app_type not in('client','pos') then raise exception 'Invalid app type';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix,system_role)
  values(v_id,p_tenant_id,p_location_id,v_device_code,coalesce(nullif(trim(p_name),''),'System'),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,case when p_app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else null end,v_role);
  perform private.business_audit_write(p_tenant_id,'system.create','business_device',v_id,v_device_code,null,jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules,'system_role',v_role);
end $$;
grant execute on function public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_modules text[];v_role text;v_old_location uuid;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;if not found then raise exception 'System not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and (not private.erp_user_location_allowed(p_tenant_id,d.location_id,'manage') or not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage')) then raise exception 'Location manage access denied';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before moving this system to another store';end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then raise exception 'Resume or remove held invoices before moving this POS to another store';end if;
  end if;
  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices x where x.tenant_id=p_tenant_id and x.id<>p_system_id and x.status<>'revoked' and upper(coalesce(x.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  else v_modules:='{}'::text[];end if;
  update public.business_devices set location_id=p_location_id,name=coalesce(nullif(trim(p_name),''),name),allowed_modules=v_modules,invoice_prefix=case when d.app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else invoice_prefix end,system_role=v_role,updated_at=now() where id=p_system_id;
  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules);
end $$;
grant execute on function public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_revoke_v471(p_tenant_id uuid,p_system_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare d public.business_devices%rowtype;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;if not found then raise exception 'System not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,d.location_id,'manage') then raise exception 'Location manage access denied';end if;
  if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before revoking this POS';end if;
  update public.system_installations set status='revoked',deactivated_at=coalesce(deactivated_at,now()),deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'Revoked by business manager') where tenant_id=p_tenant_id and system_id=p_system_id and status<>'revoked';
  update public.business_devices set status='revoked',activation_hash=null,activation_expires_at=null,device_secret_hash=null,installation_id=null,updated_at=now() where id=p_system_id;
  perform private.business_audit_write(p_tenant_id,'system.revoke','business_device',p_system_id,d.device_code,null,jsonb_build_object('reason',coalesce(p_reason,'Business manager revoke')));
  return jsonb_build_object('success',true,'system_id',p_system_id,'status','revoked');
end $$;
grant execute on function public.tenant_system_revoke_v471(uuid,uuid,text) to authenticated;

-- Keep the Client directory on the same system terminology and expose logical role.
create or replace function public.tenant_locations_devices_list_v42(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_all boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  return jsonb_build_object(
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'parent_location_id',l.parent_location_id,'location_code',l.location_code,'tracking_code',l.tracking_code,'name',l.name,'location_type',l.location_type,'hierarchy_role',l.hierarchy_role,'sort_order',l.sort_order,'phone',l.phone,'email',l.email,'gstin',l.gstin,'address_line1',l.address_line1,'address_line2',l.address_line2,'city',l.city,'state',l.state,'postal_code',l.postal_code,'country',l.country,'invoice_prefix',l.invoice_prefix,'settings',coalesce(l.settings,'{}'::jsonb),'active',l.active,'access_level',case when v_all then 'manage' else a.access_level end) order by case when l.hierarchy_role='main_store' then 0 when l.hierarchy_role='warehouse' then 2 else 1 end,l.sort_order,l.name) from public.business_locations l left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id where l.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'location_id',d.location_id,'device_code',d.device_code,'tracking_code',d.tracking_code,'name',d.name,'app_type',d.app_type,'system_role',d.system_role,'platform_hint',d.platform_hint,'status',d.status,'allowed_modules',d.allowed_modules,'invoice_prefix',d.invoice_prefix,'activated_at',d.activated_at,'last_seen_at',d.last_seen_at,'settings',coalesce(d.settings,'{}'::jsonb)) order by d.created_at desc) from public.business_devices d join public.business_locations l on l.id=d.location_id left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id where d.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb)
  );
end $$;
grant execute on function public.tenant_locations_devices_list_v42(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(111,'4.7.1','Operational Stabilization Patch','Fix POS module editing, system reassignment, safe store/system deletion, and explicit system roles.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.7.1 migration 111 system/admin fixes ready' as status;
