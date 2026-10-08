-- Preserve legacy entry-point integrity and saved operational evidence.


CREATE OR REPLACE FUNCTION private.aggregate_load_confirm_core_v630(p_tenant_id uuid, p_load_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  perform private.v4_location_access(p_tenant_id,v_row.location_id,'operate');

  if v_row.status='completed' then
    return jsonb_build_object(
      'success',true,
      'already_confirmed',true,
      'load_id',v_row.id,
      'load_number',v_row.load_number,
      'status','completed'
    );
  end if;

  if v_row.status='cancelled' then
    raise exception 'Cancelled load cannot be confirmed';
  end if;

  update public.aggregate_loads_v617
  set status='completed',
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_row.id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,created_by
  )
  values(
    p_tenant_id,v_row.id,'confirmed',v_row.status,'completed',
    'Load confirmed',auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.confirm',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    jsonb_build_object('status','completed')
  );

  return jsonb_build_object(
    'success',true,
    'already_confirmed',false,
    'load_id',v_row.id,
    'load_number',v_row.load_number,
    'status','completed'
  );
end
$function$
;
CREATE OR REPLACE FUNCTION private.aggregate_load_sale_core_v630(p_tenant_id uuid, p_load_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_payment_allocations jsonb, p_notes text, p_location_id uuid, p_device_id uuid, p_request_id text, p_supply_type text, p_place_of_supply_code text, p_charge_selections jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_load public.aggregate_loads_v617%rowtype;v_result jsonb;v_id uuid;
begin
  v_load := private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
  if v_load.customer_id is not null and v_load.customer_id is distinct from p_customer_id then
    raise exception 'Sale customer must match the confirmed load customer';
  end if;
  v_result := public.gst_client_sale_create_v611(
    p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,
    p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections
  );
  v_id := nullif(v_result->>'sale_id','')::uuid;
  if v_id is null then raise exception 'Authoritative Sale did not return a sale ID'; end if;
  perform public.aggregate_load_link_document_v617(p_tenant_id,p_load_id,'sale',v_id);
  update public.aggregate_loads_v617 set customer_id=p_customer_id where id=p_load_id and tenant_id=p_tenant_id and customer_id is null;
  return v_result||jsonb_build_object('material_load_id',p_load_id,'load_linked',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION private.gst_document_quote_non_gst_v520(p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric DEFAULT 0, p_round_off numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  d date:=coalesce(p_document_date,current_date);
  kind text:=lower(trim(coalesce(p_document_kind,'')));
  x jsonb;
  v_variant uuid;
  prod record;
  qty numeric;
  price numeric;
  discount numeric;
  base numeric;
  line_total numeric;
  v_hsn text;
  v_supply_kind text;
  lines jsonb:='[]'::jsonb;
  subtotal numeric:=0;
  discount_total numeric:=0;
  base_total numeric:=0;
  line_total_sum numeric:=0;
  grand numeric;
begin
  if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
          or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then
    raise exception 'GST/tax calculation permission required';
  end if;
  if private.gst_tax_mode_resolve_v520(p_tenant_id,d)<>'non_gst' then
    raise exception 'Non-GST quote requested for a business that is not in Non-GST mode';
  end if;
  if kind not in ('sale','purchase') then
    raise exception 'Document kind must be sale or purchase';
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Tax quote requires at least one item';
  end if;
  if coalesce(p_additional_charges,0)<0 then raise exception 'Additional charges cannot be negative'; end if;
  if abs(coalesce(p_round_off,0))>1.000001 then raise exception 'Round-off cannot exceed 1.00 in either direction'; end if;
  if not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then
    raise exception 'Active location not found';
  end if;
  if kind='sale' and (p_party_id is null or not exists(select 1 from public.customers c where c.id=p_party_id and c.tenant_id=p_tenant_id and c.status='active')) then
    raise exception 'Active customer not found';
  end if;
  if kind='purchase' and (p_party_id is null or not exists(select 1 from public.suppliers s where s.id=p_party_id and s.tenant_id=p_tenant_id and s.status='active')) then
    raise exception 'Active supplier not found';
  end if;

  for x in select value from jsonb_array_elements(p_items) loop
    begin
      if x ? 'thq_tax_override_v630' then
      if kind<>'sale' or not private.erp_has_permission(p_tenant_id,'sales.tax_override') then raise exception 'Invoice tax adjustment permission required' using errcode='42501';end if;
      if jsonb_typeof(x->'thq_tax_override_v630')<>'object' or (x->'thq_tax_override_v630'->>'gst_rate') is null then raise exception 'Invalid invoice tax adjustment';end if;
      if (x->'thq_tax_override_v630'->>'gst_rate')::numeric<>0 then raise exception 'A Non-GST invoice must have zero GST';end if;
    end if;
      v_variant:=(x->>'variant_id')::uuid;
      qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
      price:=coalesce(nullif(x->>'unit_price','')::numeric,nullif(x->>'unit_cost','')::numeric,0);
      discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);
    exception when others then
      raise exception 'Invalid Non-GST quote item';
    end;
    if v_variant is null or qty<=0 or price<0 or discount<0 then
      raise exception 'Non-GST quote item has invalid product/quantity/price/discount';
    end if;

    select p.id product_id,p.name,p.item_type,pv.name variant_name,pv.sku,a.hsn_sac legacy_hsn
      into prod
    from public.product_variants pv
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    left join public.product_invoice_attributes_v45 a on a.tenant_id=pv.tenant_id and a.variant_id=pv.id
    where pv.id=v_variant and pv.tenant_id=p_tenant_id and pv.status='active' and p.status='active';
    if not found then raise exception 'Product is invalid or inactive'; end if;

    select coalesce(g.hsn_sac,prod.legacy_hsn) into v_hsn
    from (select 1) z
    left join lateral(
      select gp.hsn_sac
      from public.gst_product_tax_profiles_v520 gp
      where gp.tenant_id=p_tenant_id and gp.variant_id=v_variant and gp.active
        and d between gp.effective_from and coalesce(gp.effective_to,'infinity'::date)
      order by gp.effective_from desc,gp.created_at desc
      limit 1
    ) g on true;

    v_supply_kind:=case when prod.item_type='service' then 'service' else 'goods' end;
    base:=round(qty*price,4);
    if discount>base then raise exception 'Discount exceeds line value'; end if;
    base:=base-discount;
    line_total:=round(base,2);

    subtotal:=subtotal+round(qty*price,4);
    discount_total:=discount_total+discount;
    base_total:=base_total+base;
    line_total_sum:=line_total_sum+line_total;

    lines:=lines||jsonb_build_array(jsonb_build_object(
      'variant_id',v_variant,
      'product_id',prod.product_id,
      'product_name',coalesce(nullif(trim(x->>'invoice_description'),''),prod.name),
      'variant_name',prod.variant_name,
      'sku',prod.sku,
      'supply_kind',v_supply_kind,
      'hsn_sac',v_hsn,
      'quantity',qty,
      'unit_price',price,
      'discount',discount,
      'taxability','non_gst',
      'tax_inclusive',false,
      'reverse_charge',false,
      'gst_rate',0,
      'applied_gst_rate',0,
      'cess_rate',0,
      'applied_cess_rate',0,
      'cess_per_unit',0,
      'applied_cess_per_unit',0,
      'taxable_value',round(base,2),
      'cgst',0,'sgst',0,'utgst',0,'igst',0,'cess',0,'tax_amount',0,
      'rcm_cgst',0,'rcm_sgst',0,'rcm_utgst',0,'rcm_igst',0,'rcm_cess',0,'rcm_tax_amount',0,
      'rcm_liability_party',null,
      'line_total',line_total,
      'calculation_rounding',0,
      'profile_source','tenant_non_gst',
      'profile_status','not_applicable'
    ));
  end loop;

  grand:=round(line_total_sum+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);

  return jsonb_build_object(
    'engine','gst_v520_document_non_gst_1',
    'tax_mode','non_gst',
    'gst_applicable',false,
    'compliance_status','not_applicable',
    'document_kind',kind,
    'document_class','commercial_invoice',
    'document_date',d,
    'supply_type','NON_GST',
    'supplier_registration_id',null,
    'recipient_registration_id',null,
    'supplier_gstin',null,
    'supplier_state_code',null,
    'recipient_gstin',null,
    'recipient_state_code',null,
    'party_profile_id',null,
    'place_of_supply_code',null,
    'interstate',false,
    'local_tax_name',null,
    'zero_rated',false,
    'without_payment',false,
    'deemed_export',false,
    'composition_supplier',false,
    'lines',lines,
    'totals',jsonb_build_object(
      'subtotal',round(subtotal,2),
      'discount',round(discount_total,2),
      'taxable_value',round(base_total,2),
      'cgst',0,'sgst',0,'utgst',0,'igst',0,'cess',0,
      'tax_collected_total',0,
      'rcm_cgst',0,'rcm_sgst',0,'rcm_utgst',0,'rcm_igst',0,'rcm_cess',0,
      'rcm_tax_payable_total',0,
      'thq_rcm_tax_payable_total',0,
      'recipient_rcm_tax_payable_total',0,
      'government_tax_total',0,
      'additional_charges',coalesce(p_additional_charges,0),
      'calculation_rounding',0,
      'round_off',coalesce(p_round_off,0),
      'grand_total',grand
    ),
    'ready_for_compliance',true,
    'warnings','[]'::jsonb,
    'errors','[]'::jsonb
  );
end
$function$
;



create or replace function private.load_delivery_save_v630(t uuid,load uuid,data jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;old jsonb;start_meter numeric;end_meter numeric;depart timestamptz;arrive timestamptz;latitude numeric;longitude numeric;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 select details into old from public.material_load_delivery_v630 where tenant_id=t and load_id=load;
 data:=coalesce(old,'{}'::jsonb)||(data-'load_id');
 if jsonb_typeof(data)<>'object' or octet_length(data::text)>64000 then raise exception 'Invalid delivery details';end if;
 latitude:=nullif(data->>'delivery_latitude','')::numeric;longitude:=nullif(data->>'delivery_longitude','')::numeric;
 if (latitude is null)<>(longitude is null) or latitude not between -90 and 90 or longitude not between -180 and 180 then raise exception 'Enter both valid delivery latitude and longitude, or leave both blank';end if;
 start_meter:=nullif(data->>'odometer_start','')::numeric;end_meter:=nullif(data->>'odometer_end','')::numeric;
 depart:=nullif(data->>'dispatch_at','')::timestamptz;arrive:=nullif(data->>'delivered_at','')::timestamptz;
 if start_meter<0 or end_meter<0 or end_meter<start_meter or start_meter>1000000000 or end_meter>1000000000 then raise exception 'Check the start and end odometer readings';end if;
 if arrive<depart then raise exception 'Delivery time must follow departure';end if;
 insert into public.material_load_delivery_v630(load_id,tenant_id,details) values(load,t,coalesce(old,'{}'::jsonb)||data)
 on conflict(load_id) do update set details=excluded.details,updated_by=auth.uid(),updated_at=now();
 insert into public.workforce_audit_v630(tenant_id,load_id,action,before_data,after_data) values(t,load,'delivery.save',old,coalesce(old,'{}'::jsonb)||data);
end $$;

create or replace function public.material_load_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;load uuid:=nullif(p_data->>'load_id','')::uuid;location uuid:=p_location_id;
 l public.aggregate_loads_v617%rowtype;data jsonb:=coalesce(p_data->'load',p_data);result jsonb;prior public.material_load_requests_v630%rowtype;
 costs jsonb:=coalesce(p_data->'costs','[]'::jsonb);req text:=p_data->>'request_id';variant uuid;v_sku text;mode text;name text;
begin
 if p_action='context' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'driver_id',s.driver_id,'name',s.name,'phone',s.phone,'wage_basis',s.wage_basis,'base_rate',case when private.erp_has_permission(t,'staff.view') then s.base_rate else null end,'location_id',s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id=t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t,s.location_id,location,'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id=t and m.module_key='staff' and m.enabled)),'[]'::jsonb),
   'billing_services',coalesce((select jsonb_agg(jsonb_build_object('variant_id',v.id,'name',p.name,'tax_rate',p.tax_rate,'hsn_sac',g.hsn_sac,'taxability',g.taxability,'gst_rate',g.gst_rate,'validation_status',g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t,v.id,current_date)) g on true where v.tenant_id=t and v.status='active' and p.status='active' and p.item_type='service'),'[]'::jsonb),
   'tax_mode',private.gst_tax_mode_resolve_v520(t,current_date),'can_manage_costs',private.erp_has_permission(t,'aggregate_yard.costs'),
   'can_create_billing_service',private.erp_has_permission(t,'inventory.manage') and private.erp_has_permission(t,'gst_compliance.manage')
  );
 elsif p_action='billing_service' then
  perform private.yard_cost_assert_v630(t,location,true);
  name:=nullif(trim(data->>'name'),'');if name is null then raise exception 'Charge service name is required';end if;
  mode:=private.gst_tax_mode_resolve_v520(t,current_date);
  if mode='unconfigured' then raise exception 'Configure the business tax mode first';end if;
  if mode='non_gst' and coalesce((data->>'gst_rate')::numeric,0)<>0 then raise exception 'Non-GST charges must have zero GST';end if;
  if mode='gst_registered' and nullif(trim(data->>'hsn_sac'),'') is null then raise exception 'Select the correct SAC for this charge service';end if;
  v_sku:='YARD-SVC-'||upper(left(coalesce(nullif(data->>'new_id',''),gen_random_uuid()::text),12));
  if exists(select 1 from public.product_variants where tenant_id=t and sku=v_sku) then raise exception 'Charge service already exists; refresh the list';end if;
  result:=public.inventory_create_product_v481(p_tenant_id=>t,p_location_id=>location,p_device_id=>nullif(data->>'device_id','')::uuid,p_name=>name,p_sku=>v_sku,p_item_type=>'service',p_description=>coalesce(data->>'description',name),p_category_name=>'Load Charges',p_brand_name=>'',p_barcode=>'',p_part_number=>'',p_cost_price=>0,p_selling_price=>0,p_list_price=>null,p_tax_rate=>coalesce((data->>'gst_rate')::numeric,0),p_reorder_level=>0,p_opening_stock=>0,p_base_unit_code=>'PCS',p_units=>'[]'::jsonb);
  variant:=(result->>'variant_id')::uuid;
  if mode='gst_registered' then perform public.gst_product_profile_save_v520(t,variant,'service',data->>'hsn_sac',coalesce(data->>'taxability','taxable'),coalesce((data->>'gst_rate')::numeric,0),0,0,false,false,'Load charge service setup',current_date);end if;
  return jsonb_build_object('variant_id',variant,'recorded',true);
 elsif p_action='report' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  if coalesce((data->>'to')::date,current_date)<coalesce((data->>'from')::date,date_trunc('month',current_date)::date) then raise exception 'End date must follow start date';end if;
  return jsonb_build_object('loads',coalesce((select jsonb_agg(private.load_evidence_v630(t,x.id) order by x.load_date desc,x.load_number) from public.aggregate_loads_v617 x where x.tenant_id=t and x.direction<>'direct_delivery' and x.load_date between coalesce((data->>'from')::date,date_trunc('month',current_date)::date) and coalesce((data->>'to')::date,current_date) and private.erp_document_scope_allowed(t,x.location_id,location,'view') and (nullif(data->>'vehicle_id','') is null or x.vehicle_id=(data->>'vehicle_id')::uuid) and (nullif(data->>'driver_id','') is null or x.driver_id=(data->>'driver_id')::uuid)),'[]'::jsonb));
 end if;
 if p_action='create' then
  perform private.aggregate_yard_assert_manage_v617(t);
  if req is null or length(req)>256 then raise exception 'A stable load request ID is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text||':load:'||req,0));
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id=req;
  if found then if prior.payload<>p_data then raise exception 'Load retry has different data';end if;return jsonb_build_object('load_id',prior.load_id,'replayed',true);end if;
  result:=public.aggregate_load_create_v617(t,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  load:=(result->>'load_id')::uuid;
  select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
  perform private.v4_location_access(t,l.location_id,'operate');
  if jsonb_array_length(costs)>0 then perform private.load_cost_save_v630(t,load,costs);end if;
  perform private.load_delivery_save_v630(t,load,jsonb_build_object('driver_license_snapshot',(select license_number from public.logistics_drivers_v61 where id=l.driver_id and tenant_id=t))||coalesce(p_data->'delivery','{}'::jsonb));
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,req,p_data,load);
  return result;
 end if;
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 if p_action='detail' then return private.load_evidence_v630(t,load);end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 if p_action='edit' then
  result:=public.aggregate_load_edit_v628(t,load,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  perform private.v4_location_access(t,(select location_id from public.aggregate_loads_v617 where id=load),'operate');
  if p_data ? 'costs' and private.erp_has_permission(t,'aggregate_yard.costs') then perform private.load_cost_save_v630(t,load,costs);end if;
  if p_data ? 'delivery' then perform private.load_delivery_save_v630(t,load,p_data->'delivery');end if;
 elsif p_action='confirm' then
  result:=public.aggregate_load_confirm_v628(t,load);perform private.load_costs_post_v630(t,load);
 elsif p_action='delivery' then perform private.load_delivery_save_v630(t,load,data);result:=jsonb_build_object('recorded',true);
 elsif p_action='payment' then result:=jsonb_build_object('payment_id',private.load_cost_payment_v630(t,(data->>'cost_id')::uuid,data));
 elsif p_action='add_cost' then
  if req is null or length(req)>256 then raise exception 'A stable expense submission request ID is required';end if;
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id='add-cost:'||req;
  if found then if prior.load_id<>load or prior.payload<>p_data then raise exception 'Expense retry has different data';end if;return jsonb_build_object('recorded',true,'replayed',true);end if;
  perform private.load_cost_save_v630(t,load,case when p_data ? 'costs' then costs else jsonb_build_array(p_data->'cost') end,false);
  if l.status='completed' then perform private.load_costs_post_v630(t,load);end if;
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,'add-cost:'||req,p_data,load);
  result:=jsonb_build_object('recorded',true);
 elsif p_action='cancel' then
  if l.status='completed' or l.sale_id is not null or l.purchase_id is not null then raise exception 'Only an unconfirmed load can be cancelled. Confirmed costs and linked documents retain their financial history.';end if;
  result:=public.aggregate_load_status_v617(t,load,'cancelled',coalesce(p_data->>'reason','Cancelled before confirmation'));
 elsif p_action='delete' then
  if exists(select 1 from public.material_load_costs_v630 where tenant_id=t and load_id=load) or exists(select 1 from public.material_load_delivery_v630 where tenant_id=t and load_id=load) then raise exception 'This load has saved costs or delivery records. Cancel it to retain its history instead of deleting it.';end if;
  result:=public.aggregate_load_delete_v628(t,load);
 else raise exception 'Unknown material load action';end if;
 return result;
end $$;

create or replace function public.aggregate_load_sale_create_v630(
 p_tenant_id uuid,p_load_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,
 p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text,p_supply_type text,p_place_of_supply_code text,p_charge_selections jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;result jsonb;items jsonb;id uuid;
begin
 l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
 perform private.load_costs_post_v630(p_tenant_id,p_load_id);
 items:=private.load_sale_items_v630(p_tenant_id,p_load_id,p_items);
 result:=private.aggregate_load_sale_core_v630(p_tenant_id,p_load_id,p_customer_id,p_sale_date,p_due_date,items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
 id:=(result->>'sale_id')::uuid;
 insert into public.material_load_sale_snapshots_v630(sale_id,tenant_id,load_id,evidence)
 values(id,p_tenant_id,p_load_id,private.load_evidence_v630(p_tenant_id,p_load_id)||jsonb_build_object('invoice_items_entered',p_items,'invoice_terms_entered',jsonb_build_object('customer_id',p_customer_id,'sale_date',p_sale_date,'due_date',p_due_date,'notes',p_notes,'supply_type',p_supply_type,'place_of_supply_code',p_place_of_supply_code,'payment_allocations',p_payment_allocations,'charge_selections',p_charge_selections),'snapshot_at',now()))
 on conflict(sale_id) do nothing;
 return result||jsonb_build_object('load_costs_recorded',true);
end $$;

create or replace function public.staff_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;location uuid:=p_location_id;s uuid:=nullif(p_data->>'staff_id','')::uuid;
 member public.staff_members_v630%rowtype;old jsonb;result uuid;driver uuid;day date;start_day date;end_day date;
begin
 if p_action in('list','detail','report') then
  perform private.staff_assert_v630(t,'staff.view',location);
  start_day:=coalesce((p_data->>'from')::date,date_trunc('month',current_date)::date);
  end_day:=coalesce((p_data->>'to')::date,current_date);
  if end_day<start_day then raise exception 'End date must follow start date';end if;
  if s is not null then
   select * into member from public.staff_members_v630 where tenant_id=t and id=s;
   if not found then raise exception 'Staff member not found';end if;
   if member.location_id is not null then perform private.v4_location_access(t,member.location_id,'view');end if;
  end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object(
    'license_number',(select license_number from public.logistics_drivers_v61 d where d.tenant_id=t and d.id=x.driver_id),
    'earned',coalesce((select sum(e.amount) from public.staff_earnings_v630 e where e.tenant_id=t and e.staff_id=x.id and private.erp_document_scope_allowed(t,e.location_id,location,'view')),0),
    'paid',coalesce((select sum(p.amount) from public.staff_payments_v630 p where p.tenant_id=t and p.staff_id=x.id and private.erp_document_scope_allowed(t,p.location_id,location,'view')),0),
    'outstanding',coalesce((select sum(e.amount-private.staff_earning_paid_v630(e.id)) from public.staff_earnings_v630 e where e.tenant_id=t and e.staff_id=x.id and private.erp_document_scope_allowed(t,e.location_id,location,'view')),0),
    'advance_balance',coalesce((select sum(p.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a where a.payment_id=p.id and a.from_advance),0)) from public.staff_payments_v630 p where p.tenant_id=t and p.staff_id=x.id and private.erp_document_scope_allowed(t,p.location_id,location,'view')),0)
   ) order by x.active desc,x.name) from public.staff_members_v630 x where x.tenant_id=t and (s is null or x.id=s) and (x.location_id is null or private.erp_document_scope_allowed(t,x.location_id,location,'view'))),'[]'::jsonb),
   'load_allocations',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('load_number',l.load_number,'load_date',l.load_date)) from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id where c.tenant_id=t and c.staff_mode='salary_allocation' and c.status='posted' and (s is null or c.staff_id=s) and l.load_date between start_day and end_day and private.erp_document_scope_allowed(t,l.location_id,location,'view')),'[]'::jsonb),
   'attendance',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('staff_name',x.name) order by a.work_date desc,x.name) from public.staff_attendance_v630 a join public.staff_members_v630 x on x.id=a.staff_id and x.tenant_id=a.tenant_id where a.tenant_id=t and (s is null or a.staff_id=s) and a.work_date between start_day and end_day and private.erp_document_scope_allowed(t,a.location_id,location,'view')),'[]'::jsonb),
   'earnings',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('staff_name',x.name,'paid_amount',private.staff_earning_paid_v630(e.id),'outstanding',e.amount-private.staff_earning_paid_v630(e.id)) order by e.earning_date desc,e.created_at desc) from public.staff_earnings_v630 e join public.staff_members_v630 x on x.id=e.staff_id and x.tenant_id=e.tenant_id where e.tenant_id=t and (s is null or e.staff_id=s) and e.earning_date between start_day and end_day and private.erp_document_scope_allowed(t,e.location_id,location,'view')),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('staff_name',x.name,'allocations',coalesce((select jsonb_agg(to_jsonb(a)) from public.staff_payment_allocations_v630 a where a.payment_id=p.id),'[]'::jsonb)) order by p.payment_date desc,p.created_at desc) from public.staff_payments_v630 p join public.staff_members_v630 x on x.id=p.staff_id and x.tenant_id=p.tenant_id where p.tenant_id=t and (s is null or p.staff_id=s) and p.payment_date between start_day and end_day and private.erp_document_scope_allowed(t,p.location_id,location,'view')),'[]'::jsonb),
   'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.workforce_audit_v630 a join public.staff_members_v630 x on x.id=a.staff_id and x.tenant_id=a.tenant_id where a.tenant_id=t and (s is null or a.staff_id=s) and a.created_at::date between start_day and end_day and (x.location_id is null or private.erp_document_scope_allowed(t,x.location_id,location,'view'))),'[]'::jsonb)
  );
 end if;
 if p_action='save' then
  perform private.staff_assert_v630(t,'staff.manage',location);
  if location is null then raise exception 'Select a location to save staff';end if;
  if nullif(trim(p_data->>'name'),'') is null then raise exception 'Staff name is required';end if;
  if s is not null then
   select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
   if not found then raise exception 'Staff member not found';end if;
   if member.location_id is not null then perform private.v4_location_access(t,member.location_id,'operate');end if;
   old:=to_jsonb(member)||jsonb_build_object('license_number',(select license_number from public.logistics_drivers_v61 where tenant_id=t and id=member.driver_id));driver:=member.driver_id;
   if member.location_id is distinct from location and exists(select 1 from public.staff_earnings_v630 where staff_id=s) then raise exception 'A staff member with earnings cannot move payroll location; retain their financial history';end if;
  else s:=coalesce(nullif(p_data->>'new_id','')::uuid,gen_random_uuid());if exists(select 1 from public.staff_members_v630 where id=s) then raise exception 'Staff ID already exists; refresh and edit that record';end if;end if;
  if coalesce(p_data->>'job_role','staff')='driver' then
   if driver is null then
    insert into public.logistics_drivers_v61(tenant_id,name,phone,license_number,notes,active) values(t,trim(p_data->>'name'),p_data->>'phone',p_data->>'license_number',p_data->>'notes',coalesce((p_data->>'active')::boolean,true)) returning id into driver;
   else update public.logistics_drivers_v61 set name=trim(p_data->>'name'),phone=p_data->>'phone',license_number=p_data->>'license_number',active=coalesce((p_data->>'active')::boolean,true),updated_at=now() where tenant_id=t and id=driver;end if;
  end if;
  if driver is not null and coalesce(p_data->>'job_role','staff')<>'driver' then update public.logistics_drivers_v61 set name=trim(p_data->>'name'),phone=p_data->>'phone',active=false,updated_at=now() where tenant_id=t and id=driver;end if;
  insert into public.staff_members_v630(id,tenant_id,location_id,driver_id,staff_code,name,phone,address,job_role,joined_on,left_on,wage_basis,base_rate,overtime_rate,bank_name,bank_account,bank_ifsc,emergency_contact,notes,active)
  values(s,t,location,driver,coalesce(nullif(p_data->>'staff_code',''),member.staff_code,'STF-'||upper(left(s::text,8))),trim(p_data->>'name'),p_data->>'phone',p_data->>'address',coalesce(p_data->>'job_role','staff'),coalesce((p_data->>'joined_on')::date,current_date),(p_data->>'left_on')::date,coalesce(p_data->>'wage_basis','monthly'),coalesce((p_data->>'base_rate')::numeric,0),coalesce((p_data->>'overtime_rate')::numeric,0),p_data->>'bank_name',p_data->>'bank_account',p_data->>'bank_ifsc',p_data->>'emergency_contact',p_data->>'notes',coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set location_id=excluded.location_id,driver_id=excluded.driver_id,staff_code=excluded.staff_code,name=excluded.name,phone=excluded.phone,address=excluded.address,job_role=excluded.job_role,joined_on=excluded.joined_on,left_on=excluded.left_on,wage_basis=excluded.wage_basis,base_rate=excluded.base_rate,overtime_rate=excluded.overtime_rate,bank_name=excluded.bank_name,bank_account=excluded.bank_account,bank_ifsc=excluded.bank_ifsc,emergency_contact=excluded.emergency_contact,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now();
  insert into public.workforce_audit_v630(tenant_id,staff_id,action,before_data,after_data) values(t,s,'staff.save',old,(select to_jsonb(x)||jsonb_build_object('license_number',p_data->>'license_number') from public.staff_members_v630 x where id=s));
  return jsonb_build_object('staff_id',s);
 elsif p_action='attendance' then
  perform private.staff_assert_v630(t,'staff.manage',location);
  select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
  if not found or not member.active then raise exception 'Active staff member not found';end if;
  if member.location_id is not null and member.location_id<>location then raise exception 'Staff belongs to a different location';end if;
  day:=(p_data->>'date')::date;
  if day is null or day<member.joined_on or (member.left_on is not null and day>member.left_on) then raise exception 'Attendance date must be inside the employment period';end if;
  if exists(select 1 from public.staff_earnings_v630 where tenant_id=t and staff_id=s and kind='payroll' and day between period_from and period_to) then raise exception 'Attendance is locked for an already posted payroll period';end if;
  select to_jsonb(a) into old from public.staff_attendance_v630 a where tenant_id=t and staff_id=s and work_date=day;
  insert into public.staff_attendance_v630(tenant_id,staff_id,location_id,work_date,status,hours,overtime_hours,notes)
  values(t,s,location,day,p_data->>'status',coalesce((p_data->>'hours')::numeric,0),coalesce((p_data->>'overtime_hours')::numeric,0),p_data->>'notes')
  on conflict(tenant_id,staff_id,work_date) do update set status=excluded.status,hours=excluded.hours,overtime_hours=excluded.overtime_hours,notes=excluded.notes,updated_by=auth.uid(),updated_at=now() returning id into result;
  insert into public.workforce_audit_v630(tenant_id,staff_id,action,before_data,after_data) values(t,s,'attendance.save',old,(select to_jsonb(a) from public.staff_attendance_v630 a where id=result));
 elsif p_action='payroll' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_earning_post_v630(t,s,location,p_data);
 elsif p_action='payment' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_payment_post_v630(t,s,location,p_data);
 else raise exception 'Unknown staff action';
 end if;
 return jsonb_build_object('id',result,'recorded',true);
end $$;

CREATE OR REPLACE FUNCTION public.gst_client_sale_create_v630(p_tenant_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_payment_allocations jsonb, p_notes text, p_location_id uuid, p_device_id uuid, p_request_id text, p_supply_type text, p_place_of_supply_code text, p_charge_selections jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
begin
 return public.gst_client_sale_create_v611(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
end $function$;

create or replace function public.aggregate_load_confirm_v628(p_tenant_id uuid,p_load_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;
begin
 result:=private.aggregate_load_confirm_core_v630(p_tenant_id,p_load_id);
 perform private.load_costs_post_v630(p_tenant_id,p_load_id);
 return result;
end $$;
create or replace function public.aggregate_load_sale_create_v629(p_tenant_id uuid,p_load_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text,p_supply_type text,p_place_of_supply_code text,p_charge_selections jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 return public.aggregate_load_sale_create_v630(p_tenant_id,p_load_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
end $$;
revoke all on function private.aggregate_load_confirm_core_v630(uuid,uuid) from public,anon,authenticated;
revoke all on function private.aggregate_load_sale_core_v630(uuid,uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;

