-- THQ ERP v6.0 Build 1
-- Migration 268: Audit Center Client navigation.
-- Live migration applied to flexi-erp-dev on 2026-09-02.
-- Navigation-only: no transaction, GST, accounting, inventory or risk-calculation writer is changed.

begin;

update public.app_menu_nodes_v45 n
set module_key = 'audit_center',
    parent_id = p.id,
    label = 'Audit Center',
    icon_key = 'compliance',
    sort_order = 20,
    enabled = true,
    collapsed_by_default = false,
    metadata = jsonb_build_object(
      'permissions',
      jsonb_build_array('audit_center.view')
    ),
    updated_at = now()
from public.app_menu_nodes_v45 p
where n.tenant_id is null
  and n.app_key = 'client'
  and n.node_key = 'audit_center'
  and p.tenant_id is null
  and p.app_key = 'client'
  and p.node_key = 'compliance'
  and p.node_type = 'group';

insert into public.app_menu_nodes_v45(
  id,
  tenant_id,
  app_key,
  node_key,
  node_type,
  module_key,
  parent_id,
  label,
  icon_key,
  sort_order,
  enabled,
  collapsed_by_default,
  metadata,
  created_at,
  updated_at
)
select
  gen_random_uuid(),
  null,
  'client',
  'audit_center',
  'module',
  'audit_center',
  p.id,
  'Audit Center',
  'compliance',
  20,
  true,
  false,
  jsonb_build_object(
    'permissions',
    jsonb_build_array('audit_center.view')
  ),
  now(),
  now()
from public.app_menu_nodes_v45 p
where p.tenant_id is null
  and p.app_key = 'client'
  and p.node_key = 'compliance'
  and p.node_type = 'group'
  and not exists (
    select 1
    from public.app_menu_nodes_v45 n
    where n.tenant_id is null
      and n.app_key = 'client'
      and n.node_key = 'audit_center'
  );

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  268,
  '6.0.0-build1',
  'Audit Center Client Navigation',
  'Adds Audit Center to the existing server-driven Client Compliance menu, permission-gated by audit_center.view. No financial or GST writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
