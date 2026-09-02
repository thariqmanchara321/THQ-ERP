begin;

-- THQ ERP v6.0 Build 1 — application release registry.
-- Non-mandatory release. Backend provenance applies to all apps; the full Audit Center workspace is exposed in Client.

insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
select
  gen_random_uuid(), v.app_key, v.platform, '6.0.0', 1, 'stable',
  false, false,
  'THQ ERP v6.0 Build 1 — Audit Intelligence & Explainability. Immutable transaction provenance, Audit Center risk/review lifecycle, recognized-COGS product profitability, deterministic metric explanations and History/Why evidence. Full Audit Center workspace is provided in Client; POS provenance remains automatic with a lightweight read-only history source; Admin risk-configuration source is included.',
  null, now()
from (values
  ('client','windows'),
  ('client','web'),
  ('client','android'),
  ('pos','windows'),
  ('pos','android'),
  ('admin','web')
) as v(app_key,platform)
on conflict(app_key,platform,version) do update
set build_number = excluded.build_number,
    status = excluded.status,
    minimum_supported = excluded.minimum_supported,
    mandatory = excluded.mandatory,
    release_notes = excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  269,
  '6.0.0-build1',
  'v6.0 Build 1 App Release Registry',
  'Registers non-mandatory v6.0 Build 1 application releases for Client, POS and Admin. No transaction, GST, inventory or accounting writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
