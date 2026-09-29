begin;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','android','6.2.7',12,'stable',false,false,
  'THQ ERP v6.2.7 Build 12 — Production Release Readiness. Adds production-signing enforcement and repeatable signed APK/AAB release tooling for Client Mobile.',
  null,now()
),
(
  gen_random_uuid(),'pos','android','6.2.7',12,'stable',false,false,
  'THQ ERP v6.2.7 Build 12 — Production Release Readiness. Adds Clear / Reset Order in Mobile POS plus production-signing enforcement and repeatable signed APK/AAB release tooling. GST and authoritative sale sync are unchanged.',
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
  295,'6.2.7-build12',
  'v6.2.7 Build 12 Production Release Readiness',
  'Mobile-only release metadata for Clear / Reset Order and production Android signing readiness. No transaction, GST, accounting, stock or backend writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
