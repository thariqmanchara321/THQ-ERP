-- THQ ERP V4.7.1 — read-only post-upgrade catalog checks.
-- Safe to run from Supabase SQL Editor. Tenant System Health should be run from THQ Admin,
-- because the integrity scanner correctly requires an authenticated THQ admin/business user.

select public.thq_backend_contract_v47() as backend_contract;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 111 and 114
order by migration_no;

select
  to_regclass('public.customer_receipts') is not null as customer_receipts_table,
  to_regclass('public.customer_receipt_allocations') is not null as receipt_allocations_table,
  to_regclass('public.system_installations') is not null as system_installations_table,
  to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is not null as receive_payment_rpc,
  to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is not null as held_feed_rpc,
  to_regprocedure('public.pos_terminal_day_v471(uuid,uuid,date)') is not null as terminal_day_rpc,
  to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is not null as platform_system_update_rpc,
  to_regprocedure('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is not null as tenant_system_update_rpc,
  to_regprocedure('public.platform_business_delete_v471(uuid)') is not null as business_delete_rpc;

select count(*) as pos_enabled_businesses_missing_shift_or_day_module
from public.tenant_modules pos
where pos.module_key='pos' and pos.enabled
  and (
    not exists(select 1 from public.tenant_modules x where x.tenant_id=pos.tenant_id and x.module_key='cashier_shifts' and x.enabled)
    or not exists(select 1 from public.tenant_modules x where x.tenant_id=pos.tenant_id and x.module_key='terminal_day' and x.enabled)
  );
