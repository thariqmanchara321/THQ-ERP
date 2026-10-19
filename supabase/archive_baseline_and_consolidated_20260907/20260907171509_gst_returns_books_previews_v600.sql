create or replace function private.gst_aato_context_v600(p_tenant_id uuid,p_document_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare
  d date:=coalesce(p_document_date,current_date);
  fy date;
  prev_fy date;
  prior_aato numeric;
  max_aato numeric;
  threshold numeric:=5;
  window_rule jsonb;
begin
  fy:=case when extract(month from d)>=4 then make_date(extract(year from d)::int,4,1) else make_date(extract(year from d)::int-1,4,1) end;
  prev_fy:=(fy-interval '1 year')::date;
  select aato_crore into prior_aato from public.gst_turnover_profiles_v600 where tenant_id=p_tenant_id and financial_year_start=prev_fy;
  select max(aato_crore) into max_aato from public.gst_turnover_profiles_v600 where tenant_id=p_tenant_id and financial_year_start<=fy;
  select rule_value into threshold from public.gst_policy_rules_v520 where rule_key='einvoice_aato_threshold_crore' and effective_from<=d and (effective_to is null or effective_to>=d) order by effective_from desc limit 1;
  select rule_value into window_rule from public.gst_policy_rules_v520 where rule_key='einvoice_reporting_window' and effective_from<=d and (effective_to is null or effective_to>=d) order by effective_from desc limit 1;
  return jsonb_build_object(
    'financial_year_start',fy,'previous_financial_year_start',prev_fy,
    'previous_fy_aato_crore',prior_aato,'max_recorded_aato_crore',max_aato,
    'profile_available',max_aato is not null,
    'table12_hsn_digits',case when coalesce(prior_aato,0)>5 then 6 else 4 end,
    'einvoice_threshold_crore',coalesce(threshold,5),
    'einvoice_threshold_met',max_aato is not null and max_aato>=coalesce(threshold,5),
    'einvoice_reporting_window_days',coalesce((window_rule->>'days')::int,30),
    'einvoice_reporting_window_aato_crore',coalesce((window_rule->>'aato_crore')::numeric,10),
    'einvoice_reporting_window_applies',max_aato is not null and max_aato>=coalesce((window_rule->>'aato_crore')::numeric,10) and d>=date '2025-04-01'
  );
end
$function$;

create or replace function public.gst_gstr1_preview_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare
  reg public.gst_registrations_v520%rowtype;
  aato jsonb;
  hsn_digits int;
  b2b jsonb;
  b2cl jsonb;
  b2cs jsonb;
  exports jsonb;
  sez_dexp jsonb;
  notes jsonb;
  nil_exempt jsonb;
  hsn jsonb;
  summary jsonb;
  blockers text[]:='{}';
  warnings text[]:='{}';
  legacy_count bigint:=0;
  missing_hsn bigint:=0;
  missing_irn bigint:=0;
  b2cl_threshold numeric:=100000;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then raise exception 'GST returns permission required'; end if;
  if p_from is null or p_to is null or p_to<p_from then raise exception 'Valid GSTR-1 period is required'; end if;
  select * into reg from public.gst_registrations_v520 where id=p_registration_id and tenant_id=p_tenant_id and active;
  if not found then raise exception 'GST registration not found'; end if;
  aato:=private.gst_aato_context_v600(p_tenant_id,p_to);
  hsn_digits:=coalesce((aato->>'table12_hsn_digits')::int,4);
  if coalesce((aato->>'previous_fy_aato_crore')::numeric,null) is null then warnings:=array_append(warnings,'Previous-FY AATO profile is missing; Table 12 is being validated at the 4-digit minimum'); end if;

  select count(*) into legacy_count
  from public.gst_legacy_document_markers_v520 m
  join public.gst_location_registrations_v520 lm on lm.tenant_id=m.tenant_id and lm.location_id=m.location_id and m.document_date between lm.effective_from and coalesce(lm.effective_to,'infinity'::date)
  where m.tenant_id=p_tenant_id and lm.registration_id=p_registration_id and m.document_date between p_from and p_to;
  if legacy_count>0 then blockers:=array_append(blockers,'legacy_unverified_documents_in_period'); end if;

  with docs as(
    select s.*,case when s.source_type='sales_return' or s.document_class='credit_note' then -1 else 1 end effect,
      (select j.irn from public.gst_provider_jobs_v600 j where j.snapshot_id=s.id and j.operation='einvoice_generate' and j.status='succeeded' order by j.created_at desc limit 1) irn,
      (select j.ack_at from public.gst_provider_jobs_v600 j where j.snapshot_id=s.id and j.operation='einvoice_generate' and j.status='succeeded' order by j.created_at desc limit 1) irn_date
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.document_date between p_from and p_to
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('snapshot_id',id,'invoice_number',document_number,'invoice_date',document_date,'recipient_gstin',recipient_gstin,'place_of_supply',place_of_supply_code,'invoice_value',grand_total,'taxable_value',taxable_total,'igst',igst_total,'cgst',cgst_total,'sgst_utgst',sgst_total+utgst_total,'cess',cess_total,'reverse_charge',rcm_tax_payable_total>0,'irn',irn,'irn_date',irn_date)) order by document_date,document_number),'[]'::jsonb)
  into b2b from docs where source_type='sale' and document_class='tax_invoice' and upper(supply_type)='B2B';

  with docs as(
    select s.* from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.document_date between p_from and p_to
  )
  select coalesce(jsonb_agg(jsonb_build_object('snapshot_id',id,'invoice_number',document_number,'invoice_date',document_date,'place_of_supply',place_of_supply_code,'invoice_value',grand_total,'taxable_value',taxable_total,'igst',igst_total,'rate_summary',(select coalesce(jsonb_agg(jsonb_build_object('rate',l.applied_gst_rate,'taxable',sum_taxable,'igst',sum_igst) order by l.applied_gst_rate),'[]'::jsonb) from (select applied_gst_rate,sum(taxable_value) sum_taxable,sum(igst) sum_igst from public.gst_document_line_snapshots_v520 where snapshot_id=docs.id group by applied_gst_rate) l)) order by document_date,document_number),'[]'::jsonb)
  into b2cl from docs where source_type='sale' and document_class='tax_invoice' and upper(supply_type)='B2C' and interstate is true and grand_total>b2cl_threshold;

  with lines as(
    select s.place_of_supply_code,l.applied_gst_rate,sum(l.taxable_value) taxable,sum(l.igst) igst,sum(l.cgst) cgst,sum(l.sgst+l.utgst) sgst_utgst,sum(l.cess) cess
    from public.gst_document_snapshots_v520 s join public.gst_document_line_snapshots_v520 l on l.snapshot_id=s.id
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.source_type='sale' and s.document_class='tax_invoice' and upper(s.supply_type)='B2C' and s.document_date between p_from and p_to
      and not(s.interstate is true and s.grand_total>b2cl_threshold)
    group by s.place_of_supply_code,l.applied_gst_rate
  ) select coalesce(jsonb_agg(jsonb_build_object('place_of_supply',place_of_supply_code,'rate',applied_gst_rate,'taxable_value',round(taxable,2),'igst',round(igst,2),'cgst',round(cgst,2),'sgst_utgst',round(sgst_utgst,2),'cess',round(cess,2)) order by place_of_supply_code,applied_gst_rate),'[]'::jsonb) into b2cs from lines;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('snapshot_id',s.id,'invoice_number',s.document_number,'invoice_date',s.document_date,'export_type',upper(s.supply_type),'invoice_value',s.grand_total,'taxable_value',s.taxable_total,'igst',s.igst_total,'irn',(select j.irn from public.gst_provider_jobs_v600 j where j.snapshot_id=s.id and j.operation='einvoice_generate' and j.status='succeeded' order by j.created_at desc limit 1))) order by s.document_date,s.document_number),'[]'::jsonb)
  into exports from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.source_type='sale' and upper(s.supply_type) in('EXPWP','EXPWOP') and s.document_date between p_from and p_to;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('snapshot_id',s.id,'invoice_number',s.document_number,'invoice_date',s.document_date,'supply_type',upper(s.supply_type),'recipient_gstin',s.recipient_gstin,'invoice_value',s.grand_total,'taxable_value',s.taxable_total,'igst',s.igst_total,'cgst',s.cgst_total,'sgst_utgst',s.sgst_total+s.utgst_total,'cess',s.cess_total,'irn',(select j.irn from public.gst_provider_jobs_v600 j where j.snapshot_id=s.id and j.operation='einvoice_generate' and j.status='succeeded' order by j.created_at desc limit 1))) order by s.document_date,s.document_number),'[]'::jsonb)
  into sez_dexp from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.source_type='sale' and upper(s.supply_type) in('SEZWP','SEZWOP','DEXP') and s.document_date between p_from and p_to;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('snapshot_id',s.id,'document_number',s.document_number,'document_date',s.document_date,'document_class',s.document_class,'recipient_gstin',s.recipient_gstin,'place_of_supply',s.place_of_supply_code,'document_value',s.grand_total,'taxable_value',s.taxable_total,'igst',s.igst_total,'cgst',s.cgst_total,'sgst_utgst',s.sgst_total+s.utgst_total,'cess',s.cess_total,'original_snapshot_id',coalesce(nullif(s.quote_payload->>'original_sale_snapshot_id',''),nullif(s.quote_payload->>'original_purchase_snapshot_id','')))) order by s.document_date,s.document_number),'[]'::jsonb)
  into notes from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and (s.source_type='sales_return' or s.document_class in('credit_note','debit_note')) and s.document_date between p_from and p_to;

  with x as(
    select l.taxability,l.supply_kind,sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.taxable_value else l.taxable_value end) value
    from public.gst_document_snapshots_v520 s join public.gst_document_line_snapshots_v520 l on l.snapshot_id=s.id
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.document_date between p_from and p_to and l.taxability in('nil_rated','exempt','non_gst')
    group by l.taxability,l.supply_kind
  ) select coalesce(jsonb_agg(jsonb_build_object('taxability',taxability,'supply_kind',supply_kind,'value',round(value,2)) order by taxability,supply_kind),'[]'::jsonb) into nil_exempt from x;

  with x as(
    select l.hsn_sac,l.supply_kind,l.applied_gst_rate,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.quantity else l.quantity end) quantity,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.taxable_value else l.taxable_value end) taxable,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.igst else l.igst end) igst,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.cgst else l.cgst end) cgst,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -(l.sgst+l.utgst) else l.sgst+l.utgst end) sgst_utgst,
      sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -l.cess else l.cess end) cess
    from public.gst_document_snapshots_v520 s join public.gst_document_line_snapshots_v520 l on l.snapshot_id=s.id
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.document_date between p_from and p_to
    group by l.hsn_sac,l.supply_kind,l.applied_gst_rate
  ) select coalesce(jsonb_agg(jsonb_build_object('hsn_sac',hsn_sac,'supply_kind',supply_kind,'rate',applied_gst_rate,'quantity',round(quantity,3),'taxable_value',round(taxable,2),'igst',round(igst,2),'cgst',round(cgst,2),'sgst_utgst',round(sgst_utgst,2),'cess',round(cess,2),'required_digits',hsn_digits,'valid_digits',length(regexp_replace(coalesce(hsn_sac,''),'\D','','g'))>=hsn_digits) order by hsn_sac,applied_gst_rate),'[]'::jsonb) into hsn from x;

  select count(*) into missing_hsn
  from public.gst_document_snapshots_v520 s join public.gst_document_line_snapshots_v520 l on l.snapshot_id=s.id
  where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.document_date between p_from and p_to and length(regexp_replace(coalesce(l.hsn_sac,''),'\D','','g'))<hsn_digits;
  if missing_hsn>0 then blockers:=array_append(blockers,'gstr1_table12_hsn_validation_failed'); end if;

  if reg.einvoice_enabled then
    if coalesce((aato->>'profile_available')::boolean,false) is not true then blockers:=array_append(blockers,'aato_profile_required_for_einvoice_validation'); end if;
    select count(*) into missing_irn from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and s.source_type='sale' and s.document_class='tax_invoice' and upper(s.supply_type) in('B2B','SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') and s.document_date between p_from and p_to
      and not exists(select 1 from public.gst_provider_jobs_v600 j where j.snapshot_id=s.id and j.operation='einvoice_generate' and j.status='succeeded');
    if missing_irn>0 then blockers:=array_append(blockers,'eligible_einvoice_documents_missing_successful_irn'); end if;
  end if;

  select jsonb_build_object(
    'documents',count(*),
    'taxable_value',round(coalesce(sum(case when source_type='sales_return' or document_class='credit_note' then -taxable_total else taxable_total end),0),2),
    'igst',round(coalesce(sum(case when source_type='sales_return' or document_class='credit_note' then -igst_total else igst_total end),0),2),
    'cgst',round(coalesce(sum(case when source_type='sales_return' or document_class='credit_note' then -cgst_total else cgst_total end),0),2),
    'sgst_utgst',round(coalesce(sum(case when source_type='sales_return' or document_class='credit_note' then -(sgst_total+utgst_total) else sgst_total+utgst_total end),0),2),
    'cess',round(coalesce(sum(case when source_type='sales_return' or document_class='credit_note' then -cess_total else cess_total end),0),2)
  ) into summary from public.gst_document_snapshots_v520 where tenant_id=p_tenant_id and thq_registration_id=p_registration_id and direction='outward' and document_date between p_from and p_to;

  return jsonb_build_object(
    'form','GSTR-1','registration_id',p_registration_id,'gstin',reg.gstin,'from',p_from,'to',p_to,
    'ready',cardinality(blockers)=0,'blockers',to_jsonb(blockers),'warnings',to_jsonb(warnings),
    'aato',aato,'b2cl_threshold',b2cl_threshold,'legacy_unverified_count',legacy_count,'missing_hsn_count',missing_hsn,'missing_irn_count',missing_irn,
    'summary',summary,
    'sections',jsonb_build_object('b2b',b2b,'b2cl',b2cl,'b2cs',b2cs,'exports',exports,'sez_deemed_exports',sez_dexp,'credit_debit_notes',notes,'nil_exempt_non_gst',nil_exempt,'hsn_table12',hsn)
  );
