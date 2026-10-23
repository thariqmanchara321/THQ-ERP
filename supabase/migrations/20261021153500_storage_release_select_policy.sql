begin;

drop policy if exists thq_releases_admin_select on storage.objects;
create policy thq_releases_admin_select
  on storage.objects for select
  using (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() in ('service_role', 'anon'))
  );

drop policy if exists thq_releases_admin_update on storage.objects;
create policy thq_releases_admin_update
  on storage.objects for update
  using (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() in ('service_role', 'anon'))
  )
  with check (
    bucket_id = 'thq-releases'
    and (private.platform_v2_is_admin() or auth.role() in ('service_role', 'anon'))
  );

commit;
