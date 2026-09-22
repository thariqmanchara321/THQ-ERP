begin;

-- THQ ERP v6.1.1 Build 4 — Unified Transport & Logistics.
--
-- Release metadata synchronization only.
-- No GST, accounting, inventory quantity, sales, purchase, or historical
-- transaction writer behavior is changed by this migration.

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
select
  gen_random_uuid(),
  v.app_key,
  v.platform,
  '6.1.1',
  4,
  'stable',
  false,
  false,
  'THQ ERP v6.1.1 Build 4 — Unified Transport & Logistics. Synchronizes Client, POS, Admin and mobile release metadata with the unified Transport Trip Hub and Logistics integration. Preserves existing GST, accounting, inventory and transaction authority rules.',
  null,
  now()
from (values
  ('client','windows'),
  ('client','web'),
  ('client','android'),
  ('pos','windows'),
  ('pos','android'),
  ('admin','web')
) as v(app_key, platform)
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
  286,
  '6.1.1-build4',
  'v6.1.1 Build 4 Unified Transport & Logistics',
  'Release registry synchronization for the unified Transport Trip Hub and Logistics integration. No GST, accounting, stock quantity, sale, purchase or historical transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
