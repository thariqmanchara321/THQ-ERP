-- THQ ERP V4.8.3 — post-upgrade verification
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_api_contract_v480() as api_contract;
select public.thq_v483_release_verify() as release_verification;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 135 and 139
order by migration_no;

select
  to_regclass('public.product_tracking_policies_v483') is not null as tracking_policy_ready,
  to_regclass('public.inventory_serials_v483') is not null as serial_registry_ready,
  to_regclass('public.inventory_batches_v483') is not null as batch_registry_ready,
  to_regclass('public.inventory_batch_balances_v483') is not null as batch_balances_ready,
  to_regclass('public.inventory_trace_events_v483') is not null as trace_events_ready,
  to_regclass('public.product_warranties_v483') is not null as warranties_ready,
  to_regprocedure('public.purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is not null as tracked_purchases_ready,
  to_regprocedure('public.sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is not null as tracked_sales_ready,
  to_regprocedure('public.inventory_serial_search_v483(uuid,text,uuid,integer)') is not null as serial_search_ready,
  to_regprocedure('public.inventory_batch_history_v483(uuid,uuid)') is not null as batch_history_ready,
  to_regprocedure('public.warranty_register_v483(uuid,text,text,integer,integer,uuid)') is not null as warranty_register_ready;
