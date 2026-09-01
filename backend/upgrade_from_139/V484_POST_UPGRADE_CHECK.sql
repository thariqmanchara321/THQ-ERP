-- THQ ERP V4.8.4 — post-upgrade verification
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_api_contract_v480() as api_contract;
select public.thq_v484_release_verify() as release_verification;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 140 and 146
order by migration_no;

select
  to_regclass('public.purchase_requests_v484') is not null as purchase_requests_ready,
  to_regclass('public.purchase_request_items_v484') is not null as purchase_request_items_ready,
  to_regclass('public.goods_receipts_v484') is not null as grn_ready,
  to_regclass('public.goods_receipt_items_v484') is not null as grn_items_ready,
  to_regclass('public.purchase_invoices_v484') is not null as purchase_invoices_ready,
  to_regclass('public.purchase_invoice_items_v484') is not null as purchase_invoice_items_ready,
  to_regclass('public.supplier_payments_v484') is not null as supplier_payments_ready,
  to_regclass('public.supplier_ledger_entries_v484') is not null as supplier_ledger_ready,
  to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is not null as purchase_request_create_ready,
  to_regprocedure('public.purchase_order_decide_v484(uuid,uuid,boolean,text)') is not null as po_approval_ready,
  to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is not null as grn_post_ready,
  to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is not null as purchase_invoice_post_ready,
  to_regprocedure('public.supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text)') is not null as supplier_payment_ready,
  to_regprocedure('public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid)') is not null as supplier_ledger_api_ready,
  to_regprocedure('public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)') is not null as purchase_price_history_ready;
