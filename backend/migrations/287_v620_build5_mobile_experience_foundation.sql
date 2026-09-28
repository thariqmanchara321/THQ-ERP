begin;

-- THQ ERP v6.2.0 Build 5 — Mobile Experience Foundation.
--
-- Release metadata synchronization only.
-- No GST, accounting, inventory quantity, sale, purchase, return, payment,
-- offline sync, restaurant, logistics, or historical transaction writer
-- behavior is changed by this migration.

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
  'android',
  '6.2.0',
  5,
  'stable',
  false,
  false,
  'THQ ERP v6.2.0 Build 5 — Mobile Experience Foundation. Adds the shared advanced mobile visual foundation, correct mobile activation version reporting, Android device heartbeat/release awareness and mobile error telemetry. Existing GST, accounting, stock, sales, purchase, payment and offline synchronization authority remains unchanged.',
  null,
  now()
from (values ('client'), ('pos')) as v(app_key)
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
  287,
  '6.2.0-build5',
  'v6.2.0 Build 5 Mobile Experience Foundation',
  'Mobile release registry synchronization and client-side mobile foundation checkpoint. No GST, accounting, stock quantity, sales, purchase, payment, offline synchronization, restaurant, logistics, or historical transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
