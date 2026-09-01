-- THQ ERP v4.8.9 — stabilized THQ API contract metadata.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(179,'4.8.9','Stabilization & Operations','THQ API v1 contract expanded for v4.8.9 runtime health and restaurant operations; Purchasing V2 invoice create carries round-off.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 179 API contract applied' as status;
