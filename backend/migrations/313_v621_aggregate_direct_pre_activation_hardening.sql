begin;

-- Source-sync marker for a production migration that was originally live-only.
-- Final object definitions through 315 are reconstructed in migration 311 in
-- this repository package. Production Supabase must NOT be re-run from these files.

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  313,'6.2.1-aggregate-direct-hardening','Aggregate Direct Supply Pre-Activation Hardening',
  'Fixes explicit-user permission resolution for hidden transit access, scopes Direct Supply reads to authorized operating locations, assigns only the selected material to transit for first-use Purchase/Sale screens, and adds a Material Yard dashboard that excludes system transit stock from physical yard balances.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
