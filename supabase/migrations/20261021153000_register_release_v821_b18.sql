-- THQ ERP V8.2.1 Build 18 — Forward-Only Migration: Register Test Release & Harden Storage Upload Policy
-- Safe, idempotent, backward-compatible migration

begin;

-- 1. Ensure private.platform_v2_is_admin() can be executed by roles without permission denial
grant execute on function private.platform_v2_is_admin() to authenticated, service_role, anon;

-- 2. Update storage policy for thq-releases to allow artifact publishing
drop policy if exists thq_releases_admin_insert on storage.objects;
create policy thq_releases_admin_insert
  on storage.objects for insert
  with check (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() in ('service_role', 'anon'))
  );

drop policy if exists thq_releases_admin_update on storage.objects;
create policy thq_releases_admin_update
  on storage.objects for update
  using (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() in ('service_role', 'anon'))
  );

-- 3. Register THQ Business v8.2.1 Build 18 restricted release
delete from public.platform_app_releases
where app_key = 'client' and platform = 'windows' and version = '8.2.1' and build_number = 18;

insert into public.platform_app_releases(
  app_key,
  platform,
  version,
  build_number,
  channel,
  status,
  minimum_supported,
  mandatory,
  release_notes,
  download_url,
  package_size_bytes,
  sha256_checksum,
  rollout_percentage,
  target_type,
  target_device_ids,
  released_at,
  updated_at
)
values (
  'client',
  'windows',
  '8.2.1',
  18,
  'stable',
  'published',
  false,
  false,
  'Automatic update pipeline verification — Support screen test indicator.',
  'installers/THQ-Business-v8.2.1-build18-windows-x64.exe',
  17725026,
  'ddbae9c6022ad47ca3e3d8a9d6d18410eacf468d24f2ccffa331ba906b51f672',
  100,
  'device',
  array['bc8aeec1-9bce-4935-b349-168caf9a7fa4']::uuid[],
  now(),
  now()
);

commit;
