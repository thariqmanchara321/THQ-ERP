-- THQ ERP V4.8.8 — Mobile POS hardening/indexes/settings RPC.
begin;
create index if not exists idx_mobile_pos_kot_requests_v488_device on public.mobile_pos_kot_requests_v488(tenant_id,device_id,status,updated_at desc);
create index if not exists idx_mobile_pos_terminal_settings_v488_location on public.mobile_pos_terminal_settings_v488(tenant_id,location_id,updated_at desc);
revoke all on public.mobile_pos_kot_requests_v488 from anon,authenticated;
revoke all on public.mobile_pos_receipt_events_v488 from anon,authenticated;
revoke all on public.mobile_pos_terminal_settings_v488 from anon,authenticated;

create or replace function public.mobile_pos_terminal_settings_get_v488(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  select to_jsonb(s) into v from public.mobile_pos_terminal_settings_v488 s where s.tenant_id=p_tenant_id and s.device_id=p_device_id;
  return coalesce(v,jsonb_build_object('tenant_id',p_tenant_id,'device_id',p_device_id,'location_id',v_location,'camera_scanner_enabled',true,'system_printing_enabled',true,'kot_groundwork_enabled',true,'settings','{}'::jsonb));
end$$;
grant execute on function public.mobile_pos_terminal_settings_get_v488(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(173,'4.8.8','Mobile POS Foundation','Direct mobile audit/settings tables remain RPC-only; terminal scope and queue/KOT indexes hardened for production usage.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 173 hardening applied' as status;
