-- THQ ERP V4.8.8 — Mobile POS server sync status.
begin;
create or replace function public.mobile_pos_sync_status_v488(p_tenant_id uuid,p_device_id uuid,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_summary jsonb;v_rows jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_summary:=public.pos_offline_sync_summary_v486(p_tenant_id,p_device_id);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_attempt_at desc nulls last,x.first_seen_at desc),'[]'::jsonb) into v_rows
    from public.pos_offline_sync_list_v486(p_tenant_id,p_device_id,null,greatest(1,least(coalesce(p_limit,100),500))) x;
  return jsonb_build_object('release','4.8.8','location_id',v_location,'summary',coalesce(v_summary,'{}'::jsonb),'recent',coalesce(v_rows,'[]'::jsonb));
end$$;
grant execute on function public.mobile_pos_sync_status_v488(uuid,uuid,integer) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(171,'4.8.8','Mobile POS Foundation','Mobile terminal server-side sync/conflict status contract backed by the existing Offline POS audit queue.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 171 sync status applied' as status;
