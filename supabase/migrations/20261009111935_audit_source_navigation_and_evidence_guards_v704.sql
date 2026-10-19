CREATE OR REPLACE FUNCTION public.transaction_explain_core_v600(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_event_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type text:=lower(trim(coalesce(p_entity_type,'')));
  v_dataset text;
  v_root_type text;
  v_root_id uuid;
  v_location uuid;
  v_corr uuid;
  v_sensitive boolean;
  v_audit boolean;
  v_accounting boolean;
  v_inventory boolean;
  v_current jsonb;
  v_origin jsonb;
  v_story jsonb:='[]'::jsonb;
  v_legacy_audit jsonb:='[]'::jsonb;
  v_payments jsonb:='[]'::jsonb;
  v_approvals jsonb:='[]'::jsonb;
  v_journals jsonb:='[]'::jsonb;
  v_stock jsonb:='[]'::jsonb;
  v_gst jsonb:='[]'::jsonb;
  v_story_count integer:=0;
  v_legacy_count integer:=0;
  v_quality text;
  v_notice text;
begin
  if p_entity_id is null then raise exception 'Entity id is required'; end if;
  if not private.v600_can_view_entity(p_tenant_id,v_type) then raise exception 'Permission denied' using errcode='42501'; end if;

  v_sensitive:=private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  v_audit:=private.has_permission(p_tenant_id,'audit_center.view');
  v_accounting:=v_audit or private.has_permission(p_tenant_id,'accounting.view') or private.has_permission(p_tenant_id,'accounting.manage');
  v_inventory:=v_audit or private.has_permission(p_tenant_id,'inventory.view') or private.has_permission(p_tenant_id,'inventory.manage');
  v_root_type:=v_type; v_root_id:=p_entity_id;

  if v_type='sale' then
    select to_jsonb(s) into v_current from public.sales s where s.tenant_id=p_tenant_id and s.id=p_entity_id;
  elsif v_type='sale_item' then
    select to_jsonb(si),si.sale_id into v_current,v_root_id from public.sale_items si where si.tenant_id=p_tenant_id and si.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='sale_payment' then
    select to_jsonb(sp),sp.sale_id into v_current,v_root_id from public.sale_payments sp where sp.tenant_id=p_tenant_id and sp.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='sales_return' then
    select to_jsonb(sr),sr.sale_id into v_current,v_root_id from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='purchase' then
    select to_jsonb(p) into v_current from public.purchases p where p.tenant_id=p_tenant_id and p.id=p_entity_id;
  elsif v_type='purchase_item' then
    select to_jsonb(pi),pi.purchase_id into v_current,v_root_id from public.purchase_items pi where pi.tenant_id=p_tenant_id and pi.id=p_entity_id;
    v_root_type:='purchase';
  elsif v_type='purchase_payment' then
    select to_jsonb(pp),pp.purchase_id into v_current,v_root_id from public.purchase_payments pp where pp.tenant_id=p_tenant_id and pp.id=p_entity_id;
    v_root_type:='purchase';
  elsif v_type='purchase_invoice' then
    select to_jsonb(pi) into v_current from public.purchase_invoices_v484 pi where pi.tenant_id=p_tenant_id and pi.id=p_entity_id;
  elsif v_type='supplier_payment' then
    select to_jsonb(sp) into v_current from public.supplier_payments_v484 sp where sp.tenant_id=p_tenant_id and sp.id=p_entity_id;
  elsif v_type='journal_entry' then
    select to_jsonb(j) into v_current from public.journal_entries j where j.tenant_id=p_tenant_id and j.id=p_entity_id;
    if v_current is not null and nullif(v_current->>'source_id','') is not null then
      v_root_id:=(v_current->>'source_id')::uuid; v_root_type:=coalesce(nullif(v_current->>'source_type',''),'journal_entry');
    end if;
  elsif v_type='stock_adjustment' then
    select to_jsonb(a) into v_current from public.stock_adjustment_requests_v500 a where a.tenant_id=p_tenant_id and a.id=p_entity_id;
  else
    if v_audit then
      select value->>'key' into v_dataset from jsonb_array_elements(private.audit_catalog_v704()) where value->>'entity'=v_type limit 1;
    end if;
    if v_dataset is not null then
      v_current:=private.audit_record_v704(p_tenant_id,v_dataset,p_entity_id::text,null);
    else
      select jsonb_build_object('entity_type',v_type,'entity_id',p_entity_id) into v_current;
    end if;
  end if;

  if v_current is null then raise exception 'Transaction not found'; end if;
  v_location:=nullif(v_current->>'location_id','')::uuid;
  if v_location is null and v_root_type='sale' then
    select o.location_id into v_location from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=v_root_id order by o.created_at limit 1;
  elsif v_location is null and v_root_type='purchase' then
    select o.location_id into v_location from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=v_root_id order by o.created_at limit 1;
  end if;
  if v_location is null and v_dataset is not null then
    select l into v_location from unnest(private.audit_record_locations_v704(p_tenant_id,v_dataset,v_current)) l where private.reports_scope_v631(p_tenant_id,l,null,'view') limit 1;
  end if;
  if auth.uid() is null or not private.reports_scope_v631(p_tenant_id,v_location,null,'view') then
    raise exception 'Transaction store access denied' using errcode='42501';
  end if;
  v_corr:=extensions.uuid_generate_v5(extensions.uuid_ns_url(),'thq:v600:'||p_tenant_id::text||':'||lower(v_root_type)||':'||v_root_id::text);

  select to_jsonb(o) into v_origin
  from public.document_origins o
  where o.tenant_id=p_tenant_id and o.entity_type=v_root_type and o.entity_id=v_root_id
  order by o.created_at asc limit 1;

  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'sequence',e.event_sequence,'id',e.id,'action',e.action,'event_time',e.event_time,
    'entity_type',e.entity_type,'entity_id',e.entity_id,'entity_reference',e.entity_reference,
    'actor',jsonb_build_object('user_id',e.actor_user_id,'name',e.actor_name,'roles',e.actor_role_keys),
    'location_id',e.location_id,'device',jsonb_build_object('id',e.device_id,'name',e.device_name,'code',e.device_code,'app',e.source_app),
    'changed_fields',e.changed_fields,'before',case when v_sensitive then e.before_data else null end,'after',case when v_sensitive then e.after_data else null end,
    'reason',e.reason,'approval',jsonb_build_object('request_id',e.approval_request_id,'approved_by',e.approved_by,'approved_at',e.approved_at,'note',e.approval_note),
    'source_module',e.source_module,'related_entities',e.related_entities,'event_hash',e.event_hash
  ) order by e.event_sequence),'[]'::jsonb)
  into v_story_count,v_story
  from (
    select * from public.transaction_story_events_v600
    where tenant_id=p_tenant_id and correlation_id=v_corr
      and private.reports_scope_v631(p_tenant_id,coalesce(location_id,v_location),null,'view')
    order by event_sequence
    limit greatest(1,least(coalesce(p_event_limit,500),2000))
  ) e;

  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'action',a.action,'entity_type',a.entity_type,'entity_id',a.entity_id,'entity_reference',a.entity_reference,
    'user_id',a.user_id,'created_at',a.created_at,'location_id',a.location_id,'device_id',a.device_id,'reason',a.reason,
    'before',case when v_sensitive then a.before_data else null end,'after',case when v_sensitive then a.after_data else null end,'metadata',a.metadata
  ) order by a.created_at),'[]'::jsonb)
  into v_legacy_count,v_legacy_audit
  from public.business_audit_log a
  where a.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,coalesce(a.location_id,v_location),null,'view') and (
    (a.entity_type=v_type and a.entity_id=p_entity_id) or
    (a.entity_type=v_root_type and a.entity_id=v_root_id)
  );

  if v_root_type='sale' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'method',sp.payment_method,'reference',sp.reference_number,'notes',sp.notes,
      'paid_at',sp.paid_at,'created_by',sp.created_by,'created_by_name',u.username::text
    ) order by sp.paid_at,sp.id),'[]'::jsonb) into v_payments
    from public.sale_payments sp left join public.user_login_names u on u.user_id=sp.created_by
    where sp.tenant_id=p_tenant_id and sp.sale_id=v_root_id;
  elsif v_root_type='purchase' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',pp.id,'amount',pp.amount,'method',pp.payment_method,'reference',pp.reference_number,'notes',pp.notes,
      'paid_at',pp.paid_at,'created_by',pp.created_by,'created_by_name',u.username::text
    ) order by pp.paid_at,pp.id),'[]'::jsonb) into v_payments
    from public.purchase_payments pp left join public.user_login_names u on u.user_id=pp.created_by
    where pp.tenant_id=p_tenant_id and pp.purchase_id=v_root_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',ar.id,'module',ar.module_key,'action',ar.action_key,'entity_type',ar.entity_type,'entity_id',ar.entity_id,
    'amount',ar.amount,'percentage',ar.percentage,'status',ar.status,'reason',ar.reason,
    'requested_by',ar.requested_by,'requested_at',ar.requested_at,'decided_by',ar.decided_by,'decided_at',ar.decided_at,'decision_note',ar.decision_note
  ) order by ar.requested_at),'[]'::jsonb) into v_approvals
  from public.approval_requests ar
  where ar.tenant_id=p_tenant_id and (
    (ar.entity_type=v_type and ar.entity_id=p_entity_id) or
    (ar.entity_type=v_root_type and ar.entity_id=v_root_id)
  );

  if v_accounting then
    select coalesce(jsonb_agg(x order by x->>'date',x->>'created_at',x->>'id'),'[]') into v_journals
    from private.accounting_rows_v702(p_tenant_id,'journal',date '1900-01-01',date '9999-12-31',null,'{}') x
    where (v_type='journal_entry' and x->>'id'=p_entity_id::text)
       or (x->>'source_type'=v_root_type and x->>'source_id'=v_root_id::text)
       or (x->>'document_type'=v_root_type and x->>'document_id'=v_root_id::text);
  end if;

  if v_inventory then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',m.id,'movement_type',m.movement_type,'variant_id',m.variant_id,'quantity_delta',m.quantity_delta,'unit_cost',m.unit_cost,
      'reference_type',m.reference_type,'reference_id',m.reference_id,'reference_number',m.reference_number,'note',m.note,
      'created_by',m.created_by,'device_id',m.device_id,'created_at',m.created_at,'balance_before',m.balance_before,'balance_after',m.balance_after,
      'movement_group',m.movement_group
    ) order by m.created_at,m.id),'[]'::jsonb) into v_stock
    from public.location_stock_movements m
    where m.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,coalesce(m.location_id,v_location),null,'view') and (
      (m.reference_type=v_root_type and m.reference_id=v_root_id) or
      (v_root_type='sale' and m.reference_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=m.reference_id))
    );
  end if;

  select coalesce(jsonb_agg(x.evidence order by x.evidence_time,x.evidence_id),'[]'::jsonb) into v_gst
  from (
    select s.id evidence_id,s.created_at evidence_time,jsonb_build_object(
      'evidence_type','authoritative_snapshot','id',s.id,'source_type',s.source_type,'source_id',s.source_id,'source_number',s.source_number,
      'document_number',s.document_number,'document_date',s.document_date,'location_id',s.location_id,'tax_mode',s.tax_mode,
      'taxable_total',s.taxable_total,'cgst_total',s.cgst_total,'sgst_total',s.sgst_total,'utgst_total',s.utgst_total,'igst_total',s.igst_total,
      'cess_total',s.cess_total,'tax_collected_total',s.tax_collected_total,'rcm_tax_payable_total',s.rcm_tax_payable_total,
      'government_tax_total',s.government_tax_total,'grand_total',s.grand_total,'engine_version',s.engine_version,
      'snapshot_hash',s.snapshot_hash,'document_identity_hash',s.document_identity_hash,'created_at',s.created_at
    ) evidence
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,coalesce(s.location_id,v_location),null,'view') and (
      (s.source_type=v_root_type and s.source_id=v_root_id) or
      (v_root_type='sale' and s.source_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=s.source_id))
    )
    union all
    select l.id,l.marked_at,jsonb_build_object(
      'evidence_type','legacy_unverified','id',l.id,'source_type',l.source_type,'source_id',l.source_id,'source_number',l.source_number,
      'document_date',l.document_date,'location_id',l.location_id,'legacy_taxable_total',l.legacy_taxable_total,'legacy_tax_total',l.legacy_tax_total,
      'legacy_grand_total',l.legacy_grand_total,'verification_status',l.verification_status,'note',l.note,'source_hash',l.source_hash,'marked_at',l.marked_at
    )
    from public.gst_legacy_document_markers_v520 l
    where l.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,coalesce(l.location_id,v_location),null,'view') and (
      (l.source_type=v_root_type and l.source_id=v_root_id) or
      (v_root_type='sale' and l.source_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=l.source_id))
    )
  ) x;

  if v_story_count>0 then
    v_quality:='enhanced_v600';
    v_notice:='v6.0 Transaction Story evidence is available. Older actions not captured before v6.0 are shown only when existing THQ records provide real evidence.';
  elsif v_legacy_count>0 then
    v_quality:='historical_partial';
    v_notice:='Historical transaction: enhanced v6.0 event tracking was not active. Existing audit/payment/stock/journal/GST records are shown; missing actor/edit/device/reason history is not inferred.';
  else
    v_quality:='historical_baseline_only';
    v_notice:='Historical transaction: enhanced tracking was not active when this record was created. THQ shows current state and related recorded evidence only; no missing history is fabricated.';
  end if;

  return jsonb_build_object(
    'requested_entity',jsonb_build_object('type',v_type,'id',p_entity_id),
    'transaction_root',jsonb_build_object('type',v_root_type,'id',v_root_id,'correlation_id',v_corr),
    'tracking_quality',v_quality,'historical_notice',v_notice,'sensitive_values_visible',v_sensitive,
    'current_record',v_current,'origin',v_origin,
    'transaction_story',v_story,'legacy_audit_evidence',v_legacy_audit,
    'payments',v_payments,'approvals',v_approvals,'journals',v_journals,'stock_movements',v_stock,'gst_evidence',v_gst,
    'accounting_visible',v_accounting,'inventory_visible',v_inventory,
    'gst_integrity_rule','Authoritative v5.2 GST snapshots remain authoritative. A failed v5.2 transaction must never be re-routed to a legacy writer; legacy markers are historical evidence only.'
  );
