-- THQ ERP V4.7 — runtime heartbeat keeps logical system + physical installation in sync.
begin;

create or replace function public.device_heartbeat_v4(p_tenant_id uuid,p_device_id uuid,p_app_key text,p_platform text,p_version text,p_build integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_latest record;v_installation text;begin
  select installation_id into v_installation from public.business_devices
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_installation is null then raise exception 'System installation is not active';end if;

  update public.business_devices set last_seen_at=now() where id=p_device_id;
  update public.system_installations
  set last_seen_at=now(),platform_hint=coalesce(nullif(trim(p_platform),''),platform_hint),app_version=nullif(trim(coalesce(p_version,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and installation_id=v_installation and status='active';

  insert into public.device_app_status(device_id,tenant_id,app_key,platform,version,build_number,last_seen_at,metadata)
  values(p_device_id,p_tenant_id,p_app_key,p_platform,p_version,coalesce(p_build,0),now(),coalesce(p_metadata,'{}'::jsonb))
  on conflict(device_id) do update set app_key=excluded.app_key,platform=excluded.platform,version=excluded.version,build_number=excluded.build_number,last_seen_at=now(),metadata=excluded.metadata;

  select * into v_latest from public.platform_app_releases
  where app_key=p_app_key and platform=p_platform and status='stable' order by released_at desc limit 1;
  return jsonb_build_object(
    'latest_version',v_latest.version,'mandatory',coalesce(v_latest.mandatory,false),
    'status',case when v_latest.version is null or v_latest.version=p_version then 'latest' when coalesce(v_latest.mandatory,false) then 'update_required' else 'update_available' end,
    'release_notes',v_latest.release_notes,'download_url',v_latest.download_url,
    'backend',public.thq_backend_contract_v47()
  );
end $$;
grant execute on function public.device_heartbeat_v4(uuid,uuid,text,text,text,integer,jsonb) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(110,'4.7.0','Foundation Lock & Production Stabilization','Heartbeat updates both the logical system compatibility row and the active physical installation history.')
on conflict(migration_no) do update set notes=excluded.notes;

commit;
select 'THQ ERP V4.7 migration 110 runtime hardening ready' as status;
