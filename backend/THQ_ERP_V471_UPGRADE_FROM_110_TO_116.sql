
-- ============================================================================
-- 111_v471_system_admin_fixes.sql
-- ============================================================================
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


-- ============================================================================
-- 112_v471_customer_receivables.sql
-- ============================================================================
-- THQ ERP V4.7.1 — customer receivables, account receipts and invoice allocation.
begin;

create table if not exists public.customer_receipts(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  receipt_number text not null,
  receipt_date date not null default current_date,
  amount numeric not null check(amount>0),
  payment_method text not null,
  reference_number text,
  notes text,
  location_id uuid references public.business_locations(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(tenant_id,receipt_number)
);

create table if not exists public.customer_receipt_allocations(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  receipt_id uuid not null references public.customer_receipts(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  payment_id uuid,
  amount numeric not null check(amount>0),
  created_at timestamptz not null default now(),
  unique(receipt_id,sale_id)
);
create index if not exists idx_customer_receipts_customer_v471 on public.customer_receipts(tenant_id,customer_id,receipt_date desc,created_at desc);
create index if not exists idx_customer_receipt_allocations_sale_v471 on public.customer_receipt_allocations(tenant_id,sale_id);
alter table public.customer_receipts enable row level security;
alter table public.customer_receipt_allocations enable row level security;
revoke all on public.customer_receipts,public.customer_receipt_allocations from anon,authenticated;
create sequence if not exists public.customer_receipt_number_seq;

-- Customer receipts deliberately allocate into sale_payments so every existing report,
-- statement and outstanding calculation continues to use one source of truth.
-- The receipt flow sets a transaction-local marker; payment rows created under that
-- marker are accounted once at receipt level instead of once per allocation.
create or replace function private.v4_sale_payment_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant uuid;v_loc uuid;v_ref text;v_customer uuid;v_lines jsonb;v_receipt text;begin
  v_receipt:=current_setting('thq.customer_receipt_id',true);
  if nullif(v_receipt,'') is not null then return new;end if;
  select s.tenant_id,s.sale_number,s.customer_id,o.location_id into v_tenant,v_ref,v_customer,v_loc
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.id=new.sale_id;
  if v_tenant is null or v_loc is null then return new;end if;
  if exists(select 1 from public.journal_entries where tenant_id=v_tenant and source_type='sale_payment' and source_id=new.id) then return new;end if;
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(v_tenant,new.payment_method),'debit',new.amount,'credit',0,'party_type','customer','party_id',v_customer,'description','Customer receipt'),
    jsonb_build_object('account_id',private.v4_account_id(v_tenant,'accounts_receivable'),'debit',0,'credit',new.amount,'party_type','customer','party_id',v_customer,'description','Receivable settlement')
  );
  perform private.v4_journal_create(v_tenant,v_loc,coalesce(new.paid_at::date,current_date),'Customer receipt • '||v_ref,'sale_payment',new.id,v_ref,v_lines);
  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,'Customer cash receipt',auth.uid()
    from public.document_origins o join public.cashier_shifts sh on sh.tenant_id=v_tenant and sh.device_id=o.device_id and sh.status='open'
    where o.entity_type='sale' and o.entity_id=new.sale_id
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='sale_payment' and m.reference_id=new.id)
    limit 1;
  end if;
  return new;
end $$;

-- Dedicated cash-drawer type for payments of old customer balances. This avoids
-- incorrectly reporting a customer receipt as a new cash sale.
alter table public.cash_drawer_movements drop constraint if exists cash_drawer_movements_movement_type_check;
alter table public.cash_drawer_movements add constraint cash_drawer_movements_movement_type_check
  check(movement_type in('opening','sale','refund','cash_in','cash_out','expense','closing_adjustment','receipt'));

create or replace function public.cashier_shift_current_v4(p_tenant_id uuid,p_device_id uuid)
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
select coalesce((
  select to_jsonb(s) || jsonb_build_object(
    'cash_movement_total',coalesce(sum(m.amount),0),
    'expected_cash',coalesce(sum(m.amount),0),
    'cash_sales',coalesce(sum(case when m.movement_type='sale' then m.amount else 0 end),0),
    'customer_receipts',coalesce(sum(case when m.movement_type='receipt' then m.amount else 0 end),0),
    'cash_in',coalesce(sum(case when m.movement_type='cash_in' then m.amount else 0 end),0),
    'cash_out',abs(coalesce(sum(case when m.movement_type='cash_out' then m.amount else 0 end),0)),
    'cash_expenses',abs(coalesce(sum(case when m.movement_type='expense' then m.amount else 0 end),0)),
    'refunds',abs(coalesce(sum(case when m.movement_type='refund' then m.amount else 0 end),0))
  )
  from public.cashier_shifts s left join public.cash_drawer_movements m on m.shift_id=s.id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
  group by s.id limit 1
),'{}'::jsonb)
$$;
grant execute on function public.cashier_shift_current_v4(uuid,uuid) to authenticated;