end;
$function$;
CREATE OR REPLACE FUNCTION private.audit_workspace_v703(t uuid, k text, f date, z date, loc uuid, q text, severity text, lifecycle text, sort_key text, descending boolean, page_offset integer, page_limit integer, source_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare raw jsonb:='[]'; matched jsonb; paged jsonb; summary jsonb; tz text; lo timestamptz; hi timestamptz; n bigint; totals jsonb; checks jsonb;
begin
 perform private.audit_access_v703(t,loc);
 if f is null or z is null or f>z or page_offset is null or page_limit is null or page_offset<0 or page_limit<1 or page_limit>200 then raise exception 'Invalid audit query' using errcode='22023';end if;
 if k not in ('findings','activity','accounts','journals') then raise exception 'Unknown audit view' using errcode='22023';end if;
 tz:=coalesce((select timezone from public.tenant_settings where tenant_id=t),'UTC');
 lo:=f::timestamp at time zone tz; hi:=(z+1)::timestamp at time zone tz;
 select jsonb_build_object('high_risk',count(*) filter(where a.severity='high_risk' and a.status in('open','under_review','escalated')),
 'needs_review',count(*) filter(where a.severity='needs_review' and a.status in('open','under_review','escalated')),
 'open_attention',count(*) filter(where a.status in('open','under_review','escalated')),'total_findings',count(*)) into summary
 from public.audit_findings_v600 a where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.audit_record_allowed_v704(t,'audit_findings_v600',to_jsonb(a),loc);
 if k='findings' then
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'finding_id',a.id,'date',a.detected_at,'reference',coalesce(a.entity_reference,e.entity_reference),
   'title',a.title,'description',a.description,'severity',a.severity,'status',a.status,'risk_score',a.risk_score,'entity_type',a.entity_type,'entity_id',a.entity_id,
   'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,'location',coalesce(b.location_code,'Unassigned / business-wide'),'device',e.device_name,'rule',a.rule_code)), '[]') into raw
  from public.audit_findings_v600 a left join public.transaction_story_events_v600 e on e.tenant_id=t and e.id=a.source_event_id
  left join public.business_locations b on b.tenant_id=t and b.id=(select l from unnest(private.audit_record_locations_v704(t,'audit_findings_v600',to_jsonb(a))) l where l is not null and private.reports_scope_v631(t,l,loc,'view') limit 1)
  where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.audit_record_allowed_v704(t,'audit_findings_v600',to_jsonb(a),loc)
   and (coalesce($7,'')='' or a.severity=$7)
   and (coalesce(lifecycle,'')='' or (lifecycle='active' and a.status in('open','under_review','escalated')) or a.status=lifecycle);
 elsif k='activity' then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.event_time,'reference',e.entity_reference,'title',initcap(replace(e.action,'_',' ')),
   'dataset',e.metadata->>'dataset','entity_type',e.entity_type,'entity_id',e.entity_id,'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,
   'location',coalesce(b.location_code,'Unassigned / business-wide'),'device',e.device_name,'reason',e.reason,'evidence_quality',case when coalesce((e.metadata->>'historical_reconstruction')::boolean,false) then 'Historical baseline' else 'Recorded event' end)), '[]') into raw
  from public.transaction_story_events_v600 e left join public.business_locations b on b.tenant_id=t and b.id=e.location_id
  where e.tenant_id=t and e.event_time>=lo and e.event_time<hi and private.reports_scope_v631(t,e.location_id,loc,'view');
 elsif k='journals' then
  select coalesce(jsonb_agg(x),'[]') into raw from private.accounting_rows_v702(t,'journal',f,z,loc,'{}') x where coalesce($13,'')='' or x->>'source_type'=$13;
 elsif k='accounts' then
  with lines as materialized(select x from private.accounting_lines_v702(t,z,loc) x), grouped as(
   select x->>'account_id' aid,coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric) filter(where (x->>'date')::date<f),0) opening,
   coalesce(sum((x->>'debit')::numeric) filter(where (x->>'date')::date>=f),0) debit,
   coalesce(sum((x->>'credit')::numeric) filter(where (x->>'date')::date>=f),0) credit,
   sum((x->>'debit')::numeric-(x->>'credit')::numeric) closing,count(distinct x->>'journal_id') journals,max(x->>'date') last_posted
   from lines group by x->>'account_id')
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'account_id',a.id,'reference',a.code,'account_name',a.name,'account_type',a.account_type,
   'status',case when a.active then 'Active' else 'Archived' end,'opening',coalesce(g.opening,0),'debit',coalesce(g.debit,0),'credit',coalesce(g.credit,0),
   'closing',coalesce(g.closing,0),'journals',coalesce(g.journals,0),'last_posted',g.last_posted)), '[]') into raw
  from public.accounting_accounts a left join grouped g on g.aid=a.id::text where a.tenant_id=t;
  select jsonb_build_object('debit',coalesce(sum((x->>'debit')::numeric),0),'credit',coalesce(sum((x->>'credit')::numeric),0),
   'difference',coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric),0),'closing_difference',coalesce(sum((x->>'closing')::numeric),0)) into totals from jsonb_array_elements(raw) x;
 end if;
 -- Independent checks retain all journal statuses; effective balances use v702.
 select jsonb_build_object('unbalanced_journals',count(*) filter(where x->>'balance_status'='Unbalanced'),
   'draft_journals',count(*) filter(where x->>'status'='draft'),'journal_count',count(*)) into checks from private.accounting_rows_v702(t,'journal',f,z,loc,'{}') x where coalesce($13,'')='' or x->>'source_type'=$13;
 select coalesce(jsonb_agg(value order by
  case when not descending and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end asc nulls last,
  case when descending and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end desc nulls last,
  case when not descending then lower(value->>sort_key) end asc nulls last,
  case when descending then lower(value->>sort_key) end desc nulls last,value->>'id'),'[]') into matched
 from jsonb_array_elements(raw) records(value) where private.accounting_search_v702(value,q);
 select coalesce(jsonb_agg(value order by ordinality),'[]') into paged from jsonb_array_elements(matched) with ordinality where ordinality>page_offset and ordinality<=page_offset+page_limit;
 return jsonb_build_object('rows',paged,'total_rows',jsonb_array_length(matched),'summary',summary,'account_totals',totals,'checks',checks,
   'snapshot_token',md5(matched::text),'generated_at',statement_timestamp(),'basis','Effective journal lines, including compensating reversals. Account totals are before search and pagination. Positive balances are debit; negative balances are credit.');
