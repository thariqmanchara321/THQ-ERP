begin;

create or replace function public.gst_transaction_cutover_contract_v520(
  p_tenant_id uuid,
  p_channel text default 'client',
  p_device_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_channel text := lower(trim(coalesce(p_channel,'client')));
  v_device_contract jsonb := null;
begin
  if p_tenant_id is null then
    raise exception 'Tenant is required';
  end if;

  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
     and not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then
    raise exception 'GST transaction access required';
  end if;

  if v_channel not in ('client','pos','pos_offline','mobile_pos') then
    raise exception 'Unsupported GST cutover channel: %', p_channel;
  end if;

  if v_channel in ('pos_offline','mobile_pos') then
    if p_device_id is null then
      raise exception 'Device is required for % GST cutover contract', v_channel;
    end if;

    if v_channel='pos_offline' then
      v_device_contract := public.pos_offline_api_contract_v520(p_tenant_id,p_device_id);
    else
      v_device_contract := public.mobile_pos_api_contract_v520(p_tenant_id,p_device_id);
    end if;
  end if;

  return jsonb_build_object(
    'release','5.2.0-foundation',
    'contract_version',1,
    'channel',v_channel,
    'cutover_ready',true,
    'activation_mode','explicit_app_rpc_switch',
    'legacy_app_baseline',jsonb_build_object(
      'app_version','5.1.0',
      'build',27,
      'backend_contract_migration',213,
      'behavior','unchanged'
    ),
    'rules',jsonb_build_object(
      'old_clients_continue_v510',true,
      'v520_route_requires_v520_writer',true,
      'legacy_fallback_after_v520_route',false,
      'tax_calculation','server_authoritative_only',
      'request_id','required_for_retryable_writes',
      'authoritative_evidence','same_transaction',
      'authoritative_accounting','same_transaction'
    ),
    'rpc',jsonb_build_object(
      'sale','gst_sale_create_v520',
      'purchase','gst_purchase_create_v520',
      'purchase_invoice_v2','gst_purchase_invoice_create_v520',
      'sales_return','gst_sales_return_create_v520',
      'purchase_return','gst_purchase_return_create_v520',
      'service_bill','gst_service_job_bill_v520',
      'restaurant_bill',case when v_channel='mobile_pos' then 'mobile_pos_restaurant_bill_v520' else 'gst_restaurant_order_bill_v520' end,
      'offline_sale_sync','gst_pos_offline_sale_sync_v520',
      'mobile_sale_sync','gst_mobile_pos_sale_sync_v520',
      'gst_workspace','gst_ui_contract_v520'
    ),
    'channel_routes',
      case v_channel
        when 'client' then jsonb_build_object(
          'sale','gst_sale_create_v520',
          'purchase','gst_purchase_create_v520',
          'purchase_invoice_v2','gst_purchase_invoice_create_v520',
          'sales_return','gst_sales_return_create_v520',
          'purchase_return','gst_purchase_return_create_v520',
          'service_bill','gst_service_job_bill_v520',
          'gst_workspace','gst_ui_contract_v520'
        )
        when 'pos' then jsonb_build_object(
          'sale','gst_sale_create_v520',
          'sales_return','gst_sales_return_create_v520',
          'restaurant_bill','gst_restaurant_order_bill_v520'
        )
        when 'pos_offline' then jsonb_build_object(
          'sale_sync','gst_pos_offline_sale_sync_v520',
          'api_contract','pos_offline_api_contract_v520'
        )
        else jsonb_build_object(
          'sale_sync','gst_mobile_pos_sale_sync_v520',
          'restaurant_bill','mobile_pos_restaurant_bill_v520',
          'api_contract','mobile_pos_api_contract_v520'
        )
      end,
    'device_contract',v_device_contract
  );
end$$;

revoke all on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) from public;
revoke all on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) from anon;
grant execute on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) to authenticated;
grant execute on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) to service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  247,
  '5.2.0-foundation',
  'GST Application Cutover Contract',
  'Publishes the explicit Client/POS/Offline POS/Mobile POS v5.2 GST transaction RPC map while preserving the frozen v5.1.0 Build 27 backend contract and legacy behavior. No automatic routing or legacy fallback is changed; applications opt into authoritative v5.2 writers explicitly.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;