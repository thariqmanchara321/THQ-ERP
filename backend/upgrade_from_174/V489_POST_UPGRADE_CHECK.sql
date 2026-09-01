-- THQ ERP v4.8.9 Build 17 post-upgrade check.
-- Expected latest migration: 180 / schema version: 4.8.9.

select migration_no, schema_version, release_name
from public.thq_schema_releases
order by migration_no desc
limit 1;

select public.thq_v489_release_verify() as v489_release_verify;

select
  to_regprocedure('public.operations_pipeline_v489(uuid,uuid)') is not null as operations_pipeline_ok,
  to_regprocedure('public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is not null as sales_rounding_ok,
  to_regprocedure('public.restaurant_operations_summary_v489(uuid,uuid,uuid)') is not null as restaurant_operations_ok,
  to_regprocedure('public.erp_runtime_health_v489(uuid)') is not null as runtime_health_ok,
  to_regprocedure('public.thq_api_contract_v480()') is not null as api_contract_ok;
