begin;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','windows','6.1.3',6,'stable',false,false,
  'THQ ERP v6.1.3 Build 6 — Windows Production Readiness. Adds repeatable Windows release builds, portable release bundles, Inno Setup installer packaging, Visual C++ runtime bundling, SHA-256 manifests and optional Authenticode signing. Business, GST and accounting transaction authority is unchanged.',
  null,now()
),
(
  gen_random_uuid(),'pos','windows','6.1.3',6,'stable',false,false,
  'THQ ERP v6.1.3 Build 6 — Windows Production Readiness. Adds repeatable Windows release builds, portable release bundles, Inno Setup installer packaging, Visual C++ runtime bundling, SHA-256 manifests and optional Authenticode signing. Business, GST and accounting transaction authority is unchanged.',
  null,now()
),
(
  gen_random_uuid(),'admin','web','6.1.3',6,'stable',false,false,
  'THQ ERP v6.1.3 Build 6 — desktop release contract synchronization only. No Admin feature or backend transaction-authority change.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  296,'6.1.3-build6',
  'v6.1.3 Build 6 Windows Production Readiness',
  'Release-metadata-only checkpoint for Windows Client/POS production packaging, installer tooling and signing readiness. No GST, accounting, inventory or transaction writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
