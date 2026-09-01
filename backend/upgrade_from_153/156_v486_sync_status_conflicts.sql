-- THQ ERP V4.8.6 — offline sync status, conflict visibility and audit summaries.
begin;

create or replace function public.pos_offline_sync_list_v486(
  p_tenant_id uuid,p_device_id uuid default null,p_status text default null,p_limit integer default 500
) returns table(
  request_id text,device_id uuid,device_code text,location_id uuid,location_name text,local_invoice_number text,status text,
  conflict_code text,conflict_message text,attempts integer,first_seen_at timestamptz,last_attempt_at timestamptz,synced_at timestamptz,server_response jsonb
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select q.request_id,q.device_id,d.device_code,q.location_id,l.location_code||' • '||l.name,q.local_invoice_number,q.status,
         q.conflict_code,q.conflict_message,q.attempts,q.first_seen_at,q.last_attempt_at,q.synced_at,q.server_response
  from public.pos_offline_sync_v486 q
  join public.business_devices d on d.id=q.device_id
  join public.business_locations l on l.id=q.location_id
  where q.tenant_id=p_tenant_id and (p_device_id is null or q.device_id=p_device_id)
    and (p_status is null or p_status='' or q.status=p_status)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,q.location_id,'view'))
  order by q.updated_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.pos_offline_sync_list_v486(uuid,uuid,text,integer) to authenticated;

create or replace function public.pos_offline_sync_summary_v486(p_tenant_id uuid,p_device_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return (select jsonb_build_object(
    'pending',count(*) filter(where status in('pending','syncing')),
    'conflict',count(*) filter(where status='conflict'),
    'error',count(*) filter(where status='error'),
    'synced_today',count(*) filter(where status='synced' and synced_at::date=current_date),
    'last_synced_at',max(synced_at)
  ) from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and (p_device_id is null or device_id=p_device_id));
end$$;
grant execute on function public.pos_offline_sync_summary_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(156,'4.8.6','Offline POS','Server audit list and summary for pending/synced/conflicted offline POS requests.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 156 sync status/conflicts applied' as status;