end
$function$;

create or replace function public.gst_gstr1a_preview_v600(
  p_tenant_id uuid,
  p_period_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; docs jsonb; blockers text[]:='{}';
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then raise exception 'GST returns permission required'; end if;
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST return period not found'; end if;
  if p.gstr1_filed_at is null then blockers:=array_append(blockers,'gstr1_not_filed'); end if;
  if p.gstr1a_filed_at is not null then blockers:=array_append(blockers,'gstr1a_already_filed'); end if;
  if p.gstr3b_filed_at is not null then blockers:=array_append(blockers,'gstr3b_already_filed'); end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('snapshot_id',s.id,'source_type',s.source_type,'document_class',s.document_class,'document_number',s.document_number,'document_date',s.document_date,'supply_type',s.supply_type,'recipient_gstin',s.recipient_gstin,'taxable_value',s.taxable_total,'igst',s.igst_total,'cgst',s.cgst_total,'sgst_utgst',s.sgst_total+s.utgst_total,'cess',s.cess_total,'grand_total',s.grand_total,'snapshot_created_at',s.created_at)) order by s.created_at,s.document_number),'[]'::jsonb)
  into docs from public.gst_document_snapshots_v520 s
  where s.tenant_id=p_tenant_id and s.thq_registration_id=p.registration_id and s.direction='outward' and s.document_date between p.period_start and p.period_end and p.gstr1_filed_at is not null and s.created_at>p.gstr1_filed_at;
  return jsonb_build_object('form','GSTR-1A','period_id',p.id,'registration_id',p.registration_id,'from',p.period_start,'to',p.period_end,'ready',cardinality(blockers)=0,'blockers',to_jsonb(blockers),'post_gstr1_documents',docs,'note','THQ immutable transactions use new documents/credit-debit notes; destructive invoice amendments are not generated.');
