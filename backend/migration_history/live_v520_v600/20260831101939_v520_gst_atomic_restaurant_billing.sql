create or replace function public.gst_restaurant_order_bill_v520(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_customer_id uuid,
  p_due_date date,
  p_initial_payment numeric,
  p_payment_method text,
  p_payment_reference text,
  p_round_off numeric default 0,
  p_supply_type text default null,
  p_place_of_supply_code text default null
) returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
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

  perform private.thq_sync_bump_v480(p_tenant_id,'restaurant','restaurant_order',o.id::text,'bill');

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
    p_tenant_id,v_wrapper_request,'gst.restaurant.order.bill.v520','sale',v_sale_id,v_snapshot,v_sale_journal,v_response
  );
  return v_response;
end
$$;

revoke all on function public.gst_restaurant_order_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text) from public,anon;
grant execute on function public.gst_restaurant_order_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text) to authenticated,service_role;