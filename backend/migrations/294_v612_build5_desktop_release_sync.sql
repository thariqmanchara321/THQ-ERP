-- THQ ERP v6.1.2 Build 5 — Desktop Release Sync
-- Source captured from the already-live Supabase migration
-- 20260929070211 / v612_build5_desktop_release_sync.
-- Applied statement MD5 in Supabase history: 4f899e502bdcfdd3d03dd89143b0de73
-- DO NOT execute manually on the live project; migration 294 is already live.

begin;
insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values(
  gen_random_uuid(),'admin','web','6.1.2',5,'stable',false,false,
  'THQ ERP v6.1.2 Build 5 — Party Payments & Settlement desktop release synchronization. Admin functionality is unchanged; version metadata advances with the shared desktop ERP core used by Windows Client/POS.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,status=excluded.status,
    minimum_supported=excluded.minimum_supported,mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  294,'6.1.2-build5',
  'v6.1.2 Build 5 Desktop Release Sync',
  'Synchronizes Admin Web release metadata with the shared desktop v6.1.2 Build 5 release contract. No functional or database writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