end $function$;

CREATE OR REPLACE FUNCTION private.audit_workspace_v703(t uuid, k text, f date, z date, loc uuid, q text, severity text, lifecycle text, sort_key text, descending boolean, page_offset integer, page_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare raw jsonb:='[]'; matched jsonb; paged jsonb; summary jsonb; tz text; lo timestamptz; hi timestamptz; n bigint; totals jsonb; checks jsonb;
begin
 perform private.audit_access_v703(t,loc);
 if f is null or z is null or page_offset is null or page_limit is null or f>z or page_offset<0 or page_limit<1 or page_limit>200 then raise exception 'Invalid audit query' using errcode='22023';end if;
 if k not in ('findings','activity','accounts','journals') then raise exception 'Unknown audit view' using errcode='22023';end if;
 tz:=coalesce((select timezone from public.tenant_settings where tenant_id=t),'UTC');
 lo:=f::timestamp at time zone tz; hi:=(z+1)::timestamp at time zone tz;
 select jsonb_build_object('high_risk',count(*) filter(where a.severity='high_risk' and a.status in('open','under_review','escalated')),
 'needs_review',count(*) filter(where a.severity='needs_review' and a.status in('open','under_review','escalated')),
 'open_attention',count(*) filter(where a.status in('open','under_review','escalated')),'total_findings',count(*)) into summary
 from public.audit_findings_v600 a where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.audit_record_allowed_v704(t,'audit_findings_v600',to_jsonb(a),loc);
 if k='findings' then
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'finding_id',a.id,'date',a.detected_at,'reference',coalesce(a.entity_reference,e.entity_reference),
   'title',a.title,'description',a.description,'severity',a.severity,'status',a.status,'risk_score',a.risk_score,'entity_type',a.entity_type,'entity_id',a.entity_id,
   'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,'location',coalesce(b.location_code,'Unassigned / business-wide'),'device',e.device_name,'rule',a.rule_code)), '[]') into raw
  from public.audit_findings_v600 a left join public.transaction_story_events_v600 e on e.tenant_id=t and e.id=a.source_event_id
  left join public.business_locations b on b.tenant_id=t and b.id=(select l from unnest(private.audit_record_locations_v704(t,'audit_findings_v600',to_jsonb(a))) l where l is not null and private.reports_scope_v631(t,l,loc,'view') limit 1)
  where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.audit_record_allowed_v704(t,'audit_findings_v600',to_jsonb(a),loc)
   and (coalesce($7,'')='' or a.severity=$7)
   and (coalesce(lifecycle,'')='' or (lifecycle='active' and a.status in('open','under_review','escalated')) or a.status=lifecycle);
 elsif k='activity' then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.event_time,'reference',e.entity_reference,'title',initcap(replace(e.action,'_',' ')),
   'dataset',e.metadata->>'dataset','entity_type',e.entity_type,'entity_id',e.entity_id,'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,
   'location',coalesce(b.location_code,'Unassigned / business-wide'),'device',e.device_name,'reason',e.reason,'evidence_quality',case when coalesce((e.metadata->>'historical_reconstruction')::boolean,false) then 'Historical baseline' else 'Recorded event' end)), '[]') into raw
  from public.transaction_story_events_v600 e left join public.business_locations b on b.tenant_id=t and b.id=e.location_id
  where e.tenant_id=t and e.event_time>=lo and e.event_time<hi and private.reports_scope_v631(t,e.location_id,loc,'view');
 elsif k='journals' then
  select coalesce(jsonb_agg(x),'[]') into raw from private.accounting_rows_v702(t,'journal',f,z,loc,'{}') x;
 elsif k='accounts' then
  with lines as materialized(select x from private.accounting_lines_v702(t,z,loc) x), grouped as(
   select x->>'account_id' aid,coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric) filter(where (x->>'date')::date<f),0) opening,
   coalesce(sum((x->>'debit')::numeric) filter(where (x->>'date')::date>=f),0) debit,
   coalesce(sum((x->>'credit')::numeric) filter(where (x->>'date')::date>=f),0) credit,
   sum((x->>'debit')::numeric-(x->>'credit')::numeric) closing,count(distinct x->>'journal_id') journals,max(x->>'date') last_posted
   from lines group by x->>'account_id')
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'account_id',a.id,'reference',a.code,'account_name',a.name,'account_type',a.account_type,
   'status',case when a.active then 'Active' else 'Archived' end,'opening',coalesce(g.opening,0),'debit',coalesce(g.debit,0),'credit',coalesce(g.credit,0),
   'closing',coalesce(g.closing,0),'journals',coalesce(g.journals,0),'last_posted',g.last_posted)), '[]') into raw
  from public.accounting_accounts a left join grouped g on g.aid=a.id::text where a.tenant_id=t;
  select jsonb_build_object('debit',coalesce(sum((x->>'debit')::numeric),0),'credit',coalesce(sum((x->>'credit')::numeric),0),
   'difference',coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric),0),'closing_difference',coalesce(sum((x->>'closing')::numeric),0)) into totals from jsonb_array_elements(raw) x;
 end if;
 -- Independent checks retain all journal statuses; effective balances use v702.
 select jsonb_build_object('unbalanced_journals',count(*) filter(where x->>'balance_status'='Unbalanced'),
   'draft_journals',count(*) filter(where x->>'status'='draft'),'journal_count',count(*)) into checks from private.accounting_rows_v702(t,'journal',f,z,loc,'{}') x;
 select coalesce(jsonb_agg(value order by
  case when not descending and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end asc nulls last,
  case when descending and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end desc nulls last,
  case when not descending then lower(value->>sort_key) end asc nulls last,
  case when descending then lower(value->>sort_key) end desc nulls last,value->>'id'),'[]') into matched
 from jsonb_array_elements(raw) records(value) where private.accounting_search_v702(value,q);
 select coalesce(jsonb_agg(value order by ordinality),'[]') into paged from jsonb_array_elements(matched) with ordinality where ordinality>page_offset and ordinality<=page_offset+page_limit;
 return jsonb_build_object('rows',paged,'total_rows',jsonb_array_length(matched),'summary',summary,'account_totals',totals,'checks',checks,
   'generated_at',statement_timestamp(),'basis','Effective journal lines, including compensating reversals. Account totals are before search and pagination. Positive balances are debit; negative balances are credit.');
