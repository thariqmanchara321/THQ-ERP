-- THQ ERP v4.9.0 Build 21 post-upgrade verification.
-- Expected latest migration: 193 / schema compatibility line: 4.9.0.

select migration_no, schema_version, release_name
from public.thq_schema_releases
order by migration_no desc
limit 1;

select public.thq_v490_release_verify() as v490_loan_release_verify;
select public.thq_v490_build19_verify() as v490_build19_verify;
select public.thq_v490_build20_verify() as v490_build20_verify;
select public.thq_v490_build21_verify() as v490_build21_verify;
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_api_contract_v480() as api_contract;

select
  to_regprocedure('public.loan_warnings_v490(uuid,uuid,integer)') is not null as loan_warnings_ok,
  to_regprocedure('public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid)') is not null as loan_collection_hardened,
  to_regprocedure('public.loan_payment_reverse_v490(uuid,uuid,text)') is not null as loan_payment_reverse_ok,
  to_regprocedure('public.loan_detail_v490(uuid,uuid)') is not null as loan_detail_ok,
  to_regprocedure('public.payments_party_summary_v491(uuid,uuid,text,integer)') is not null as party_payment_summary_ok,
  to_regprocedure('public.payments_party_detail_v491(uuid,text,uuid,uuid)') is not null as party_payment_detail_ok,
  to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is not null as purchase_request_create_ok,
  to_regprocedure('public.purchase_order_create_v484(uuid,uuid,uuid,jsonb,date,text,uuid)') is not null as purchase_order_create_ok,
  to_regprocedure('public.goods_receipt_create_v484(uuid,uuid,date,jsonb,text,text)') is not null as grn_create_ok,
  to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is not null as grn_post_ok,
  to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is not null as purchase_invoice_post_ok,
  to_regprocedure('public.supplier_payment_create_v490(uuid,uuid,uuid,date,numeric,text,jsonb,text,text,uuid)') is not null as supplier_payment_ok,
  to_regprocedure('public.transaction_bulk_import_v490(uuid,text,uuid,uuid,text,text,jsonb)') is not null as bulk_transaction_import_ok;

select key,name,category,is_active,sort_order
from public.modules
where key in ('sales','sales_details','purchases','purchase_details','loans','bulk_import')
order by sort_order,key;

select mapping_key,count(*) as tenant_mapping_count
from public.accounting_account_mappings
where mapping_key in(
  'payment.cash','payment.bank','payment.upi','payment.card',
  'loan_receivable','loan_interest_income','loan_penalty_income',
  'accounts_payable','input_gst','inventory_asset','rounding'
)
group by mapping_key
order by mapping_key;

select
  to_regclass('public.loan_accounts_v490') is not null as loan_accounts_table,
  to_regclass('public.loan_schedule_v490') is not null as loan_schedule_table,
  to_regclass('public.loan_payments_v490') is not null as loan_payments_table,
  to_regclass('public.purchase_invoices_v484') is not null as purchase_invoices_table,
  to_regclass('public.supplier_payments_v484') is not null as supplier_payments_table,
  to_regclass('public.transaction_import_runs_v490') is not null as transaction_import_runs_table;
