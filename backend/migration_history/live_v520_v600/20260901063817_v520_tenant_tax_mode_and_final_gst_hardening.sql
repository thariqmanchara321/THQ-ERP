-- THQ ERP v5.2 migration 253
-- Explicit tenant tax mode + authoritative Non-GST path + final GST table hardening.

create table if not exists public.gst_tenant_tax_modes_v520 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  tax_mode text not null check (tax_mode in ('gst_registered','non_gst')),
  effective_from date not null default current_date,
  effective_to date,
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint gst_tenant_tax_modes_v520_dates_check check (effective_to is null or effective_to >= effective_from)
);

create unique index if not exists uq_gst_tenant_tax_modes_v520_start
  on public.gst_tenant_tax_modes_v520(tenant_id,effective_from);
create unique index if not exists uq_gst_tenant_tax_modes_v520_open
  on public.gst_tenant_tax_modes_v520(tenant_id) where effective_to is null;

alter table public.gst_tenant_tax_modes_v520 enable row level security;
revoke all privileges on table public.gst_tenant_tax_modes_v520 from public, anon, authenticated;

-- Fix the one GST history table that remained directly exposed.
alter table public.gst_registration_versions_v520 enable row level security;
revoke all privileges on table public.gst_registration_versions_v520 from public, anon, authenticated;

-- Authoritative tax snapshots also represent deliberate Non-GST decisions.
alter table public.gst_document_snapshots_v520
  add column if not exists tax_mode text not null default 'gst_registered';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.gst_document_snapshots_v520'::regclass
      and conname='gst_document_snapshots_v520_tax_mode_check'
  ) then
    alter table public.gst_document_snapshots_v520
      add constraint gst_document_snapshots_v520_tax_mode_check
      check (tax_mode in ('gst_registered','non_gst'));
  end if;
end$$;

alter table public.gst_document_snapshots_v520
  alter column thq_registration_id drop not null;

alter table public.gst_document_snapshots_v520
  drop constraint if exists gst_document_snapshots_v520_document_class_check;
alter table public.gst_document_snapshots_v520
  add constraint gst_document_snapshots_v520_document_class_check
  check (document_class in ('tax_invoice','bill_of_supply','commercial_invoice','credit_note','debit_note'));

create or replace function private.gst_tax_mode_resolve_v520(
  p_tenant_id uuid,
  p_date date default current_date
) returns text
language sql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
  select coalesce((
    select m.tax_mode
    from public.gst_tenant_tax_modes_v520 m
    where m.tenant_id=p_tenant_id
      and coalesce(p_date,current_date) between m.effective_from and coalesce(m.effective_to,'infinity'::date)
    order by m.effective_from desc,m.created_at desc
    limit 1
  ),'unconfigured');
$function$;

revoke all on function private.gst_tax_mode_resolve_v520(uuid,date) from public, anon, authenticated;

