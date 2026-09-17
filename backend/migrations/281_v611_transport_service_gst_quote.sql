-- THQ ERP v6.1.1 Transport/Service authoritative GST quote
-- Source parity for live migration 20260917083429_v611_transport_service_gst_quote.
-- The quote is read-only. Final posting remains gst_service_job_bill_v520 and
-- legacy fallback remains disabled after v5.2 routing.

create or replace function public.gst_service_job_quote_v520(
  p_tenant_id uuid,
  p_job_id uuid,
  p_billing_variant_id uuid,
  p_supply_type text default null,
  p_place_of_supply_code text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  j public.service_jobs%rowtype;
  v_item_type text;
  v_variant_status text;
  v_product_status text;
  v_contract_items jsonb;
  v_normalized jsonb;
  v_supply text;
  v_pos text;
  v_quote jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
  ) then
    raise exception 'Transport service permission required';
  end if;
  if not (
    private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
    or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
  ) then
    raise exception 'GST calculation permission required';
  end if;
  if p_job_id is null then raise exception 'Service job is required'; end if;
  if p_billing_variant_id is null then raise exception 'Billing service item is required'; end if;

  select * into j
  from public.service_jobs
  where id=p_job_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Service job not found'; end if;
  if j.sale_id is not null then raise exception 'Service job is already billed'; end if;
  if j.status='cancelled' then raise exception 'Cancelled service job cannot be billed'; end if;
  if j.customer_id is null then raise exception 'Assign a customer before billing'; end if;
  if j.location_id is null then raise exception 'Service job must have a business location before billing'; end if;
  if coalesce(j.quantity,0)<=0 then raise exception 'Service job quantity must be positive'; end if;
  if coalesce(j.rate,0)<0 then raise exception 'Service job rate cannot be negative'; end if;

  perform private.v4_location_access(p_tenant_id,j.location_id,'operate');

  select p.item_type,p.status,pv.status
    into v_item_type,v_product_status,v_variant_status
  from public.product_variants pv
  join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  where pv.id=p_billing_variant_id and pv.tenant_id=p_tenant_id;
  if v_item_type is null or v_product_status<>'active' or v_variant_status<>'active' then
    raise exception 'Billing service item is invalid or inactive';
  end if;
  if v_item_type='stock' then
    raise exception 'Transport/service billing requires a Service or Non-stock item';
  end if;

  v_contract_items:=jsonb_build_array(jsonb_build_object(
    'variant_id',p_billing_variant_id,
    'quantity',j.quantity,
    'unit_price',j.rate,
    'discount_amount',0
  ));
  v_normalized:=private.v481_normalize_items(p_tenant_id,v_contract_items,'sale');
  v_supply:=private.gst_sale_supply_type_resolve_v520(
    p_tenant_id,j.customer_id,j.service_date,p_supply_type
  );
  v_pos:=private.gst_sale_pos_resolve_v520(
    p_tenant_id,j.customer_id,j.location_id,j.service_date,v_supply,
    v_normalized,p_place_of_supply_code
  );
  if v_pos is null then
    raise exception 'Place of supply is required for GST service billing; select the legally applicable GST state/territory code for this service';
  end if;

  v_quote:=public.gst_document_quote_v520(
    p_tenant_id,'sale',j.location_id,j.customer_id,j.service_date,
    v_supply,v_pos,v_normalized,0,0
  );

  return coalesce(v_quote,'{}'::jsonb) || jsonb_build_object(
    'job_id',j.id,
    'job_number',j.job_number,
    'service_rate',j.rate,
    'service_quantity',j.quantity,
    'service_quantity_unit',j.quantity_unit,
    'supply_type',v_supply,
    'place_of_supply_code',v_pos,
    'billing_variant_id',p_billing_variant_id,
    'preview_authority','gst_v520_server'
  );
end $$;

revoke all on function public.gst_service_job_quote_v520(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.gst_service_job_quote_v520(uuid,uuid,uuid,text,text) to authenticated,service_role;