end
$function$;

create or replace function public.gst_gstr3b_preview_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare
  reg public.gst_registrations_v520%rowtype;
  p public.gst_return_periods_v600%rowtype;
  rec jsonb;
  sec31 jsonb;
  sec32 jsonb;
  books_itc jsonb;
  portal_itc jsonb;
  blockers text[]:='{}';
  legacy_count bigint:=0;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then raise exception 'GST returns permission required'; end if;
  if p_from is null or p_to is null or p_to<p_from then raise exception 'Valid GSTR-3B period is required'; end if;
  select * into reg from public.gst_registrations_v520 where id=p_registration_id and tenant_id=p_tenant_id and active;
  if not found then raise exception 'GST registration not found'; end if;
  select * into p from public.gst_return_periods_v600 where tenant_id=p_tenant_id and registration_id=p_registration_id and period_start=p_from and period_end=p_to limit 1;

  with d as(
    select s.*,case when s.source_type in('sales_return','purchase_return') or s.document_class='credit_note' then -1 else 1 end effect
    from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.document_date between p_from and p_to
  )
  select jsonb_build_object(
    '3_1_a_taxable_outward',jsonb_build_object('taxable_value',round(coalesce(sum(effect*taxable_total) filter(where direction='outward' and not zero_rated and coalesce(document_class,'')<>'bill_of_supply' and tax_collected_total<>0),0),2),'igst',round(coalesce(sum(effect*igst_total) filter(where direction='outward' and not zero_rated and tax_collected_total<>0),0),2),'cgst',round(coalesce(sum(effect*cgst_total) filter(where direction='outward' and not zero_rated and tax_collected_total<>0),0),2),'sgst_utgst',round(coalesce(sum(effect*(sgst_total+utgst_total)) filter(where direction='outward' and not zero_rated and tax_collected_total<>0),0),2),'cess',round(coalesce(sum(effect*cess_total) filter(where direction='outward' and not zero_rated and tax_collected_total<>0),0),2)),
    '3_1_b_zero_rated_outward',jsonb_build_object('taxable_value',round(coalesce(sum(effect*taxable_total) filter(where direction='outward' and zero_rated),0),2),'igst',round(coalesce(sum(effect*igst_total) filter(where direction='outward' and zero_rated),0),2),'cess',round(coalesce(sum(effect*cess_total) filter(where direction='outward' and zero_rated),0),2)),
    '3_1_c_nil_exempt_outward',jsonb_build_object('value',round(coalesce(sum(effect*grand_total) filter(where direction='outward' and tax_collected_total=0 and not zero_rated and tax_mode='gst_registered'),0),2)),
    '3_1_d_inward_reverse_charge',jsonb_build_object('taxable_value',round(coalesce(sum(effect*taxable_total) filter(where direction='inward' and rcm_tax_payable_total<>0),0),2),'igst',round(coalesce(sum(effect*rcm_igst_total) filter(where direction='inward'),0),2),'cgst',round(coalesce(sum(effect*rcm_cgst_total) filter(where direction='inward'),0),2),'sgst_utgst',round(coalesce(sum(effect*(rcm_sgst_total+rcm_utgst_total)) filter(where direction='inward'),0),2),'cess',round(coalesce(sum(effect*rcm_cess_total) filter(where direction='inward'),0),2)),
    '3_1_e_non_gst_outward',jsonb_build_object('value',round(coalesce(sum(effect*grand_total) filter(where direction='outward' and tax_mode='non_gst'),0),2))
  ) into sec31 from d;

  with x as(
    select s.place_of_supply_code,sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -s.taxable_total else s.taxable_total end) taxable,sum(case when s.source_type='sales_return' or s.document_class='credit_note' then -s.igst_total else s.igst_total end) igst
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='outward' and upper(s.supply_type)='B2C' and s.interstate is true and s.document_date between p_from and p_to
    group by s.place_of_supply_code
  ) select coalesce(jsonb_agg(jsonb_build_object('place_of_supply',place_of_supply_code,'taxable_value',round(taxable,2),'igst',round(igst,2)) order by place_of_supply_code),'[]'::jsonb) into sec32 from x;

  select jsonb_build_object('igst',round(coalesce(sum(case when s.source_type='purchase_return' or s.document_class='credit_note' then -s.igst_total else s.igst_total end),0),2),'cgst',round(coalesce(sum(case when s.source_type='purchase_return' or s.document_class='credit_note' then -s.cgst_total else s.cgst_total end),0),2),'sgst_utgst',round(coalesce(sum(case when s.source_type='purchase_return' or s.document_class='credit_note' then -(s.sgst_total+s.utgst_total) else s.sgst_total+s.utgst_total end),0),2),'cess',round(coalesce(sum(case when s.source_type='purchase_return' or s.document_class='credit_note' then -s.cess_total else s.cess_total end),0),2)) into books_itc
  from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='inward' and s.document_date between p_from and p_to;

  if date_trunc('month',p_from)::date=p_from and (p_from+interval '1 month-1 day')::date=p_to then
    rec:=public.gst_gstr2b_reconciliation_v600(p_tenant_id,p_registration_id,p_from);
  else
    rec:=jsonb_build_object('ready',false,'gstr2b_imported',false,'blockers',jsonb_build_array('gstr2b_reconciliation_currently_monthly'));
  end if;

  with latest as(
    select id from public.gst_portal_import_batches_v600 where tenant_id=p_tenant_id and registration_id=p_registration_id and period_start=date_trunc('month',p_from)::date and source='gstr2b' order by created_at desc limit 1
  ), portal as(
    select d.* from public.gst_portal_itc_documents_v600 d join latest b on b.id=d.batch_id
  ), books as(
    select s.* from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='inward' and s.document_date between p_from and p_to
  ), exact as(
    select po.* from portal po join books bo on upper(regexp_replace(coalesce(po.supplier_gstin,''),'\s','','g'))=upper(regexp_replace(coalesce(bo.supplier_gstin,''),'\s','','g')) and upper(trim(coalesce(po.document_number,'')))=upper(trim(coalesce(bo.document_number,''))) and po.document_date=bo.document_date
    where abs(coalesce(bo.taxable_total,0)-coalesce(po.taxable_value,0))<=0.01 and abs(coalesce(bo.igst_total,0)-coalesce(po.igst,0))<=0.01 and abs(coalesce(bo.cgst_total,0)-coalesce(po.cgst,0))<=0.01 and abs(coalesce(bo.sgst_total+bo.utgst_total,0)-coalesce(po.sgst+po.utgst,0))<=0.01 and abs(coalesce(bo.cess_total,0)-coalesce(po.cess,0))<=0.01 and po.itc_available
  ) select jsonb_build_object('igst',round(coalesce(sum(case when document_type='credit_note' then -igst else igst end),0),2),'cgst',round(coalesce(sum(case when document_type='credit_note' then -cgst else cgst end),0),2),'sgst_utgst',round(coalesce(sum(case when document_type='credit_note' then -(sgst+utgst) else sgst+utgst end),0),2),'cess',round(coalesce(sum(case when document_type='credit_note' then -cess else cess end),0),2)) into portal_itc from exact;

  select count(*) into legacy_count from public.gst_legacy_document_markers_v520 m join public.gst_location_registrations_v520 lm on lm.tenant_id=m.tenant_id and lm.location_id=m.location_id and m.document_date between lm.effective_from and coalesce(lm.effective_to,'infinity'::date) where m.tenant_id=p_tenant_id and lm.registration_id=p_registration_id and m.document_date between p_from and p_to;
  if legacy_count>0 then blockers:=array_append(blockers,'legacy_unverified_documents_in_period'); end if;
  if coalesce((rec->>'gstr2b_imported')::boolean,false) is not true and exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='inward' and s.document_date between p_from and p_to) then blockers:=array_append(blockers,'gstr2b_not_imported'); end if;
  if coalesce((rec->>'gstr2b_imported')::boolean,false) and coalesce((rec->>'ready')::boolean,false) is not true then blockers:=array_append(blockers,'gstr2b_books_reconciliation_has_exceptions'); end if;
  if p.id is null then blockers:=array_append(blockers,'return_period_not_created');
  elsif p.gstr1_filed_at is null then blockers:=array_append(blockers,'gstr1_not_marked_filed'); end if;

  return jsonb_build_object('form','GSTR-3B','registration_id',p_registration_id,'gstin',reg.gstin,'from',p_from,'to',p_to,'ready',cardinality(blockers)=0,'blockers',to_jsonb(blockers),'legacy_unverified_count',legacy_count,'section_3_1',sec31,'section_3_2_interstate_unregistered',sec32,'itc',jsonb_build_object('books',books_itc,'gstr2b_matched_claimable',coalesce(portal_itc,'{}'::jsonb),'reconciliation',rec),'note','Final ITC claim remains governed by GSTR-2B/IMS eligibility and taxpayer review; THQ does not infer claimable ITC from books alone.');