end $function$;
create or replace function private.audit_checks_v704(t uuid,f date,z date,loc uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb:='[]';x record;cfg jsonb;n bigint;sqlq text;cash numeric;accounts jsonb;tax jsonb;tz text;root record;verification jsonb;failed integer:=0;partial integer:=0;verified integer:=0;
begin
 perform private.audit_access_v703(t,loc);
 if f is null or z is null or f>z then raise exception 'Invalid audit period' using errcode='22023';end if;
 -- Document-to-journal completeness is independent of journal balance.
 for x in select * from (values
  ('sales','sale','sale_date','status=''posted'''),('purchases','purchase','purchase_date','status=''posted'''),
  ('expenses','expense','expense_date','status=''posted'''),('staff_earnings_v630','staff_earning','earning_date','true'),('staff_payments_v630','staff_payment','payment_date','true'),
  ('purchase_invoices_v484','purchase_invoice_v484','invoice_date','status in (''posted'',''partially_paid'',''paid'')'),('customer_receipts','customer_receipt','receipt_date','status=''posted'''),('supplier_payments_v484','supplier_payment','payment_date','status=''posted''')
 ) v(dataset,source,datefield,condition) loop
  execute format('select count(*) from public.%I d where d.tenant_id=$1 and d.%I between $2 and $3 and (%s) and private.audit_record_allowed_v704($1,$4,to_jsonb(d),$5) and not exists(select 1 from public.journal_entries j where j.tenant_id=$1 and j.source_id=d.id and j.source_type=$6 and j.status in(''posted'',''reversed''))',x.dataset,x.datefield,x.condition)
  into n using t,f,z,x.dataset,loc,x.source;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','posting_'||x.dataset,'reference',replace(x.dataset,'_',' '),'title','Posted records without linked journals','count',n,'status',case when n>0 then 'Needs review' else 'Passed' end,'dataset',x.dataset,'basis','Source ID and source type; posted or reversed journal required.'));
 end loop;
 accounts:=private.audit_workspace_v703(t,'accounts',f,z,loc,'','','','account_name',false,0,200);
 rows:=rows||jsonb_build_array(jsonb_build_object('id','trial_balance','reference','Trial balance','title','Period debits minus credits','amount',accounts#>'{account_totals,difference}','count',case when abs((accounts#>>'{account_totals,difference}')::numeric)>0.005 then 1 else 0 end,'status',case when abs((accounts#>>'{account_totals,difference}')::numeric)>0.005 then 'Needs review' else 'Passed' end));
 select coalesce(sum((a->>'debit')::numeric-(a->>'credit')::numeric),0) into cash from private.accounting_lines_v702(t,z,loc) a where a->>'money_method'='cash';
 rows:=rows||jsonb_build_array(jsonb_build_object('id','negative_cash','reference','Cash','title','Cash closing balance requires review when negative','amount',cash,'count',case when cash< -0.005 then 1 else 0 end,'status',case when cash< -0.005 then 'Needs review' else 'Passed' end,'basis','Effective posted ledger through period end.'));
 select count(*) into n from public.bank_statement_lines_v500 b where b.tenant_id=t and b.transaction_date between f and z and (b.matched_journal_id is null or b.status<>'matched') and private.audit_record_allowed_v704(t,'bank_statement_lines_v500',to_jsonb(b),loc);
 rows:=rows||jsonb_build_array(jsonb_build_object('id','bank_unmatched','reference','Bank statements','title','Unmatched saved bank statement lines','count',n,'status',case when n>0 then 'Needs review' else 'Passed' end,'dataset','bank_statement_lines_v500','basis','Checks only imported statement lines; absence of imports is not proof of reconciliation.'));
 select count(*) into n from public.bank_statement_lines_v500 b where b.tenant_id=t and private.audit_record_allowed_v704(t,'bank_statement_lines_v500',to_jsonb(b),loc) and b.transaction_date between f and z;
 rows:=rows||jsonb_build_array(jsonb_build_object('id','bank_coverage','reference','Bank evidence coverage','title','Saved bank statement lines in period','count',n,'status',case when n=0 then 'Not supplied' else 'Recorded' end,'dataset','bank_statement_lines_v500'));
 for x in select * from (values ('stock_balances','stock_movements'),('location_stock_balances','location_stock_movements')) v(balances,movements) loop
  execute format('with b as(select variant_id,location_id,quantity from public.%I x where tenant_id=$1 and private.audit_record_allowed_v704($1,$2,to_jsonb(x),$3)),m as(select variant_id,location_id,sum(quantity_delta) qty from public.%I x where tenant_id=$1 and private.audit_record_allowed_v704($1,$4,to_jsonb(x),$3) group by variant_id,location_id) select count(*) from b full join m using(variant_id,location_id) where abs(coalesce(b.quantity,0)-coalesce(m.qty,0))>0.0001',x.balances,x.movements)
  into n using t,x.balances,loc,x.movements;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','stock_'||x.balances,'reference',replace(x.balances,'_',' '),'title','Current saved quantity differs from movement ledger','count',n,'status',case when n>0 then 'Needs review' else 'Passed' end,'dataset',x.balances,'basis','Current balance versus all recorded movements. Historical opening gaps require investigation; quantities are not repaired automatically.'));
 end loop;
 -- Single-column FKs can exist while linking a row to another tenant.
 for x in
  select distinct cn.relname child,pn.relname parent,ca.attname col
  from pg_catalog.pg_constraint fk join pg_catalog.pg_class cn on cn.oid=fk.conrelid join pg_catalog.pg_class pn on pn.oid=fk.confrelid
  join pg_catalog.pg_attribute ca on ca.attrelid=cn.oid and ca.attnum=fk.conkey[1]
  join pg_catalog.pg_attribute pa on pa.attrelid=pn.oid and pa.attnum=fk.confkey[1]
  where fk.contype='f' and cardinality(fk.conkey)=1 and fk.connamespace='public'::regnamespace and pa.attname='id'
   and exists(select 1 from jsonb_array_elements(private.audit_catalog_v704()) c where c->>'key'=cn.relname and (c->>'tenant_column')::boolean)
   and exists(select 1 from jsonb_array_elements(private.audit_catalog_v704()) c where c->>'key'=pn.relname and (c->>'tenant_column')::boolean)
 loop
  execute format('select count(*) from public.%I c join public.%I p on p.id=c.%I where c.tenant_id=$1 and p.tenant_id<>$1 and private.audit_record_allowed_v704($1,$2,to_jsonb(c),$3)',x.child,x.parent,x.col)
  into n using t,x.child,loc;
  if n>0 then rows:=rows||jsonb_build_array(jsonb_build_object('id','tenant_link_'||x.child||'_'||x.col,'reference',replace(x.child,'_',' '),'title','Linked record belongs to another business','count',n,'status','High risk','dataset',x.child));end if;
 end loop;
 for root in select distinct e.correlation_id,e.root_entity_type,e.root_entity_id from public.transaction_story_events_v600 e where e.tenant_id=t and private.audit_record_allowed_v704(t,'transaction_story_events_v600',to_jsonb(e),loc) loop
  if exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=t and e.correlation_id=root.correlation_id and not private.audit_record_allowed_v704(t,'transaction_story_events_v600',to_jsonb(e),loc)) then partial:=partial+1;continue;end if;
  verification:=public.transaction_story_verify_v600(t,root.root_entity_type,root.root_entity_id);
  if coalesce((verification->>'valid')::boolean,false) then verified:=verified+1;else failed:=failed+1;end if;
 end loop;
 rows:=rows||jsonb_build_array(jsonb_build_object('id','story_integrity','reference','History integrity','title','Recorded story chains failing hash verification','count',failed,'status',case when failed>0 then 'High risk' else 'Passed' end,'verified_chains',verified,'partial_scope_chains',partial,'basis','Verifies recorded chains only. Chains crossing the authorised store scope are excluded; missing earlier history is not reconstructed.'));
 return jsonb_build_object('rows',rows,'total_rows',jsonb_array_length(rows),'generated_at',statement_timestamp(),'basis','Checks inspect saved evidence. Passed checks do not establish completeness of documents never entered or imported. External statements, confirmations, physical counts and statutory filings still need supporting evidence.');
end $$;

create or replace function private.audit_record_allowed_v704(t uuid,dataset text,r jsonb,loc uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if dataset='entity_attachments' and r->>'visibility'='private' and not private.erp_user_is_owner(t) and r->>'uploaded_by' is distinct from auth.uid()::text then return false;end if;
 return exists(select 1 from unnest(private.audit_record_locations_v704(t,dataset,r)) l where private.reports_scope_v631(t,l,loc,'view'));
end $$;
revoke all on function private.audit_record_allowed_v704(uuid,text,jsonb,uuid) from public,anon,authenticated;
create or replace function private.audit_capture_v704() returns trigger
language plpgsql security definer set search_path='' as $$
declare r jsonb;b jsonb;a jsonb;cfg jsonb;t uuid;eid uuid;root_id uuid;root_type text;lid uuid;reference text;related jsonb:='[]';
begin
 b:=case when tg_op<>'INSERT' then to_jsonb(old) end;
 a:=case when tg_op<>'DELETE' then to_jsonb(new) end;
 if tg_op='UPDATE' and b is not distinct from a then return new;end if;
 r:=coalesce(a,b);t:=(r->>'tenant_id')::uuid;eid:=(r->>'id')::uuid;
 select value into cfg from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=tg_table_name;
 if cfg is null then raise exception 'Audit capture table is not registered';end if;
 root_id:=eid;root_type:=cfg->>'entity';
 if cfg->'parent'<>'null'::jsonb and nullif(r->>(cfg#>>'{parent,0}'),'') is not null then
  root_id:=(r->>(cfg#>>'{parent,0}'))::uuid;
  select value->>'entity' into root_type from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=cfg#>>'{parent,1}';
  related:=jsonb_build_array(jsonb_build_object('type',root_type,'id',root_id));
 end if;
 select l into lid from unnest(private.audit_record_locations_v704(t,tg_table_name,r)) l where l is not null limit 1;
 reference:=coalesce(r->>'sale_number',r->>'purchase_number',r->>'payment_number',r->>'receipt_number',r->>'loan_number',r->>'load_number',r->>'order_number',r->>'trip_number',r->>'voucher_number',r->>'job_number',r->>'run_number',r->>'staff_code',r->>'return_number',r->>'name',cfg->>'label');
 perform private.v600_story_write(
  p_tenant_id=>t,p_entity_type=>cfg->>'entity',p_entity_id=>eid,
  p_entity_reference=>reference,p_action=>lower(tg_op)||'_saved_record',
  p_event_time=>statement_timestamp(),p_actor_user_id=>auth.uid(),
  p_location_id=>lid,p_before=>private.audit_clean_v704(b,true),
  p_after=>private.audit_clean_v704(a,true),
  p_reason=>coalesce(r->>'reason',r->>'void_reason',r->>'cancel_reason'),
  p_source_module=>cfg->>'group',p_source_function=>'audit_capture_v704',
  p_root_entity_type=>root_type,p_root_entity_id=>root_id,
  p_related_entities=>related,p_metadata=>jsonb_build_object('capture_version','v704','dataset',tg_table_name)
 );
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create or replace function private.audit_clean_v704(v jsonb, sensitive boolean) returns jsonb
language plpgsql immutable set search_path='' as $$
declare outv jsonb; k text; x jsonb;
begin
 if jsonb_typeof(v)='object' then
  outv:='{}';
  for k,x in select * from jsonb_each(v) loop
   if k ~* '(secret|password|token|credential|activation_hash|provider_config|stack_trace|api[_-]?key|authorization|cookie)' then continue;end if;
   if not sensitive and k in('before_data','after_data','before_state','after_state','bank_account','bank_ifsc','payee_snapshot','address','emergency_contact') then continue;end if;
   outv:=outv||jsonb_build_object(k,private.audit_clean_v704(x,sensitive));
  end loop;return outv;
 elsif jsonb_typeof(v)='array' then
  select coalesce(jsonb_agg(private.audit_clean_v704(value,sensitive)),'[]') into outv from jsonb_array_elements(v);return outv;
 end if;return v;
end $$;
;
