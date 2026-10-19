-- =====================================================================
-- THQ ERP v6.0 TRANSACTION CORRECTNESS HOTFIX
--
-- Fixes:
--   1. v5.2.2 Sale authoritative payment response contract
--   2. Service Billing metadata finalized before GST immutability
--   3. Restaurant Billing settlement response contract
--   4. GST validator reports immutable posted journal after posting
--
-- No legacy fallback.
-- No RLS/security weakening.
-- No table/data changes.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.gst_sale_create_v522(p_tenant_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_payment_allocations jsonb, p_notes text DEFAULT NULL::text, p_location_id uuid DEFAULT NULL::uuid, p_device_id uuid DEFAULT NULL::uuid, p_request_id text DEFAULT NULL::text, p_supply_type text DEFAULT NULL::text, p_place_of_supply_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_req_payload jsonb;v_req_state jsonb;v_old_req jsonb;v_supply text;v_pos text;v_priced jsonb;v_normalized jsonb;
  v_quote0 jsonb;v_quote jsonb;v_bridge jsonb;v_source jsonb;v_sale_id uuid;v_sale_number text;v_line_ids jsonb;v_snapshot uuid;v_journal uuid;
  v_document_number text;v_response jsonb;v_totals jsonb;v_round numeric;v_payment_result jsonb;v_discount numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not(private.erp_user_is_owner(p_tenant_id, auth.uid()) or private.erp_has_permission(p_tenant_id,'sales.manage')) then raise exception 'Sales permission required'; end if;
  if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required'; end if;
  if p_location_id is null then raise exception 'Business location is required'; end if;
  if p_sale_date is null then raise exception 'Sale date is required'; end if;
  if p_due_date is not null and p_due_date<p_sale_date then raise exception 'Due date cannot be before sale date'; end if;
  v_req_payload:=jsonb_build_object('customer_id',p_customer_id,'sale_date',p_sale_date,'due_date',p_due_date,'items',coalesce(p_items,'[]'::jsonb),
    'payment_allocations',coalesce(p_payment_allocations,'[]'::jsonb),'notes',nullif(trim(coalesce(p_notes,'')),''),'location_id',p_location_id,
    'device_id',p_device_id,'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),'') );
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.sale.create.v522',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response'; end if;
  v_old_req:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create');if v_old_req is not null then raise exception 'Request ID is already used by the legacy Sale path'; end if;
  v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);
  v_normalized:=private.v481_normalize_items(p_tenant_id,v_priced,'sale');
  v_supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,p_customer_id,p_sale_date,p_supply_type);
  v_pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,p_customer_id,p_location_id,p_sale_date,v_supply,v_normalized,p_place_of_supply_code);
  v_quote0:=public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_customer_id,p_sale_date,v_supply,v_pos,v_normalized,0,0);
  if coalesce((v_quote0->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Sale is not compliance-ready: %',coalesce(v_quote0->'errors','[]'::jsonb)::text; end if;
  v_round:=round(round(coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),0)-coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),2);
  v_quote:=public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_customer_id,p_sale_date,v_supply,v_pos,v_normalized,0,v_round);
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Sale is not compliance-ready after round-off: %',coalesce(v_quote->'errors','[]'::jsonb)::text; end if;
  v_totals:=v_quote->'totals';v_discount:=coalesce((v_totals->>'discount')::numeric,0);
  v_bridge:=private.gst_sale_bridge_v520(v_priced,v_normalized,(v_totals->>'grand_total')::numeric);
  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'sale');
  v_source:=public.sales_create_v483(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_bridge->'items',(v_bridge->>'additional_charges')::numeric,0,'cash',null,p_notes,p_location_id,p_device_id,p_request_id);
  v_sale_id:=nullif(v_source->>'sale_id','')::uuid;if v_sale_id is null then raise exception 'GST Sale source could not be resolved'; end if;
  perform private.gst_authoritative_context_bind_v520(v_sale_id);
  select sale_number into v_sale_number from public.sales where tenant_id=p_tenant_id and id=v_sale_id and status='posted' for update;
  if v_sale_number is null then raise exception 'GST Sale source is not posted'; end if;
  if exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and source_type='sale' and source_id=v_sale_id and status='posted') then raise exception 'Legacy Sale journal was created inside authoritative GST context'; end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 where tenant_id=p_tenant_id and source_type='sale' and source_id=v_sale_id) then raise exception 'Legacy GST evidence was created inside authoritative GST context'; end if;
  v_line_ids:=private.gst_sale_reconcile_source_v520(p_tenant_id,v_sale_id,v_quote);
  v_payment_result:=private.sale_payment_allocations_create_v522(p_tenant_id,v_sale_id,p_customer_id,(v_totals->>'grand_total')::numeric,coalesce(p_payment_allocations,'[]'::jsonb));
  perform private.gst_sale_credit_limit_assert_v600(p_tenant_id,v_sale_id,p_customer_id,coalesce((v_payment_result->>'credit_amount')::numeric,0));
  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sale',v_sale_id,v_sale_number,p_location_id,p_sale_date,v_quote,v_line_ids);
  v_journal:=private.gst_authoritative_sale_journal_post_v522(p_tenant_id,v_snapshot);
  select document_number into v_document_number from public.gst_document_snapshots_v520 where id=v_snapshot and tenant_id=p_tenant_id;
  if v_document_number is null then raise exception 'GST Sale legal document number was not captured'; end if;
  v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object('success',true,'writer','gst_sale_create_v522','version','5.2.2','gst_engine',v_quote->>'engine',
    'gst_status','POSTED','gst_supply_type',v_supply,'place_of_supply_code',v_quote->>'place_of_supply_code','sale_id',v_sale_id,'sale_number',v_sale_number,
    'invoice_number',v_document_number,'subtotal',(v_totals->>'subtotal')::numeric,'discount_total',v_discount,'round_off',v_round,
    'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,
    'payments',v_payment_result,
    'paid_amount',coalesce((v_payment_result->>'settled_amount')::numeric,0),
    'balance_due',coalesce((v_payment_result->>'accounts_receivable')::numeric,0),
    'payment_status',case
      when coalesce((v_payment_result->>'accounts_receivable')::numeric,0)<=0.005 then 'paid'
      when coalesce((v_payment_result->>'settled_amount')::numeric,0)>0 then 'part_paid'
      else 'unpaid'
    end,
    'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'gst_ready_for_compliance',true,'legacy_fallback_used',false);
  v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.sale.create.v522','sale',v_sale_id,v_snapshot,v_journal,v_response);
  update public.transaction_requests_v47 set response=v_response where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='sale.create';
  perform private.gst_authoritative_context_exit_v520();return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.gst_service_job_bill_v520(p_tenant_id uuid, p_job_id uuid, p_billing_variant_id uuid, p_due_date date, p_initial_payment numeric, p_payment_method text, p_payment_reference text, p_device_id uuid, p_request_id text, p_supply_type text DEFAULT NULL::text, p_place_of_supply_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  -- Finalize source metadata before the authoritative snapshot makes Sale lines immutable.
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

  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sale',v_sale_id,v_sale_number,j.location_id,j.service_date,v_quote,v_line_ids);
  v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);

  select s.document_number into v_document_number
  from public.gst_document_snapshots_v520 s
  where s.id=v_snapshot and s.tenant_id=p_tenant_id;
  if v_document_number is null then raise exception 'GST Service legal document number was not captured'; end if;


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
$function$;

CREATE OR REPLACE FUNCTION public.gst_restaurant_order_bill_v520(p_tenant_id uuid, p_order_id uuid, p_device_id uuid, p_customer_id uuid, p_due_date date, p_initial_payment numeric, p_payment_method text, p_payment_reference text, p_round_off numeric DEFAULT 0, p_supply_type text DEFAULT NULL::text, p_place_of_supply_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  o public.restaurant_orders%rowtype;
  v_customer uuid;
  v_items jsonb;
  v_method text;
  v_wrapper_request text;
  v_sale_request text;
  v_payment_request text;
  v_req_payload jsonb;
  v_req_state jsonb;
  v_sale jsonb;
  v_payment jsonb;
  v_sale_id uuid;
  v_snapshot uuid;
  v_sale_journal uuid;
  v_payment_id uuid;
  v_payment_journal uuid;
  v_total numeric;
  v_response jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'restaurant.order')
          or private.erp_has_permission(p_tenant_id,'restaurant.manage')) then
    raise exception 'Restaurant billing permission denied';
  end if;
  if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
          or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then
    raise exception 'GST calculation permission required';
  end if;
  if p_order_id is null then raise exception 'Restaurant order is required'; end if;
  if abs(coalesce(p_round_off,0))>0.999999 then raise exception 'Round off must be between -1.00 and 1.00'; end if;

  v_method:=coalesce(nullif(lower(trim(p_payment_method)),''),'cash');
  if v_method not in('cash','bank','card','upi','cheque','other','credit') then
    raise exception 'Invalid restaurant payment method';
  end if;

  v_wrapper_request:='gst-restaurant-order:'||p_order_id::text;
  v_sale_request:='gst-restaurant-sale:'||p_order_id::text;
  v_payment_request:='gst-restaurant-payment:'||p_order_id::text;
  v_req_payload:=jsonb_build_object(
    'order_id',p_order_id,
    'device_id',p_device_id,
    'customer_id',p_customer_id,
    'due_date',p_due_date,
    -- v4.8.9 already treats non-credit Restaurant billing as full settlement.
    -- Retain this input in the idempotency payload for caller compatibility,
    -- but do not let it create a partial/ambiguous restaurant settlement.
    'legacy_initial_payment_argument',coalesce(p_initial_payment,0),
    'payment_method',v_method,
    'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),''),
    'round_off',round(coalesce(p_round_off,0),2),
    'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),
    'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),'')
  );
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,v_wrapper_request,'gst.restaurant.order.bill.v520',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then
    return v_req_state->'response';
  end if;

  select * into o
  from public.restaurant_orders
  where id=p_order_id and tenant_id=p_tenant_id
  for update;
  if not found then raise exception 'Restaurant order not found'; end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,o.location_id,p_device_id,'restaurant','operate');
  if o.status='cancelled' then raise exception 'Cancelled restaurant order cannot be billed'; end if;
  if o.status='billed' or o.sale_id is not null then
    raise exception 'Restaurant order is already billed outside this v5.2 GST billing request; reconcile the existing invoice instead of converting it silently';
  end if;

  v_customer:=coalesce(o.customer_id,p_customer_id);
  if v_customer is null or not exists(
    select 1 from public.customers c
    where c.id=v_customer and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
  ) then
    raise exception 'Choose an active customer before billing';
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'variant_id',i.variant_id,
      'quantity',i.quantity,
      'unit_id',i.unit_id,
      'unit_price',i.unit_price,
      'discount_amount',i.discount_amount
    )) order by i.created_at,i.id),'[]'::jsonb)
  into v_items
  from public.restaurant_order_items i
  where i.order_id=o.id and i.tenant_id=p_tenant_id;
  if jsonb_array_length(v_items)=0 then raise exception 'Restaurant order has no items'; end if;

  -- GST Sale remains the legal invoice.  The Sale writer re-resolves current server
  -- pricing at the instant of billing, preserving the v4.8.9 Restaurant rule.
  -- KOT/order tax_rate fields are never authoritative GST evidence.
  v_sale:=public.gst_sale_create_v520(
    p_tenant_id=>p_tenant_id,
    p_customer_id=>v_customer,
    p_sale_date=>current_date,
    p_due_date=>p_due_date,
    p_items=>v_items,
    p_additional_charges=>0,
    p_round_off=>round(coalesce(p_round_off,0),2),
    p_initial_payment=>0,
    p_payment_method=>'credit',
    p_payment_reference=>null,
    p_notes=>'Restaurant '||o.order_number,
    p_location_id=>o.location_id,
    p_device_id=>p_device_id,
    p_request_id=>v_sale_request,
    p_supply_type=>p_supply_type,
    p_place_of_supply_code=>p_place_of_supply_code
  );
  v_sale_id:=nullif(v_sale->>'sale_id','')::uuid;
  v_snapshot:=nullif(v_sale->>'gst_snapshot_id','')::uuid;
  v_sale_journal:=nullif(v_sale->>'journal_id','')::uuid;
  v_total:=coalesce(nullif(v_sale->>'grand_total','')::numeric,0);
  if v_sale_id is null or v_snapshot is null or v_sale_journal is null then
    raise exception 'Restaurant GST Sale did not create complete authoritative evidence';
  end if;

  -- Preserve v4.8.9 semantics: every non-credit Restaurant bill is settled for
  -- the exact server-authoritative invoice total.  The legacy initial-payment argument
  -- is intentionally not used for partial settlement.
  if v_method<>'credit' and v_total>0.005 then
    v_payment:=public.sales_add_payment_v47(
      p_tenant_id,v_sale_id,v_total,v_method,coalesce(p_payment_reference,''),
      'Restaurant settlement '||o.order_number,v_payment_request
    );
    v_payment_id:=nullif(v_payment->>'payment_id','')::uuid;
    if v_payment_id is null then raise exception 'Restaurant settlement payment was not created'; end if;
    select j.id into v_payment_journal
    from public.journal_entries j
    where j.tenant_id=p_tenant_id and j.source_type='sale_payment' and j.source_id=v_payment_id and j.status='posted'
    order by j.created_at desc limit 1;
    if v_payment_journal is null then raise exception 'Restaurant settlement payment journal was not created'; end if;
  else
    v_payment:=jsonb_build_object(
      'success',true,'payment_id',null,'amount',0,'paid_amount',0,
      'balance_due',v_total,'payment_status','unpaid'
    );
  end if;

  update public.restaurant_orders
  set status='billed',sale_id=v_sale_id,billed_at=coalesce(billed_at,now()),updated_at=now()
  where id=o.id and tenant_id=p_tenant_id and status<>'cancelled' and sale_id is null;
  if not found then raise exception 'Restaurant order billing state changed concurrently'; end if;

  update public.restaurant_kots
  set status='served',served_at=coalesce(served_at,now())
  where tenant_id=p_tenant_id and order_id=o.id and status not in('served','cancelled');

  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','restaurant_order',o.id::text,'bill');

  v_response:=coalesce(v_sale,'{}'::jsonb)||jsonb_build_object(
    'success',true,
    'order_id',o.id,
    'order_number',o.order_number,
    'restaurant_billing','v5.2-gst',
    'settlement_mode',case when v_method='credit' then 'credit' else 'full' end,
    'requested_initial_payment_argument',coalesce(p_initial_payment,0),
    'payment_method',v_method,
    'payment',v_payment,
    'payment_id',v_payment_id,
    'payment_journal_id',v_payment_journal,
    'paid_amount',coalesce(nullif(v_payment->>'paid_amount','')::numeric,0),
    'balance_due',coalesce(nullif(v_payment->>'balance_due','')::numeric,v_total),
    'payment_status',coalesce(nullif(v_payment->>'payment_status',''),case when v_method='credit' then 'unpaid' else 'paid' end),
    'gst_snapshot_id',v_snapshot,
    'journal_id',v_sale_journal
  );

  perform private.business_audit_write_v471(
    p_tenant_id,'restaurant.order.bill.gst_v520','restaurant_order',o.id,o.order_number,to_jsonb(o),
    jsonb_build_object(
      'sale_id',v_sale_id,'sale_number',v_sale->>'sale_number','grand_total',v_total,
      'payment_method',v_method,'payment_id',v_payment_id,
      'gst_snapshot_id',v_snapshot,'journal_id',v_sale_journal
    )
  );

  v_response:=private.gst_request_complete_v520(
    p_tenant_id,v_wrapper_request,'gst.restaurant.order.bill.v520','restaurant_order',o.id,v_snapshot,v_sale_journal,v_response
  );
  return v_response;
