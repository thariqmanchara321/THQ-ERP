begin;

-- THQ ERP v6.2.1 Build 6 — Client Mobile Workspace.
--
-- Adds capability/context metadata for the Client Mobile workspace and
-- synchronizes the Android client release registry.
-- No GST, accounting, stock quantity, sale, purchase, return, payment,
-- offline sync, restaurant or logistics writer behavior is changed.

create or replace function public.mobile_client_context_v621(
  p_tenant_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_trace boolean;
  v_audit boolean;
begin
  -- Existing v4.8.7 context validates the authenticated tenant/device pair.
  v_base := public.mobile_client_context_v487(p_tenant_id, p_device_id);

  v_trace := private.v483_trace_view_allowed(p_tenant_id);
  v_audit := private.has_permission(p_tenant_id, 'audit_center.view');

  return v_base || jsonb_build_object(
    'release', '6.2.1',
    'workspace_release', 'client-mobile-build6',
    'can_view_notifications', true,
    'can_view_audit', coalesce(v_audit, false),
    'can_view_traceability', coalesce(v_trace, false),
    'can_view_warranty', coalesce(v_trace, false)
  );
end;
$function$;

revoke execute on function public.mobile_client_context_v621(uuid, uuid)
  from public, anon;
grant execute on function public.mobile_client_context_v621(uuid, uuid)
  to authenticated, service_role;

create or replace function public.mobile_client_api_contract_v621(
  p_tenant_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_context jsonb;
begin
  v_base := public.mobile_client_api_contract_v487(p_tenant_id, p_device_id);
  v_context := public.mobile_client_context_v621(p_tenant_id, p_device_id);

  return v_base || jsonb_build_object(
    'api_version', 'v2',
    'release', '6.2.1',
    'resource', 'client-mobile',
    'workspace', true,
    'notifications', true,
    'audit_center', coalesce((v_context ->> 'can_view_audit')::boolean, false),
    'traceability', coalesce((v_context ->> 'can_view_traceability')::boolean, false),
    'warranty', coalesce((v_context ->> 'can_view_warranty')::boolean, false),
    'global_search', true,
    'release_awareness', true
  );
end;
$function$;

revoke execute on function public.mobile_client_api_contract_v621(uuid, uuid)
  from public, anon;
grant execute on function public.mobile_client_api_contract_v621(uuid, uuid)
  to authenticated, service_role;

insert into public.platform_app_releases(
  id,
  app_key,
  platform,
  version,
  build_number,
  status,
  minimum_supported,
  mandatory,
  release_notes,
  download_url,
  released_at
)
values(
  gen_random_uuid(),
  'client',
  'android',
  '6.2.1',
  6,
  'stable',
  false,
  false,
  'THQ ERP v6.2.1 Build 6 — Client Mobile Workspace. Adds the advanced mobile workspace, unified navigation, global business search, improved sales/inventory/money/approval views, notifications, audit visibility, traceability and release-aware UI. Existing authoritative GST, accounting, stock and transaction writers remain unchanged.',
  null,
  now()
)
on conflict(app_key, platform, version) do update
set build_number = excluded.build_number,
    status = excluded.status,
    minimum_supported = excluded.minimum_supported,
    mandatory = excluded.mandatory,
    release_notes = excluded.release_notes;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  288,
  '6.2.1-build6',
  'v6.2.1 Build 6 Client Mobile Workspace',
  'Adds Client Mobile workspace capability metadata and release registry synchronization only. Reuses existing tenant-scoped RPCs for business data. No authoritative GST, accounting, inventory quantity or transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
