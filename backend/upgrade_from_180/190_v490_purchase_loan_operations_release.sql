-- THQ ERP v4.9.0 Build 20 — Purchase + Loan operations release contract.
begin;

-- Bulk Import now also includes transaction templates/imports, not only masters.
update public.modules
set description='Bulk products, customers, suppliers, sales and purchases import'
where key='bulk_import';

-- Publish the complete API surface used by Build 20. The previous API contract
-- stays source-compatible; these resources are additive.
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','purchase-cycle',
      'loans','loan-dashboard','loan-warnings','customer-loans',
      'finance-operations-health','transaction-bulk-import',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'loan_engine','v4.9.0','loan_accounting','double_entry','loan_warnings',true,
    'purchase_cycle_engine','v4.9.0','transaction_bulk_import','v4.9.0','purchase_reversals','v4.9.0',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

-- Build 20 remains on the 4.9.0 compatibility line. Older 4.9.0 clients can
-- keep working after these additive migrations while Build 20 requires the
-- corrected Purchase/Loan functions for its enhanced workspaces.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Purchase & Loan Operations',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build20_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'loan_create_v490','loan_update_v490','loan_submit_v490','loan_decide_v490','loan_disburse_v490',
    'loan_payment_create_v490','loan_payment_reverse_v490','loan_rate_change_v490','loan_status_v490',
    'loan_list_v490','loan_detail_v490','loan_dashboard_v490','loan_warnings_v490','customer_loan_summary_v490',
    'purchase_request_create_v484','purchase_request_list_v484','purchase_request_detail_v484','purchase_request_status_v484',
    'purchase_order_create_v484','purchase_order_list_v484','purchase_order_detail_v484','purchase_order_decide_v484',
    'goods_receipt_create_v484','goods_receipt_post_v484','goods_receipt_cancel_v490','goods_receipt_detail_v484',
    'purchase_invoice_create_v489','purchase_invoice_post_v484','purchase_invoice_void_v490','purchase_invoice_detail_v484',
    'supplier_payment_create_v490','supplier_payment_void_v490','suppliers_get_statement_v484','purchase_price_history_v484',
    'purchasing_dashboard_v484','purchase_cycle_summary_v490','finance_operations_health_v490',
    'transaction_bulk_import_v490','transaction_bulk_import_history_v490','thq_api_contract_v480'
  ];
begin
  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if to_regclass('public.loan_accounts_v490') is null then v_missing:=array_append(v_missing,'loan_accounts_v490');end if;
  if to_regclass('public.loan_schedule_v490') is null then v_missing:=array_append(v_missing,'loan_schedule_v490');end if;
  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.transaction_import_runs_v490') is null then v_missing:=array_append(v_missing,'transaction_import_runs_v490');end if;
  if to_regclass('public.transaction_import_documents_v490') is null then v_missing:=array_append(v_missing,'transaction_import_documents_v490');end if;

  if not exists(select 1 from public.modules where key='loans' and is_active) then v_missing:=array_append(v_missing,'module.loans');end if;
  if not exists(select 1 from public.modules where key='purchases' and is_active) then v_missing:=array_append(v_missing,'module.purchases');end if;
  if not exists(select 1 from public.modules where key='purchase_details' and is_active) then v_missing:=array_append(v_missing,'module.purchase_details');end if;
  if not exists(select 1 from public.modules where key='sales' and is_active) then v_missing:=array_append(v_missing,'module.sales');end if;
  if not exists(select 1 from public.modules where key='bulk_import' and is_active) then v_missing:=array_append(v_missing,'module.bulk_import');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.permissions where key='purchases.manage') then v_missing:=array_append(v_missing,'permission.purchases.manage');end if;
  if not exists(select 1 from public.permissions where key='bulk_import.use') then v_missing:=array_append(v_missing,'permission.bulk_import.use');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='accounts_payable') then v_missing:=array_append(v_missing,'mapping.accounts_payable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='input_gst') then v_missing:=array_append(v_missing,'mapping.input_gst');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',190,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'loan_runtime_fix',true,
    'loan_collection_and_details',true,
    'loan_accounting',true,
    'purchase_price_history_fix',true,
    'purchase_request_to_payment_cycle',true,
    'grn_stock_traceability',true,
    'purchase_invoice_accounts_payable',true,
    'supplier_payment_allocation',true,
    'controlled_purchase_reversals',true,
    'bulk_sales_import',true,
    'bulk_purchase_import',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build20_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  190,
  '4.9.0',
  'Purchase & Loan Operations',
  'Build 20 completes loan collection/details, repairs loan warnings and purchase price history, completes PR/PO/GRN/invoice/supplier-payment operations and adds auditable bulk Sales/Purchase import.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 190 purchase/loan operations release applied' as status;
