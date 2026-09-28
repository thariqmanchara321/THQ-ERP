begin;

-- THQ ERP v6.2.3 Build 8 — Mobile POS Operations & Speed.
-- Release metadata only. Do not rerun manually on the live project.

insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
values(
  gen_random_uuid(),
  'pos',
  'android',
  '6.2.3',
  8,
  'stable',
  false,
  false,
  'THQ ERP v6.2.3 Build 8 — Mobile POS Operations & Speed. Adds durable device-local Hold/Resume carts, favorite and recent product shortcuts, improved order queue filtering and sync visibility, and cashier shift access using the existing v4.7.2 shift APIs. Existing v5.2 authoritative GST routing, offline sale queue, payment allocation, stock reservation, purchase, expense, restaurant and logistics writer behavior remains unchanged.',
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
  290,
  '6.2.3-build8',
  'v6.2.3 Build 8 Mobile POS Operations & Speed',
  'Release registry checkpoint for Mobile POS Build 8. Client-side operations use existing v5.2 POS/GST/offline APIs and existing cashier shift v4.7.2 APIs. No authoritative transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