create or replace function public.gst_tax_mode_get_v520(
  p_tenant_id uuid,
  p_date date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  r public.gst_tenant_tax_modes_v520%rowtype;
  d date:=coalesce(p_date,current_date);
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
     and not private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') then
    raise exception 'GST/tax configuration view permission required';
  end if;

  select * into r
  from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id=p_tenant_id
    and d between m.effective_from and coalesce(m.effective_to,'infinity'::date)
  order by m.effective_from desc,m.created_at desc
  limit 1;

  return jsonb_build_object(
    'tax_mode',coalesce(r.tax_mode,'unconfigured'),
    'configured',r.id is not null,
    'gst_applicable',coalesce(r.tax_mode,'unconfigured')='gst_registered',
    'effective_from',r.effective_from,
    'effective_to',r.effective_to,
    'reason',r.reason,
    'as_of',d
  );
end
$function$;

create or replace function public.gst_tax_mode_set_v520(
  p_tenant_id uuid,
  p_tax_mode text,
  p_effective_from date default current_date,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_mode text:=lower(trim(coalesce(p_tax_mode,'')));
  v_date date:=coalesce(p_effective_from,current_date);
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  cur public.gst_tenant_tax_modes_v520%rowtype;
  v_id uuid;
  v_before jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.configure') then
    raise exception 'GST/tax configuration permission required';
  end if;
  if v_mode not in ('gst_registered','non_gst') then
    raise exception 'Tax mode must be gst_registered or non_gst';
  end if;
  if not exists(select 1 from public.tenants t where t.id=p_tenant_id and t.status='active') then
    raise exception 'Active business not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':tax-mode-v520',0));

  if exists(
    select 1 from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id
      and s.document_date>=v_date
      and s.tax_mode<>v_mode
  ) then
    raise exception 'Tax mode cannot be changed across already-posted authoritative documents. Choose a later effective date.';
  end if;

  select * into cur
  from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id=p_tenant_id and m.effective_to is null
  order by m.effective_from desc
  limit 1
  for update;

  if cur.id is null then
    insert into public.gst_tenant_tax_modes_v520(tenant_id,tax_mode,effective_from,reason,created_by)
    values(p_tenant_id,v_mode,v_date,v_reason,auth.uid())
    returning id into v_id;
  elsif v_date<cur.effective_from then
    raise exception 'Effective date cannot precede the current tax-mode period (%)',cur.effective_from;
  elsif v_date=cur.effective_from then
    v_before:=to_jsonb(cur);
    update public.gst_tenant_tax_modes_v520
    set tax_mode=v_mode,reason=v_reason
    where id=cur.id
    returning id into v_id;
  elsif cur.tax_mode=v_mode then
    v_id:=cur.id;
  else
    v_before:=to_jsonb(cur);
    update public.gst_tenant_tax_modes_v520
      set effective_to=v_date-1
      where id=cur.id;
    insert into public.gst_tenant_tax_modes_v520(tenant_id,tax_mode,effective_from,reason,created_by)
    values(p_tenant_id,v_mode,v_date,v_reason,auth.uid())
    returning id into v_id;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,'gst.tax_mode.set','tenant',p_tenant_id,v_mode,
    v_before,
    (select to_jsonb(m) from public.gst_tenant_tax_modes_v520 m where m.id=v_id)
  );

  return public.gst_tax_mode_get_v520(p_tenant_id,v_date);
end
$function$;

revoke all on function public.gst_tax_mode_get_v520(uuid,date) from public, anon;
revoke all on function public.gst_tax_mode_set_v520(uuid,text,date,text) from public, anon;
grant execute on function public.gst_tax_mode_get_v520(uuid,date) to authenticated;
grant execute on function public.gst_tax_mode_set_v520(uuid,text,date,text) to authenticated;

create or replace function private.gst_document_quote_non_gst_v520(
  p_tenant_id uuid,
  p_document_kind text,
  p_location_id uuid,
  p_party_id uuid,
  p_document_date date,
  p_supply_type text,
  p_place_of_supply_code text,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
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
      'product_name',prod.name,
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

revoke all on function private.gst_document_quote_non_gst_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) from public, anon, authenticated;

create or replace function private.gst_snapshot_create_non_gst_v520(
  p_tenant_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_source_number text,
  p_location_id uuid,
  p_document_date date,
  p_quote jsonb,
  p_source_line_ids jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  q jsonb:=coalesce(p_quote,'{}'::jsonb);
  totals jsonb:=coalesce(p_quote->'totals','{}'::jsonb);
  lines jsonb:=coalesce(p_quote->'lines','[]'::jsonb);
  links jsonb:=coalesce(p_source_line_ids,'[]'::jsonb);
  line jsonb;
  v_id uuid:=gen_random_uuid();
  v_kind text:=q->>'document_kind';
  v_class text:=q->>'document_class';
  v_direction text;
  v_hash text;
  v_line_source uuid;
  i integer:=0;
  s_subtotal numeric:=0;
  s_discount numeric:=0;
  s_base numeric:=0;
  s_line_total numeric:=0;
  t_subtotal numeric:=coalesce((totals->>'subtotal')::numeric,0);
  t_discount numeric:=coalesce((totals->>'discount')::numeric,0);
  t_base numeric:=coalesce((totals->>'taxable_value')::numeric,0);
  t_additional numeric:=coalesce((totals->>'additional_charges')::numeric,0);
  t_round numeric:=coalesce((totals->>'round_off')::numeric,0);
  t_grand numeric:=coalesce((totals->>'grand_total')::numeric,0);
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if q->>'tax_mode'<>'non_gst' then raise exception 'Non-GST snapshot requires an explicit Non-GST quote'; end if;
  if coalesce((q->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Authoritative Non-GST quote is not ready'; end if;
  if v_kind not in ('sale','purchase') then raise exception 'Invalid authoritative tax document kind'; end if;
  if v_class not in ('commercial_invoice','credit_note','debit_note') then raise exception 'Invalid Non-GST document class'; end if;
  if p_source_type not in ('sale','purchase','sales_return','purchase_return','purchase_invoice_v484','credit_note','debit_note') then raise exception 'Unsupported authoritative snapshot source type'; end if;
  if p_source_id is null or nullif(trim(coalesce(p_source_number,'')),'') is null or p_location_id is null or p_document_date is null then
    raise exception 'Authoritative snapshot source id/number/date/location required';
  end if;
  if jsonb_typeof(lines)<>'array' or jsonb_array_length(lines)=0 then raise exception 'Authoritative Non-GST snapshot requires quote lines'; end if;
  if jsonb_typeof(links)<>'array' or jsonb_array_length(links)<>jsonb_array_length(lines) then raise exception 'Authoritative snapshot requires one source line id for every quote line'; end if;
  if exists(select 1 from jsonb_array_elements_text(links) x where nullif(x,'') is null) then raise exception 'Authoritative snapshot source line ids cannot be blank'; end if;
  if exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.source_type=p_source_type and s.source_id=p_source_id) then raise exception 'Authoritative snapshot already exists for source document'; end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type=p_source_type and m.source_id=p_source_id) then raise exception 'Legacy-unverified evidence cannot be replaced by an authoritative Non-GST snapshot'; end if;

  perform private.gst_source_assert_v520(p_tenant_id,p_source_type,p_source_id,trim(p_source_number),p_document_date,p_location_id,links);

  for line in select value from jsonb_array_elements(lines) loop
    if coalesce((line->>'quantity')::numeric,0)<=0 then raise exception 'Authoritative Non-GST line quantity must be positive'; end if;
    if coalesce(line->>'taxability','')<>'non_gst' then raise exception 'Non-GST snapshot line must be classified non_gst'; end if;
    if abs(coalesce((line->>'cgst')::numeric,0))+abs(coalesce((line->>'sgst')::numeric,0))+abs(coalesce((line->>'utgst')::numeric,0))+
       abs(coalesce((line->>'igst')::numeric,0))+abs(coalesce((line->>'cess')::numeric,0))+abs(coalesce((line->>'tax_amount')::numeric,0))+
       abs(coalesce((line->>'rcm_cgst')::numeric,0))+abs(coalesce((line->>'rcm_sgst')::numeric,0))+abs(coalesce((line->>'rcm_utgst')::numeric,0))+
       abs(coalesce((line->>'rcm_igst')::numeric,0))+abs(coalesce((line->>'rcm_cess')::numeric,0))+abs(coalesce((line->>'rcm_tax_amount')::numeric,0)) > 0.0001 then
      raise exception 'Non-GST snapshot cannot contain GST/cess/RCM amounts';
    end if;
    s_subtotal:=s_subtotal+round(coalesce((line->>'quantity')::numeric,0)*coalesce((line->>'unit_price')::numeric,0),4);
    s_discount:=s_discount+coalesce((line->>'discount')::numeric,0);
    s_base:=s_base+coalesce((line->>'taxable_value')::numeric,0);
    s_line_total:=s_line_total+coalesce((line->>'line_total')::numeric,0);
  end loop;

  if abs(round(s_subtotal,2)-round(t_subtotal,2))>0.011
     or abs(round(s_discount,2)-round(t_discount,2))>0.011
     or abs(round(s_base,2)-round(t_base,2))>0.011 then
    raise exception 'Authoritative Non-GST commercial totals do not reconcile to lines';
  end if;
  if abs(coalesce((totals->>'tax_collected_total')::numeric,0))>0.0001
     or abs(coalesce((totals->>'government_tax_total')::numeric,0))>0.0001
     or abs(coalesce((totals->>'rcm_tax_payable_total')::numeric,0))>0.0001 then
    raise exception 'Non-GST snapshot header cannot contain GST liability';
  end if;
  if abs(round(s_line_total+t_additional+t_round,2)-round(t_grand,2))>0.011 then
    raise exception 'Authoritative Non-GST grand total does not reconcile';
  end if;

  v_direction:=case when v_kind='sale' then 'outward' else 'inward' end;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tenant_id',p_tenant_id,'tax_mode','non_gst','source_type',p_source_type,'source_id',p_source_id,
    'source_number',trim(p_source_number),'document_date',p_document_date,'location_id',p_location_id,
    'source_line_ids',links,'quote',q)::text,'UTF8'),'sha256'),'hex');

  insert into public.gst_document_snapshots_v520(
    id,tenant_id,source_type,source_id,source_number,direction,document_kind,document_class,document_date,location_id,
    thq_registration_id,supplier_gstin,supplier_state_code,recipient_gstin,recipient_state_code,place_of_supply_code,
    supply_type,interstate,zero_rated,without_payment,deemed_export,composition_supplier,
    subtotal,discount_total,taxable_total,cgst_total,sgst_total,utgst_total,igst_total,cess_total,tax_collected_total,
    rcm_cgst_total,rcm_sgst_total,rcm_utgst_total,rcm_igst_total,rcm_cess_total,rcm_tax_payable_total,government_tax_total,
    additional_charges,calculation_rounding,round_off,grand_total,engine_version,quote_payload,snapshot_hash,created_by,tax_mode
  ) values(
    v_id,p_tenant_id,p_source_type,p_source_id,trim(p_source_number),v_direction,v_kind,v_class,p_document_date,p_location_id,
    null,null,null,null,null,null,
    'NON_GST',false,false,false,false,false,
    t_subtotal,t_discount,t_base,0,0,0,0,0,0,
    0,0,0,0,0,0,0,
    t_additional,0,t_round,t_grand,q->>'engine',q,v_hash,auth.uid(),'non_gst'
  );

  for line in select value from jsonb_array_elements(lines) loop
    i:=i+1;
    v_line_source:=(links->>(i-1))::uuid;
    insert into public.gst_document_line_snapshots_v520(
      tenant_id,snapshot_id,line_no,source_line_id,variant_id,product_name,variant_name,sku,supply_kind,hsn_sac,
      quantity,unit_price,discount_amount,taxability,tax_inclusive,reverse_charge,gst_rate,applied_gst_rate,
      cess_rate,applied_cess_rate,cess_per_unit,applied_cess_per_unit,taxable_value,cgst,sgst,utgst,igst,cess,tax_amount,
      rcm_cgst,rcm_sgst,rcm_utgst,rcm_igst,rcm_cess,rcm_tax_amount,calculation_rounding,line_total,profile_source,profile_status,line_payload
    ) values(
      p_tenant_id,v_id,i,v_line_source,nullif(line->>'variant_id','')::uuid,line->>'product_name',line->>'variant_name',line->>'sku',
      coalesce(line->>'supply_kind','goods'),nullif(line->>'hsn_sac',''),
      coalesce((line->>'quantity')::numeric,0),coalesce((line->>'unit_price')::numeric,0),coalesce((line->>'discount')::numeric,0),
      'non_gst',false,false,0,0,0,0,0,0,coalesce((line->>'taxable_value')::numeric,0),0,0,0,0,0,0,
      0,0,0,0,0,0,coalesce((line->>'calculation_rounding')::numeric,0),coalesce((line->>'line_total')::numeric,0),
      'tenant_non_gst','not_applicable',line
    );
  end loop;

  return v_id;