end
$function$;

create or replace function public.gst_returns_workspace_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date,
  p_frequency text default 'monthly'
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p jsonb; pid uuid; ps date; pe date; g1 jsonb; g1a jsonb; g3 jsonb; rec jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then raise exception 'GST returns permission required'; end if;
  p:=public.gst_return_period_ensure_v600(p_tenant_id,p_registration_id,p_period_start,p_frequency);
  pid:=(p->>'id')::uuid; ps:=(p->>'period_start')::date; pe:=(p->>'period_end')::date;
  g1:=public.gst_gstr1_preview_v600(p_tenant_id,p_registration_id,ps,pe);
  g1a:=public.gst_gstr1a_preview_v600(p_tenant_id,pid);
  g3:=public.gst_gstr3b_preview_v600(p_tenant_id,p_registration_id,ps,pe);
  if lower(coalesce(p_frequency,'monthly'))='monthly' then rec:=public.gst_gstr2b_reconciliation_v600(p_tenant_id,p_registration_id,ps); else rec:=jsonb_build_object('ready',false,'blockers',jsonb_build_array('monthly_gstr2b_reconciliation_required')); end if;
  return jsonb_build_object('period',p,'gstr1',g1,'gstr1a',g1a,'gstr3b',g3,'gstr2b_reconciliation',rec,'provider',public.gst_provider_connection_status_v600(p_tenant_id,p_registration_id));
end
$function$;

revoke all on function public.gst_gstr1_preview_v600(uuid,uuid,date,date) from public,anon;
grant execute on function public.gst_gstr1_preview_v600(uuid,uuid,date,date) to authenticated;
revoke all on function public.gst_gstr1a_preview_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_gstr1a_preview_v600(uuid,uuid) to authenticated;
revoke all on function public.gst_gstr3b_preview_v600(uuid,uuid,date,date) from public,anon;
grant execute on function public.gst_gstr3b_preview_v600(uuid,uuid,date,date) to authenticated;
revoke all on function public.gst_returns_workspace_v600(uuid,uuid,date,text) from public,anon;
grant execute on function public.gst_returns_workspace_v600(uuid,uuid,date,text) to authenticated;