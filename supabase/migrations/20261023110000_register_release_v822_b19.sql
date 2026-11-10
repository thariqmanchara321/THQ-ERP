-- THQ ERP V8.2.2 Build 19 — Forward-Only Migration: Register Test Release #2
-- Safe, idempotent, backward-compatible migration

begin;

-- Register THQ Business v8.2.2 Build 19 restricted release targeting test PC CLIENT-BC8AEE
delete from public.platform_app_releases
where app_key = 'client' and platform = 'windows' and version = '8.2.2' and build_number = 19;

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
  '8.2.2',
  19,
  'stable',
  'published',
  false,
  false,
  'THQ Update Test #2 — System Health & Update Verification panel with live runtime and database connectivity check.',
  'installers/THQ-Business-v8.2.2-build19-windows-x64.exe',
  17728041,
  '81498e89fa2a67031d76f187b8e356837bab93e1c6de34dcd754c53e164b590e',
  100,
  'device',
  array['bc8aeec1-9bce-4935-b349-168caf9a7fa4']::uuid[],
  now(),
  now()
);

commit;
