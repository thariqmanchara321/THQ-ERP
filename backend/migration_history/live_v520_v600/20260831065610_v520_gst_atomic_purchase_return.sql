-- THQ ERP v5.2: authoritative GST Purchase Return lifecycle

-- Supplier statement must be able to represent an explicit purchase return.
alter table public.supplier_ledger_entries_v484
  drop constraint if exists supplier_ledger_entries_v484_entry_type_check;
alter table public.supplier_ledger_entries_v484
  add constraint supplier_ledger_entries_v484_entry_type_check
  check (entry_type = any (array['purchase_invoice'::text,'supplier_payment'::text,'purchase_return'::text,'adjustment'::text,'void'::text]));

create index if not exists idx_purchase_returns_tenant_purchase_v520
  on public.purchase_returns(tenant_id,purchase_id,created_at);
create index if not exists idx_purchase_return_items_return_item_v520
  on public.purchase_return_items(purchase_return_id,purchase_item_id);
create index if not exists idx_purchase_return_items_purchase_item_v520
  on public.purchase_return_items(purchase_item_id);
create index if not exists idx_purchase_return_items_variant_v520
  on public.purchase_return_items(variant_id);

create or replace function private.gst_purchase_return_quote_v520(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_return_date date,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  p public.purchases%rowtype;
  os public.gst_document_snapshots_v520%rowtype;
  x jsonb;
  pi public.purchase_items%rowtype;
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
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'At least one return line is required';
  end if;

  select * into p from public.purchases
  where tenant_id=p_tenant_id and id=p_purchase_id and status='posted'
  for share;
  if not found then raise exception 'Posted Purchase not found'; end if;
  if p_return_date<p.purchase_date then raise exception 'Return date cannot be before the original Purchase date'; end if;

  select * into os from public.gst_document_snapshots_v520
  where tenant_id=p_tenant_id and source_type='purchase' and source_id=p_purchase_id
  order by created_at limit 1;
  if os.id is null then
    raise exception 'Authoritative GST Purchase evidence is required before creating a v5.2 GST Purchase Return';
  end if;

  if exists(
    select 1 from public.purchase_returns r
    where r.tenant_id=p_tenant_id and r.purchase_id=p_purchase_id and coalesce(r.grand_total,0)>0
      and not exists(
        select 1 from public.gst_document_snapshots_v520 d
        where d.tenant_id=p_tenant_id and d.source_type='purchase_return' and d.source_id=r.id
      )
  ) then
    raise exception 'A legacy/unverified return already exists for this Purchase; authoritative GST return continuation requires reconciliation first';
  end if;

  if exists(
    select 1 from (
      select (j->>'purchase_item_id')::uuid purchase_item_id,count(*) c
      from jsonb_array_elements(p_items) j
      group by 1 having count(*)>1
    ) q
  ) then raise exception 'The same Purchase line cannot appear twice in one GST return'; end if;

  for x in select value from jsonb_array_elements(p_items) loop
    begin v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
    exception when others then raise exception 'Invalid return quantity'; end;
    if v_qty<=0 then raise exception 'Return quantity must be positive'; end if;

    select * into pi from public.purchase_items
    where tenant_id=p_tenant_id and purchase_id=p_purchase_id and id=nullif(x->>'purchase_item_id','')::uuid
    for share;
    if not found then raise exception 'Purchase item not found'; end if;

    select * into ol from public.gst_document_line_snapshots_v520
    where snapshot_id=os.id and source_line_id=pi.id;
    if ol.id is null then raise exception 'Original GST Purchase line evidence is missing'; end if;

    select jsonb_build_object(
      'quantity',coalesce(sum(dl.quantity),0),
      'discount',coalesce(sum(dl.discount_amount),0),
      'taxable',coalesce(sum(dl.taxable_value),0),
      'cgst',coalesce(sum(dl.cgst),0),'sgst',coalesce(sum(dl.sgst),0),'utgst',coalesce(sum(dl.utgst),0),'igst',coalesce(sum(dl.igst),0),'cess',coalesce(sum(dl.cess),0),
      'rcm_cgst',coalesce(sum(dl.rcm_cgst),0),'rcm_sgst',coalesce(sum(dl.rcm_sgst),0),'rcm_utgst',coalesce(sum(dl.rcm_utgst),0),'rcm_igst',coalesce(sum(dl.rcm_igst),0),'rcm_cess',coalesce(sum(dl.rcm_cess),0),
      'line_total',coalesce(sum(dl.line_total),0),'calc_round',coalesce(sum(dl.calculation_rounding),0)
    ) into prev
    from public.gst_document_line_snapshots_v520 dl
    join public.gst_document_snapshots_v520 dh
      on dh.id=dl.snapshot_id and dh.tenant_id=p_tenant_id and dh.source_type='purchase_return'
    join public.purchase_return_items ri
      on ri.id=dl.source_line_id and ri.purchase_item_id=pi.id
    join public.purchase_returns rh
      on rh.id=ri.purchase_return_id and rh.purchase_id=p_purchase_id and rh.tenant_id=p_tenant_id;

    v_prev_qty:=coalesce((prev->>'quantity')::numeric,0);
    if v_prev_qty+v_qty>ol.quantity+0.000001 then
      raise exception 'Return quantity exceeds the unreturned GST Purchase quantity for item %',pi.id;
    end if;
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

    subtotal:=subtotal+round(v_qty*ol.unit_price,4);
    discount_total:=discount_total+v_discount;
    taxable_total:=taxable_total+v_taxable;
    cgst_total:=cgst_total+v_cgst; sgst_total:=sgst_total+v_sgst; utgst_total:=utgst_total+v_utgst; igst_total:=igst_total+v_igst; cess_total:=cess_total+v_cess;
    rcm_cgst_total:=rcm_cgst_total+v_rcm_cgst; rcm_sgst_total:=rcm_sgst_total+v_rcm_sgst; rcm_utgst_total:=rcm_utgst_total+v_rcm_utgst; rcm_igst_total:=rcm_igst_total+v_rcm_igst; rcm_cess_total:=rcm_cess_total+v_rcm_cess;
    line_total_sum:=line_total_sum+v_line_total;
    calc_round_total:=calc_round_total+v_calc_round;

    lines:=lines||jsonb_build_array(jsonb_build_object(
      'purchase_item_id',pi.id,'variant_id',ol.variant_id,'product_name',ol.product_name,'variant_name',ol.variant_name,'sku',ol.sku,
      'supply_kind',ol.supply_kind,'hsn_sac',ol.hsn_sac,'quantity',v_qty,'unit_price',ol.unit_price,'discount',v_discount,
      'taxability',ol.taxability,'tax_inclusive',ol.tax_inclusive,'reverse_charge',ol.reverse_charge,
      'gst_rate',ol.gst_rate,'applied_gst_rate',ol.applied_gst_rate,'cess_rate',ol.cess_rate,'applied_cess_rate',ol.applied_cess_rate,
      'cess_per_unit',ol.cess_per_unit,'applied_cess_per_unit',ol.applied_cess_per_unit,'taxable_value',v_taxable,
      'cgst',v_cgst,'sgst',v_sgst,'utgst',v_utgst,'igst',v_igst,'cess',v_cess,'tax_amount',round(v_cgst+v_sgst+v_utgst+v_igst+v_cess,2),
      'rcm_cgst',v_rcm_cgst,'rcm_sgst',v_rcm_sgst,'rcm_utgst',v_rcm_utgst,'rcm_igst',v_rcm_igst,'rcm_cess',v_rcm_cess,
      'rcm_tax_amount',round(v_rcm_cgst+v_rcm_sgst+v_rcm_utgst+v_rcm_igst+v_rcm_cess,2),
      'rcm_liability_party',case when ol.reverse_charge then 'thq' else null end,
      'calculation_rounding',v_calc_round,'line_total',v_line_total,'profile_source',ol.profile_source,'profile_status',ol.profile_status,
      'original_snapshot_line_id',ol.id
    ));
  end loop;

  select not exists(
    select 1 from public.purchase_items pi2
    where pi2.tenant_id=p_tenant_id and pi2.purchase_id=p_purchase_id
      and coalesce((
        select sum(ri.quantity)
        from public.purchase_return_items ri
        join public.purchase_returns rr on rr.id=ri.purchase_return_id
        where rr.tenant_id=p_tenant_id and rr.purchase_id=p_purchase_id and ri.purchase_item_id=pi2.id
      ),0)
      +coalesce((
        select sum((j->>'quantity')::numeric)
        from jsonb_array_elements(p_items) j
        where (j->>'purchase_item_id')::uuid=pi2.id
      ),0)
      < pi2.quantity-0.000001
  ) into v_all_returned;

  if v_all_returned then
    select round(os.round_off-coalesce(sum(rs.round_off),0),2) into v_round_off
    from public.gst_document_snapshots_v520 rs
    join public.purchase_returns rr on rr.id=rs.source_id and rs.source_type='purchase_return'
    where rr.tenant_id=p_tenant_id and rr.purchase_id=p_purchase_id;
    v_round_off:=coalesce(v_round_off,round(os.round_off,2));
  else
    v_round_off:=0;
  end if;

  return jsonb_build_object(
    'engine','gst_v520_document_purchase_return_1',
    'document_kind','purchase',
    'document_class','credit_note',
    'document_date',p_return_date,
    'supply_type',os.supply_type,
    'recipient_registration_id',os.thq_registration_id,
    'supplier_gstin',os.supplier_gstin,'supplier_state_code',os.supplier_state_code,
    'recipient_gstin',os.recipient_gstin,'recipient_state_code',os.recipient_state_code,
    'place_of_supply_code',os.place_of_supply_code,
    'interstate',os.interstate,'zero_rated',os.zero_rated,'without_payment',os.without_payment,
    'deemed_export',os.deemed_export,'composition_supplier',os.composition_supplier,
    'lines',lines,
    'totals',jsonb_build_object(
      'subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),
      'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),
      'tax_collected_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),
      'rcm_cgst',round(rcm_cgst_total,2),'rcm_sgst',round(rcm_sgst_total,2),'rcm_utgst',round(rcm_utgst_total,2),'rcm_igst',round(rcm_igst_total,2),'rcm_cess',round(rcm_cess_total,2),
      'rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'thq_rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'recipient_rcm_tax_payable_total',0,
      'government_tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total+rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),
      'additional_charges',0,'calculation_rounding',round(calc_round_total,2),'round_off',v_round_off,
      'grand_total',round(line_total_sum+v_round_off,2)
    ),
    'ready_for_compliance',true,'warnings','[]'::jsonb,'errors','[]'::jsonb,
    'original_purchase_snapshot_id',os.id
  );
end
$function$;

create or replace function private.gst_purchase_return_tracking_apply_v520(
  p_tenant_id uuid,
  p_return_id uuid,
  p_return_item_id uuid,
  p_input jsonb
) returns void
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  r public.purchase_returns%rowtype;
  ri public.purchase_return_items%rowtype;
  p public.purchases%rowtype;
  v_mode text;
  v_serials jsonb;
  v_batches jsonb;
  x jsonb;
  v_serial text;
  v_serial_id uuid;
  v_count numeric;
  v_batch_id uuid;
  v_batch text;
  v_qty numeric;
  v_sum numeric:=0;
  v_purchased numeric;
  v_returned numeric;
  v_available numeric;
  v_seen_serials text[]:='{}'::text[];
  v_seen_batches uuid[]:='{}'::uuid[];
begin
  select * into r from public.purchase_returns where tenant_id=p_tenant_id and id=p_return_id;
  select * into ri from public.purchase_return_items where purchase_return_id=p_return_id and id=p_return_item_id;
  select * into p from public.purchases where tenant_id=p_tenant_id and id=r.purchase_id;
  if r.id is null or ri.id is null or p.id is null then raise exception 'Purchase Return tracking source not found'; end if;

  v_mode:=private.v483_tracking_mode(p_tenant_id,ri.variant_id);
  if v_mode='none' then return; end if;

  if v_mode='serial' then
    if ri.quantity<>trunc(ri.quantity) then raise exception 'Serial-tracked return quantity must be whole base units'; end if;
    v_serials:=coalesce(p_input->'serial_numbers','[]'::jsonb);
    if jsonb_typeof(v_serials)<>'array' then raise exception 'Serial numbers must be an array'; end if;
    select count(*)::numeric into v_count from jsonb_array_elements(v_serials);
    if v_count<>ri.quantity then raise exception 'Provide exactly % serial numbers for the returned line',ri.quantity; end if;

    for x in select value from jsonb_array_elements(v_serials) loop
      v_serial:=trim(coalesce(case when jsonb_typeof(x)='string' then x#>>'{}' else x->>'serial_number' end,''));
      if v_serial='' then raise exception 'Returned serial number cannot be blank'; end if;
      if lower(v_serial)=any(v_seen_serials) then raise exception 'Duplicate returned serial number %',v_serial; end if;
      v_seen_serials:=array_append(v_seen_serials,lower(v_serial));

      v_serial_id:=null;
      select id into v_serial_id from public.inventory_serials_v483
      where tenant_id=p_tenant_id and variant_id=ri.variant_id
        and purchase_id=r.purchase_id and purchase_item_id=ri.purchase_item_id
        and status='in_stock' and current_location_id=r.location_id
        and lower(trim(serial_number))=lower(v_serial)
      for update;
      if v_serial_id is null then
        raise exception 'Serial % is not available at this branch from the original Purchase line, or was already returned/sold/transferred',v_serial;
      end if;

      update public.inventory_serials_v483
      set status='returned',current_location_id=null,reserved_transfer_id=null,updated_at=now()
      where id=v_serial_id;

      insert into public.inventory_trace_events_v483(
        tenant_id,variant_id,serial_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,
        reference_number,source_key,metadata,created_by
      ) values(
        p_tenant_id,ri.variant_id,v_serial_id,'purchase_return',1,r.location_id,p.supplier_id,r.purchase_id,ri.purchase_item_id,
        r.return_number,'purchase_return:'||r.id::text||':serial:'||v_serial_id::text,
        jsonb_build_object('purchase_return_id',r.id,'purchase_return_item_id',ri.id),auth.uid()
      );
    end loop;
  else
    v_batches:=coalesce(p_input->'batches','[]'::jsonb);
    if jsonb_typeof(v_batches)<>'array' or jsonb_array_length(v_batches)=0 then
      raise exception 'Batch allocations are required for a batch-tracked Purchase Return';
    end if;

    for x in select value from jsonb_array_elements(v_batches) loop
      v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
      if v_qty<=0 then raise exception 'Returned batch quantity must be positive'; end if;

      v_batch_id:=null;
      if nullif(x->>'batch_id','') is not null then
        select id into v_batch_id from public.inventory_batches_v483
        where id=(x->>'batch_id')::uuid and tenant_id=p_tenant_id and variant_id=ri.variant_id;
      else
        v_batch:=trim(coalesce(x->>'batch_number',''));
        select id into v_batch_id from public.inventory_batches_v483
        where tenant_id=p_tenant_id and variant_id=ri.variant_id and lower(trim(batch_number))=lower(v_batch);
      end if;
      if v_batch_id is null then raise exception 'Returned batch was not found for this product'; end if;
      if v_batch_id=any(v_seen_batches) then raise exception 'The same batch cannot appear twice in one returned line'; end if;
      v_seen_batches:=array_append(v_seen_batches,v_batch_id);

      select coalesce(sum(quantity),0) into v_purchased
      from public.inventory_trace_events_v483
      where tenant_id=p_tenant_id and batch_id=v_batch_id and event_type='purchase'
        and purchase_id=r.purchase_id and purchase_item_id=ri.purchase_item_id;
      select coalesce(sum(quantity),0) into v_returned
      from public.inventory_trace_events_v483
      where tenant_id=p_tenant_id and batch_id=v_batch_id and event_type='purchase_return'
        and purchase_id=r.purchase_id and purchase_item_id=ri.purchase_item_id;
      if v_returned+v_qty>v_purchased+0.000001 then
        raise exception 'Returned quantity exceeds quantity received from batch % on the original Purchase line',v_batch_id;
      end if;

      select quantity-reserved_quantity-damaged_quantity into v_available
      from public.inventory_batch_balances_v483
      where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=r.location_id
      for update;
      if coalesce(v_available,0)+0.000001<v_qty then
        raise exception 'Insufficient available branch quantity in batch % for Purchase Return',v_batch_id;
      end if;

      update public.inventory_batch_balances_v483
      set quantity=quantity-v_qty,updated_at=now()
      where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=r.location_id;

      insert into public.inventory_trace_events_v483(
        tenant_id,variant_id,batch_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,
        reference_number,source_key,metadata,created_by
      ) values(
        p_tenant_id,ri.variant_id,v_batch_id,'purchase_return',v_qty,r.location_id,p.supplier_id,r.purchase_id,ri.purchase_item_id,
        r.return_number,'purchase_return:'||r.id::text||':item:'||ri.id::text||':batch:'||v_batch_id::text,
        jsonb_build_object('purchase_return_id',r.id,'purchase_return_item_id',ri.id),auth.uid()
      );

      if not exists(
        select 1 from public.inventory_batch_balances_v483 b
        where b.tenant_id=p_tenant_id and b.batch_id=v_batch_id and b.quantity>0.000001
      ) then
        update public.inventory_batches_v483 set status='exhausted',updated_at=now()
        where id=v_batch_id and status='active';
      end if;
      v_sum:=v_sum+v_qty;
    end loop;

    if abs(v_sum-ri.quantity)>0.000001 then
      raise exception 'Returned batch allocations must equal return base quantity %',ri.quantity;
    end if;
  end if;
end
$function$;

create or replace function public.gst_purchase_return_create_v520(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_return_date date,
  p_items jsonb,
  p_reason text,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_req_payload jsonb; v_req_state jsonb; v_quote jsonb; v_totals jsonb;
  v_purchase public.purchases%rowtype; v_origin public.document_origins%rowtype;
  v_id uuid:=gen_random_uuid(); v_no text; x jsonb; ql jsonb; pi public.purchase_items%rowtype; v_ri uuid;
  v_line_ids jsonb:='[]'::jsonb; v_snapshot uuid; v_journal uuid; v_response jsonb;
  v_stock_type text; v_available numeric; v_paid numeric:=0; v_prev_returns numeric:=0; v_ap_reduce numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.return') or private.erp_has_permission(p_tenant_id,'purchases.manage')) then
    raise exception 'Purchase return permission required';
  end if;
  if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then
    raise exception 'GST calculation permission required';
  end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Return reason is required'; end if;
  if p_return_date is null then raise exception 'Return date is required'; end if;

  select * into v_purchase from public.purchases
  where tenant_id=p_tenant_id and id=p_purchase_id and status='posted'
  for update;
  if not found then raise exception 'Posted Purchase not found'; end if;

  select * into v_origin from public.document_origins
  where tenant_id=p_tenant_id and entity_type='purchase' and entity_id=p_purchase_id
  order by created_at limit 1;
  if v_origin.location_id is null then raise exception 'Original Purchase does not have a business location'; end if;
  if p_location_id is not null and p_location_id<>v_origin.location_id then
    raise exception 'Purchase Return location must match the original Purchase location';
  end if;
  perform private.v4_location_access(p_tenant_id,v_origin.location_id,'operate');
  if p_device_id is not null then
    perform private.erp_validate_transaction_origin(p_tenant_id,v_origin.location_id,p_device_id,'purchases');
  end if;

  v_req_payload:=jsonb_build_object(
    'purchase_id',p_purchase_id,'return_date',p_return_date,'items',coalesce(p_items,'[]'::jsonb),
    'reason',trim(p_reason),'location_id',v_origin.location_id,'device_id',p_device_id
  );
  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.purchase_return.create.v520',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response'; end if;

  v_quote:=private.gst_purchase_return_quote_v520(p_tenant_id,p_purchase_id,p_return_date,p_items);
  v_totals:=v_quote->'totals';
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then
    raise exception 'GST Purchase Return is not compliance-ready';
  end if;

  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'purchase_return');
  v_no:='PRN-'||lpad(nextval('public.purchase_return_number_seq')::text,6,'0');
  insert into public.purchase_returns(
    id,tenant_id,purchase_id,return_number,location_id,device_id,return_date,reason,credit_status,created_by
  ) values(
    v_id,p_tenant_id,p_purchase_id,v_no,v_origin.location_id,p_device_id,p_return_date,trim(p_reason),'supplier_credit',auth.uid()
  );
  perform private.gst_authoritative_context_bind_v520(v_id);

  for ql in select value from jsonb_array_elements(v_quote->'lines') loop
    select * into pi from public.purchase_items
    where tenant_id=p_tenant_id and purchase_id=p_purchase_id and id=(ql->>'purchase_item_id')::uuid;

    insert into public.purchase_return_items(
      purchase_return_id,purchase_item_id,variant_id,quantity,unit_cost,discount_amount,tax_rate,line_total,
      entered_unit_id,entered_unit_code,entered_quantity,conversion_to_base
    ) values(
      v_id,pi.id,pi.variant_id,(ql->>'quantity')::numeric,(ql->>'unit_price')::numeric,(ql->>'discount')::numeric,
      coalesce((ql->>'applied_gst_rate')::numeric,0),(ql->>'line_total')::numeric,
      pi.entered_unit_id,pi.entered_unit_code,
      case when coalesce(pi.conversion_to_base,1)>0 then (ql->>'quantity')::numeric/coalesce(pi.conversion_to_base,1) else (ql->>'quantity')::numeric end,
      coalesce(pi.conversion_to_base,1)
    ) returning id into v_ri;
    v_line_ids:=v_line_ids||jsonb_build_array(v_ri);

    select p.item_type into v_stock_type
    from public.product_variants pv
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=pi.variant_id and pv.tenant_id=p_tenant_id;

    if v_stock_type='stock' then
      select quantity-reserved_quantity-damaged_quantity-quarantine_quantity into v_available
      from public.location_stock_balances
      where tenant_id=p_tenant_id and location_id=v_origin.location_id and variant_id=pi.variant_id
      for update;
      if coalesce(v_available,0)+0.000001<(ql->>'quantity')::numeric then
        raise exception 'Insufficient available branch stock for GST Purchase Return item %',pi.id;
      end if;

      perform public.inventory_adjust_stock(p_tenant_id,pi.variant_id,-(ql->>'quantity')::numeric,'GST Purchase return • '||v_no);
      perform private.v4_location_stock_apply(
        p_tenant_id,v_origin.location_id,pi.variant_id,-(ql->>'quantity')::numeric,
        'purchase_return','purchase_return',v_id,v_no,trim(p_reason),p_device_id,false
      );
    end if;

    select value into x from jsonb_array_elements(p_items)
    where (value->>'purchase_item_id')::uuid=pi.id limit 1;
    perform private.gst_purchase_return_tracking_apply_v520(p_tenant_id,v_id,v_ri,coalesce(x,'{}'::jsonb));
  end loop;

  update public.purchase_returns
  set subtotal=(v_totals->>'taxable_value')::numeric,
      tax_total=(v_totals->>'tax_collected_total')::numeric,
      grand_total=(v_totals->>'grand_total')::numeric
  where id=v_id and tenant_id=p_tenant_id;

  if exists(
    select 1 from public.journal_entries
    where tenant_id=p_tenant_id and source_type='purchase_return' and source_id=v_id and status='posted'
  ) then raise exception 'Legacy Purchase Return journal was created inside authoritative GST context'; end if;
  if exists(
    select 1 from public.gst_legacy_document_markers_v520
    where tenant_id=p_tenant_id and source_type='purchase_return' and source_id=v_id
  ) then raise exception 'Legacy GST evidence was created inside authoritative GST context'; end if;

  insert into public.transaction_corrections(
    tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata
  ) values(
    p_tenant_id,'purchase',p_purchase_id,'return',trim(p_reason),auth.uid(),
    jsonb_build_object('return_id',v_id,'return_number',v_no,'amount',(v_totals->>'grand_total')::numeric,'gst_engine','v5.2')
  );

  v_snapshot:=private.gst_snapshot_create_v520(
    p_tenant_id,'purchase_return',v_id,v_no,v_origin.location_id,p_return_date,v_quote,v_line_ids
  );
  v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);

  insert into public.supplier_ledger_entries_v484(
    tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
  ) values(
    p_tenant_id,v_purchase.supplier_id,v_origin.location_id,p_return_date,'purchase_return',v_id,v_no,
    'GST Purchase Return '||v_no,0,(v_totals->>'grand_total')::numeric,auth.uid()
  ) on conflict(tenant_id,entry_type,source_id) do nothing;

  select coalesce(sum(amount),0) into v_paid
  from public.purchase_payments where tenant_id=p_tenant_id and purchase_id=p_purchase_id;
  select coalesce(sum(grand_total),0) into v_prev_returns
  from public.purchase_returns
  where tenant_id=p_tenant_id and purchase_id=p_purchase_id and id<>v_id and credit_status<>'waived'
    and created_at<=(select created_at from public.purchase_returns where id=v_id);
  v_ap_reduce:=least((v_totals->>'grand_total')::numeric,greatest(v_purchase.grand_total-v_paid-v_prev_returns,0));
  v_credit:=greatest((v_totals->>'grand_total')::numeric-v_ap_reduce,0);

  perform private.thq_sync_bump_v480(p_tenant_id,'finance','purchase_return',v_id::text,'post');

  v_response:=jsonb_build_object(
    'success',true,'gst_engine',v_quote->>'engine','gst_status','POSTED',
    'return_id',v_id,'return_number',v_no,'purchase_id',p_purchase_id,'document_class','credit_note',
    'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,
    'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,
    'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,
    'thq_rcm_tax_reversal_total',(v_totals->>'thq_rcm_tax_payable_total')::numeric,
    'payable_reduction',round(v_ap_reduce,2),'supplier_credit_due',round(v_credit,2),'credit_status','supplier_credit',
    'gst_snapshot_id',v_snapshot,'journal_id',v_journal,
    'original_purchase_snapshot_id',v_quote->>'original_purchase_snapshot_id'
  );

  v_response:=private.gst_request_complete_v520(
    p_tenant_id,p_request_id,'gst.purchase_return.create.v520','purchase_return',v_id,v_snapshot,v_journal,v_response
  );
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end
$function$;

revoke all on function private.gst_purchase_return_quote_v520(uuid,uuid,date,jsonb) from public,anon,authenticated,service_role;
revoke all on function private.gst_purchase_return_tracking_apply_v520(uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.gst_purchase_return_create_v520(uuid,uuid,date,jsonb,text,uuid,uuid,text) from public,anon;
grant execute on function public.gst_purchase_return_create_v520(uuid,uuid,date,jsonb,text,uuid,uuid,text) to authenticated,service_role;
