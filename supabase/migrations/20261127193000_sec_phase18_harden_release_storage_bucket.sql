-- ============================================================================
-- THQ ERP Phase 18: Harden Production Storage Policy for thq-releases Bucket
-- Safe, idempotent, backward-compatible migration
-- Schema release: #720 / v8.3.14
--
-- Security objective:
-- Revoke the 'anon' role from insert and update policies on the 'thq-releases' bucket.
-- In production, release artifacts (installers, executables, update packages) must
-- ONLY be published by authenticated platform administrators (private.platform_v2_is_admin())
-- or authorized service_role keys, preventing unauthenticated uploads or binary tampering.
-- ============================================================================

begin;

-- 1. Ensure private.platform_v2_is_admin() exists and can be executed by authenticated/service_role
grant execute on function private.platform_v2_is_admin() to authenticated, service_role;

-- 2. Update storage policy for thq-releases to strictly allow admin/service_role writes
drop policy if exists thq_releases_admin_insert on storage.objects;
create policy thq_releases_admin_insert
  on storage.objects for insert
  with check (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() = 'service_role')
  );

drop policy if exists thq_releases_admin_update on storage.objects;
create policy thq_releases_admin_update
  on storage.objects for update
  using (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() = 'service_role')
  );

-- 3. Register Schema Release #720 (v8.3.14)
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  720,
  'v8.3.14',
  'sec_phase18_harden_release_storage_bucket',
  'Production readiness security hardening: revoke anon write permissions on thq-releases storage bucket, restricting release artifact publishing strictly to platform admin and service_role.'
)
on conflict do nothing;

commit;

notify pgrst, 'reload schema';