end
$function$;

revoke all on function private.gst_snapshot_create_non_gst_v520(uuid,text,uuid,text,uuid,date,jsonb,jsonb) from public, anon, authenticated;

-- Clone the proven GST-only implementations before replacing their public names with mode-aware dispatchers.
do $clone$
declare d text;
begin
  if to_regprocedure('public.gst_document_quote_registered_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric)') is null then
    select pg_get_functiondef('public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric)'::regprocedure) into d;
    d:=replace(d,'FUNCTION public.gst_document_quote_v520(','FUNCTION public.gst_document_quote_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('private.gst_snapshot_create_registered_v520(uuid,text,uuid,text,uuid,date,jsonb,jsonb)') is null then
    select pg_get_functiondef('private.gst_snapshot_create_v520(uuid,text,uuid,text,uuid,date,jsonb,jsonb)'::regprocedure) into d;
    d:=replace(d,'FUNCTION private.gst_snapshot_create_v520(','FUNCTION private.gst_snapshot_create_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('private.gst_profile_for_variant_registered_v520(uuid,uuid,date)') is null then
    select pg_get_functiondef('private.gst_profile_for_variant_v520(uuid,uuid,date)'::regprocedure) into d;
    d:=replace(d,'FUNCTION private.gst_profile_for_variant_v520(','FUNCTION private.gst_profile_for_variant_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('private.gst_sale_supply_type_resolve_registered_v520(uuid,uuid,date,text)') is null then
    select pg_get_functiondef('private.gst_sale_supply_type_resolve_v520(uuid,uuid,date,text)'::regprocedure) into d;
    d:=replace(d,'FUNCTION private.gst_sale_supply_type_resolve_v520(','FUNCTION private.gst_sale_supply_type_resolve_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('private.gst_purchase_supply_type_resolve_registered_v520(uuid,uuid,date,text)') is null then
    select pg_get_functiondef('private.gst_purchase_supply_type_resolve_v520(uuid,uuid,date,text)'::regprocedure) into d;
    d:=replace(d,'FUNCTION private.gst_purchase_supply_type_resolve_v520(','FUNCTION private.gst_purchase_supply_type_resolve_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('private.gst_sale_pos_resolve_registered_v520(uuid,uuid,uuid,date,text,jsonb,text)') is null then
    select pg_get_functiondef('private.gst_sale_pos_resolve_v520(uuid,uuid,uuid,date,text,jsonb,text)'::regprocedure) into d;
    d:=replace(d,'FUNCTION private.gst_sale_pos_resolve_v520(','FUNCTION private.gst_sale_pos_resolve_registered_v520(');
    execute d;
  end if;
  if to_regprocedure('public.gst_transaction_cutover_contract_base_v520(uuid,text,uuid)') is null then
    select pg_get_functiondef('public.gst_transaction_cutover_contract_v520(uuid,text,uuid)'::regprocedure) into d;
    d:=replace(d,'FUNCTION public.gst_transaction_cutover_contract_v520(','FUNCTION public.gst_transaction_cutover_contract_base_v520(');
    execute d;
  end if;
  if to_regprocedure('public.gst_ui_contract_base_v520(uuid)') is null then
    select pg_get_functiondef('public.gst_ui_contract_v520(uuid)'::regprocedure) into d;
    d:=replace(d,'FUNCTION public.gst_ui_contract_v520(','FUNCTION public.gst_ui_contract_base_v520(');
    execute d;
  end if;
end
$clone$;

create or replace function public.gst_document_quote_v520(
  p_tenant_id uuid,
  p_document_kind text,
  p_location_id uuid,
  p_party_id uuid,
  p_document_date date,
  p_supply_type text,
  p_place_of_supply_code text,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,coalesce(p_document_date,current_date));
  v jsonb;
begin
  if v_mode='unconfigured' then
    raise exception 'Business tax mode is not configured. Choose GST Registered or Non-GST before using v5.2 transactions.';
  end if;
  if v_mode='non_gst' then
    return private.gst_document_quote_non_gst_v520(
      p_tenant_id,p_document_kind,p_location_id,p_party_id,p_document_date,p_supply_type,p_place_of_supply_code,
      p_items,p_additional_charges,p_round_off
    );
  end if;
  v:=public.gst_document_quote_registered_v520(
    p_tenant_id,p_document_kind,p_location_id,p_party_id,p_document_date,p_supply_type,p_place_of_supply_code,
    p_items,p_additional_charges,p_round_off
  );
  return coalesce(v,'{}'::jsonb)||jsonb_build_object('tax_mode','gst_registered','gst_applicable',true);
end
$function$;

create or replace function private.gst_snapshot_create_v520(
  p_tenant_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_source_number text,
  p_location_id uuid,
  p_document_date date,
  p_quote jsonb,
  p_source_line_ids jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  q jsonb:=coalesce(p_quote,'{}'::jsonb);
  v_mode text:=nullif(q->>'tax_mode','');
  v_original uuid;
begin
  if v_mode is null then
    v_original:=coalesce(nullif(q->>'original_sale_snapshot_id','')::uuid,nullif(q->>'original_purchase_snapshot_id','')::uuid);
    if v_original is not null then
      select s.tax_mode into v_mode from public.gst_document_snapshots_v520 s where s.id=v_original and s.tenant_id=p_tenant_id;
    end if;
  end if;
  v_mode:=coalesce(v_mode,private.gst_tax_mode_resolve_v520(p_tenant_id,p_document_date));
  if v_mode='non_gst' then
    q:=q||jsonb_build_object('tax_mode','non_gst','gst_applicable',false);
    return private.gst_snapshot_create_non_gst_v520(
      p_tenant_id,p_source_type,p_source_id,p_source_number,p_location_id,p_document_date,q,p_source_line_ids
    );
  elsif v_mode='gst_registered' then
    q:=q||jsonb_build_object('tax_mode','gst_registered','gst_applicable',true);
    return private.gst_snapshot_create_registered_v520(
      p_tenant_id,p_source_type,p_source_id,p_source_number,p_location_id,p_document_date,q,p_source_line_ids
    );
  end if;
  raise exception 'Business tax mode is not configured for the document date';
end
$function$;

create or replace function private.gst_profile_for_variant_v520(
  p_tenant_id uuid,
  p_variant_id uuid,
  p_date date
) returns public.gst_product_tax_profiles_v520
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  r public.gst_product_tax_profiles_v520%rowtype;
  v_kind text;
  v_hsn text;
  d date:=coalesce(p_date,current_date);
begin
  if private.gst_tax_mode_resolve_v520(p_tenant_id,d)<>'non_gst' then
    return private.gst_profile_for_variant_registered_v520(p_tenant_id,p_variant_id,d);
  end if;

  select * into r from public.gst_product_tax_profiles_v520 p
  where p.tenant_id=p_tenant_id and p.variant_id=p_variant_id and p.active
    and d between p.effective_from and coalesce(p.effective_to,'infinity'::date)
  order by p.effective_from desc,p.created_at desc limit 1;

  select case when p.item_type='service' then 'service' else 'goods' end,
         coalesce(r.hsn_sac,a.hsn_sac)
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

create or replace function private.gst_sale_supply_type_resolve_v520(
  p_tenant_id uuid,p_customer_id uuid,p_document_date date,p_requested text default null
) returns text
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,coalesce(p_document_date,current_date));
begin
  if v_mode='unconfigured' then raise exception 'Business tax mode is not configured'; end if;
  if v_mode='non_gst' then
    if not exists(select 1 from public.customers c where c.tenant_id=p_tenant_id and c.id=p_customer_id and c.status='active') then raise exception 'Active customer not found'; end if;
    return 'B2C';
  end if;
  return private.gst_sale_supply_type_resolve_registered_v520(p_tenant_id,p_customer_id,p_document_date,p_requested);
end
$function$;

create or replace function private.gst_purchase_supply_type_resolve_v520(
  p_tenant_id uuid,p_supplier_id uuid,p_document_date date,p_requested text default null
) returns text
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,coalesce(p_document_date,current_date));
begin
  if v_mode='unconfigured' then raise exception 'Business tax mode is not configured'; end if;
  if v_mode='non_gst' then
    if not exists(select 1 from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_supplier_id and s.status='active') then raise exception 'Active supplier not found'; end if;
    return 'B2C';
  end if;
  return private.gst_purchase_supply_type_resolve_registered_v520(p_tenant_id,p_supplier_id,p_document_date,p_requested);
end
$function$;

create or replace function private.gst_sale_pos_resolve_v520(
  p_tenant_id uuid,p_customer_id uuid,p_location_id uuid,p_document_date date,p_supply_type text,p_items jsonb,p_requested text default null
) returns text
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,coalesce(p_document_date,current_date));
begin
  if v_mode='unconfigured' then raise exception 'Business tax mode is not configured'; end if;
  if v_mode='non_gst' then return coalesce(nullif(trim(coalesce(p_requested,'')),''),'NA'); end if;
  return private.gst_sale_pos_resolve_registered_v520(p_tenant_id,p_customer_id,p_location_id,p_document_date,p_supply_type,p_items,p_requested);
end
$function$;

create or replace function public.gst_transaction_cutover_contract_v520(
  p_tenant_id uuid,p_channel text default 'client',p_device_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v jsonb;
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,current_date);
begin
  v:=public.gst_transaction_cutover_contract_base_v520(p_tenant_id,p_channel,p_device_id);
  v:=coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'tax_mode',v_mode,
    'tax_mode_configured',v_mode<>'unconfigured',
    'gst_applicable',v_mode='gst_registered',
    'tax_mode_rpc','gst_tax_mode_get_v520',
    'tax_mode_save_rpc','gst_tax_mode_set_v520'
  );
  v:=jsonb_set(v,'{cutover_ready}',to_jsonb(v_mode<>'unconfigured'),true);
  v:=jsonb_set(v,'{rules}',coalesce(v->'rules','{}'::jsonb)||jsonb_build_object(
    'tenant_tax_mode_required',true,
    'non_gst_uses_v520_writer',true,
    'non_gst_gst_amounts_zero',true,
    'non_gst_legacy_fallback',false
  ),true);
  if v_mode='unconfigured' then
    v:=v||jsonb_build_object('blocking_reason','tax_mode_unconfigured');
  end if;
  return v;
end
$function$;

create or replace function public.gst_ui_contract_v520(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v jsonb;
  v_mode jsonb;
begin
  v:=public.gst_ui_contract_base_v520(p_tenant_id);
  v_mode:=public.gst_tax_mode_get_v520(p_tenant_id,current_date);
  v:=coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'contract_version',5,
    'tax_mode',v_mode,
    'tax_mode_rpc','gst_tax_mode_get_v520',
    'tax_mode_save_rpc','gst_tax_mode_set_v520',
    'gst_compliance_required',coalesce(v_mode->>'tax_mode','unconfigured')='gst_registered'
  );
  v:=jsonb_set(v,'{form_options}',coalesce(v->'form_options','{}'::jsonb)||jsonb_build_object(
    'business_tax_modes',jsonb_build_array('gst_registered','non_gst')
  ),true);
  v:=jsonb_set(v,'{rules}',coalesce(v->'rules','{}'::jsonb)||jsonb_build_object(
    'tenant_tax_mode_required',true,
    'non_gst_invoice_class','commercial_invoice',
    'non_gst_gst_amounts_zero',true,
    'non_gst_returns_follow_original_document_tax_mode',true
  ),true);
  return v;
end
$function$;

-- Keep only the intended authenticated RPC surface executable.
revoke all on function public.gst_document_quote_registered_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) from public, anon, authenticated;
revoke all on function public.gst_transaction_cutover_contract_base_v520(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.gst_ui_contract_base_v520(uuid) from public, anon, authenticated;
revoke all on function private.gst_snapshot_create_registered_v520(uuid,text,uuid,text,uuid,date,jsonb,jsonb) from public, anon, authenticated;
revoke all on function private.gst_profile_for_variant_registered_v520(uuid,uuid,date) from public, anon, authenticated;
revoke all on function private.gst_sale_supply_type_resolve_registered_v520(uuid,uuid,date,text) from public, anon, authenticated;
revoke all on function private.gst_purchase_supply_type_resolve_registered_v520(uuid,uuid,date,text) from public, anon, authenticated;
revoke all on function private.gst_sale_pos_resolve_registered_v520(uuid,uuid,uuid,date,text,jsonb,text) from public, anon, authenticated;

revoke all on function public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) from public, anon;
grant execute on function public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) to authenticated;
revoke all on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) from public, anon;
grant execute on function public.gst_transaction_cutover_contract_v520(uuid,text,uuid) to authenticated;
revoke all on function public.gst_ui_contract_v520(uuid) from public, anon;
grant execute on function public.gst_ui_contract_v520(uuid) to authenticated;

revoke all on function private.gst_snapshot_create_v520(uuid,text,uuid,text,uuid,date,jsonb,jsonb) from public, anon, authenticated;
revoke all on function private.gst_profile_for_variant_v520(uuid,uuid,date) from public, anon, authenticated;
revoke all on function private.gst_sale_supply_type_resolve_v520(uuid,uuid,date,text) from public, anon, authenticated;
revoke all on function private.gst_purchase_supply_type_resolve_v520(uuid,uuid,date,text) from public, anon, authenticated;
revoke all on function private.gst_sale_pos_resolve_v520(uuid,uuid,uuid,date,text,jsonb,text) from public, anon, authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
select 253,'5.2.0','GST Tenant Tax Mode + Non-GST Authoritative Path',
       'Adds explicit effective-dated GST Registered/Non-GST tenant mode; Non-GST transactions stay on v5.2 authoritative writers with zero GST and commercial-invoice evidence; returns inherit original document tax mode; hardens GST registration version table RLS.'
where not exists(select 1 from public.thq_schema_releases where migration_no=253);
