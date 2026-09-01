-- THQ ERP V4.8.6 — THQ API offline POS contract metadata.
begin;

create or replace function public.pos_offline_api_contract_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  return jsonb_build_object(
    'api_version','v1','release','4.8.6','resource','offline-pos','device_id',p_device_id,'location_id',v_location,
    'local_first',true,'idempotent_request_id',true,'automatic_sync',true,'price_conflict_protection',true,
    'serial_cache_paged',true,'supported_states',jsonb_build_array('pending','syncing','synced','conflict','error','cancelled')
  );
end$$;
grant execute on function public.pos_offline_api_contract_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(158,'4.8.6','Offline POS','THQ API contract for offline POS cache, sync, status and conflicts.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 158 API contract applied' as status;
