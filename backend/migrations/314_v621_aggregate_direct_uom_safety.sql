begin;

-- Source-sync marker for a production migration that was originally live-only.
-- Final object definitions through 315 are reconstructed in migration 311 in
-- this repository package. Production Supabase must NOT be re-run from these files.

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  314,'6.2.1-aggregate-direct-uom','Aggregate Direct Supply UOM Safety',
  'Adds a Direct Supply material/unit catalog and rejects direct loads whose entered unit is not compatible with both Purchase and Sale. Base units remain valid for backward-compatible stock products.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
