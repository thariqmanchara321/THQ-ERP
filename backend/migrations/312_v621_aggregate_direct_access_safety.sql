begin;

-- Source-sync marker for a production migration that was originally live-only.
-- Final object definitions through 315 are reconstructed in migration 311 in
-- this repository package. Production Supabase must NOT be re-run from these files.

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  312,'6.2.1-aggregate-direct-access-safety','Aggregate Direct Supply Access Safety',
  'Makes Direct Supply management require the dedicated permission, bridges hidden transit-location access back to the authorized operating location for Purchase/Sale document origin checks, and self-heals the system transit location legal/address fields on use. Existing non-transit location authorization behavior is unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
