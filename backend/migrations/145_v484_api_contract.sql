-- THQ ERP V4.8.4 — THQ API v1 Purchasing V2 contract.
begin;

create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
  'resources',jsonb_build_array(
    'sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
    'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
    'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
    'business-summary','store-summary'
  ),
  'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3',
  'purchasing_engine','v4.8.4','stock_receipt_event','goods_receipt','supplier_liability_event','purchase_invoice','mobile_ready',true
 )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(145,'4.8.4','Purchasing V2','THQ API v1 resources for Purchase Requests, Purchase Orders, GRNs, Purchase Invoices, Supplier Payments/Ledger and Purchase Price History.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 145 API contract applied' as status;
