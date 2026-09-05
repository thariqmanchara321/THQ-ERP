-- THQ ERP v5.2 - authorize installation business/store changes.
-- Read-only authorization gate. It does not sign out, clear activation,
-- change device bindings, or modify business data.

create or replace function public.installation_change_authorize_v520(
  p_tenant_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if auth.uid() is null then
    return false;
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    return false;
  end if;

  return private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'settings.manage');
end;
$function$;

revoke all on function public.installation_change_authorize_v520(uuid) from public;
revoke all on function public.installation_change_authorize_v520(uuid) from anon;
grant execute on function public.installation_change_authorize_v520(uuid) to authenticated;
grant execute on function public.installation_change_authorize_v520(uuid) to service_role;
