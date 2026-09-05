create or replace function public.gst_app_cutover_contract_v520(
  p_tenant_id uuid,
  p_device_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_location uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if p_device_id is not null then
    v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  end if;

  return jsonb_build_object(
    'release','5.2',
    'contract','gst-authoritative-v520',
    'tenant_id',p_tenant_id,
    'device_id',p_device_id,
    'location_id',v_location,
    'cutover_ready',true,
    'rules',jsonb_build_object(
      'new_transactions_must_use_v520',true,
      'legacy_writers_compatibility_only',true,
      'legacy_fallback_for_failed_v520',false,
      'authoritative_snapshot_required',true,
      'authoritative_journal_required',true,
      'legacy_unverified_required_for_legacy_transactions',true
    ),
    'client',jsonb_build_object(
      'sale_create','gst_sale_create_v520',
      'purchase_create','gst_purchase_create_v520',
      'purchasing_v2_invoice_create','gst_purchase_invoice_create_v520',
      'sales_return_create','gst_sales_return_create_v520',
      'purchase_return_create','gst_purchase_return_create_v520',
      'service_job_bill','gst_service_job_bill_v520',
      'restaurant_bill','gst_restaurant_order_bill_v520'
    ),
    'desktop_pos',jsonb_build_object(
      'sale_create','gst_sale_create_v520',
      'restaurant_bill','gst_restaurant_order_bill_v520',
      'offline_sale_sync','gst_pos_offline_sale_sync_v520',
      'offline_contract','pos_offline_api_contract_v520'
    ),
    'mobile_pos',jsonb_build_object(
      'api_contract','mobile_pos_api_contract_v520',
      'sale_sync','gst_mobile_pos_sale_sync_v520',
      'product_cache','mobile_pos_product_cache_v520',
      'cache_manifest','mobile_pos_cache_manifest_v520',
      'sync_status','mobile_pos_sync_status_v520',
      'receipt_event','mobile_pos_receipt_event_v520',
      'kot_create','mobile_pos_kot_create_v520',
      'restaurant_bill','mobile_pos_restaurant_bill_v520'
    ),
    'compatibility_only',jsonb_build_object(
      'sale_create','sales_create_v483',
      'purchase_create','purchases_create_v483',
      'sales_return_create','sales_return_create_v483',
      'purchase_return_create','purchase_return_create_v481',
      'service_job_bill','service_job_bill_v51',
      'restaurant_bill','restaurant_order_bill_v489',
      'offline_sale_sync','pos_offline_sale_sync_v486',
      'mobile_sale_sync','mobile_pos_sale_sync_v488'
    )
  );
end
$$;

revoke all on function public.gst_app_cutover_contract_v520(uuid,uuid) from public,anon;
grant execute on function public.gst_app_cutover_contract_v520(uuid,uuid) to authenticated,service_role;
comment on function public.gst_app_cutover_contract_v520(uuid,uuid) is
'Authoritative THQ ERP v5.2 GST Client/POS RPC cutover map. Legacy transaction writers remain compatibility-only and must not be used as fallback for new v5.2 GST transactions.';