end
$function$;

CREATE OR REPLACE FUNCTION private.gst_snapshot_document_journal_validate_v520(p_tenant_id uuid, p_snapshot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  s public.gst_document_snapshots_v520%rowtype;
  v jsonb;
  v_journal uuid;
  dr numeric;
  cr numeric;
  zero_count int;
  generic_gst int;
begin
  select * into s
  from public.gst_document_snapshots_v520
  where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Authoritative GST snapshot not found'; end if;

  select j.id into v_journal
  from public.journal_entries j
  where j.tenant_id=p_tenant_id
    and j.source_type=s.source_type
    and j.source_id=s.source_id
    and j.status='posted'
  order by j.created_at,j.id
  limit 1;

  if v_journal is null then
    v:=private.gst_snapshot_document_journal_lines_v520(p_tenant_id,p_snapshot_id);
  else
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'account_id',l.account_id,
      'system_key',a.system_key,
      'party_type',l.party_type,
      'party_id',l.party_id,
      'description',l.description,
      'debit',round(l.debit,2),
      'credit',round(l.credit,2)
    )) order by l.id),'[]'::jsonb)
    into v
    from public.journal_lines l
    join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=p_tenant_id
    where l.journal_entry_id=v_journal;
  end if;

  if jsonb_typeof(v)<>'array' or jsonb_array_length(v)<2 then
    raise exception 'GST document journal requires at least two lines';
  end if;

  select
    round(coalesce(sum((x->>'debit')::numeric),0),2),
    round(coalesce(sum((x->>'credit')::numeric),0),2),
    count(*) filter(where coalesce((x->>'debit')::numeric,0)=0 and coalesce((x->>'credit')::numeric,0)=0),
    count(*) filter(where x->>'mapping_key' in('input_gst','output_gst') or x->>'system_key' in('input_gst','output_gst'))
  into dr,cr,zero_count,generic_gst
  from jsonb_array_elements(v)x;

  if dr<=0 or cr<=0 or dr<>cr then
    raise exception 'GST composed journal is not balanced. Debit %, Credit %',dr,cr;
  end if;
  if zero_count>0 then raise exception 'GST composed journal contains zero-value lines'; end if;
  if generic_gst>0 then raise exception 'GST authoritative journal must not use legacy generic Input/Output GST control lines'; end if;

  return jsonb_build_object(
    'valid',true,
    'debit',dr,
    'credit',cr,
    'line_count',jsonb_array_length(v),
    'lines',v,
    'validation_source',case when v_journal is null then 'composed_expected' else 'posted_journal' end,
    'journal_id',v_journal
  );
