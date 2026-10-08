
begin;

create or replace function public.system_release_binding_v628(
  p_tenant_id uuid,
  p_system_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_system public.business_devices%rowtype;
  v_reason text := coalesce(
    nullif(trim(coalesce(p_reason,'')),''),
    'Owner/admin authorized store/business change'
  );
  v_installations integer := 0;
begin
  select *
    into v_system
  from public.business_devices
  where id=p_system_id
    and tenant_id=p_tenant_id
    and app_type in ('client','pos')
  for update;

  if not found then
    raise exception 'System not found';
  end if;

  update public.system_installations
  set status='inactive',
      deactivated_at=now(),
      deactivation_reason=v_reason
  where tenant_id=p_tenant_id
    and system_id=p_system_id
    and status='active';

  get diagnostics v_installations = row_count;

  update public.business_devices
  set status=case when status='revoked' then status else 'inactive' end,
      installation_id=null,
      device_secret_hash=null,
      last_seen_at=null,
      deactivated_at=case when status='revoked' then deactivated_at else now() end,
      deactivated_by=null,
      deactivation_reason=case when status='revoked' then deactivation_reason else v_reason end,
      updated_at=now()
  where id=p_system_id
    and tenant_id=p_tenant_id;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'system.binding.release',
    'business_device',
    p_system_id,
    v_system.device_code,
    to_jsonb(v_system),
    jsonb_build_object(
      'status',case when v_system.status='revoked' then 'revoked' else 'inactive' end,
      'installation_id',null,
      'reason',v_reason,
      'released_installations',v_installations
    )
  );

  return jsonb_build_object(
    'success',true,
    'system_id',p_system_id,
    'device_code',v_system.device_code,
    'released_installations',v_installations,
    'status',case when v_system.status='revoked' then 'revoked' else 'inactive' end
  );
end
$function$;

revoke all on function public.system_release_binding_v628(uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function public.system_release_binding_v628(uuid,uuid,text)
  to service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  325,
  '6.2.8-authorized-system-binding-release',
  'Authorized System Binding Release',
  'Adds service-role-only atomic release of Client/POS installation bindings after owner/admin authorization so Change Store / Business can re-activate the same physical installation without leaving a stale active binding.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;

