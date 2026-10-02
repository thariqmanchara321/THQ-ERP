begin;

-- Source-sync marker for a production migration that was originally live-only.
-- Final object definitions through 315 are reconstructed in migration 311 in
-- this repository package. Production Supabase must NOT be re-run from these files.

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  315,'6.2.1-aggregate-direct-recovery','Aggregate Direct Supply Document Recovery',
  'Adds a permission- and location-scoped candidate lookup for already-posted Direct Supply Purchases/Sales so interrupted client linking can recover safely without reposting financial documents.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
