-- Match billing units to physical loads and preserve tax-exclusive charge entry.

create or replace function private.load_sale_items_v630(t uuid,load uuid,items jsonb,document_date date)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;extra jsonb;factor numeric;invoiced numeric;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
 if not found then raise exception 'Load not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,false);
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items)=0 then raise exception 'Invoice items are required';end if;
 if not exists(select 1 from jsonb_array_elements(items) x where (x->>'variant_id')::uuid=l.variant_id) then raise exception 'The invoice must include the load material';end if;
 select pu.conversion_to_base into factor from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id and u.tenant_id=pu.tenant_id where pu.tenant_id=t and pu.variant_id=l.variant_id and pu.active and upper(u.code)=upper(l.unit_code);
 select sum((private.v481_normalize_line(t,x,'sale')->>'quantity')::numeric) into invoiced from jsonb_array_elements(items) x where (x->>'variant_id')::uuid=l.variant_id;
 if factor is null or abs(invoiced-l.quantity*factor)>.000001 then raise exception 'The invoice material quantity must match the confirmed load after unit conversion. Correct the load before confirmation or choose the equivalent sale quantity and unit.';end if;
 if exists(select 1 from public.material_load_costs_v630 c join lateral private.gst_profile_for_variant_v520(t,c.billing_variant_id,document_date) g on true where c.tenant_id=t and c.load_id=load and c.status='posted' and c.bill_amount>0 and g.tax_inclusive) then raise exception 'Load customer charges are entered before GST. Select a tax-exclusive service or create a separate invoice charge service.';end if;

 if exists(select 1 from public.material_load_costs_v630 c join jsonb_array_elements(items) x on (x->>'variant_id')::uuid=c.billing_variant_id where c.tenant_id=t and c.load_id=load and c.status='posted' and c.bill_amount>0) then raise exception 'A load billing service is already an invoice product; select a separate billing service for the load charges';end if;
 select coalesce(jsonb_agg(jsonb_build_object('variant_id',c.billing_variant_id,'unit_id',(select unit_id from public.product_units_v481 pu where pu.tenant_id=t and pu.variant_id=c.billing_variant_id and pu.is_base and pu.active and pu.allow_sale limit 1),'quantity',1,'unit_price',c.bill_amount,'discount_amount',0,'tax_rate',0,'invoice_description',c.description,'material_cost_ids',c.ids) order by c.description),'[]'::jsonb)
 into extra from (select billing_variant_id,sum(bill_amount) bill_amount,string_agg(description,'; ' order by created_at,id) description,jsonb_agg(id order by created_at,id) ids from public.material_load_costs_v630 where tenant_id=t and load_id=load and status='posted' and bill_amount>0 group by billing_variant_id) c;
 return items||extra;
end $$;

create or replace function public.client_sale_quote_v630(
 p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_items jsonb,p_location_id uuid,p_device_id uuid,
 p_supply_type text default null,p_place_of_supply_code text default null,p_charge_selections jsonb default '[]'::jsonb,p_load_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare items jsonb:=p_items;commercial jsonb;quote jsonb;base_subtotal numeric;load_charges numeric:=0;totals jsonb;rounding numeric;supply text;pos text;normalized jsonb;l public.aggregate_loads_v617%rowtype;
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied' using errcode='42501';end if;
 perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
 if p_load_id is not null then
  l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
  items:=private.load_sale_items_v630(p_tenant_id,p_load_id,items,p_sale_date);
  select coalesce(sum(bill_amount),0) into load_charges from public.material_load_costs_v630 where tenant_id=p_tenant_id and load_id=p_load_id and status='posted';
 end if;
 if not public.sales_additional_charges_enabled_v611(p_tenant_id) and jsonb_array_length(p_charge_selections)>0 then raise exception 'Additional charges are disabled in Business Settings';end if;
 if private.gst_tax_mode_resolve_v520(p_tenant_id,p_sale_date)='non_gst' and exists(select 1 from jsonb_array_elements(items) x where coalesce((x->'thq_tax_override_v630'->>'gst_rate')::numeric,0)<>0) then raise exception 'A Non-GST invoice must have zero GST';end if;
 commercial:=private.sales_commercial_expand_v610(p_tenant_id,'sale',items,'none',0,p_charge_selections);
 normalized:=private.v481_normalize_items(p_tenant_id,private.v482_price_sale_items(p_tenant_id,p_customer_id,commercial->'items',p_location_id),'sale');
 supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,p_customer_id,p_sale_date,p_supply_type);
 pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,p_customer_id,p_location_id,p_sale_date,supply,normalized,p_place_of_supply_code);
 quote:=public.gst_quote_v520(p_tenant_id,p_location_id,'customer',p_customer_id,p_sale_date,supply,pos,normalized,0,0);
 if coalesce((quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Invoice needs GST review: %',coalesce(quote->'errors','[]'::jsonb);end if;
 totals:=quote->'totals';rounding:=round(round((totals->>'grand_total')::numeric,0)-(totals->>'grand_total')::numeric,2);
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric) into base_subtotal from jsonb_array_elements(p_items) x;
 return jsonb_build_object('totals',totals||jsonb_build_object('subtotal',base_subtotal,'tax',(totals->>'tax_collected_total')::numeric,'before_round_off',(totals->>'grand_total')::numeric,'automatic_round_off',rounding,'grand_total',(totals->>'grand_total')::numeric+rounding),'classified_charge_total',load_charges+coalesce((commercial->>'classified_charge_total')::numeric,0),
  'gst',quote,'items',commercial->'items','charge_breakdown',commercial->'charge_breakdown','load_charge_total',load_charges);
end $$;

create or replace function public.aggregate_load_sale_create_v630(
 p_tenant_id uuid,p_load_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,
 p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text,p_supply_type text,p_place_of_supply_code text,p_charge_selections jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;result jsonb;items jsonb;id uuid;
begin
 l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
 perform private.load_costs_post_v630(p_tenant_id,p_load_id);
 items:=private.load_sale_items_v630(p_tenant_id,p_load_id,p_items,p_sale_date);
 result:=private.aggregate_load_sale_core_v630(p_tenant_id,p_load_id,p_customer_id,p_sale_date,p_due_date,items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
 id:=(result->>'sale_id')::uuid;
 insert into public.material_load_sale_snapshots_v630(sale_id,tenant_id,load_id,evidence)
 values(id,p_tenant_id,p_load_id,private.load_evidence_v630(p_tenant_id,p_load_id)||jsonb_build_object('invoice_items_entered',p_items,'invoice_terms_entered',jsonb_build_object('customer_id',p_customer_id,'sale_date',p_sale_date,'due_date',p_due_date,'notes',p_notes,'supply_type',p_supply_type,'place_of_supply_code',p_place_of_supply_code,'payment_allocations',p_payment_allocations,'charge_selections',p_charge_selections),'snapshot_at',now()))
 on conflict(sale_id) do nothing;
 return result||jsonb_build_object('load_costs_recorded',true);
end $$;
revoke all on function private.load_sale_items_v630(uuid,uuid,jsonb,date) from public,anon,authenticated;
