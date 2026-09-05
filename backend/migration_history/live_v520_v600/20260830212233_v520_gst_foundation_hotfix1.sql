begin;
create or replace function public.gst_quote_v520(
 p_tenant_id uuid,p_location_id uuid,p_party_type text,p_party_id uuid,p_document_date date,p_supply_type text,
 p_place_of_supply_code text,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0
) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
 d date:=coalesce(p_document_date,current_date);supply text:=upper(trim(coalesce(p_supply_type,'B2C')));v_party_type text:=lower(trim(coalesce(p_party_type,'customer')));
 reg public.gst_registrations_v520%rowtype;loc public.business_locations%rowtype;party public.gst_party_registrations_v520%rowtype;
 seller_state text;pos text:=nullif(trim(coalesce(p_place_of_supply_code,'')),'');seller_ut boolean:=false;interstate boolean;zero_rated boolean:=false;
 x jsonb;prof public.gst_product_tax_profiles_v520%rowtype;variant uuid;prod record;qty numeric;price numeric;discount numeric;gross numeric;taxable numeric;rate numeric;cess_rate numeric;cess_unit numeric;
 cgst numeric;sgst numeric;utgst numeric;igst numeric;cess numeric;gst_tax numeric;line_total numeric;
 lines jsonb:='[]'::jsonb;subtotal numeric:=0;discount_total numeric:=0;taxable_total numeric:=0;cgst_total numeric:=0;sgst_total numeric:=0;utgst_total numeric:=0;igst_total numeric:=0;cess_total numeric:=0;grand numeric;
 warnings text[]:='{}';errors text[]:='{}';profile_source text;profile_status text;hsn text;taxability text;inclusive boolean;rcm boolean;local_tax_name text;ready boolean;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required';end if;
 if supply not in('B2B','B2C','SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') then raise exception 'Invalid GST supply type';end if;
 if v_party_type not in('customer','supplier') then raise exception 'Party type must be customer or supplier';end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'GST quote requires at least one item';end if;
 select * into loc from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active;
 if not found then raise exception 'Active location not found';end if;
 select r.* into reg from public.gst_location_registrations_v520 m join public.gst_registrations_v520 r on r.id=m.registration_id
 where m.tenant_id=p_tenant_id and m.location_id=p_location_id and m.effective_from<=d and (m.effective_to is null or m.effective_to>=d) and r.active and r.effective_from<=d and (r.effective_to is null or r.effective_to>=d)
 order by m.effective_from desc limit 1;
 seller_state:=coalesce(reg.state_code,public.gst_state_code_resolve_v520(loc.state));
 if reg.id is null then warnings:=array_append(warnings,'Location is not mapped to a normalized GST registration');end if;
 if seller_state is null then errors:=array_append(errors,'Seller/location GST state is unresolved');end if;
 select coalesce(s.is_union_territory,false) into seller_ut from public.gst_state_master_v520 s where s.code=seller_state;
 if p_party_id is not null then
  select * into party from public.gst_party_registrations_v520 g where g.tenant_id=p_tenant_id and g.party_type=v_party_type and g.party_id=p_party_id and g.active and g.is_default and g.effective_from<=d and (g.effective_to is null or g.effective_to>=d) order by g.effective_from desc limit 1;
  if party.id is null then warnings:=array_append(warnings,'Party has no normalized GST profile; legacy address/state fallback is being used');end if;
 end if;
 if supply in('EXPWP','EXPWOP') then pos:='96';zero_rated:=true;
 elsif supply in('SEZWP','SEZWOP') then pos:=coalesce(pos,party.place_of_supply_code,party.state_code);zero_rated:=supply='SEZWOP';
 else
  if pos is null then pos:=coalesce(party.place_of_supply_code,party.state_code);end if;
  if pos is null and p_party_id is not null then
    if v_party_type='customer' then select public.gst_state_code_resolve_v520(c.state) into pos from public.customers c where c.id=p_party_id and c.tenant_id=p_tenant_id;
    else select public.gst_state_code_resolve_v520(s.state) into pos from public.suppliers s where s.id=p_party_id and s.tenant_id=p_tenant_id;end if;
  end if;
 end if;
 if pos is null then errors:=array_append(errors,'Place of Supply is unresolved');end if;
 if supply='B2B' and (party.id is null or party.registration_type not in('registered','composition')) then warnings:=array_append(warnings,'B2B quote does not have a validated registered buyer profile');end if;
 interstate:=case when supply in('SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') then true when seller_state is null or pos is null then null else seller_state<>pos end;
 local_tax_name:=case when seller_ut then 'UTGST' else 'SGST' end;
 for x in select value from jsonb_array_elements(p_items) loop
  begin variant:=(x->>'variant_id')::uuid;qty:=coalesce(nullif(x->>'quantity','')::numeric,0);price:=coalesce(nullif(x->>'unit_price','')::numeric,nullif(x->>'unit_cost','')::numeric,0);discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);exception when others then raise exception 'Invalid GST quote item';end;
  if variant is null or qty<=0 or price<0 or discount<0 then raise exception 'GST quote item has invalid product/quantity/price/discount';end if;
  select p.id product_id,p.name,p.item_type,p.tax_rate,pv.name variant_name,pv.sku,a.hsn_sac legacy_hsn into prod
  from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id left join public.product_invoice_attributes_v45 a on a.tenant_id=pv.tenant_id and a.variant_id=pv.id
  where pv.id=variant and pv.tenant_id=p_tenant_id and pv.status='active' and p.status='active';
  if not found then raise exception 'GST quote product is invalid or inactive';end if;
  select * into prof from private.gst_profile_for_variant_v520(p_tenant_id,variant,d);
  if prof.id is null then
    rate:=coalesce(prod.tax_rate,0);cess_rate:=0;cess_unit:=0;inclusive:=false;rcm:=false;taxability:='taxable';hsn:=prod.legacy_hsn;profile_source:='legacy_product';profile_status:='review_required';
    warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');
  else
    rate:=prof.gst_rate;cess_rate:=prof.cess_rate;cess_unit:=prof.cess_per_unit;inclusive:=prof.tax_inclusive;rcm:=prof.reverse_charge;taxability:=prof.taxability;hsn:=prof.hsn_sac;profile_source:=prof.source;profile_status:=prof.validation_status;
    if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');end if;
  end if;
  if hsn is null then warnings:=array_append(warnings,'Product '||prod.sku||' is missing HSN/SAC');end if;
  gross:=round(qty*price,4);if discount>gross then raise exception 'GST quote discount exceeds line value';end if;gross:=gross-discount;
  if taxability<>'taxable' or zero_rated then rate:=0;cess_rate:=0;cess_unit:=0;end if;
  if inclusive and (rate+cess_rate)>0 then taxable:=round(gross*100/(100+rate+cess_rate),4);else taxable:=round(gross,4);end if;
  cgst:=0;sgst:=0;utgst:=0;igst:=0;cess:=round(taxable*cess_rate/100+qty*cess_unit,2);
  if rate>0 then
    if interstate is true then igst:=round(taxable*rate/100,2);
    elsif interstate is false then
      cgst:=round(taxable*(rate/2)/100,2);
      if seller_ut then utgst:=round(taxable*(rate/2)/100,2);else sgst:=round(taxable*(rate/2)/100,2);end if;
    end if;
  end if;
  gst_tax:=cgst+sgst+utgst+igst;
  line_total:=case when inclusive then round(gross+qty*cess_unit,2) else round(taxable+gst_tax+cess,2) end;
  subtotal:=subtotal+round(qty*price,4);discount_total:=discount_total+discount;taxable_total:=taxable_total+taxable;cgst_total:=cgst_total+cgst;sgst_total:=sgst_total+sgst;utgst_total:=utgst_total+utgst;igst_total:=igst_total+igst;cess_total:=cess_total+cess;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',variant,'product_id',prod.product_id,'product_name',prod.name,'variant_name',prod.variant_name,'sku',prod.sku,'supply_kind',coalesce(prof.supply_kind,case when prod.item_type='service' then 'service' else 'goods' end),'hsn_sac',hsn,'quantity',qty,'unit_price',price,'discount',discount,'taxability',taxability,'tax_inclusive',inclusive,'reverse_charge',rcm,'gst_rate',rate,'cess_rate',cess_rate,'cess_per_unit',cess_unit,'taxable_value',round(taxable,2),'cgst',cgst,'sgst',sgst,'utgst',utgst,'igst',igst,'cess',cess,'tax_amount',round(gst_tax+cess,2),'line_total',line_total,'profile_source',profile_source,'profile_status',profile_status));
 end loop;
 grand:=round(taxable_total+cgst_total+sgst_total+utgst_total+igst_total+cess_total+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);
 ready:=cardinality(errors)=0 and reg.id is not null and not exists(select 1 from jsonb_array_elements(lines) as j(value) where j.value->>'profile_status'='review_required');
 return jsonb_build_object('engine','gst_v520','document_date',d,'supply_type',supply,'supplier_registration_id',reg.id,'supplier_gstin',reg.gstin,'supplier_state_code',seller_state,'place_of_supply_code',pos,'interstate',interstate,'local_tax_name',local_tax_name,'zero_rated',zero_rated,'party_profile_id',party.id,'party_gstin',party.gstin,'lines',lines,'totals',jsonb_build_object('subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),'tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),'additional_charges',round(coalesce(p_additional_charges,0),2),'round_off',round(coalesce(p_round_off,0),2),'grand_total',grand),'ready_for_compliance',ready,'warnings',to_jsonb(warnings),'errors',to_jsonb(errors));
end $$;
revoke all on function public.gst_quote_v520(uuid,uuid,text,uuid,date,text,text,jsonb,numeric,numeric) from public,anon;
grant execute on function public.gst_quote_v520(uuid,uuid,text,uuid,date,text,text,jsonb,numeric,numeric) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(215,'5.2.0-foundation','GST Foundation Hotfix 1','Repairs GST quote PL/pgSQL variable/column ambiguity discovered by rollback calculation matrix.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;