create or replace function private.v471_platform_insert_sale_payment(
  p_sale_id uuid,p_amount numeric,p_method text,p_reference text,p_notes text
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;v_sql text;v_cols text:='sale_id,amount,payment_method';v_vals text:='$1,$2,$3';
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_payments' and column_name='reference_number') then
    v_cols:=v_cols||',reference_number';v_vals:=v_vals||',$4';
  end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_payments' and column_name='notes') then
    v_cols:=v_cols||',notes';
    v_vals:=v_vals||case when position('reference_number' in v_cols)>0 then ',$5' else ',$4' end;
  end if;
  v_sql:='insert into public.sale_payments('||v_cols||') values('||v_vals||') returning id';
  if position('reference_number' in v_cols)>0 and position('notes' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_reference,p_notes;
  elsif position('reference_number' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_reference;
  elsif position('notes' in v_cols)>0 then execute v_sql into v_id using p_sale_id,p_amount,p_method,p_notes;
  else execute v_sql into v_id using p_sale_id,p_amount,p_method;end if;
  return v_id;
end $$;
revoke all on function private.v471_platform_insert_sale_payment(uuid,numeric,text,text,text) from public;

create or replace function public.customer_account_v471(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_customer jsonb;v_invoices jsonb;v_receipts jsonb;v_outstanding numeric:=0;v_platform boolean:=private.platform_v2_is_admin();
begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not v_platform and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;
  select to_jsonb(c) into v_customer from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id;
  if v_customer is null then raise exception 'Customer not found';end if;
  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0),
    coalesce(jsonb_agg(jsonb_build_object(
      'sale_id',s.id,'sale_number',s.sale_number,'sale_date',s.sale_date,'due_date',s.due_date,'grand_total',s.grand_total,
      'paid',coalesce(py.paid,0),'returned',coalesce(rt.returned,0),'balance',greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0),'location_id',o.location_id,'location_name',l.name
    ) order by coalesce(s.due_date,s.sale_date),s.created_at) filter(where greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005),'[]'::jsonb)
  into v_outstanding,v_invoices
  from public.sales s
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'));

  select coalesce(jsonb_agg(jsonb_build_object(
    'receipt_id',r.id,'receipt_number',r.receipt_number,'receipt_date',r.receipt_date,'amount',r.amount,
    'payment_method',r.payment_method,'reference_number',r.reference_number,'notes',r.notes,'location_id',r.location_id,
    'location_name',l.name,'device_id',r.device_id,'device_name',d.name,'created_at',r.created_at,
    'allocations',coalesce((select jsonb_agg(jsonb_build_object('sale_id',a.sale_id,'sale_number',s.sale_number,'amount',a.amount))
      from public.customer_receipt_allocations a join public.sales s on s.id=a.sale_id where a.receipt_id=r.id),'[]'::jsonb)
  ) order by r.created_at desc),'[]'::jsonb) into v_receipts
  from public.customer_receipts r left join public.business_locations l on l.id=r.location_id left join public.business_devices d on d.id=r.device_id
  where r.tenant_id=p_tenant_id and r.customer_id=p_customer_id
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'));

  return jsonb_build_object('customer',v_customer,'outstanding',v_outstanding,'open_invoices',coalesce(v_invoices,'[]'::jsonb),'receipts',coalesce(v_receipts,'[]'::jsonb));
end $$;
grant execute on function public.customer_account_v471(uuid,uuid) to authenticated;

create or replace function public.customer_accounts_list_v471(p_tenant_id uuid,p_query text default null,p_limit integer default 500)
returns table(customer_id uuid,public_id text,customer_name text,phone text,credit_limit numeric,outstanding numeric,open_invoice_count bigint,last_sale_date date)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v_platform boolean:=private.platform_v2_is_admin();begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not v_platform and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;
  return query
  with visible_sales as (
    select s.id,s.customer_id,s.sale_date,s.grand_total,coalesce(py.paid,0)::numeric as paid,coalesce(rt.returned,0)::numeric as returned
    from public.sales s
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
      and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'))
  )
  select c.id,coalesce(c.tracking_code,''),c.name,coalesce(c.phone,''),coalesce(c.credit_limit,0),
    coalesce(sum(greatest(vs.grand_total-vs.returned-vs.paid,0)),0)::numeric,
    count(vs.id) filter(where greatest(vs.grand_total-vs.returned-vs.paid,0)>0.005),max(vs.sale_date)
  from public.customers c
  left join visible_sales vs on vs.customer_id=c.id
  where c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active' and not coalesce(c.is_walk_in,false)
    and (trim(coalesce(p_query,''))='' or lower(c.name) like '%'||lower(trim(p_query))||'%' or lower(coalesce(c.phone,'')) like '%'||lower(trim(p_query))||'%' or lower(coalesce(c.tracking_code,'')) like '%'||lower(trim(p_query))||'%')
  group by c.id,c.tracking_code,c.name,c.phone,c.credit_limit
  order by 6 desc,c.name limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
grant execute on function public.customer_accounts_list_v471(uuid,text,integer) to authenticated;

create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,
  p_sale_id uuid default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;v_receipt uuid:=gen_random_uuid();v_receipt_no text;v_remaining numeric:=round(coalesce(p_amount,0),2);v_total_outstanding numeric:=0;
  v_location uuid:=p_location_id;v_sale record;v_alloc numeric;v_result jsonb;v_payment_id uuid;v_started timestamptz:=clock_timestamp();v_lines jsonb;v_response jsonb;
  v_is_platform boolean:=private.platform_v2_is_admin();v_device_type text;v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');if v_existing is not null then return v_existing;end if;
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'payments.receive') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Receive payment permission required';end if;
  end if;
  if v_remaining<=0 then raise exception 'Payment amount must be greater than zero';end if;
  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false) for update;
  if not found then raise exception 'Select an active non-walk-in customer';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then raise exception 'Invalid payment method';end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found';end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then raise exception 'Collecting POS/location mismatch';end if;
      v_location:=v_device_location;
    else
      v_location:=coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0) into v_total_outstanding
  from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));
  if v_total_outstanding<=0.005 then raise exception 'Customer has no outstanding balance in the permitted scope';end if;
  if v_remaining>v_total_outstanding+0.005 then raise exception 'Payment % exceeds outstanding balance %',v_remaining,v_total_outstanding;end if;

  if v_location is null then
    select o.location_id into v_location from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null and v_is_platform then
    select id into v_location from public.business_locations where tenant_id=p_tenant_id and active order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then raise exception 'Could not determine collection location';end if;
  v_receipt_no:='RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');
  insert into public.customer_receipts(id,tenant_id,customer_id,receipt_number,receipt_date,amount,payment_method,reference_number,notes,location_id,device_id,created_by)
  values(v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,v_remaining,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid());

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance,o.location_id
    from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005 and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_sale.balance);
    v_payment_id:=null;
    if v_is_platform then
      v_payment_id:=private.v471_platform_insert_sale_payment(v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
    else
      v_result:=public.sales_add_payment_v32(p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
      begin v_payment_id:=nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;exception when others then v_payment_id:=null;end;
      if v_payment_id is null then
        select sp.id into v_payment_id from public.sale_payments sp where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds' order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;
    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);
    v_remaining:=v_remaining-v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);
  if v_remaining>0.005 then raise exception 'Could not allocate full receipt. Remaining %',v_remaining;end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,'description','Customer account receipt'),
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,'description','Receivable settlement')
  );
  perform private.v4_journal_create(p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,'customer_receipt',v_receipt,v_receipt_no,v_lines);

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write(p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null,
    jsonb_build_object('receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id));
  v_response:=jsonb_build_object('success',true,'receipt_id',v_receipt,'receipt_number',v_receipt_no,'amount',p_amount,'outstanding_before',v_total_outstanding,'outstanding_after',greatest(v_total_outstanding-p_amount,0));
  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;
grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(112,'4.7.1','Operational Stabilization Patch','Customer receivable accounts and partial/account-level receipt allocation with accounting and POS cash-drawer support.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.7.1 migration 112 customer receivables ready' as status;


-- ============================================================================
-- 113_v471_pos_operations.sql
-- ============================================================================
-- THQ ERP V4.7.1 — POS hold/resume and terminal operations completion.
begin;

-- Cashier Shift and Terminal Daily are POS operational capabilities. Ensure they are
-- available at business level whenever POS is enabled; per-terminal assignment still
-- controls whether an individual POS sees them.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tm.tenant_id,'cashier_shifts',true from public.tenant_modules tm where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do update set enabled=true;
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tm.tenant_id,'terminal_day',true from public.tenant_modules tm where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do update set enabled=true;

-- New businesses enabling POS later should receive the operational POS capabilities.
create or replace function private.v471_pos_operational_modules_sync()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if new.module_key='pos' and new.enabled then
    insert into public.tenant_modules(tenant_id,module_key,enabled) values(new.tenant_id,'cashier_shifts',true)
      on conflict(tenant_id,module_key) do update set enabled=true;
    insert into public.tenant_modules(tenant_id,module_key,enabled) values(new.tenant_id,'terminal_day',true)
      on conflict(tenant_id,module_key) do update set enabled=true;
  end if;
  return new;
end $$;
drop trigger if exists trg_v471_pos_operational_modules_sync on public.tenant_modules;
create trigger trg_v471_pos_operational_modules_sync after insert or update of enabled on public.tenant_modules
for each row when(new.module_key='pos') execute function private.v471_pos_operational_modules_sync();

-- Compact held-sale feed for the billing screen. It returns the held state too, allowing
-- the product screen to restore without a second lookup if desired.
create or replace function public.pos_held_sales_feed_v471(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz,state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(coalesce(h.state->'items','[]'::jsonb)),0),coalesce((h.state->>'total')::numeric,0),
    coalesce(ul.username::text,''),h.created_at,h.state
  from public.pos_held_sales h left join public.customers c on c.id=h.customer_id left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_feed_v471(uuid,uuid) to authenticated;

-- Return-aware Terminal Daily plus customer account receipts collected at this terminal.
create or replace function public.pos_terminal_day_v471(p_tenant_id uuid,p_device_id uuid,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v jsonb;v_receipts numeric:=0;v_receipt_count bigint:=0;v_receipt_rows jsonb:='[]'::jsonb;begin
  select public.pos_terminal_day_v45(p_tenant_id,p_device_id,p_day) into v;
  select coalesce(sum(r.amount),0),count(*) into v_receipts,v_receipt_count from public.customer_receipts r
  where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.receipt_date=p_day;
  select coalesce(jsonb_agg(jsonb_build_object('receipt_id',r.id,'receipt_number',r.receipt_number,'customer_id',r.customer_id,
    'customer_name',c.name,'amount',r.amount,'payment_method',r.payment_method,'reference_number',r.reference_number,'created_at',r.created_at)
    order by r.created_at desc),'[]'::jsonb) into v_receipt_rows
  from public.customer_receipts r join public.customers c on c.id=r.customer_id
  where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.receipt_date=p_day;
  return coalesce(v,'{}'::jsonb)||jsonb_build_object('customer_receipts',v_receipts,'customer_receipt_count',v_receipt_count,'customer_receipt_rows',v_receipt_rows);
end $$;
grant execute on function public.pos_terminal_day_v471(uuid,uuid,date) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(113,'4.7.1','Operational Stabilization Patch','POS held-sale feed, POS operational module provisioning, and customer receipts in Terminal Daily.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.7.1 migration 113 POS operations ready' as status;


-- ============================================================================
-- 114_v471_release_hardening.sql
-- ============================================================================
-- THQ ERP V4.7.1 — operational stabilization release hardening and verification.
begin;

-- One create contract for every logical system type. app_type remains the runtime
-- compatibility contract (pos/client); system_role describes how the installation is used.
create or replace function public.platform_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,
  p_platform_hint text default null,p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null,p_system_role text default null
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;v_id uuid;v_role text;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  v:=public.platform_system_create_v46(p_tenant_id,p_location_id,p_name,p_app_type,p_platform_hint,p_module_keys,p_invoice_prefix);
  v_id:=nullif(v->>'device_id','')::uuid;
  update public.business_devices set system_role=v_role,updated_at=now() where id=v_id and tenant_id=p_tenant_id;
  return v||jsonb_build_object('system_role',v_role,'location_id',p_location_id);
end $$;
grant execute on function public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

-- If Cashier Shift is enabled on a POS, a sale cannot bypass it. Existing idempotent
-- results are returned before this check, so a lost-response retry remains safe even
-- if the shift was closed after the original transaction committed.
create or replace function public.sales_create_v47(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_type text;v_modules text[];begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create'); if v is not null then return v;end if;
  if p_device_id is not null then
    select app_type,coalesce(allowed_modules,'{}'::text[]) into v_type,v_modules
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_type='pos' and 'cashier_shifts'=any(v_modules)
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before billing on this POS';
    end if;
  end if;
  v:=public.sales_create_v4(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'sale.create',v);
end $$;
grant execute on function public.sales_create_v47(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

-- Service-role-only deletion endpoint used after the Edge Function has reauthenticated
-- the Platform Super Admin and validated the immutable business code.
create or replace function public.platform_business_delete_v471(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_name text;begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required';end if;
  select name into v_name from public.tenants where id=p_tenant_id for update;
  if v_name is null then raise exception 'Business not found';end if;
  delete from public.tenants where id=p_tenant_id;
  if found then return jsonb_build_object('success',true,'tenant_id',p_tenant_id,'business_name',v_name);end if;
  raise exception 'Business delete did not complete';
end $$;
revoke all on function public.platform_business_delete_v471(uuid) from public,anon,authenticated;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;

-- Update backend compatibility contract for patched apps.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.7.1',2,'stable',false,false,
  'THQ ERP V4.7.1: held-sale resume feed, customer receivables/partial payments, system reassignment/deletion, POS module fixes, cashier shift enforcement and Terminal Daily completion.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),('admin','web')
) x(app_key,platform)
where not exists(select 1 from public.platform_app_releases r where r.app_key=x.app_key and r.platform=x.platform and r.version='4.7.1' and r.build_number=2);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(114,'4.7.1','Operational Stabilization Patch','Release verification: customer receivables, held sale feed, system hierarchy/admin fixes, cashier/day controls and app compatibility contract.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

do $$begin
  if to_regclass('public.customer_receipts') is null then raise exception 'Customer receipts table missing';end if;
  if to_regclass('public.customer_receipt_allocations') is null then raise exception 'Customer receipt allocations table missing';end if;
  if to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is null then raise exception 'Customer receive-payment RPC missing';end if;
  if to_regprocedure('public.customer_account_v471(uuid,uuid)') is null then raise exception 'Customer account RPC missing';end if;
  if to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is null then raise exception 'Held-sale feed missing';end if;
  if to_regprocedure('public.pos_terminal_day_v471(uuid,uuid,date)') is null then raise exception 'Terminal Daily V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text)') is null then raise exception 'System create V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'System update V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_delete_v471(uuid,uuid,text)') is null then raise exception 'System delete V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_location_delete_v471(uuid,uuid,text)') is null then raise exception 'Location delete V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text)') is null then raise exception 'Tenant system create V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'Tenant system update V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_revoke_v471(uuid,uuid,text)') is null then raise exception 'Tenant system revoke V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_business_delete_v471(uuid)') is null then raise exception 'Business delete V4.7.1 RPC missing';end if;
  if (select max(migration_no) from public.thq_schema_releases)<>114 then raise exception 'V4.7.1 schema release registration incomplete';end if;
end$$;

commit;
select 'THQ ERP V4.7.1 migrations 111-114 verified' as status;


-- ============================================================================
-- 115_v471_hotfix1_runtime_errors.sql
-- ============================================================================
-- THQ ERP V4.7.1 Hotfix 1
-- Runtime fixes found during release acceptance testing.
-- 1) Fix POS held-invoice feed: RETURNS TABLE output column `id` conflicted with an unqualified business_devices.id reference.
-- 2) Fix Admin/system/customer-receipt audit calls: private.business_audit_write has JSONB and UUID compatibility overloads, so an untyped NULL was ambiguous at runtime.
-- Safe to apply once after migration 114.
begin;

create or replace function public.platform_system_deactivate_v46(p_tenant_id uuid,p_device_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_code text;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select device_code into v_code from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_code is null then raise exception 'System not found';end if;
  update public.system_installations set status='inactive',deactivated_at=now(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and status='active';
  update public.business_devices set status='inactive',installation_id=null,device_secret_hash=null,last_seen_at=null,
    deactivated_at=now(),deactivated_by=auth.uid(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  perform private.business_audit_write(p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null::jsonb,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end$$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

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

  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
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
    perform private.business_audit_write(p_tenant_id,'system.archive','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','system_id',p_system_id,'message','System has transaction/installation history and was safely archived.');
  end if;

  delete from public.business_devices where id=p_system_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'system.delete','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
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
    perform private.business_audit_write(p_tenant_id,'location.archive','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','location_id',p_location_id,'message','Store has business history and was safely archived.');
  end if;

  delete from public.business_locations where id=p_location_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'location.delete','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','location_id',p_location_id,'message','Unused store permanently deleted.');
end $$;
grant execute on function public.platform_location_delete_v471(uuid,uuid,text) to authenticated;

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
  perform private.business_audit_write(p_tenant_id,'system.create','business_device',v_id,v_device_code,null::jsonb,jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules));
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
  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
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
  perform private.business_audit_write(p_tenant_id,'system.revoke','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',coalesce(p_reason,'Business manager revoke')));
  return jsonb_build_object('success',true,'system_id',p_system_id,'status','revoked');
end $$;
grant execute on function public.tenant_system_revoke_v471(uuid,uuid,text) to authenticated;

create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,
  p_sale_id uuid default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;v_receipt uuid:=gen_random_uuid();v_receipt_no text;v_remaining numeric:=round(coalesce(p_amount,0),2);v_total_outstanding numeric:=0;
  v_location uuid:=p_location_id;v_sale record;v_alloc numeric;v_result jsonb;v_payment_id uuid;v_started timestamptz:=clock_timestamp();v_lines jsonb;v_response jsonb;
  v_is_platform boolean:=private.platform_v2_is_admin();v_device_type text;v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');if v_existing is not null then return v_existing;end if;
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'payments.receive') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Receive payment permission required';end if;
  end if;
  if v_remaining<=0 then raise exception 'Payment amount must be greater than zero';end if;
  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false) for update;
  if not found then raise exception 'Select an active non-walk-in customer';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then raise exception 'Invalid payment method';end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found';end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then raise exception 'Collecting POS/location mismatch';end if;
      v_location:=v_device_location;
    else
      v_location:=coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0) into v_total_outstanding
  from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));
  if v_total_outstanding<=0.005 then raise exception 'Customer has no outstanding balance in the permitted scope';end if;
  if v_remaining>v_total_outstanding+0.005 then raise exception 'Payment % exceeds outstanding balance %',v_remaining,v_total_outstanding;end if;

  if v_location is null then
    select o.location_id into v_location from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null and v_is_platform then
    select id into v_location from public.business_locations where tenant_id=p_tenant_id and active order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then raise exception 'Could not determine collection location';end if;
  v_receipt_no:='RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');
  insert into public.customer_receipts(id,tenant_id,customer_id,receipt_number,receipt_date,amount,payment_method,reference_number,notes,location_id,device_id,created_by)
  values(v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,v_remaining,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid());

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance,o.location_id
    from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005 and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_sale.balance);
    v_payment_id:=null;
    if v_is_platform then
      v_payment_id:=private.v471_platform_insert_sale_payment(v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
    else
      v_result:=public.sales_add_payment_v32(p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
      begin v_payment_id:=nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;exception when others then v_payment_id:=null;end;
      if v_payment_id is null then
        select sp.id into v_payment_id from public.sale_payments sp where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds' order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;
    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);
    v_remaining:=v_remaining-v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);
  if v_remaining>0.005 then raise exception 'Could not allocate full receipt. Remaining %',v_remaining;end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,'description','Customer account receipt'),
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,'description','Receivable settlement')
  );
  perform private.v4_journal_create(p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,'customer_receipt',v_receipt,v_receipt_no,v_lines);

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write(p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null::jsonb,jsonb_build_object('receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id));
  v_response:=jsonb_build_object('success',true,'receipt_id',v_receipt,'receipt_number',v_receipt_no,'amount',p_amount,'outstanding_before',v_total_outstanding,'outstanding_after',greatest(v_total_outstanding-p_amount,0));
  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;
grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated;

create or replace function public.pos_held_sales_feed_v471(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz,state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(coalesce(h.state->'items','[]'::jsonb)),0),coalesce((h.state->>'total')::numeric,0),
    coalesce(ul.username::text,''),h.created_at,h.state
  from public.pos_held_sales h left join public.customers c on c.id=h.customer_id left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_feed_v471(uuid,uuid) to authenticated;

-- Keep the v4.7 contract compatible with the same 4.7.1 applications while reporting the hotfix migration.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch — Hotfix 1'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(115,'4.7.1','Operational Stabilization Patch — Hotfix 1',
  'Runtime fixes for held-sale feed ambiguous id and business_audit_write overload ambiguity in system/customer receipt operations.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

-- Sanity checks: definitions must exist after replacement.
do $$begin
  if to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is null then raise exception 'Held-sale feed missing after hotfix';end if;
  if to_regprocedure('public.platform_system_deactivate_v46(uuid,uuid,text)') is null then raise exception 'System deactivate RPC missing after hotfix';end if;
  if to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'System update RPC missing after hotfix';end if;
  if to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is null then raise exception 'Customer payment RPC missing after hotfix';end if;
end$$;

commit;
select 'THQ ERP V4.7.1 Hotfix 1 migration 115 applied' as status;


-- ============================================================================
-- 116_v471_hotfix2_audit_overload_hardening.sql
-- ============================================================================
-- THQ ERP V4.7.1 Hotfix 2
-- Harden audit writing for all V4.7.1 operational RPCs.
-- Root cause: private.business_audit_write has JSONB and UUID overloads for legacy compatibility.
-- Untyped NULL arguments can therefore be ambiguous. V4.7.1 now calls a uniquely named wrapper.
-- Safe to apply after migration 115. Reapplying the V4.7.1 RPC definitions is intentional.
begin;

create or replace function private.business_audit_write_v471(
  p_tenant_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_reference text,
  p_before jsonb,
  p_after jsonb
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  -- All argument types are fixed at this boundary, so PostgreSQL cannot choose
  -- the legacy UUID overload accidentally.
  perform private.business_audit_write(
    p_tenant_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_reference,
    p_before::jsonb,
    coalesce(p_after,'{}'::jsonb)::jsonb
  );
end $$;
revoke all on function private.business_audit_write_v471(uuid,text,text,uuid,text,jsonb,jsonb) from public;

create or replace function public.platform_system_deactivate_v46(p_tenant_id uuid,p_device_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_code text;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select device_code into v_code from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_code is null then raise exception 'System not found';end if;
  update public.system_installations set status='inactive',deactivated_at=now(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and status='active';
  update public.business_devices set status='inactive',installation_id=null,device_secret_hash=null,last_seen_at=null,
    deactivated_at=now(),deactivated_by=auth.uid(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  perform private.business_audit_write_v471(p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null::jsonb,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end$$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

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

  perform private.business_audit_write_v471(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
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
    perform private.business_audit_write_v471(p_tenant_id,'system.archive','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','system_id',p_system_id,'message','System has transaction/installation history and was safely archived.');
  end if;

  delete from public.business_devices where id=p_system_id and tenant_id=p_tenant_id;
  perform private.business_audit_write_v471(p_tenant_id,'system.delete','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
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
    perform private.business_audit_write_v471(p_tenant_id,'location.archive','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','location_id',p_location_id,'message','Store has business history and was safely archived.');
  end if;

  delete from public.business_locations where id=p_location_id and tenant_id=p_tenant_id;
  perform private.business_audit_write_v471(p_tenant_id,'location.delete','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','location_id',p_location_id,'message','Unused store permanently deleted.');
end $$;
grant execute on function public.platform_location_delete_v471(uuid,uuid,text) to authenticated;

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
  perform private.business_audit_write_v471(p_tenant_id,'system.create','business_device',v_id,v_device_code,null::jsonb,jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules));
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
  perform private.business_audit_write_v471(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
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
  perform private.business_audit_write_v471(p_tenant_id,'system.revoke','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',coalesce(p_reason,'Business manager revoke')));
  return jsonb_build_object('success',true,'system_id',p_system_id,'status','revoked');
end $$;
grant execute on function public.tenant_system_revoke_v471(uuid,uuid,text) to authenticated;

create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,
  p_sale_id uuid default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;v_receipt uuid:=gen_random_uuid();v_receipt_no text;v_remaining numeric:=round(coalesce(p_amount,0),2);v_total_outstanding numeric:=0;
  v_location uuid:=p_location_id;v_sale record;v_alloc numeric;v_result jsonb;v_payment_id uuid;v_started timestamptz:=clock_timestamp();v_lines jsonb;v_response jsonb;
  v_is_platform boolean:=private.platform_v2_is_admin();v_device_type text;v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');if v_existing is not null then return v_existing;end if;
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'payments.receive') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Receive payment permission required';end if;
  end if;
  if v_remaining<=0 then raise exception 'Payment amount must be greater than zero';end if;
  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false) for update;
  if not found then raise exception 'Select an active non-walk-in customer';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then raise exception 'Invalid payment method';end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found';end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then raise exception 'Collecting POS/location mismatch';end if;
      v_location:=v_device_location;
    else
      v_location:=coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0) into v_total_outstanding
  from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));
  if v_total_outstanding<=0.005 then raise exception 'Customer has no outstanding balance in the permitted scope';end if;
  if v_remaining>v_total_outstanding+0.005 then raise exception 'Payment % exceeds outstanding balance %',v_remaining,v_total_outstanding;end if;

  if v_location is null then
    select o.location_id into v_location from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null and v_is_platform then
    select id into v_location from public.business_locations where tenant_id=p_tenant_id and active order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then raise exception 'Could not determine collection location';end if;
  v_receipt_no:='RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');
  insert into public.customer_receipts(id,tenant_id,customer_id,receipt_number,receipt_date,amount,payment_method,reference_number,notes,location_id,device_id,created_by)
  values(v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,v_remaining,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid());

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance,o.location_id
    from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005 and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_sale.balance);
    v_payment_id:=null;
    if v_is_platform then
      v_payment_id:=private.v471_platform_insert_sale_payment(v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
    else
      v_result:=public.sales_add_payment_v32(p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
      begin v_payment_id:=nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;exception when others then v_payment_id:=null;end;
      if v_payment_id is null then
        select sp.id into v_payment_id from public.sale_payments sp where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds' order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;
    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);
    v_remaining:=v_remaining-v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);
  if v_remaining>0.005 then raise exception 'Could not allocate full receipt. Remaining %',v_remaining;end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,'description','Customer account receipt'),
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,'description','Receivable settlement')
  );
  perform private.v4_journal_create(p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,'customer_receipt',v_receipt,v_receipt_no,v_lines);

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write_v471(p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null::jsonb,jsonb_build_object('receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id));
  v_response:=jsonb_build_object('success',true,'receipt_id',v_receipt,'receipt_number',v_receipt_no,'amount',p_amount,'outstanding_before',v_total_outstanding,'outstanding_after',greatest(v_total_outstanding-p_amount,0));
  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;
grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated;

create or replace function public.pos_held_sales_feed_v471(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz,state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(coalesce(h.state->'items','[]'::jsonb)),0),coalesce((h.state->>'total')::numeric,0),
    coalesce(ul.username::text,''),h.created_at,h.state
  from public.pos_held_sales h left join public.customers c on c.id=h.customer_id left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_feed_v471(uuid,uuid) to authenticated;
-- Report the hotfix level through the existing V4.7 contract.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch — Hotfix 2'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(116,'4.7.1','Operational Stabilization Patch — Hotfix 2',
  'Routes V4.7.1 system and receivables RPCs through a unique audit writer to permanently avoid overloaded business_audit_write NULL ambiguity.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

do $$
declare vdef text;
begin
  if to_regprocedure('private.business_audit_write_v471(uuid,text,text,uuid,text,jsonb,jsonb)') is null then
    raise exception 'V4.7.1 audit writer missing after Hotfix 2';
  end if;

  select pg_get_functiondef('public.tenant_system_revoke_v471(uuid,uuid,text)'::regprocedure) into vdef;
  if position('business_audit_write_v471' in vdef)=0 then raise exception 'Client system revoke was not hardened'; end if;

  select pg_get_functiondef('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)'::regprocedure) into vdef;
  if position('business_audit_write_v471' in vdef)=0 then raise exception 'Client system update was not hardened'; end if;

  select pg_get_functiondef('public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text)'::regprocedure) into vdef;
  if position('business_audit_write_v471' in vdef)=0 then raise exception 'Client system create was not hardened'; end if;

  select pg_get_functiondef('public.platform_system_deactivate_v46(uuid,uuid,text)'::regprocedure) into vdef;
  if position('business_audit_write_v471' in vdef)=0 then raise exception 'Admin system deactivate was not hardened'; end if;

  select pg_get_functiondef('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)'::regprocedure) into vdef;
  if position('business_audit_write_v471' in vdef)=0 then raise exception 'Customer receipt was not hardened'; end if;
end $$;

commit;
select 'THQ ERP V4.7.1 Hotfix 2 migration 116 applied' as status;
