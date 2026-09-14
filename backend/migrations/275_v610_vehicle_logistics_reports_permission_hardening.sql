-- THQ ERP v6.1 Vehicle Logistics report permission hardening.
-- NOTE: flexi-erp-dev already has this migration applied by ChatGPT.
-- This file is for Git/source history and future environments only.

do $migration$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
    into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'logistics_reports_dashboard_v1'
    and p.oid::regprocedure::text = 'logistics_reports_dashboard_v1(uuid,uuid,date,date)';

  if v_sql is null then
    raise exception 'logistics_reports_dashboard_v1(uuid,uuid,date,date) not found';
  end if;

  if position('Logistics report permission required' in v_sql) = 0 then
    v_sql := replace(
      v_sql,
      E'  if not private.erp_user_has_tenant_access(p_tenant_id) then\n    raise exception ''Access denied'';\n  end if;',
      E'  if not private.erp_user_has_tenant_access(p_tenant_id) then\n    raise exception ''Access denied'';\n  end if;\n  if not (\n    private.erp_user_is_owner(p_tenant_id, auth.uid())\n    or private.erp_has_permission(p_tenant_id, ''transport_service.view'')\n    or private.erp_has_permission(p_tenant_id, ''transport_service.manage'')\n    or private.erp_has_permission(p_tenant_id, ''inventory.view'')\n    or private.erp_has_permission(p_tenant_id, ''inventory.transfer'')\n    or private.erp_has_permission(p_tenant_id, ''inventory.manage'')\n  ) then\n    raise exception ''Logistics report permission required'';\n  end if;'
    );

    if position('Logistics report permission required' in v_sql) = 0 then
      raise exception 'Could not patch logistics_reports_dashboard_v1 permission guard';
    end if;

    execute v_sql;
  end if;
end
$migration$;

revoke execute on function public.logistics_reports_dashboard_v1(uuid,uuid,date,date) from public, anon;
grant execute on function public.logistics_reports_dashboard_v1(uuid,uuid,date,date) to authenticated, service_role;
