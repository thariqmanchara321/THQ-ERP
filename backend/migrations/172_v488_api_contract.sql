-- THQ ERP V4.8.8 — Mobile POS THQ API contract.
begin;
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array('sync','attention','inventory-intelligence','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary','tracking-policy','serials','batches','warranties','warehouses','stock-transfers','stock-counts','stock-reconciliation','purchase-requests','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','offline-pos','client-mobile','mobile-pos'),
    'core_financial_posting','direct_hardened_rpc','mobile_ready',true,'client_mobile_release','4.8.7','mobile_pos_release','4.8.8'
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;
create or replace function public.mobile_pos_api_contract_v488(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  return jsonb_build_object('api_version','v1','release','4.8.8','resource','mobile-pos','terminal_activation',true,'billing',true,'barcode_scan','device_camera','customers','offline_cache','offline_queue','idempotent_sync','v4.8.6-engine','printing','system-print-share','kot_groundwork',true);
end$$;
grant execute on function public.mobile_pos_api_contract_v488(uuid,uuid) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(172,'4.8.8','Mobile POS Foundation','THQ API contract metadata for Mobile POS terminal context, cache, billing sync, status, receipt events and KOT groundwork.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 172 API contract applied' as status;
