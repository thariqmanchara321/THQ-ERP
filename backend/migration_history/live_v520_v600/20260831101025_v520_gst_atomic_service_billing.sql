create or replace function public.gst_service_job_bill_v520(
  p_tenant_id uuid,
  p_job_id uuid,
  p_billing_variant_id uuid,
  p_due_date date,
  p_initial_payment numeric,
  p_payment_method text,
  p_payment_reference text,
  p_device_id uuid,
  p_request_id text,
  p_supply_type text default null,
  p_place_of_supply_code text default null
) returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  j public.service_jobs%rowtype;
  v_item_type text;
  v_variant_status text;
  v_product_status text;
  v_req_payload jsonb;
  v_req_state jsonb;
  v_old_req jsonb;
  v_contract_items jsonb;
  v_normalized jsonb;
  v_supply text;
  v_pos text;
  v_quote jsonb;
  v_totals jsonb;
  v_bridge jsonb;
  v_source jsonb;
  v_sale_id uuid;
  v_sale_number text;
  v_line_ids jsonb;
  v_snapshot uuid;
  v_journal uuid;
  v_document_number text;
  v_response jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'transport_service.create')
          or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then
    raise exception 'Transport service permission required';
  end if;
  if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
          or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then
    raise exception 'GST calculation permission required';
  end if;
  if p_job_id is null then raise exception 'Service job is required'; end if;
  if p_billing_variant_id is null then raise exception 'Billing service item is required'; end if;
  if coalesce(p_initial_payment,0)<0 then raise exception 'Initial payment cannot be negative'; end if;

  v_req_payload:=jsonb_build_object(
    'job_id',p_job_id,
    'billing_variant_id',p_billing_variant_id,
    'due_date',p_due_date,
    'initial_payment',coalesce(p_initial_payment,0),
    'payment_method',lower(trim(coalesce(p_payment_method,''))),
    'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),''),
    'device_id',p_device_id,
    'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),
    'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),'')
  );
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.service_job.bill.v520',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then
    return v_req_state->'response';
  end if;

  v_old_req:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create');
  if v_old_req is not null then
    raise exception 'Request ID is already used by the legacy Sale path';
  end if;

  select * into j
  from public.service_jobs
  where id=p_job_id and tenant_id=p_tenant_id
  for update;
  if not found then raise exception 'Service job not found'; end if;
  if j.sale_id is not null then raise exception 'Service job is already billed'; end if;
  if j.status='cancelled' then raise exception 'Cancelled service job cannot be billed'; end if;
  if j.customer_id is null then raise exception 'Assign a customer before billing'; end if;
  if j.location_id is null then raise exception 'Service job must have a business location before billing'; end if;
  if coalesce(j.quantity,0)<=0 then raise exception 'Service job quantity must be positive'; end if;
  if coalesce(j.rate,0)<0 then raise exception 'Service job rate cannot be negative'; end if;
  if p_due_date is not null and p_due_date<j.service_date then raise exception 'Due date cannot be before service date'; end if;

  perform private.v4_location_access(p_tenant_id,j.location_id,'operate');
  perform private.erp_validate_transaction_origin(p_tenant_id,j.location_id,p_device_id,'sales');

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
  v_supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,j.customer_id,j.service_date,p_supply_type);
  v_pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,j.customer_id,j.location_id,j.service_date,v_supply,v_normalized,p_place_of_supply_code);
  if v_pos is null then
    raise exception 'Place of supply is required for GST service billing; select the legally applicable GST state/territory code for this service';
  end if;

  v_quote:=public.gst_document_quote_v520(
    p_tenant_id,'sale',j.location_id,j.customer_id,j.service_date,v_supply,v_pos,v_normalized,0,0
  );
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then
    raise exception 'GST Service invoice is not compliance-ready: %',coalesce(v_quote->'errors','[]'::jsonb)::text;
  end if;
  v_totals:=v_quote->'totals';
  if coalesce(p_initial_payment,0)>coalesce((v_totals->>'grand_total')::numeric,0)+0.005 then
    raise exception 'Initial payment cannot exceed GST service invoice total';
  end if;
  if coalesce(p_initial_payment,0)>0
     and lower(trim(coalesce(p_payment_method,''))) not in('cash','bank','card','upi','cheque','other') then
    raise exception 'Invalid payment method';
  end if;

  -- Preserve the contractual service-job rate.  Do not call the ordinary v4.8.2
  -- price resolver here: service jobs are already commercially priced upstream.
  -- The bridge lets the legacy operational Sale carry the exact GST grand total
  -- without making legacy tax calculation authoritative.
  v_bridge:=private.gst_sale_bridge_v520(v_contract_items,v_normalized,(v_totals->>'grand_total')::numeric);

  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'sale');
  v_source:=public.sales_create_v481(
    p_tenant_id,j.customer_id,j.service_date,p_due_date,
    v_bridge->'items',(v_bridge->>'additional_charges')::numeric,
    coalesce(p_initial_payment,0),
    case when coalesce(p_initial_payment,0)>0 then lower(trim(p_payment_method)) else 'credit' end,
    coalesce(p_payment_reference,''),
    'Transport service '||j.job_number||' • '||coalesce(j.tracking_code,''),
    j.location_id,p_device_id,p_request_id
  );
  v_sale_id:=nullif(v_source->>'sale_id','')::uuid;
  if v_sale_id is null then raise exception 'GST Service Sale source could not be resolved'; end if;
  perform private.gst_authoritative_context_bind_v520(v_sale_id);

  select s.sale_number into v_sale_number
  from public.sales s
  where s.tenant_id=p_tenant_id and s.id=v_sale_id and s.status='posted'
  for update;
  if v_sale_number is null then raise exception 'GST Service Sale source is not posted'; end if;

  if exists(select 1 from public.journal_entries x where x.tenant_id=p_tenant_id and x.source_type='sale' and x.source_id=v_sale_id and x.status='posted') then
    raise exception 'Legacy Sale journal was created inside authoritative GST service context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 x where x.tenant_id=p_tenant_id and x.source_type='sale' and x.source_id=v_sale_id) then
    raise exception 'Legacy GST evidence was created inside authoritative GST service context';
  end if;

  v_line_ids:=private.gst_sale_reconcile_source_v520(p_tenant_id,v_sale_id,v_quote);
  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sale',v_sale_id,v_sale_number,j.location_id,j.service_date,v_quote,v_line_ids);
  v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);

  select s.document_number into v_document_number
  from public.gst_document_snapshots_v520 s
  where s.id=v_snapshot and s.tenant_id=p_tenant_id;
  if v_document_number is null then raise exception 'GST Service legal document number was not captured'; end if;

  update public.sale_items
  set pricing_source='service_job',
      pricing_metadata=coalesce(pricing_metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'service_job_id',j.id,
        'service_job_number',j.job_number,
        'service_rate',j.rate,
        'quantity_unit',j.quantity_unit,
        'from_location',j.from_location,
        'to_location',j.to_location,
        'distance_km',j.distance_km,
        'pricing_policy','contract_rate_preserved_v520'
      ))
  where tenant_id=p_tenant_id and sale_id=v_sale_id and variant_id=p_billing_variant_id;

  update public.service_jobs
  set sale_id=v_sale_id,status='completed',updated_at=now()
  where id=j.id and tenant_id=p_tenant_id and sale_id is null;
  if not found then raise exception 'Service job billing link changed concurrently'; end if;

  v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object(
    'success',true,
    'billing_source','service_job_v520',
    'gst_engine',v_quote->>'engine',
    'gst_status','POSTED',
    'gst_supply_type',v_supply,
    'place_of_supply_code',v_quote->>'place_of_supply_code',
    'job_id',j.id,
    'job_number',j.job_number,
    'service_rate',j.rate,
    'service_quantity',j.quantity,
    'service_quantity_unit',j.quantity_unit,
    'sale_id',v_sale_id,
    'sale_number',v_sale_number,
    'invoice_number',v_document_number,
    'grand_total',(v_totals->>'grand_total')::numeric,
    'taxable_total',(v_totals->>'taxable_value')::numeric,
    'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,
    'sgst',(v_totals->>'sgst')::numeric,
    'utgst',(v_totals->>'utgst')::numeric,
    'igst',(v_totals->>'igst')::numeric,
    'cess',(v_totals->>'cess')::numeric,
    'recipient_rcm_tax_payable_total',coalesce((v_totals->>'recipient_rcm_tax_payable_total')::numeric,0),
    'gst_snapshot_id',v_snapshot,
    'journal_id',v_journal,
    'gst_ready_for_compliance',true
  );

  perform private.business_audit_write_v471(
    p_tenant_id,'service.job.bill.gst_v520','service_job',j.id,j.job_number,to_jsonb(j),
    jsonb_build_object('sale_id',v_sale_id,'sale_number',v_sale_number,'invoice_number',v_document_number,'grand_total',(v_totals->>'grand_total')::numeric,'gst_snapshot_id',v_snapshot,'journal_id',v_journal)
  );

  v_response:=private.gst_request_complete_v520(
    p_tenant_id,p_request_id,'gst.service_job.bill.v520','sale',v_sale_id,v_snapshot,v_journal,v_response
  );
  update public.transaction_requests_v47
  set response=v_response
  where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='sale.create';

  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end
$$;

revoke all on function public.gst_service_job_bill_v520(uuid,uuid,uuid,date,numeric,text,text,uuid,text,text,text) from public,anon;
grant execute on function public.gst_service_job_bill_v520(uuid,uuid,uuid,date,numeric,text,text,uuid,text,text,text) to authenticated,service_role;