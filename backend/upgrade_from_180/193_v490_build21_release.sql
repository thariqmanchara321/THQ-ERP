-- THQ ERP v4.9.0 Build 21 — Loan collections, contrast and Party Payment Center release.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','purchase-cycle',
      'loans','loan-dashboard','loan-warnings','customer-loans','payment-center',
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
    'party_payment_center','v4.9.0','loan_collection_hardening','v4.9.0',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Payments & Collections Hardening',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build21_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'loan_payment_create_v490','loan_detail_v490','loan_dashboard_v490','loan_warnings_v490',
    'payments_party_summary_v491','payments_party_detail_v491',
    'purchase_request_create_v484','purchase_order_create_v484','goods_receipt_create_v484','purchase_invoice_create_v489',
    'supplier_payment_create_v490','transaction_bulk_import_v490','thq_api_contract_v480'
  ];
begin
  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.purchase_invoices_v484') is null then v_missing:=array_append(v_missing,'purchase_invoices_v484');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.permissions where key='payments.view') then v_missing:=array_append(v_missing,'permission.payments.view');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='payment.cash') then v_missing:=array_append(v_missing,'mapping.payment.cash');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',193,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'loan_collection_hardened',true,
    'client_device_cash_drawer_isolation',true,
    'party_grouped_receivables_payables',true,
    'sales_and_loan_customer_breakdown',true,
    'legacy_and_v2_supplier_breakdown',true,
    'supplier_unallocated_credit_awareness',true,
    'readable_edge_errors',true,
    'light_surface_text_contrast',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build21_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  193,
  '4.9.0',
  'Payments & Collections Hardening',
  'Build 21 hardens loan collection, separates Client devices from POS cash drawers, improves light-theme text contrast, and redesigns Pending Payments around customer/supplier balances with drill-down.'
)
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 21 migration 193 release applied' as status;
