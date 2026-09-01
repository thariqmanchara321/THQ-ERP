-- THQ ERP v4.8.6 post-upgrade verification.
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_v486_release_verify() as v486_release;
select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 154 and 160
order by migration_no;
