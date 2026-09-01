-- THQ ERP V4.8.7 — Client Mobile foundation and device/runtime contract.
begin;

create or replace function private.v487_client_mobile_location(p_tenant_id uuid,p_device_id uuid)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_type text;v_status text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id,d.app_type,d.status into v_location,v_type,v_status
  from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Client Mobile system not found';end if;
  if v_status<>'active' then raise exception 'Client Mobile system is not active';end if;
  if v_type<>'client' then raise exception 'Client Mobile requires a Client system activation';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'view') then raise exception 'Location access denied';end if;
  return v_location;
end$$;
revoke all on function private.v487_client_mobile_location(uuid,uuid) from public;

create or replace function public.mobile_client_context_v487(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;d public.business_devices%rowtype;l public.business_locations%rowtype;
begin
  v_location:=private.v487_client_mobile_location(p_tenant_id,p_device_id);
  select * into d from public.business_devices where id=p_device_id and tenant_id=p_tenant_id;
  select * into l from public.business_locations where id=v_location and tenant_id=p_tenant_id;
  return jsonb_build_object(
    'release','4.8.7','device_id',d.id,'device_code',d.device_code,'device_name',d.name,'location_id',l.id,
    'location_code',l.location_code,'location_name',l.name,'mobile_client',true,'read_first',true,
    'can_approve',private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'approvals.approve'),
    'can_receive_customer_payment',private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.manage') or private.erp_has_permission(p_tenant_id,'payments.receive')
  );
end$$;
grant execute on function public.mobile_client_context_v487(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(161,'4.8.7','Client Mobile','Client-system activation validation and mobile runtime capability contract.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.7 migration 161 Client Mobile foundation applied' as status;
