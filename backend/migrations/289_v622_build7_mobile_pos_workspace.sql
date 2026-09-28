begin;

-- THQ ERP v6.2.2 Build 7 — Mobile POS Workspace.
--
-- Release registry synchronization only.
-- No GST, accounting, inventory quantity, sale, purchase, return, payment,
-- offline sync, restaurant, logistics or historical writer behavior changes.

insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
values(
  gen_random_uuid(),
  'pos',
  'android',
  '6.2.2',
  7,
  'stable',
  false,
  false,
  'THQ ERP v6.2.2 Build 7 — Mobile POS Workspace. Adds the advanced POS shell around the proven Sell workspace, with dedicated Orders, Operations, Reports and More workspaces, independent POS mobile release tracking, stronger sync visibility and faster access to purchase, expense, logistics and terminal tools. Existing v5.2 authoritative GST routing, offline sale queue, payment allocation, inventory reservation, purchase, expense, restaurant and logistics writer behavior remains unchanged.',
  null,
  now()
)
on conflict(app_key, platform, version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(
  migration_no, schema_version, release_name, notes
)
values(
  289,
  '6.2.2-build7',
  'v6.2.2 Build 7 Mobile POS Workspace',
  'Mobile POS release registry and client-side workspace checkpoint only. Reuses existing v5.2 authoritative POS/GST/offline APIs and existing purchase, expense, restaurant, logistics and reporting APIs. No transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
