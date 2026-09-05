create or replace function private.v4_sales_return_accounting_trigger()
returns trigger
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
begin
  if private.gst_v520_authoritative_context_for_source(new.tenant_id,'sales_return',new.id) then
    return new;
  end if;
  if coalesce(new.grand_total,0)>0 and (tg_op='INSERT' or coalesce(old.grand_total,0)<>coalesce(new.grand_total,0)) then
    perform private.v4_post_sales_return(new.id);
  end if;
  return new;
end $$;

create or replace function private.gst_sales_return_quote_v520(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_return_date date,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  s public.sales%rowtype;
  os public.gst_document_snapshots_v520%rowtype;
  x jsonb;
  si public.sale_items%rowtype;
  ol public.gst_document_line_snapshots_v520%rowtype;
  prev jsonb;
  v_qty numeric;
  v_prev_qty numeric;
  v_final boolean;
  v_discount numeric; v_taxable numeric; v_cgst numeric; v_sgst numeric; v_utgst numeric; v_igst numeric; v_cess numeric;
  v_rcm_cgst numeric; v_rcm_sgst numeric; v_rcm_utgst numeric; v_rcm_igst numeric; v_rcm_cess numeric;
  v_line_total numeric; v_calc_round numeric;
  lines jsonb:='[]'::jsonb;
  subtotal numeric:=0; discount_total numeric:=0; taxable_total numeric:=0;
  cgst_total numeric:=0; sgst_total numeric:=0; utgst_total numeric:=0; igst_total numeric:=0; cess_total numeric:=0;
  rcm_cgst_total numeric:=0; rcm_sgst_total numeric:=0; rcm_utgst_total numeric:=0; rcm_igst_total numeric:=0; rcm_cess_total numeric:=0;
  line_total_sum numeric:=0; calc_round_total numeric:=0; v_round_off numeric:=0;
  v_all_returned boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_return_date is null then raise exception 'Return date is required'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'At least one return line is required'; end if;

  select * into s from public.sales where tenant_id=p_tenant_id and id=p_sale_id and status='posted' for share;
  if not found then raise exception 'Posted Sale not found'; end if;
  if p_return_date<s.sale_date then raise exception 'Return date cannot be before the original Sale date'; end if;

  select * into os from public.gst_document_snapshots_v520
  where tenant_id=p_tenant_id and source_type='sale' and source_id=p_sale_id
  order by created_at limit 1;
  if os.id is null then raise exception 'Authoritative GST Sale evidence is required before creating a v5.2 GST Sales Return'; end if;

  if exists(
    select 1 from public.sales_returns r
    where r.tenant_id=p_tenant_id and r.sale_id=p_sale_id and coalesce(r.grand_total,0)>0
      and not exists(select 1 from public.gst_document_snapshots_v520 d where d.tenant_id=p_tenant_id and d.source_type='sales_return' and d.source_id=r.id)
  ) then
    raise exception 'A legacy/unverified return already exists for this Sale; authoritative GST return continuation requires reconciliation first';
  end if;

  if exists(
    select 1 from (
      select (j->>'sale_item_id')::uuid sale_item_id,count(*) c
      from jsonb_array_elements(p_items) j
      group by 1 having count(*)>1
    ) q
  ) then raise exception 'The same Sale line cannot appear twice in one GST return'; end if;

  for x in select value from jsonb_array_elements(p_items) loop
    begin v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0); exception when others then raise exception 'Invalid return quantity'; end;
    if v_qty<=0 then raise exception 'Return quantity must be positive'; end if;
    select * into si from public.sale_items where tenant_id=p_tenant_id and sale_id=p_sale_id and id=nullif(x->>'sale_item_id','')::uuid for share;
    if not found then raise exception 'Sale item not found'; end if;
    select * into ol from public.gst_document_line_snapshots_v520 where snapshot_id=os.id and source_line_id=si.id;
    if ol.id is null then raise exception 'Original GST Sale line evidence is missing'; end if;

    select jsonb_build_object(
      'quantity',coalesce(sum(dl.quantity),0),'discount',coalesce(sum(dl.discount_amount),0),'taxable',coalesce(sum(dl.taxable_value),0),
      'cgst',coalesce(sum(dl.cgst),0),'sgst',coalesce(sum(dl.sgst),0),'utgst',coalesce(sum(dl.utgst),0),'igst',coalesce(sum(dl.igst),0),'cess',coalesce(sum(dl.cess),0),
      'rcm_cgst',coalesce(sum(dl.rcm_cgst),0),'rcm_sgst',coalesce(sum(dl.rcm_sgst),0),'rcm_utgst',coalesce(sum(dl.rcm_utgst),0),'rcm_igst',coalesce(sum(dl.rcm_igst),0),'rcm_cess',coalesce(sum(dl.rcm_cess),0),
      'line_total',coalesce(sum(dl.line_total),0),'calc_round',coalesce(sum(dl.calculation_rounding),0)
    ) into prev
    from public.gst_document_line_snapshots_v520 dl
    join public.gst_document_snapshots_v520 dh on dh.id=dl.snapshot_id and dh.tenant_id=p_tenant_id and dh.source_type='sales_return'
    join public.sales_return_items ri on ri.id=dl.source_line_id and ri.sale_item_id=si.id
    join public.sales_returns rh on rh.id=ri.sales_return_id and rh.sale_id=p_sale_id and rh.tenant_id=p_tenant_id;

    v_prev_qty:=coalesce((prev->>'quantity')::numeric,0);
    if v_prev_qty+v_qty>ol.quantity+0.000001 then raise exception 'Return quantity exceeds the unreturned GST Sale quantity for item %',si.id; end if;
    v_final:=abs((v_prev_qty+v_qty)-ol.quantity)<=0.000001;

    v_discount:=case when v_final then round(ol.discount_amount-coalesce((prev->>'discount')::numeric,0),2) else round(ol.discount_amount*(v_qty/ol.quantity),2) end;
    v_taxable:=case when v_final then round(ol.taxable_value-coalesce((prev->>'taxable')::numeric,0),2) else round(ol.taxable_value*(v_qty/ol.quantity),2) end;
    v_cgst:=case when v_final then round(ol.cgst-coalesce((prev->>'cgst')::numeric,0),2) else round(ol.cgst*(v_qty/ol.quantity),2) end;
    v_sgst:=case when v_final then round(ol.sgst-coalesce((prev->>'sgst')::numeric,0),2) else round(ol.sgst*(v_qty/ol.quantity),2) end;
    v_utgst:=case when v_final then round(ol.utgst-coalesce((prev->>'utgst')::numeric,0),2) else round(ol.utgst*(v_qty/ol.quantity),2) end;
    v_igst:=case when v_final then round(ol.igst-coalesce((prev->>'igst')::numeric,0),2) else round(ol.igst*(v_qty/ol.quantity),2) end;
    v_cess:=case when v_final then round(ol.cess-coalesce((prev->>'cess')::numeric,0),2) else round(ol.cess*(v_qty/ol.quantity),2) end;
    v_rcm_cgst:=case when v_final then round(ol.rcm_cgst-coalesce((prev->>'rcm_cgst')::numeric,0),2) else round(ol.rcm_cgst*(v_qty/ol.quantity),2) end;
    v_rcm_sgst:=case when v_final then round(ol.rcm_sgst-coalesce((prev->>'rcm_sgst')::numeric,0),2) else round(ol.rcm_sgst*(v_qty/ol.quantity),2) end;
    v_rcm_utgst:=case when v_final then round(ol.rcm_utgst-coalesce((prev->>'rcm_utgst')::numeric,0),2) else round(ol.rcm_utgst*(v_qty/ol.quantity),2) end;
    v_rcm_igst:=case when v_final then round(ol.rcm_igst-coalesce((prev->>'rcm_igst')::numeric,0),2) else round(ol.rcm_igst*(v_qty/ol.quantity),2) end;
    v_rcm_cess:=case when v_final then round(ol.rcm_cess-coalesce((prev->>'rcm_cess')::numeric,0),2) else round(ol.rcm_cess*(v_qty/ol.quantity),2) end;
    v_line_total:=case when v_final then round(ol.line_total-coalesce((prev->>'line_total')::numeric,0),2) else round(ol.line_total*(v_qty/ol.quantity),2) end;
    v_calc_round:=case when v_final then round(ol.calculation_rounding-coalesce((prev->>'calc_round')::numeric,0),2) else round(ol.calculation_rounding*(v_qty/ol.quantity),2) end;

    subtotal:=subtotal+round(v_qty*ol.unit_price,4); discount_total:=discount_total+v_discount; taxable_total:=taxable_total+v_taxable;
    cgst_total:=cgst_total+v_cgst; sgst_total:=sgst_total+v_sgst; utgst_total:=utgst_total+v_utgst; igst_total:=igst_total+v_igst; cess_total:=cess_total+v_cess;
    rcm_cgst_total:=rcm_cgst_total+v_rcm_cgst; rcm_sgst_total:=rcm_sgst_total+v_rcm_sgst; rcm_utgst_total:=rcm_utgst_total+v_rcm_utgst; rcm_igst_total:=rcm_igst_total+v_rcm_igst; rcm_cess_total:=rcm_cess_total+v_rcm_cess;
    line_total_sum:=line_total_sum+v_line_total; calc_round_total:=calc_round_total+v_calc_round;

    lines:=lines||jsonb_build_array(jsonb_build_object(
      'sale_item_id',si.id,'variant_id',ol.variant_id,'product_name',ol.product_name,'variant_name',ol.variant_name,'sku',ol.sku,
      'supply_kind',ol.supply_kind,'hsn_sac',ol.hsn_sac,'quantity',v_qty,'unit_price',ol.unit_price,'discount',v_discount,
      'taxability',ol.taxability,'tax_inclusive',ol.tax_inclusive,'reverse_charge',ol.reverse_charge,
      'gst_rate',ol.gst_rate,'applied_gst_rate',ol.applied_gst_rate,'cess_rate',ol.cess_rate,'applied_cess_rate',ol.applied_cess_rate,
      'cess_per_unit',ol.cess_per_unit,'applied_cess_per_unit',ol.applied_cess_per_unit,'taxable_value',v_taxable,
      'cgst',v_cgst,'sgst',v_sgst,'utgst',v_utgst,'igst',v_igst,'cess',v_cess,'tax_amount',round(v_cgst+v_sgst+v_utgst+v_igst+v_cess,2),
      'rcm_cgst',v_rcm_cgst,'rcm_sgst',v_rcm_sgst,'rcm_utgst',v_rcm_utgst,'rcm_igst',v_rcm_igst,'rcm_cess',v_rcm_cess,
      'rcm_tax_amount',round(v_rcm_cgst+v_rcm_sgst+v_rcm_utgst+v_rcm_igst+v_rcm_cess,2),
      'rcm_liability_party',case when ol.reverse_charge then 'recipient' else null end,
      'calculation_rounding',v_calc_round,'line_total',v_line_total,'profile_source',ol.profile_source,'profile_status',ol.profile_status,
      'original_snapshot_line_id',ol.id
    ));
  end loop;

  select not exists(
    select 1 from public.sale_items si2
    where si2.tenant_id=p_tenant_id and si2.sale_id=p_sale_id
      and coalesce((select sum(ri.quantity) from public.sales_return_items ri join public.sales_returns rr on rr.id=ri.sales_return_id where rr.tenant_id=p_tenant_id and rr.sale_id=p_sale_id and ri.sale_item_id=si2.id),0)
          +coalesce((select sum((j->>'quantity')::numeric) from jsonb_array_elements(p_items) j where (j->>'sale_item_id')::uuid=si2.id),0)
          < si2.quantity-0.000001
  ) into v_all_returned;
  if v_all_returned then
    select round(os.round_off-coalesce(sum(rs.round_off),0),2) into v_round_off
    from public.gst_document_snapshots_v520 rs
    join public.sales_returns rr on rr.id=rs.source_id and rs.source_type='sales_return'
    where rr.tenant_id=p_tenant_id and rr.sale_id=p_sale_id;
    v_round_off:=coalesce(v_round_off,round(os.round_off,2));
  else v_round_off:=0; end if;

  return jsonb_build_object(
    'engine','gst_v520_document_return_1','document_kind','sale','document_class','credit_note','document_date',p_return_date,
    'supply_type',os.supply_type,'supplier_registration_id',os.thq_registration_id,'supplier_gstin',os.supplier_gstin,'supplier_state_code',os.supplier_state_code,
    'recipient_gstin',os.recipient_gstin,'recipient_state_code',os.recipient_state_code,'place_of_supply_code',os.place_of_supply_code,
    'interstate',os.interstate,'zero_rated',os.zero_rated,'without_payment',os.without_payment,'deemed_export',os.deemed_export,'composition_supplier',os.composition_supplier,
    'lines',lines,
    'totals',jsonb_build_object('subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),
      'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),
      'tax_collected_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),
      'rcm_cgst',round(rcm_cgst_total,2),'rcm_sgst',round(rcm_sgst_total,2),'rcm_utgst',round(rcm_utgst_total,2),'rcm_igst',round(rcm_igst_total,2),'rcm_cess',round(rcm_cess_total,2),
      'rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'thq_rcm_tax_payable_total',0,'recipient_rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'government_tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total+rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'additional_charges',0,'calculation_rounding',round(calc_round_total,2),'round_off',v_round_off,'grand_total',round(line_total_sum+v_round_off,2)),
    'ready_for_compliance',true,'warnings','[]'::jsonb,'errors','[]'::jsonb,'original_sale_snapshot_id',os.id
  );
end $$;

create or replace function private.gst_sales_return_tracking_apply_v520(
  p_tenant_id uuid,p_return_id uuid,p_return_item_id uuid,p_input jsonb
) returns void
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  r public.sales_returns%rowtype; ri public.sales_return_items%rowtype; s public.sales%rowtype;
  v_mode text; v_serials jsonb; v_batches jsonb; x jsonb; v_serial text; v_serial_id uuid; v_count numeric;
  v_batch_id uuid; v_batch text; v_qty numeric; v_sum numeric:=0; v_sold numeric; v_returned numeric; w record; v_left numeric; v_take numeric;
begin
  select * into r from public.sales_returns where tenant_id=p_tenant_id and id=p_return_id;
  select * into ri from public.sales_return_items where sales_return_id=p_return_id and id=p_return_item_id;
  select * into s from public.sales where tenant_id=p_tenant_id and id=r.sale_id;
  if r.id is null or ri.id is null or s.id is null then raise exception 'Sales Return tracking source not found'; end if;
  v_mode:=private.v483_tracking_mode(p_tenant_id,ri.variant_id);
  if v_mode='none' then return; end if;

  if v_mode='serial' then
    if ri.quantity<>trunc(ri.quantity) then raise exception 'Serial-tracked return quantity must be whole base units'; end if;
    v_serials:=coalesce(p_input->'serial_numbers','[]'::jsonb);
    select count(*)::numeric into v_count from jsonb_array_elements(v_serials);
    if v_count<>ri.quantity then raise exception 'Provide exactly % serial numbers for the returned line',ri.quantity; end if;
    for x in select value from jsonb_array_elements(v_serials) loop
      v_serial:=trim(coalesce(case when jsonb_typeof(x)='string' then x#>>'{}' else x->>'serial_number' end,''));
      if v_serial='' then raise exception 'Returned serial number cannot be blank'; end if;
      select id into v_serial_id from public.inventory_serials_v483
      where tenant_id=p_tenant_id and variant_id=ri.variant_id and sale_id=r.sale_id and sale_item_id=ri.sale_item_id and status='sold'
        and lower(trim(serial_number))=lower(v_serial) for update;
      if v_serial_id is null then raise exception 'Serial % was not sold on the original Sale line or was already returned',v_serial; end if;
      update public.inventory_serials_v483 set status='in_stock',current_location_id=r.location_id,customer_id=null,sale_id=null,sale_item_id=null,sold_at=null,updated_at=now() where id=v_serial_id;
      insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
      values(p_tenant_id,ri.variant_id,v_serial_id,'sale_return',1,r.location_id,s.customer_id,r.sale_id,ri.sale_item_id,r.return_number,
        'sales_return:'||r.id::text||':serial:'||v_serial_id::text,jsonb_build_object('sales_return_id',r.id,'sales_return_item_id',ri.id),auth.uid());
      update public.product_warranties_v483 set status='void',updated_at=now()
      where tenant_id=p_tenant_id and serial_id=v_serial_id and sale_id=r.sale_id and status='active';
    end loop;
  else
    v_batches:=coalesce(p_input->'batches','[]'::jsonb);
    if jsonb_typeof(v_batches)<>'array' or jsonb_array_length(v_batches)=0 then raise exception 'Batch allocations are required for a batch-tracked return'; end if;
    for x in select value from jsonb_array_elements(v_batches) loop
      v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0); if v_qty<=0 then raise exception 'Returned batch quantity must be positive'; end if;
      if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid; else
        v_batch:=trim(coalesce(x->>'batch_number',''));
        select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=ri.variant_id and lower(trim(batch_number))=lower(v_batch);
      end if;
      if v_batch_id is null then raise exception 'Returned batch was not found'; end if;
      select coalesce(sum(quantity),0) into v_sold from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and batch_id=v_batch_id and event_type='sale' and sale_id=r.sale_id and sale_item_id=ri.sale_item_id;
      select coalesce(sum(quantity),0) into v_returned from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and batch_id=v_batch_id and event_type='sale_return' and sale_id=r.sale_id and sale_item_id=ri.sale_item_id;
      if v_returned+v_qty>v_sold+0.000001 then raise exception 'Returned quantity exceeds quantity sold from batch %',v_batch_id; end if;
      insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity)
      values(p_tenant_id,v_batch_id,r.location_id,v_qty)
      on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
      update public.inventory_batches_v483 set status=case when status='exhausted' then 'active' else status end,updated_at=now() where id=v_batch_id;
      insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
      values(p_tenant_id,ri.variant_id,v_batch_id,'sale_return',v_qty,r.location_id,s.customer_id,r.sale_id,ri.sale_item_id,r.return_number,
        'sales_return:'||r.id::text||':item:'||ri.id::text||':batch:'||v_batch_id::text,jsonb_build_object('sales_return_id',r.id,'sales_return_item_id',ri.id),auth.uid());
      v_left:=v_qty;
      for w in select id,quantity from public.product_warranties_v483 where tenant_id=p_tenant_id and batch_id=v_batch_id and sale_id=r.sale_id and status='active' order by created_at,id for update loop
        exit when v_left<=0.000001; v_take:=least(v_left,w.quantity);
        if v_take>=w.quantity-0.000001 then update public.product_warranties_v483 set status='void',updated_at=now() where id=w.id;
        else update public.product_warranties_v483 set quantity=quantity-v_take,updated_at=now() where id=w.id; end if;
        v_left:=v_left-v_take;
      end loop;
      v_sum:=v_sum+v_qty;
    end loop;
    if abs(v_sum-ri.quantity)>0.000001 then raise exception 'Returned batch allocations must equal return base quantity %',ri.quantity; end if;
  end if;
end $$;

create or replace function public.gst_sales_return_create_v520(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_return_date date,
  p_items jsonb,
  p_reason text,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_req_payload jsonb; v_req_state jsonb; v_quote jsonb; v_totals jsonb; v_sale public.sales%rowtype; v_origin public.document_origins%rowtype;
  v_id uuid:=gen_random_uuid(); v_no text; x jsonb; ql jsonb; si public.sale_items%rowtype; v_ri uuid; v_line_ids jsonb:='[]'::jsonb;
  v_snapshot uuid; v_journal uuid; v_response jsonb; v_stock_type text; v_cost numeric:=0; v_paid numeric:=0; v_prev_returns numeric:=0; v_ar_reduce numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.return') or private.erp_has_permission(p_tenant_id,'sales.manage')) then raise exception 'Sales return permission required'; end if;
  if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required'; end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Return reason is required'; end if;
  if p_return_date is null then raise exception 'Return date is required'; end if;
  select * into v_sale from public.sales where tenant_id=p_tenant_id and id=p_sale_id and status='posted' for update;
  if not found then raise exception 'Posted Sale not found'; end if;
  select * into v_origin from public.document_origins where tenant_id=p_tenant_id and entity_type='sale' and entity_id=p_sale_id order by created_at limit 1;
  if v_origin.location_id is null then raise exception 'Original Sale does not have a business location'; end if;
  if p_location_id is not null and p_location_id<>v_origin.location_id then raise exception 'Sales Return location must match the original Sale location'; end if;
  perform private.v4_location_access(p_tenant_id,v_origin.location_id,'operate');
  if p_device_id is not null then perform private.erp_validate_transaction_origin(p_tenant_id,v_origin.location_id,p_device_id,'sales'); end if;

  v_req_payload:=jsonb_build_object('sale_id',p_sale_id,'return_date',p_return_date,'items',coalesce(p_items,'[]'::jsonb),'reason',trim(p_reason),'location_id',v_origin.location_id,'device_id',p_device_id);
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.sales_return.create.v520',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response'; end if;
  v_quote:=private.gst_sales_return_quote_v520(p_tenant_id,p_sale_id,p_return_date,p_items);
  v_totals:=v_quote->'totals';
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Sales Return is not compliance-ready'; end if;

  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'sales_return');
  v_no:='SRN-'||lpad(nextval('public.sales_return_number_seq')::text,6,'0');
  insert into public.sales_returns(id,tenant_id,sale_id,return_number,location_id,device_id,return_date,reason,created_by)
  values(v_id,p_tenant_id,p_sale_id,v_no,v_origin.location_id,p_device_id,p_return_date,trim(p_reason),auth.uid());
  perform private.gst_authoritative_context_bind_v520(v_id);

  for ql in select value from jsonb_array_elements(v_quote->'lines') loop
    select * into si from public.sale_items where tenant_id=p_tenant_id and sale_id=p_sale_id and id=(ql->>'sale_item_id')::uuid;
    insert into public.sales_return_items(sales_return_id,sale_item_id,variant_id,quantity,unit_price,discount_amount,tax_rate,line_total,entered_unit_id,entered_unit_code,entered_quantity,conversion_to_base)
    values(v_id,si.id,si.variant_id,(ql->>'quantity')::numeric,(ql->>'unit_price')::numeric,(ql->>'discount')::numeric,coalesce((ql->>'applied_gst_rate')::numeric,0),(ql->>'line_total')::numeric,
      si.entered_unit_id,si.entered_unit_code,case when coalesce(si.conversion_to_base,1)>0 then (ql->>'quantity')::numeric/coalesce(si.conversion_to_base,1) else (ql->>'quantity')::numeric end,coalesce(si.conversion_to_base,1))
    returning id into v_ri;
    v_line_ids:=v_line_ids||jsonb_build_array(v_ri);
    select p.item_type into v_stock_type from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id where pv.id=si.variant_id and pv.tenant_id=p_tenant_id;
    if v_stock_type='stock' then
      perform public.inventory_adjust_stock(p_tenant_id,si.variant_id,(ql->>'quantity')::numeric,'GST Sale return • '||v_no);
      perform private.v4_location_stock_apply(p_tenant_id,v_origin.location_id,si.variant_id,(ql->>'quantity')::numeric,'sale_return','sales_return',v_id,v_no,trim(p_reason),p_device_id,false);
      select coalesce(si.cost_total,0)*((ql->>'quantity')::numeric/nullif(si.quantity,0)) into v_cost;
    end if;
    select value into x from jsonb_array_elements(p_items) where (value->>'sale_item_id')::uuid=si.id limit 1;
    perform private.gst_sales_return_tracking_apply_v520(p_tenant_id,v_id,v_ri,coalesce(x,'{}'::jsonb));
  end loop;

  update public.sales_returns set subtotal=(v_totals->>'taxable_value')::numeric,tax_total=(v_totals->>'tax_collected_total')::numeric,grand_total=(v_totals->>'grand_total')::numeric where id=v_id and tenant_id=p_tenant_id;
  if exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and source_type='sales_return' and source_id=v_id and status='posted') then raise exception 'Legacy Sales Return journal was created inside authoritative GST context'; end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 where tenant_id=p_tenant_id and source_type='sales_return' and source_id=v_id) then raise exception 'Legacy GST evidence was created inside authoritative GST context'; end if;

  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata)
  values(p_tenant_id,'sale',p_sale_id,'return',trim(p_reason),auth.uid(),jsonb_build_object('return_id',v_id,'return_number',v_no,'amount',(v_totals->>'grand_total')::numeric,'gst_engine','v5.2'));

  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sales_return',v_id,v_no,v_origin.location_id,p_return_date,v_quote,v_line_ids);
  v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);
  select coalesce(sum(amount),0) into v_paid from public.sale_payments where tenant_id=p_tenant_id and sale_id=p_sale_id;
  select coalesce(sum(grand_total),0) into v_prev_returns from public.sales_returns where tenant_id=p_tenant_id and sale_id=p_sale_id and id<>v_id and refund_status<>'waived' and created_at<=(select created_at from public.sales_returns where id=v_id);
  v_ar_reduce:=least((v_totals->>'grand_total')::numeric,greatest(v_sale.grand_total-v_paid-v_prev_returns,0));
  v_credit:=greatest((v_totals->>'grand_total')::numeric-v_ar_reduce,0);
  v_response:=jsonb_build_object('success',true,'gst_engine',v_quote->>'engine','gst_status','POSTED','return_id',v_id,'return_number',v_no,'sale_id',p_sale_id,
    'document_class','credit_note','grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,
    'recipient_rcm_tax_reversal_total',(v_totals->>'recipient_rcm_tax_payable_total')::numeric,'receivable_reduction',round(v_ar_reduce,2),'customer_credit_due',round(v_credit,2),'refund_status','credit_due',
    'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'original_sale_snapshot_id',v_quote->>'original_sale_snapshot_id');
  v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.sales_return.create.v520','sales_return',v_id,v_snapshot,v_journal,v_response);
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end $$;

revoke all on function public.gst_sales_return_create_v520(uuid,uuid,date,jsonb,text,uuid,uuid,text) from public,anon;
grant execute on function public.gst_sales_return_create_v520(uuid,uuid,date,jsonb,text,uuid,uuid,text) to authenticated;
revoke all on function private.gst_sales_return_quote_v520(uuid,uuid,date,jsonb) from public,anon,authenticated;
revoke all on function private.gst_sales_return_tracking_apply_v520(uuid,uuid,uuid,jsonb) from public,anon,authenticated;