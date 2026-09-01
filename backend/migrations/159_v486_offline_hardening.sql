-- THQ ERP V4.8.6 — offline POS hardening helpers.
begin;

create or replace function public.pos_offline_request_lookup_v486(p_tenant_id uuid,p_request_id text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v public.pos_offline_sync_v486%rowtype;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select * into v from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  if not found then return null;end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v.location_id,'view') then raise exception 'Location access denied';end if;
  return jsonb_build_object('request_id',v.request_id,'device_id',v.device_id,'location_id',v.location_id,'local_invoice_number',v.local_invoice_number,'status',v.status,'conflict_code',v.conflict_code,'conflict_message',v.conflict_message,'attempts',v.attempts,'first_seen_at',v.first_seen_at,'last_attempt_at',v.last_attempt_at,'synced_at',v.synced_at,'server_response',v.server_response);
end$$;
grant execute on function public.pos_offline_request_lookup_v486(uuid,text) to authenticated;

-- Keep server audit immutable from ordinary clients; only RPCs above may write it.
revoke insert,update,delete on public.pos_offline_sync_v486 from authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(159,'4.8.6','Offline POS','Offline request lookup, RPC-only audit writes and release hardening.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 159 offline hardening applied' as status;
