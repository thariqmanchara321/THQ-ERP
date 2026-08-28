-- THQ ERP V4.7 — Foundation Lock & Production Stabilization
-- Release/schema contract. Requires migrations through 100_v46_core_fixes.sql.
begin;

create table if not exists public.thq_schema_releases(
  migration_no integer primary key,
  schema_version text not null,
  release_name text not null,
  applied_at timestamptz not null default now(),
  notes text
);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(101,'4.7.0','Foundation Lock & Production Stabilization','V4.7 upgrade started from confirmed V4.6 migration 100 baseline.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

alter table public.thq_schema_releases enable row level security;
revoke all on public.thq_schema_releases from anon,authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.0',
    'release','Foundation Lock & Production Stabilization'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

commit;
select 'THQ ERP V4.7 migration 101 ready' as status;
