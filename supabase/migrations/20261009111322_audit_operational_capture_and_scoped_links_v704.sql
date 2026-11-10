-- Capture future operational changes through the existing immutable story writer.
-- No historical backfill: previous edits are never invented.
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
  p_reason=>coalesce(r->>'reason',r->>'void_reason',r->>'cancel_reason',r->>'notes'),
  p_source_module=>cfg->>'group',p_source_function=>'audit_capture_v704',
  p_root_entity_type=>root_type,p_root_entity_id=>root_id,
  p_related_entities=>related,p_metadata=>jsonb_build_object('capture_version','v704','dataset',tg_table_name)
 );
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function private.audit_capture_v704() from public,anon,authenticated;
do $$ declare tbl text;begin
 foreach tbl in array array[
 'accounting_accounts','customers','suppliers','products','product_variants',
 'customer_receipts','expenses','purchase_returns','party_settlements_v626',
 'finance_vouchers_v500','bank_statement_lines_v500','opening_balance_batches_v500',
 'staff_members_v630','staff_earnings_v630','staff_payments_v630',
 'aggregate_loads_v617','aggregate_orders_v618','material_load_costs_v630','material_load_cost_payments_v630',
 'transport_logistics_trips','transport_trip_hub_v611','loan_accounts_v490','loan_payments_v490',
 'stock_transfers','stock_counts','inventory_batches_v483','inventory_serials_v483',
 'production_runs','service_jobs','workshop_job_cards','restaurant_orders','restaurant_kots'
 ] loop
  if not exists(select 1 from pg_catalog.pg_trigger tr join pg_catalog.pg_proc p on p.oid=tr.tgfoid where tr.tgrelid=format('public.%I',tbl)::regclass and not tr.tgisinternal and p.proname in('v600_capture_business_row','audit_capture_v704')) then
   execute format('create trigger trg_audit_capture_v704 after insert or update or delete on public.%I for each row execute function private.audit_capture_v704()',tbl);
  end if;
 end loop;
end $$;

create or replace function private.audit_related_v704(t uuid,dataset text,field text,ref text,loc uuid,off integer,lim integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare data jsonb;matched jsonb:='[]';allrows jsonb:='[]';page jsonb;skip integer:=0;total integer;
begin
 perform private.audit_access_v703(t,loc);
 if off is null or off<0 or lim is null or lim<1 or lim>200 or ref is null or length(ref)>80 or not exists(select 1 from pg_catalog.pg_attribute where attrelid=to_regclass('public.'||dataset) and attname=field and not attisdropped) then raise exception 'Invalid relation selector' using errcode='22023';end if;
 loop
  data:=private.audit_evidence_v704(t,dataset,'1900-01-01','2200-01-01',loc,ref,skip,200);
  total:=(data->>'total_rows')::integer;
  allrows:=allrows||(data->'rows');skip:=skip+jsonb_array_length(data->'rows');
  exit when skip>=total;
 end loop;
 select coalesce(jsonb_agg(value order by value->>'date' desc nulls last,value->>'id'),'[]') into matched from jsonb_array_elements(allrows) where value#>>array['record',field]=ref;
 select coalesce(jsonb_agg(value order by ordinality),'[]') into page from jsonb_array_elements(matched) with ordinality where ordinality>off and ordinality<=off+lim;
 return jsonb_build_object('rows',page,'total_rows',jsonb_array_length(matched),'snapshot_token',md5(matched::text));
end $$;
revoke all on function private.audit_related_v704(uuid,text,text,text,uuid,integer,integer) from public,anon;
grant execute on function private.audit_related_v704(uuid,text,text,text,uuid,integer,integer) to authenticated;
create or replace function public.audit_related_v704(p_tenant_id uuid,p_dataset text,p_match_field text,p_match_value text,p_location_id uuid default null,p_offset integer default 0,p_limit integer default 50) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.audit_related_v704(p_tenant_id,p_dataset,p_match_field,p_match_value,p_location_id,p_offset,p_limit) $$;
revoke all on function public.audit_related_v704(uuid,text,text,text,uuid,integer,integer) from public,anon;
grant execute on function public.audit_related_v704(uuid,text,text,text,uuid,integer,integer) to authenticated;
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
   'entity_type',e.entity_type,'entity_id',e.entity_id,'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,
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
   'entity_type',e.entity_type,'entity_id',e.entity_id,'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,
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
;
