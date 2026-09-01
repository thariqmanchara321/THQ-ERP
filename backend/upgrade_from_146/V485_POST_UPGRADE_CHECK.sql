-- THQ ERP v4.8.5 post-upgrade verification (expected migration 153).
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_v485_release_verify() as v485_release_verify;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 147 and 153
order by migration_no;

select
  to_regclass('public.stock_transfer_allocations_v485') as transfer_allocations,
  to_regclass('public.stock_transfer_history_v485') as transfer_history,
  to_regprocedure('public.inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text)') as transfer_request_rpc,
  to_regprocedure('public.inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text)') as transfer_dispatch_rpc,
  to_regprocedure('public.inventory_transfer_receive_v485(uuid,uuid,uuid,text)') as transfer_receive_rpc,
  to_regprocedure('public.inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text)') as stock_count_rpc,
  to_regprocedure('public.inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer)') as reconciliation_rpc;
