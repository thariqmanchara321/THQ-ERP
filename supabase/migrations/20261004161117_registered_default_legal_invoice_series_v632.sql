-- v6.3.2: normal zero-tax billing without GST setup; registered billing remains authoritative.
-- Adds a private automatic GST numbering counter; no existing business records are updated.

create or replace function private.gst_tax_mode_resolve_v520(p_tenant_id uuid,p_date date default current_date)
returns text language sql stable security definer set search_path to 'public','private','pg_temp' as $fn$
 select coalesce((select m.tax_mode from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id=p_tenant_id and coalesce(p_date,current_date) between m.effective_from and coalesce(m.effective_to,'infinity'::date)
  order by m.effective_from desc,m.created_at desc limit 1),
  case when exists(select 1 from public.gst_tenant_tax_modes_v520 m where m.tenant_id=p_tenant_id and m.tax_mode='gst_registered')
    or exists(select 1 from public.gst_registrations_v520 r where r.tenant_id=p_tenant_id)
    or exists(select 1 from public.business_locations l where l.tenant_id=p_tenant_id and nullif(trim(l.gstin),'') is not null)
    or exists(select 1 from public.tenant_settings s where s.tenant_id=p_tenant_id and
      coalesce(nullif(trim(s.config->>'business.gstin'),''),nullif(trim(s.config#>>'{business,gstin}'),'')) is not null)
  then 'unconfigured' else 'non_gst' end);
$fn$;

create or replace function private.invoice_calculate_allowed_v632(p_tenant_id uuid,p_date date,p_kind text)
returns boolean language sql stable security definer set search_path to 'public','private','pg_temp' as $fn$
 select private.erp_user_has_tenant_access(p_tenant_id) and
  (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
   or (private.gst_tax_mode_resolve_v520(p_tenant_id,p_date)='non_gst' and
       private.erp_has_permission(p_tenant_id,case when p_kind='sale' then 'sales.manage' when p_kind='purchase' then 'purchases.manage' else '' end)));
$fn$;

create or replace function private.sale_items_for_tax_mode_v632(p_tenant_id uuid,p_date date,p_items jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public','private','pg_temp' as $fn$
begin
 if private.gst_tax_mode_resolve_v520(p_tenant_id,p_date)<>'non_gst' then return p_items;end if;
 if jsonb_typeof(p_items)<>'array' or p_items is null then raise exception 'Invoice items must be an array';end if;
 -- Tax settings from product masters/older clients are irrelevant to an unregistered sale.
 -- Keep quantities, prices, discounts, descriptions and stock allocations intact.
 return (select coalesce(jsonb_agg((x.value-'thq_tax_override_v630')||jsonb_build_object('tax_rate',0) order by x.ordinality),'[]'::jsonb)
  from jsonb_array_elements(p_items) with ordinality x(value,ordinality));
end $fn$;

create table if not exists public.gst_invoice_series_v632(
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 supplier_gstin text not null, financial_year integer not null, last_number bigint not null default 0 check(last_number>=0),
 primary key(tenant_id,supplier_gstin,financial_year));

alter table public.gst_invoice_series_v632 enable row level security;

revoke all on table public.gst_invoice_series_v632 from public,anon,authenticated;

create or replace function private.sale_default_legal_number_v632(p_tenant_id uuid,p_sale_id uuid,p_device_id uuid,p_gstin text,p_date date)
returns void language plpgsql security definer set search_path to 'public','private','pg_temp' as $fn$
declare n text;prefix text;fy integer:=extract(year from p_date-interval '3 months');seq bigint;
begin
 select coalesce(dn.terminal_number,ln.local_number) into n from public.sales s
 left join public.device_document_numbers dn on dn.tenant_id=s.tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
 left join public.location_document_numbers ln on ln.tenant_id=s.tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
 where s.tenant_id=p_tenant_id and s.id=p_sale_id and s.status='posted';
 if length(n)<=16 and n~'^[A-Za-z0-9/-]+$' then return;end if;
 if p_device_id is null then return;end if;
 select nullif(trim(d.invoice_prefix),'') into prefix from public.business_devices d where d.tenant_id=p_tenant_id and d.id=p_device_id;
 -- A custom invalid series must be corrected explicitly. Only the inherited
 -- branch/device default receives the automatic registration/year series.
 if prefix is not null then return;end if;
 if not private.erp_has_permission(p_tenant_id,'sales.manage') or p_gstin is null then raise exception 'Sales permission and GST registration required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':gst_invoice:'||p_gstin||':'||fy::text,0));
 loop
  insert into public.gst_invoice_series_v632(tenant_id,supplier_gstin,financial_year,last_number) values(p_tenant_id,p_gstin,fy,1)
  on conflict(tenant_id,supplier_gstin,financial_year) do update set last_number=public.gst_invoice_series_v632.last_number+1 returning last_number into seq;
  if seq>999999999 then raise exception 'GST automatic invoice numbering series is exhausted';end if;
  n:='G'||right(fy::text,2)||right((fy+1)::text,2)||'-'||lpad(seq::text,9,'0');
  exit when not exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.supplier_gstin=p_gstin and s.document_number=n);
 end loop;
 update public.device_document_numbers set terminal_number=n where tenant_id=p_tenant_id and entity_type='sale' and entity_id=p_sale_id;
 update public.location_document_numbers set local_number=n where tenant_id=p_tenant_id and entity_type='sale' and entity_id=p_sale_id;
end $fn$;

CREATE OR REPLACE FUNCTION public.gst_tax_mode_get_v520(p_tenant_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  r public.gst_tenant_tax_modes_v520%rowtype;
  d date:=coalesce(p_date,current_date);
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
     and not private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
     and not (private.erp_user_has_tenant_access(p_tenant_id) and (private.erp_has_permission(p_tenant_id,'sales.manage') or private.erp_has_permission(p_tenant_id,'purchases.manage'))) then
    raise exception 'GST/tax configuration view permission required';
  end if;

  select * into r
  from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id=p_tenant_id
    and d between m.effective_from and coalesce(m.effective_to,'infinity'::date)
  order by m.effective_from desc,m.created_at desc
  limit 1;

  return jsonb_build_object(
    'tax_mode',private.gst_tax_mode_resolve_v520(p_tenant_id,d),
    'configured',r.id is not null,
    'gst_applicable',private.gst_tax_mode_resolve_v520(p_tenant_id,d)='gst_registered',
    'billing_ready',private.gst_tax_mode_resolve_v520(p_tenant_id,d)<>'unconfigured',
    'source',case when r.id is null then 'registration_evidence' else 'explicit_configuration' end,
    'effective_from',r.effective_from,
    'effective_to',r.effective_to,
    'reason',r.reason,
    'as_of',d
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.gst_transaction_cutover_contract_base_v520(p_tenant_id uuid, p_channel text DEFAULT 'client'::text, p_device_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_channel text := lower(trim(coalesce(p_channel,'client')));
  v_device_contract jsonb := null;
begin
  if p_tenant_id is null then
    raise exception 'Tenant is required';
  end if;

  if not private.invoice_calculate_allowed_v632(p_tenant_id,current_date,'sale')
     and not private.invoice_calculate_allowed_v632(p_tenant_id,current_date,'purchase') then
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
end$function$;

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
  if not private.invoice_calculate_allowed_v632(p_tenant_id,d,kind) then
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
      if kind='sale' then x:=x-'thq_tax_override_v630';end if;
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

    v_hsn:=prod.legacy_hsn;

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
$function$;

CREATE OR REPLACE FUNCTION private.gst_profile_for_variant_v520(p_tenant_id uuid, p_variant_id uuid, p_date date)
 RETURNS gst_product_tax_profiles_v520
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  r public.gst_product_tax_profiles_v520%rowtype;
  v_kind text;
  v_hsn text;
  d date:=coalesce(p_date,current_date);
begin
  if private.gst_tax_mode_resolve_v520(p_tenant_id,d)<>'non_gst' then
    return private.gst_profile_for_variant_registered_v520(p_tenant_id,p_variant_id,d);
  end if;

  select case when p.item_type='service' then 'service' else 'goods' end,
         a.hsn_sac
    into v_kind,v_hsn
  from public.product_variants pv
  join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  left join public.product_invoice_attributes_v45 a on a.tenant_id=pv.tenant_id and a.variant_id=pv.id
  where pv.tenant_id=p_tenant_id and pv.id=p_variant_id and pv.status='active' and p.status='active';
  if not found then return null; end if;

  r.id:=coalesce(r.id,p_variant_id);
  r.tenant_id:=p_tenant_id;
  r.variant_id:=p_variant_id;
  r.supply_kind:=v_kind;
  r.hsn_sac:=v_hsn;
  r.taxability:='non_gst';
  r.gst_rate:=0;
  r.cess_rate:=0;
  r.cess_per_unit:=0;
  r.tax_inclusive:=false;
  r.reverse_charge:=false;
  r.validation_status:='locally_validated';
  r.source:='tenant_non_gst';
  r.notes:='Business tax mode is Non-GST';
  r.active:=true;
  r.effective_from:=d;
  r.effective_to:=null;
  r.created_at:=coalesce(r.created_at,now());
  r.updated_at:=now();
  return r;
end
$function$;

CREATE OR REPLACE FUNCTION public.client_sale_quote_v630(p_tenant_id uuid, p_customer_id uuid, p_sale_date date, p_items jsonb, p_location_id uuid, p_device_id uuid, p_supply_type text DEFAULT NULL::text, p_place_of_supply_code text DEFAULT NULL::text, p_charge_selections jsonb DEFAULT '[]'::jsonb, p_load_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare items jsonb:=p_items;commercial jsonb;quote jsonb;base_subtotal numeric;load_charges numeric:=0;totals jsonb;rounding numeric;supply text;pos text;normalized jsonb;l public.aggregate_loads_v617%rowtype;
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied' using errcode='42501';end if;
 perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
 if not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales permission required' using errcode='42501';end if;
 items:=private.sale_items_for_tax_mode_v632(p_tenant_id,p_sale_date,items);
 if p_load_id is not null then
  l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
  if l.customer_id is not null and l.customer_id is distinct from p_customer_id then raise exception 'Select the customer recorded on the confirmed Load Ticket';end if;
  items:=private.load_sale_items_v630(p_tenant_id,p_load_id,items,p_sale_date);
  select coalesce(sum(bill_amount),0) into load_charges from public.material_load_costs_v630 where tenant_id=p_tenant_id and load_id=p_load_id and status='posted';
 end if;
 if not public.sales_additional_charges_enabled_v611(p_tenant_id) and jsonb_array_length(p_charge_selections)>0 then raise exception 'Additional charges are disabled in Business Settings';end if;
 items:=private.sale_items_for_tax_mode_v632(p_tenant_id,p_sale_date,items);
 commercial:=private.sales_commercial_expand_v610(p_tenant_id,'sale',items,'none',0,p_charge_selections);
 normalized:=private.v481_normalize_items(p_tenant_id,private.v482_price_sale_items(p_tenant_id,p_customer_id,commercial->'items',p_location_id),'sale');
 supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,p_customer_id,p_sale_date,p_supply_type);
 pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,p_customer_id,p_location_id,p_sale_date,supply,normalized,p_place_of_supply_code);
 quote:=public.gst_quote_v520(p_tenant_id,p_location_id,'customer',p_customer_id,p_sale_date,supply,pos,normalized,0,0);
 if coalesce((quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Invoice validation failed: %',coalesce(quote->'errors','[]'::jsonb);end if;
 totals:=quote->'totals';rounding:=round(round((totals->>'grand_total')::numeric,0)-(totals->>'grand_total')::numeric,2);
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric) into base_subtotal from jsonb_array_elements(p_items) x;
 return jsonb_build_object('totals',totals||jsonb_build_object('subtotal',base_subtotal,'tax',(totals->>'tax_collected_total')::numeric,'before_round_off',(totals->>'grand_total')::numeric,'automatic_round_off',rounding,'grand_total',(totals->>'grand_total')::numeric+rounding),'classified_charge_total',load_charges+coalesce((commercial->>'classified_charge_total')::numeric,0),
  'gst',quote,'items',commercial->'items','charge_breakdown',commercial->'charge_breakdown','load_charge_total',load_charges);
end $function$;

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
  if not private.invoice_calculate_allowed_v632(p_tenant_id,p_sale_date,'sale') then raise exception 'Invoice calculation permission required';end if;
  if p_location_id is null then raise exception 'Business location is required'; end if;
  if p_sale_date is null then raise exception 'Sale date is required'; end if;
  if p_due_date is not null and p_due_date<p_sale_date then raise exception 'Due date cannot be before sale date'; end if;
  p_items:=private.sale_items_for_tax_mode_v632(p_tenant_id,p_sale_date,p_items);
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
  if coalesce((v_quote0->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Invoice is not ready to post: %',coalesce(v_quote0->'errors','[]'::jsonb)::text; end if;
  v_round:=round(round(coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),0)-coalesce((v_quote0->'totals'->>'grand_total')::numeric,0),2);
  v_quote:=public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_customer_id,p_sale_date,v_supply,v_pos,v_normalized,0,v_round);
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Invoice is not ready to post after round-off: %',coalesce(v_quote->'errors','[]'::jsonb)::text; end if;
  if v_quote->>'tax_mode'='gst_registered' then
    perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':gst_invoice:'||coalesce(v_quote->>'supplier_gstin','')||':'||extract(year from p_sale_date-interval '3 months')::text,0));
  end if;
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
  if v_quote->>'tax_mode'='gst_registered' then perform private.sale_default_legal_number_v632(p_tenant_id,v_sale_id,p_device_id,v_quote->>'supplier_gstin',p_sale_date);end if;
  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'sale',v_sale_id,v_sale_number,p_location_id,p_sale_date,v_quote,v_line_ids);
  if v_quote->>'tax_mode'='gst_registered' then
    select document_number into v_document_number from public.gst_document_snapshots_v520 where id=v_snapshot;
    if length(v_document_number)>16 or v_document_number!~'^[A-Za-z0-9/-]+$' then raise exception 'GST invoice number must be at most 16 letters, digits, slashes or hyphens. Update the location or system invoice prefix';end if;
    if exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.source_type='sale' and s.id<>v_snapshot and s.supplier_gstin=v_quote->>'supplier_gstin' and s.document_number=v_document_number and extract(year from s.document_date-interval '3 months')=extract(year from p_sale_date-interval '3 months')) then raise exception 'GST invoice number is already used for this registration and financial year. Update the invoice numbering series';end if;
  end if;
  v_journal:=private.gst_authoritative_sale_journal_post_v522(p_tenant_id,v_snapshot);
  select document_number into v_document_number from public.gst_document_snapshots_v520 where id=v_snapshot and tenant_id=p_tenant_id;
  if v_document_number is null then raise exception 'GST Sale legal document number was not captured'; end if;
  v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object('success',true,'writer','gst_sale_create_v522','version','5.2.2','gst_engine',v_quote->>'engine',
    'gst_status',case when v_quote->>'tax_mode'='non_gst' then 'NOT_APPLICABLE' else 'POSTED' end,'tax_mode',v_quote->>'tax_mode','gst_applicable',v_quote->>'tax_mode'='gst_registered','gst_supply_type',v_supply,'place_of_supply_code',v_quote->>'place_of_supply_code','sale_id',v_sale_id,'sale_number',v_sale_number,
    'invoice_number',v_document_number,'subtotal',(v_totals->>'subtotal')::numeric,'discount_total',v_discount,'round_off',v_round,
    'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,
    'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,
    'payments',v_payment_result,'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'gst_ready_for_compliance',true,'legacy_fallback_used',false);
  v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.sale.create.v522','sale',v_sale_id,v_snapshot,v_journal,v_response);
  update public.transaction_requests_v47 set response=v_response where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='sale.create';
  perform private.gst_authoritative_context_exit_v520();return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.gst_document_quote_registered_v520(p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric DEFAULT 0, p_round_off numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 d date:=coalesce(p_document_date,current_date);kind text:=lower(trim(coalesce(p_document_kind,'')));supply text:=upper(trim(coalesce(p_supply_type,case when lower(trim(coalesce(p_document_kind,'')))='purchase' then 'B2B' else 'B2C' end)));v_party_type text;
 loc public.business_locations%rowtype;reg public.gst_registrations_v520%rowtype;reg_cfg public.gst_registration_versions_v520%rowtype;party public.gst_party_registrations_v520%rowtype;
 supplier_state text;recipient_state text;pos text:=nullif(trim(coalesce(p_place_of_supply_code,'')),'');local_uses_utgst boolean:=false;interstate boolean;zero_rated boolean:=false;without_payment boolean:=false;deemed_export boolean:=false;composition_supplier boolean:=false;document_class text:='tax_invoice';
 x jsonb;prof public.gst_product_tax_profiles_v520%rowtype;variant uuid;prod record;qty numeric;price numeric;discount numeric;gross numeric;taxable numeric;v_rate numeric;cess_rate numeric;cess_unit numeric;fixed_cess numeric;applied_rate numeric;applied_cess_rate numeric;applied_cess_unit numeric;
 raw_cgst numeric;raw_sgst numeric;raw_utgst numeric;raw_igst numeric;raw_cess numeric;cgst numeric;sgst numeric;utgst numeric;igst numeric;cess numeric;rcm_cgst numeric;rcm_sgst numeric;rcm_utgst numeric;rcm_igst numeric;rcm_cess numeric;collected_tax numeric;rcm_tax numeric;line_total numeric;line_total_sum numeric:=0;calculation_rounding numeric;calculation_rounding_total numeric:=0;
 lines jsonb:='[]'::jsonb;subtotal numeric:=0;discount_total numeric:=0;taxable_total numeric:=0;cgst_total numeric:=0;sgst_total numeric:=0;utgst_total numeric:=0;igst_total numeric:=0;cess_total numeric:=0;rcm_cgst_total numeric:=0;rcm_sgst_total numeric:=0;rcm_utgst_total numeric:=0;rcm_igst_total numeric:=0;rcm_cess_total numeric:=0;grand numeric;
 warnings text[]:='{}';errors text[]:='{}';profile_source text;profile_status text;hsn text;taxability text;inclusive boolean;rcm boolean;supply_kind text;local_tax_name text;ready boolean;has_service boolean:=false;has_rcm boolean:=false;party_required boolean:=false;party_valid boolean:=false;rate_valid boolean;
begin
 if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required';end if;
 if kind not in('sale','purchase') then raise exception 'GST document kind must be sale or purchase';end if;
 v_party_type:=case when kind='sale' then 'customer' else 'supplier' end;
 if supply not in('B2B','B2C','SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP','IMPG','IMPS') then raise exception 'Invalid GST supply type';end if;
 if kind='sale' and supply in('IMPG','IMPS') then raise exception 'Import supply types are purchase-only';end if;
 if kind='purchase' and supply in('EXPWP','EXPWOP','DEXP') then raise exception 'Export/deemed-export supply types are sale-only';end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'GST quote requires at least one item';end if;
 if coalesce(p_additional_charges,0)<0 then raise exception 'Additional charges cannot be negative';end if;
 if abs(coalesce(p_round_off,0))>1.000001 then raise exception 'Round-off cannot exceed 1.00 in either direction';end if;
 select * into loc from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active;
 if not found then raise exception 'Active location not found';end if;
 select r.* into reg from public.gst_location_registrations_v520 m join public.gst_registrations_v520 r on r.id=m.registration_id and r.tenant_id=m.tenant_id where m.tenant_id=p_tenant_id and m.location_id=p_location_id and d between m.effective_from and coalesce(m.effective_to,'infinity'::date) order by m.effective_from desc limit 1;
 if reg.id is null then errors:=array_append(errors,'Location is not mapped to a GST registration for the document date');
 else
  if not reg.active or not(d between reg.effective_from and coalesce(reg.effective_to,'infinity'::date)) then errors:=array_append(errors,'Mapped GST registration is inactive for the document date');end if;
  if reg.validation_status not in('local_validated','provider_validated') or not coalesce((public.gst_gstin_validate_v520(reg.gstin)->>'structurally_valid')::boolean,false) or left(reg.gstin,2)<>reg.state_code then errors:=array_append(errors,'Supplier GSTIN requires validation and a matching state code');end if;
  select v.* into reg_cfg from public.gst_registration_versions_v520 v where v.tenant_id=p_tenant_id and v.registration_id=reg.id and d between v.effective_from and coalesce(v.effective_to,'infinity'::date) and v.active order by v.effective_from desc limit 1;
  if reg_cfg.id is null then errors:=array_append(errors,'Mapped GST registration has no active configuration version for the document date');
  elsif reg_cfg.validation_status not in('local_validated','provider_validated') or nullif(trim(reg_cfg.legal_name),'') is null or nullif(trim(reg_cfg.address_line1),'') is null then errors:=array_append(errors,'Supplier GST registration requires validated legal name and address');end if;
 end if;
 if p_party_id is not null then
  select * into party from public.gst_party_registrations_v520 g where g.tenant_id=p_tenant_id and g.party_type=v_party_type and g.party_id=p_party_id and g.active and d between g.effective_from and coalesce(g.effective_to,'infinity'::date) order by g.effective_from desc,g.created_at desc limit 1;
  if party.id is null then warnings:=array_append(warnings,'Party has no normalized GST profile for the document date');end if;
 end if;
 if kind='sale' then
  supplier_state:=reg.state_code;recipient_state:=party.state_code;
  if recipient_state is null and p_party_id is not null then select public.gst_state_code_resolve_v520(c.state) into recipient_state from public.customers c where c.id=p_party_id and c.tenant_id=p_tenant_id;end if;
  composition_supplier:=coalesce(reg_cfg.registration_type,reg.registration_type)='composition';
 else
  supplier_state:=party.state_code;
  if supplier_state is null and p_party_id is not null then select public.gst_state_code_resolve_v520(s.state) into supplier_state from public.suppliers s where s.id=p_party_id and s.tenant_id=p_tenant_id;end if;
  recipient_state:=reg.state_code;composition_supplier:=coalesce(party.registration_type,'')='composition';
 end if;
 if kind='sale' and supply in('EXPWP','EXPWOP') then pos:='96';zero_rated:=true;without_payment:=supply='EXPWOP';party_required:=false;
 elsif kind='sale' and supply in('SEZWP','SEZWOP') then pos:=coalesce(pos,party.place_of_supply_code,party.state_code);zero_rated:=true;without_payment:=supply='SEZWOP';party_required:=true;
 elsif kind='sale' and supply='DEXP' then deemed_export:=true;pos:=coalesce(pos,party.place_of_supply_code,party.state_code,recipient_state);party_required:=true;
 elsif kind='purchase' and supply in('IMPG','IMPS') then pos:=coalesce(pos,recipient_state);party_required:=false;
 else
  if pos is null then pos:=case when kind='sale' then coalesce(party.place_of_supply_code,party.state_code,recipient_state) else coalesce(recipient_state,party.place_of_supply_code) end;end if;
 end if;
 if supplier_state is null and not(kind='purchase' and supply in('IMPG','IMPS')) then errors:=array_append(errors,'Supplier GST state is unresolved');end if;
 if recipient_state is null and kind='purchase' then errors:=array_append(errors,'Recipient/THQ GST state is unresolved');end if;
 if pos is null then errors:=array_append(errors,'Place of Supply is unresolved');end if;
 if pos is not null and not exists(select 1 from public.gst_state_master_v520 s where s.code=pos and s.active) then errors:=array_append(errors,'Place of Supply code is not an active GST state/special code');end if;
 party_required:=party_required or supply in('B2B','SEZWP','SEZWOP');
 party_valid:=party.id is not null and party.validation_status in('local_validated','provider_validated','not_applicable');
 if party_required and (not coalesce((public.gst_gstin_validate_v520(party.gstin)->>'structurally_valid')::boolean,false) or left(party.gstin,2) is distinct from party.state_code) then errors:=array_append(errors,'Recipient GSTIN requires validation and a matching state code');end if;
 if party_required and not party_valid then errors:=array_append(errors,'Normalized GST party profile is required for this supply type');end if;
 if kind='sale' and supply='B2B' and coalesce(party.registration_type,'') not in('registered','composition','sez') then errors:=array_append(errors,'B2B sale requires a registered recipient GST profile');end if;
 if kind='sale' and supply in('SEZWP','SEZWOP') and coalesce(party.registration_type,'')<>'sez' then errors:=array_append(errors,'SEZ supply requires an SEZ recipient profile');end if;
 if kind='purchase' and supply='B2B' and p_party_id is null then errors:=array_append(errors,'B2B purchase requires a supplier');end if;
 if kind='purchase' and supply in('IMPG','IMPS') then interstate:=true;
 elsif kind='sale' and supply in('SEZWP','SEZWOP','EXPWP','EXPWOP') then interstate:=true;
 else interstate:=case when supplier_state is null or pos is null then null else supplier_state<>pos end;
 end if;
 select coalesce(s.uses_utgst,false) into local_uses_utgst from public.gst_state_master_v520 s where s.code=supplier_state;
 local_tax_name:=case when local_uses_utgst then 'UTGST' else 'SGST' end;
 if composition_supplier then
  document_class:='bill_of_supply';
  if kind='sale' and interstate is true then errors:=array_append(errors,'Composition taxpayer cannot use this outward inter-State tax calculation path');end if;
  if kind='sale' and supply in('SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') then errors:=array_append(errors,'Composition taxpayer cannot use export/SEZ/deemed-export tax invoice path');end if;
 end if;
 for x in select value from jsonb_array_elements(p_items) loop
  begin variant:=(x->>'variant_id')::uuid;qty:=coalesce(nullif(x->>'quantity','')::numeric,0);price:=coalesce(nullif(x->>'unit_price','')::numeric,nullif(x->>'unit_cost','')::numeric,0);discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);exception when others then raise exception 'Invalid GST quote item';end;
  if variant is null or qty<=0 or price<0 or discount<0 then raise exception 'GST quote item has invalid product/quantity/price/discount';end if;
  select p.id product_id,p.name,p.item_type,p.tax_rate,pv.name variant_name,pv.sku,a.hsn_sac legacy_hsn into prod from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id left join public.product_invoice_attributes_v45 a on a.tenant_id=pv.tenant_id and a.variant_id=pv.id where pv.id=variant and pv.tenant_id=p_tenant_id and pv.status='active' and p.status='active';
  if not found then raise exception 'GST quote product is invalid or inactive';end if;
  select * into prof from private.gst_profile_for_variant_v520(p_tenant_id,variant,d);
  if prof.id is null then
   v_rate:=coalesce(prod.tax_rate,0);cess_rate:=0;cess_unit:=0;inclusive:=false;rcm:=false;taxability:='taxable';hsn:=prod.legacy_hsn;supply_kind:=case when prod.item_type='service' then 'service' else 'goods' end;profile_source:='legacy_product';profile_status:='review_required';warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');errors:=array_append(errors,'Product '||prod.sku||' has no validated GST profile; review and validate the product GST profile before compliance posting');
  else
   v_rate:=prof.gst_rate;cess_rate:=prof.cess_rate;cess_unit:=prof.cess_per_unit;inclusive:=prof.tax_inclusive;rcm:=prof.reverse_charge;taxability:=prof.taxability;hsn:=prof.hsn_sac;supply_kind:=prof.supply_kind;profile_source:=prof.source;profile_status:=prof.validation_status;
   if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');errors:=array_append(errors,'Product '||prod.sku||' GST profile requires review and validation before compliance posting');end if;
  end if;
  -- An invoice-specific adjustment never changes the product's master GST profile.
  if x ? 'thq_tax_override_v630' then
   if kind<>'sale' or not private.erp_has_permission(p_tenant_id,'sales.tax_override') then raise exception 'Invoice tax adjustment permission required' using errcode='42501';end if;
   if jsonb_typeof(x->'thq_tax_override_v630')<>'object' then raise exception 'Invalid invoice tax adjustment';end if;
   v_rate:=(x->'thq_tax_override_v630'->>'gst_rate')::numeric;
   if v_rate is null or v_rate<0 or v_rate>100 then raise exception 'Invoice GST rate must be between 0 and 100';end if;
   profile_source:='invoice_override_v630';
  end if;
  if supply_kind='service' then has_service:=true;end if;if rcm then has_rcm:=true;end if;
  if nullif(trim(hsn),'') is null then errors:=array_append(errors,'Product '||prod.sku||' is missing HSN/SAC');
  elsif (supply_kind='service' and hsn!~'^[0-9]{6}$') or (supply_kind<>'service' and hsn!~'^([0-9]{4}|[0-9]{6}|[0-9]{8})$') then errors:=array_append(errors,'Product '||prod.sku||' has an invalid HSN/SAC format');end if;
  rate_valid:=taxability<>'taxable' or exists(select 1 from public.gst_tax_rate_master_v520 tr where tr.rate=v_rate and tr.active and d between tr.effective_from and coalesce(tr.effective_to,'infinity'::date));
  if not rate_valid then errors:=array_append(errors,'Product '||prod.sku||' GST rate is not in the active GST rate master for the document date');end if;
  gross:=round(qty*price,4);if discount>gross then raise exception 'GST quote discount exceeds line value';end if;gross:=gross-discount;
  applied_rate:=v_rate;applied_cess_rate:=cess_rate;applied_cess_unit:=cess_unit;
  if taxability<>'taxable' or without_payment or(composition_supplier and not rcm) then applied_rate:=0;applied_cess_rate:=0;applied_cess_unit:=0;end if;
  fixed_cess:=round(qty*applied_cess_unit,4);
  if rcm and inclusive then warnings:=array_append(warnings,'Product '||prod.sku||' is reverse-charge and tax-inclusive; price is treated as taxable value because recipient liability is not collected by supplier');end if;
  if inclusive and not rcm and(applied_rate+applied_cess_rate)>0 then
   if gross<fixed_cess then raise exception 'Tax-inclusive line value is lower than fixed cess';end if;
   taxable:=round((gross-fixed_cess)*100/(100+applied_rate+applied_cess_rate),4);
  else taxable:=round(gross,4);end if;
  raw_cgst:=0;raw_sgst:=0;raw_utgst:=0;raw_igst:=0;raw_cess:=round(taxable*applied_cess_rate/100+fixed_cess,2);
  if applied_rate>0 then
   if interstate is true then raw_igst:=round(taxable*applied_rate/100,2);
   elsif interstate is false then raw_cgst:=round(taxable*(applied_rate/2)/100,2);if local_uses_utgst then raw_utgst:=round(taxable*(applied_rate/2)/100,2);else raw_sgst:=round(taxable*(applied_rate/2)/100,2);end if;
   end if;
  end if;
  if rcm then cgst:=0;sgst:=0;utgst:=0;igst:=0;cess:=0;rcm_cgst:=raw_cgst;rcm_sgst:=raw_sgst;rcm_utgst:=raw_utgst;rcm_igst:=raw_igst;rcm_cess:=raw_cess;
  else cgst:=raw_cgst;sgst:=raw_sgst;utgst:=raw_utgst;igst:=raw_igst;cess:=raw_cess;rcm_cgst:=0;rcm_sgst:=0;rcm_utgst:=0;rcm_igst:=0;rcm_cess:=0;end if;
  collected_tax:=cgst+sgst+utgst+igst+cess;rcm_tax:=rcm_cgst+rcm_sgst+rcm_utgst+rcm_igst+rcm_cess;
  line_total:=case when inclusive and not rcm then round(gross,2) else round(taxable+collected_tax,2) end;calculation_rounding:=round(line_total-round(taxable+collected_tax,2),2);line_total_sum:=line_total_sum+line_total;calculation_rounding_total:=calculation_rounding_total+calculation_rounding;
  subtotal:=subtotal+round(qty*price,4);discount_total:=discount_total+discount;taxable_total:=taxable_total+taxable;cgst_total:=cgst_total+cgst;sgst_total:=sgst_total+sgst;utgst_total:=utgst_total+utgst;igst_total:=igst_total+igst;cess_total:=cess_total+cess;rcm_cgst_total:=rcm_cgst_total+rcm_cgst;rcm_sgst_total:=rcm_sgst_total+rcm_sgst;rcm_utgst_total:=rcm_utgst_total+rcm_utgst;rcm_igst_total:=rcm_igst_total+rcm_igst;rcm_cess_total:=rcm_cess_total+rcm_cess;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',variant,'product_id',prod.product_id,'product_name',coalesce(nullif(trim(x->>'invoice_description'),''),prod.name),'variant_name',prod.variant_name,'sku',prod.sku,'supply_kind',supply_kind,'hsn_sac',hsn,'quantity',qty,'unit_price',price,'discount',discount,'taxability',taxability,'tax_inclusive',inclusive,'reverse_charge',rcm,'gst_rate',v_rate,'applied_gst_rate',applied_rate,'cess_rate',cess_rate,'applied_cess_rate',applied_cess_rate,'cess_per_unit',cess_unit,'applied_cess_per_unit',applied_cess_unit,'taxable_value',round(taxable,2),'cgst',cgst,'sgst',sgst,'utgst',utgst,'igst',igst,'cess',cess,'tax_amount',round(collected_tax,2),'rcm_cgst',rcm_cgst,'rcm_sgst',rcm_sgst,'rcm_utgst',rcm_utgst,'rcm_igst',rcm_igst,'rcm_cess',rcm_cess,'rcm_tax_amount',round(rcm_tax,2),'rcm_liability_party',case when rcm then case when kind='sale' then 'recipient' else 'thq' end else null end,'line_total',line_total,'calculation_rounding',calculation_rounding,'profile_source',profile_source,'profile_status',profile_status));
 end loop;
 if has_rcm and kind='sale' and (party.id is null or party.registration_type not in('registered','composition','sez')) then errors:=array_append(errors,'Outward reverse-charge supply requires a normalized registered recipient GST profile');end if;if has_service and p_place_of_supply_code is null and supply not in('EXPWP','EXPWOP','SEZWP','SEZWOP','IMPS') then errors:=array_append(errors,'Service supply requires explicit Place of Supply until service-specific place-of-supply rules are configured');end if;
 if coalesce(p_additional_charges,0)<>0 then errors:=array_append(errors,'Additional charges must be tax-classified before GST compliance posting; unclassified additional charges are not tax-calculated');end if;
 grand:=round(line_total_sum+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);
 ready:=cardinality(errors)=0 and reg.id is not null and reg_cfg.id is not null and not exists(select 1 from jsonb_array_elements(lines) j(value) where j.value->>'profile_status'='review_required');
 return jsonb_build_object('engine','gst_v520_document_1','document_kind',kind,'document_class',document_class,'document_date',d,'supply_type',supply,'supplier_registration_id',case when kind='sale' then reg.id else null end,'supplier_gstin',case when kind='sale' then reg.gstin else party.gstin end,'supplier_legal_name',case when kind='sale' then reg_cfg.legal_name else party.legal_name end,'supplier_address',case when kind='sale' then concat_ws(', ',reg_cfg.address_line1,reg_cfg.address_line2,reg_cfg.city,reg.state_code,reg_cfg.postal_code) else concat_ws(', ',party.address_line1,party.address_line2,party.city,party.state_code,party.postal_code) end,'supplier_state_code',supplier_state,'recipient_registration_id',case when kind='purchase' then reg.id else null end,'recipient_gstin',case when kind='purchase' then reg.gstin else party.gstin end,'recipient_state_code',recipient_state,'party_profile_id',party.id,'place_of_supply_code',pos,'interstate',interstate,'local_tax_name',local_tax_name,'zero_rated',zero_rated,'without_payment',without_payment,'deemed_export',deemed_export,'composition_supplier',composition_supplier,'lines',lines,'totals',jsonb_build_object('subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),'tax_collected_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),'rcm_cgst',round(rcm_cgst_total,2),'rcm_sgst',round(rcm_sgst_total,2),'rcm_utgst',round(rcm_utgst_total,2),'rcm_igst',round(rcm_igst_total,2),'rcm_cess',round(rcm_cess_total,2),'rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'thq_rcm_tax_payable_total',case when kind='purchase' then round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2) else 0 end,'recipient_rcm_tax_payable_total',case when kind='sale' then round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2) else 0 end,'government_tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total+rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'additional_charges',round(coalesce(p_additional_charges,0),2),'round_off',round(coalesce(p_round_off,0),2),'calculation_rounding',round(calculation_rounding_total,2),'grand_total',grand),'ready_for_compliance',ready,'warnings',to_jsonb(warnings),'errors',to_jsonb(errors));
end $function$;

CREATE OR REPLACE FUNCTION public.sales_get_detail_v520(p_tenant_id uuid, p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_gst jsonb;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
begin
  v_result:=public.sales_get_detail_v495(p_tenant_id,p_sale_id);

  select s.grand_total into v_total
  from public.sales s
  where s.tenant_id=p_tenant_id and s.id=p_sale_id;

  select coalesce(sum(sp.amount),0) into v_paid
  from public.sale_payments sp
  where sp.tenant_id=p_tenant_id and sp.sale_id=p_sale_id;

  select coalesce(sum(sr.grand_total),0) into v_returned
  from public.sales_returns sr
  where sr.tenant_id=p_tenant_id
    and sr.sale_id=p_sale_id
    and sr.refund_status<>'waived';

  v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);

  v_result:=v_result||jsonb_build_object(
    'paid_amount',round(v_paid,2),
    'returned_amount',round(v_returned,2),
    'net_document_total',round(greatest(v_total-v_returned,0),2),
    'balance_due',v_balance,
    'return_adjusted',true
  );

  select jsonb_build_object(
    'authoritative',true,
    'snapshot_id',s.id,
    'document_class',s.document_class,
    'tax_mode',s.tax_mode,
    'supply_type',s.supply_type,
    'interstate',s.interstate,
    'place_of_supply_code',s.place_of_supply_code,
    'supplier_gstin',s.supplier_gstin,
    'supplier_legal_name',s.quote_payload->>'supplier_legal_name',
    'supplier_address',s.quote_payload->>'supplier_address',
    'has_reverse_charge',exists(select 1 from public.gst_document_line_snapshots_v520 l where l.snapshot_id=s.id and l.reverse_charge),
    'recipient_gstin',s.recipient_gstin,
    'taxable_total',s.taxable_total,
    'cgst_total',s.cgst_total,
    'sgst_total',s.sgst_total,
    'utgst_total',s.utgst_total,
    'igst_total',s.igst_total,
    'cess_total',s.cess_total,
    'tax_collected_total',s.tax_collected_total,
    'government_tax_total',s.government_tax_total,
    'lines',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'source_line_id',l.source_line_id,
          'line_no',l.line_no,
          'hsn_sac',l.hsn_sac,
          'gst_rate',l.applied_gst_rate,
          'taxable_value',l.taxable_value,
          'cgst',l.cgst,
          'sgst',l.sgst,
          'utgst',l.utgst,
          'igst',l.igst,
          'cess',l.cess,
          'tax_amount',l.tax_amount,
          'reverse_charge',l.reverse_charge
        ) order by l.line_no
      )
      from public.gst_document_line_snapshots_v520 l
      where l.snapshot_id=s.id
    ),'[]'::jsonb)
  )
  into v_gst
  from public.gst_document_snapshots_v520 s
  where s.tenant_id=p_tenant_id
    and s.source_type='sale'
    and s.source_id=p_sale_id
  order by s.created_at desc
  limit 1;

  return v_result||jsonb_build_object('gst',v_gst);
