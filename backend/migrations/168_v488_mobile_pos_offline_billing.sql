-- THQ ERP V4.8.8 — Mobile POS offline billing/cache wrappers over the V4.8.6 durable engine.
begin;

create or replace function public.mobile_pos_sale_sync_v488(p_tenant_id uuid,p_device_id uuid,p_request_id text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_payload jsonb;v_result jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('channel','mobile_pos','mobile_release','4.8.8');
  v_result:=public.pos_offline_sale_sync_v486(p_tenant_id,p_device_id,v_location,p_request_id,v_payload);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('mobile_pos',true,'mobile_release','4.8.8');
end$$;
grant execute on function public.mobile_pos_sale_sync_v488(uuid,uuid,text,jsonb) to authenticated;

create or replace function public.mobile_pos_cache_manifest_v488(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_base jsonb;v_settings jsonb;v_context jsonb;
begin
  perform private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_base:=public.pos_offline_cache_manifest_v486(p_tenant_id,p_device_id);
  v_context:=public.mobile_pos_terminal_context_v488(p_tenant_id,p_device_id);
  select to_jsonb(s) into v_settings from public.mobile_pos_terminal_settings_v488 s where s.tenant_id=p_tenant_id and s.device_id=p_device_id;
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object('schema_version','4.8.8','migration_no',168,'mobile_pos',true,'terminal_settings',coalesce(v_settings,'{}'::jsonb),'restaurant_enabled',coalesce((v_context->>'restaurant_enabled')::boolean,false));
end$$;
grant execute on function public.mobile_pos_cache_manifest_v488(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(168,'4.8.8','Mobile POS Foundation','Mobile local-first billing sync wrapper and offline cache manifest on the V4.8.6 request-id/idempotency engine.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 168 mobile POS offline billing applied' as status;
