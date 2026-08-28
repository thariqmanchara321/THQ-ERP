-- THQ ERP V4.7 post-upgrade verification.
select public.thq_backend_contract_v47() as backend_contract;

select migration_no,schema_version,release_name,applied_at,notes
from public.thq_schema_releases
order by migration_no;

-- Expected final migration: 110.
do $$ begin
  if coalesce((select max(migration_no) from public.thq_schema_releases),0) <> 110 then
    raise exception 'THQ V4.7 upgrade is incomplete. Expected migration 110.';
  end if;
end $$;

-- Run separately for each tenant UUID:
-- select * from public.system_integrity_scan_v47('<TENANT_UUID>') where issue_count > 0;