end
$function$;

DO $thq$
DECLARE
    v_def text;
BEGIN

    -- ================================================================
    -- v5.2.2 Sale response contract
    -- ================================================================

    SELECT pg_get_functiondef(
      'public.gst_sale_create_v522(
        uuid,
        uuid,
        date,
        date,
        jsonb,
        jsonb,
        text,
        uuid,
        uuid,
        text,
        text,
        text
      )'::regprocedure
    )
    INTO v_def;

    IF position(
         '''paid_amount'',coalesce((v_payment_result->>''settled_amount'')::numeric,0)'
         in v_def
       ) = 0
       OR position(
         '''balance_due'',coalesce((v_payment_result->>''accounts_receivable'')::numeric,0)'
         in v_def
       ) = 0
       OR position(
         '''payment_status'',case'
         in v_def
       ) = 0
       OR position(
         'legacy_fallback_used'
         in v_def
       ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: gst_sale_create_v522';
    END IF;


    -- ================================================================
    -- Service Billing immutability ordering
    -- ================================================================

    SELECT pg_get_functiondef(
      'public.gst_service_job_bill_v520(
        uuid,
        uuid,
        uuid,
        date,
        numeric,
        text,
        text,
        uuid,
        text,
        text,
        text
      )'::regprocedure
    )
    INTO v_def;

    IF position(
      'Finalize source metadata before the authoritative snapshot makes Sale lines immutable'
      in v_def
    ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: service billing ordering';
    END IF;

    IF position(
      'v_line_ids:=private.gst_sale_reconcile_source_v520'
      in v_def
    ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: service reconciliation missing';
    END IF;

    IF position(
      'v_snapshot:=private.gst_snapshot_create_v520'
      in v_def
    ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: service GST snapshot missing';
    END IF;


    -- ================================================================
    -- Restaurant settlement response
    -- ================================================================

    SELECT pg_get_functiondef(
      'public.gst_restaurant_order_bill_v520(
        uuid,
        uuid,
        uuid,
        uuid,
        date,
        numeric,
        text,
        text,
        numeric,
        text,
        text
      )'::regprocedure
    )
    INTO v_def;

    IF position(
         '''paid_amount'',coalesce(nullif(v_payment->>''paid_amount'','''')::numeric,0)'
         in v_def
       ) = 0
       OR position(
         '''balance_due'',coalesce(nullif(v_payment->>''balance_due'','''')::numeric,v_total)'
         in v_def
       ) = 0
       OR position(
         '''payment_status'',coalesce(nullif(v_payment->>''payment_status'','''')'
         in v_def
       ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: restaurant billing response';
    END IF;


    -- ================================================================
    -- GST journal validator
    -- ================================================================

    SELECT pg_get_functiondef(
      'private.gst_snapshot_document_journal_validate_v520(
        uuid,
        uuid
      )'::regprocedure
    )
    INTO v_def;

    IF position(
         'validation_source'
         in v_def
       ) = 0
       OR position(
         'posted_journal'
         in v_def
       ) = 0
       OR position(
         'journal_id'
         in v_def
       ) = 0
       OR position(
         'from public.journal_entries'
         in v_def
       ) = 0
    THEN
        RAISE EXCEPTION
          'THQ assertion failed: GST journal validator';
    END IF;

END
$thq$;