end;
$function$;

create or replace function public.sales_invoice_context_v632(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_sale_date date,p_load_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $fn$
declare m text;l public.aggregate_loads_v617%rowtype;
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) or not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales permission required' using errcode='42501';end if;
 perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
 if p_sale_date is null then raise exception 'Invoice date is required';end if;
 m:=private.gst_tax_mode_resolve_v520(p_tenant_id,p_sale_date);
 if m='unconfigured' then raise exception 'GST registration was detected. Complete the business GST setup for this invoice date before billing';end if;
 if p_load_id is not null then l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);end if;
 return jsonb_build_object('tax_mode',m,'gst_applicable',m='gst_registered','locked_customer_id',l.customer_id,'sale_date',p_sale_date,'load_id',p_load_id);
end $fn$;

revoke all on function private.invoice_calculate_allowed_v632(uuid,date,text) from public,anon,authenticated;

revoke all on function private.sale_items_for_tax_mode_v632(uuid,date,jsonb) from public,anon,authenticated;

revoke all on function private.sale_default_legal_number_v632(uuid,uuid,uuid,text,date) from public,anon,authenticated;

revoke all on function public.sales_invoice_context_v632(uuid,uuid,uuid,date,uuid) from public,anon;

grant execute on function public.sales_invoice_context_v632(uuid,uuid,uuid,date,uuid) to authenticated,service_role;
;

