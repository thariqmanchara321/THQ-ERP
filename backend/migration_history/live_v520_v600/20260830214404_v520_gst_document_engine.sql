begin;
create or replace function public.gst_document_quote_v520(
  p_tenant_id uuid,p_document_kind text,p_location_id uuid,p_party_id uuid,p_document_date date,p_supply_type text,p_place_of_supply_code text,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0
) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
 d date:=coalesce(p_document_date,current_date);kind text:=lower(trim(coalesce(p_document_kind,'')));supply text:=upper(trim(coalesce(p_supply_type,case when lower(trim(coalesce(p_document_kind,'')))='purchase' then 'B2B' else 'B2C' end)));party_type text;
 loc public.business_locations%rowtype;reg public.gst_registrations_v520%rowtype;reg_cfg public.gst_registration_versions_v520%rowtype;party public.gst_party_registrations_v520%rowtype;
 supplier_state text;recipient_state text;pos text:=nullif(trim(coalesce(p_place_of_supply_code,'')),'');local_uses_utgst boolean:=false;interstate boolean;zero_rated boolean:=false;without_payment boolean:=false;deemed_export boolean:=false;composition_supplier boolean:=false;document_class text:='tax_invoice';
 x jsonb;prof public.gst_product_tax_profiles_v520%rowtype;variant uuid;prod record;qty numeric;price numeric;discount numeric;gross numeric;taxable numeric;rate numeric;cess_rate numeric;cess_unit numeric;fixed_cess numeric;applied_rate numeric;applied_cess_rate numeric;applied_cess_unit numeric;
 raw_cgst numeric;raw_sgst numeric;raw_utgst numeric;raw_igst numeric;raw_cess numeric;cgst numeric;sgst numeric;utgst numeric;igst numeric;cess numeric;rcm_cgst numeric;rcm_sgst numeric;rcm_utgst numeric;rcm_igst numeric;rcm_cess numeric;collected_tax numeric;rcm_tax numeric;line_total numeric;
 lines jsonb:='[]'::jsonb;subtotal numeric:=0;discount_total numeric:=0;taxable_total numeric:=0;cgst_total numeric:=0;sgst_total numeric:=0;utgst_total numeric:=0;igst_total numeric:=0;cess_total numeric:=0;rcm_cgst_total numeric:=0;rcm_sgst_total numeric:=0;rcm_utgst_total numeric:=0;rcm_igst_total numeric:=0;rcm_cess_total numeric:=0;grand numeric;
 warnings text[]:='{}';errors text[]:='{}';profile_source text;profile_status text;hsn text;taxability text;inclusive boolean;rcm boolean;supply_kind text;local_tax_name text;ready boolean;has_service boolean:=false;party_required boolean:=false;party_valid boolean:=false;rate_valid boolean;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required';end if;
 if kind not in('sale','purchase') then raise exception 'GST document kind must be sale or purchase';end if;
 party_type:=case when kind='sale' then 'customer' else 'supplier' end;
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
  select v.* into reg_cfg from public.gst_registration_versions_v520 v where v.tenant_id=p_tenant_id and v.registration_id=reg.id and d between v.effective_from and coalesce(v.effective_to,'infinity'::date) and v.active order by v.effective_from desc limit 1;
  if reg_cfg.id is null then errors:=array_append(errors,'Mapped GST registration has no active configuration version for the document date');end if;
 end if;
 if p_party_id is not null then
  select * into party from public.gst_party_registrations_v520 g where g.tenant_id=p_tenant_id and g.party_type=party_type and g.party_id=p_party_id and g.active and d between g.effective_from and coalesce(g.effective_to,'infinity'::date) order by g.effective_from desc,g.created_at desc limit 1;
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
   rate:=coalesce(prod.tax_rate,0);cess_rate:=0;cess_unit:=0;inclusive:=false;rcm:=false;taxability:='taxable';hsn:=prod.legacy_hsn;supply_kind:=case when prod.item_type='service' then 'service' else 'goods' end;profile_source:='legacy_product';profile_status:='review_required';warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');
  else
   rate:=prof.gst_rate;cess_rate:=prof.cess_rate;cess_unit:=prof.cess_per_unit;inclusive:=prof.tax_inclusive;rcm:=prof.reverse_charge;taxability:=prof.taxability;hsn:=prof.hsn_sac;supply_kind:=prof.supply_kind;profile_source:=prof.source;profile_status:=prof.validation_status;
   if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');end if;
  end if;
  if supply_kind='service' then has_service:=true;end if;
  if hsn is null then errors:=array_append(errors,'Product '||prod.sku||' is missing HSN/SAC');end if;
  rate_valid:=taxability<>'taxable' or exists(select 1 from public.gst_tax_rate_master_v520 tr where tr.rate=rate and tr.active and d between tr.effective_from and coalesce(tr.effective_to,'infinity'::date));
  if not rate_valid then errors:=array_append(errors,'Product '||prod.sku||' GST rate is not in the active GST rate master for the document date');end if;
  gross:=round(qty*price,4);if discount>gross then raise exception 'GST quote discount exceeds line value';end if;gross:=gross-discount;
  applied_rate:=rate;applied_cess_rate:=cess_rate;applied_cess_unit:=cess_unit;
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
  line_total:=case when inclusive and not rcm then round(gross,2) else round(taxable+collected_tax,2) end;
  subtotal:=subtotal+round(qty*price,4);discount_total:=discount_total+discount;taxable_total:=taxable_total+taxable;cgst_total:=cgst_total+cgst;sgst_total:=sgst_total+sgst;utgst_total:=utgst_total+utgst;igst_total:=igst_total+igst;cess_total:=cess_total+cess;rcm_cgst_total:=rcm_cgst_total+rcm_cgst;rcm_sgst_total:=rcm_sgst_total+rcm_sgst;rcm_utgst_total:=rcm_utgst_total+rcm_utgst;rcm_igst_total:=rcm_igst_total+rcm_igst;rcm_cess_total:=rcm_cess_total+rcm_cess;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',variant,'product_id',prod.product_id,'product_name',prod.name,'variant_name',prod.variant_name,'sku',prod.sku,'supply_kind',supply_kind,'hsn_sac',hsn,'quantity',qty,'unit_price',price,'discount',discount,'taxability',taxability,'tax_inclusive',inclusive,'reverse_charge',rcm,'gst_rate',rate,'applied_gst_rate',applied_rate,'cess_rate',cess_rate,'applied_cess_rate',applied_cess_rate,'cess_per_unit',cess_unit,'applied_cess_per_unit',applied_cess_unit,'taxable_value',round(taxable,2),'cgst',cgst,'sgst',sgst,'utgst',utgst,'igst',igst,'cess',cess,'tax_amount',round(collected_tax,2),'rcm_cgst',rcm_cgst,'rcm_sgst',rcm_sgst,'rcm_utgst',rcm_utgst,'rcm_igst',rcm_igst,'rcm_cess',rcm_cess,'rcm_tax_amount',round(rcm_tax,2),'line_total',line_total,'profile_source',profile_source,'profile_status',profile_status));
 end loop;
 if has_service and p_place_of_supply_code is null and supply not in('EXPWP','EXPWOP','SEZWP','SEZWOP','IMPS') then errors:=array_append(errors,'Service supply requires explicit Place of Supply until service-specific place-of-supply rules are configured');end if;
 if coalesce(p_additional_charges,0)<>0 then errors:=array_append(errors,'Additional charges must be tax-classified before GST compliance posting; unclassified additional charges are not tax-calculated');end if;
 grand:=round(taxable_total+cgst_total+sgst_total+utgst_total+igst_total+cess_total+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);
 ready:=cardinality(errors)=0 and reg.id is not null and reg_cfg.id is not null and not exists(select 1 from jsonb_array_elements(lines) j(value) where j.value->>'profile_status'='review_required');
 return jsonb_build_object('engine','gst_v520_document_1','document_kind',kind,'document_class',document_class,'document_date',d,'supply_type',supply,'supplier_registration_id',case when kind='sale' then reg.id else null end,'supplier_gstin',case when kind='sale' then reg.gstin else party.gstin end,'supplier_state_code',supplier_state,'recipient_registration_id',case when kind='purchase' then reg.id else null end,'recipient_gstin',case when kind='purchase' then reg.gstin else party.gstin end,'recipient_state_code',recipient_state,'party_profile_id',party.id,'place_of_supply_code',pos,'interstate',interstate,'local_tax_name',local_tax_name,'zero_rated',zero_rated,'without_payment',without_payment,'deemed_export',deemed_export,'composition_supplier',composition_supplier,'lines',lines,'totals',jsonb_build_object('subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),'tax_collected_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),'rcm_cgst',round(rcm_cgst_total,2),'rcm_sgst',round(rcm_sgst_total,2),'rcm_utgst',round(rcm_utgst_total,2),'rcm_igst',round(rcm_igst_total,2),'rcm_cess',round(rcm_cess_total,2),'rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'government_tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total+rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'additional_charges',round(coalesce(p_additional_charges,0),2),'round_off',round(coalesce(p_round_off,0),2),'grand_total',grand),'ready_for_compliance',ready,'warnings',to_jsonb(warnings),'errors',to_jsonb(errors));
end $$;
create or replace function public.gst_quote_v520(p_tenant_id uuid,p_location_id uuid,p_party_type text,p_party_id uuid,p_document_date date,p_supply_type text,p_place_of_supply_code text,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin if lower(trim(coalesce(p_party_type,'customer')))<> 'customer' then raise exception 'gst_quote_v520 is the sales/outward wrapper. Use gst_purchase_quote_v520 for suppliers/purchases';end if;return public.gst_document_quote_v520(p_tenant_id,'sale',p_location_id,p_party_id,p_document_date,p_supply_type,p_place_of_supply_code,p_items,p_additional_charges,p_round_off);end $$;
create or replace function public.gst_purchase_quote_v520(p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_document_date date,p_supply_type text,p_place_of_supply_code text,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0) returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$select public.gst_document_quote_v520($1,'purchase',$2,$3,$4,$5,$6,$7,$8,$9)$$;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(220,'5.2.0-foundation','Central GST Document Engine','Adds one provider-neutral sale/purchase GST calculation and validation engine with correct SGST/UTGST routing, zero-rated handling, composition Bill of Supply behavior, separate reverse-charge liability, inclusive/fixed-cess math, strict party/product readiness, and backward-compatible sales/purchase wrappers.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;