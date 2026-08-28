-- THQ ERP V4.7 — logical system vs physical installation separation.
begin;

create table if not exists public.system_installations(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  system_id uuid not null references public.business_devices(id) on delete cascade,
  installation_id text not null,
  secret_hash text,
  status text not null default 'active' check(status in('active','inactive','revoked')),
  platform_hint text,
  app_version text,
  activated_at timestamptz not null default now(),
  last_seen_at timestamptz,
  deactivated_at timestamptz,
  deactivation_reason text,
  created_at timestamptz not null default now()
);
create unique index if not exists ux_system_installations_active_installation
  on public.system_installations(installation_id) where status='active';
create unique index if not exists ux_system_installations_active_system
  on public.system_installations(system_id) where status='active';
create index if not exists idx_system_installations_history
  on public.system_installations(tenant_id,system_id,activated_at desc);
alter table public.system_installations enable row level security;
revoke all on public.system_installations from anon,authenticated;

-- Preserve existing V4.6 active bindings as installation history.
insert into public.system_installations(tenant_id,system_id,installation_id,secret_hash,status,platform_hint,activated_at,last_seen_at)
select d.tenant_id,d.id,d.installation_id,d.device_secret_hash,'active',d.platform_hint,coalesce(d.activated_at,d.updated_at,d.created_at),d.last_seen_at
from public.business_devices d
where d.status='active' and nullif(d.installation_id,'') is not null
  and not exists(select 1 from public.system_installations si where si.system_id=d.id and si.status='active')
on conflict do nothing;

-- Called by the device-activate Edge Function using service role. The activation claim,
-- uniqueness checks, installation history and compatibility binding are one DB transaction.
create or replace function public.system_claim_activation_v47(
  p_business_code text,p_activation_hash text,p_installation_id text,p_app_key text,p_secret_hash text,
  p_platform_hint text default null,p_app_version text default null
) returns jsonb language plpgsql security definer
set search_path=public,private,extensions,pg_temp
as $$
declare d public.business_devices%rowtype;t public.tenants%rowtype;l public.business_locations%rowtype;v_installation uuid;
begin
  if nullif(trim(coalesce(p_business_code,'')),'') is null or nullif(trim(coalesce(p_activation_hash,'')),'') is null
     or nullif(trim(coalesce(p_installation_id,'')),'') is null or p_app_key not in('client','pos')
     or nullif(trim(coalesce(p_secret_hash,'')),'') is null then
    raise exception 'Invalid activation request';
  end if;

  select * into t from public.tenants where upper(business_code)=upper(trim(p_business_code));
  if not found then raise exception 'Invalid business or activation code';end if;

  select * into d
  from public.business_devices
  where tenant_id=t.id and app_type=p_app_key and status in('pending','inactive')
    and activation_hash=p_activation_hash
    and (activation_expires_at is null or activation_expires_at>=now())
  order by activation_issued_at desc nulls last,created_at desc
  limit 1 for update;
  if not found then raise exception 'Invalid or expired activation code';end if;

  if exists(select 1 from public.system_installations where installation_id=trim(p_installation_id) and status='active' and system_id<>d.id) then
    raise exception 'This installation is already registered to another system';
  end if;
  if exists(select 1 from public.business_devices where installation_id=trim(p_installation_id) and status='active' and id<>d.id) then
    raise exception 'This installation is already registered to another system';
  end if;

  update public.system_installations
  set status='inactive',deactivated_at=now(),deactivation_reason='Replaced by a new activation'
  where system_id=d.id and status='active';

  insert into public.system_installations(tenant_id,system_id,installation_id,secret_hash,status,platform_hint,app_version,activated_at,last_seen_at)
  values(t.id,d.id,trim(p_installation_id),p_secret_hash,'active',coalesce(nullif(trim(p_platform_hint),''),d.platform_hint),nullif(trim(coalesce(p_app_version,'')),''),now(),now())
  returning id into v_installation;

  update public.business_devices
  set status='active',installation_id=trim(p_installation_id),device_secret_hash=p_secret_hash,
      activation_hash=null,activation_expires_at=null,activated_at=now(),last_seen_at=now(),
      activation_count=coalesce(activation_count,0)+1,deactivated_at=null,deactivated_by=null,deactivation_reason=null,updated_at=now()
  where id=d.id;

  select * into l from public.business_locations where id=d.location_id;
  return jsonb_build_object(
    'success',true,'tenant_id',t.id,'tenant_name',t.name,'business_code',t.business_code,
    'device_id',d.id,'device_code',d.device_code,'device_name',d.name,'installation_record_id',v_installation,
    'location_id',l.id,'location_name',l.name,'location_code',l.location_code,'location_tracking_code',l.tracking_code
  );
end $$;
revoke all on function public.system_claim_activation_v47(text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.system_claim_activation_v47(text,text,text,text,text,text,text) to service_role;

create or replace function public.system_installations_list_v47(p_tenant_id uuid,p_system_id uuid)
returns table(id uuid,installation_id text,status text,platform_hint text,app_version text,activated_at timestamptz,last_seen_at timestamptz,deactivated_at timestamptz,deactivation_reason text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$begin
  if not private.platform_v2_is_admin()
     and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  if not exists(select 1 from public.business_devices where id=p_system_id and tenant_id=p_tenant_id) then raise exception 'System not found';end if;
  return query select s.id,s.installation_id,s.status,s.platform_hint,s.app_version,s.activated_at,s.last_seen_at,s.deactivated_at,s.deactivation_reason
  from public.system_installations s where s.tenant_id=p_tenant_id and s.system_id=p_system_id order by s.activated_at desc;
end$$;
grant execute on function public.system_installations_list_v47(uuid,uuid) to authenticated;

-- Keep the V4.6 Admin API name stable but deactivate the physical binding as well.
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
  perform private.business_audit_write(p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end$$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(105,'4.7.0','Foundation Lock & Production Stabilization','Separate physical installation history and atomic activation claim while preserving V4.6 system IDs.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 105 system installations ready' as status;
