select public.thq_backend_contract_v47();

select migration_no,schema_version,release_name,applied_at,notes
from public.thq_schema_releases
where migration_no=115;

select
  to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is not null as held_feed_ok,
  to_regprocedure('public.platform_system_deactivate_v46(uuid,uuid,text)') is not null as deactivate_ok,
  to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is not null as system_update_ok,
  to_regprocedure('public.platform_system_delete_v471(uuid,uuid,text)') is not null as system_delete_ok,
  to_regprocedure('public.platform_location_delete_v471(uuid,uuid,text)') is not null as location_delete_ok,
  to_regprocedure('public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text)') is not null as tenant_system_create_ok,
  to_regprocedure('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is not null as tenant_system_update_ok,
  to_regprocedure('public.tenant_system_revoke_v471(uuid,uuid,text)') is not null as tenant_system_revoke_ok,
  to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is not null as customer_receipt_ok;
