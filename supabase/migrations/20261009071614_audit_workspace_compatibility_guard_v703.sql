create or replace function private.audit_workspace_v703(t uuid, k text, f date, z date, loc uuid, q text, severity text, lifecycle text, sort_key text, descending boolean, page_offset integer, page_limit integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
 from public.audit_findings_v600 a where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.reports_scope_v631(t,a.location_id,loc,'view');
 if k='findings' then
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'finding_id',a.id,'date',a.detected_at,'reference',coalesce(a.entity_reference,e.entity_reference),
   'title',a.title,'description',a.description,'severity',a.severity,'status',a.status,'risk_score',a.risk_score,'entity_type',a.entity_type,'entity_id',a.entity_id,
   'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,'location',b.name,'device',e.device_name,'rule',a.rule_code)), '[]') into raw
  from public.audit_findings_v600 a left join public.transaction_story_events_v600 e on e.tenant_id=t and e.id=a.source_event_id
  left join public.business_locations b on b.tenant_id=t and b.id=a.location_id
  where a.tenant_id=t and a.detected_at>=lo and a.detected_at<hi and private.reports_scope_v631(t,a.location_id,loc,'view')
   and (coalesce($7,'')='' or a.severity=$7)
   and (coalesce(lifecycle,'')='' or (lifecycle='active' and a.status in('open','under_review','escalated')) or a.status=lifecycle);
 elsif k='activity' then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.event_time,'reference',e.entity_reference,'title',initcap(replace(e.action,'_',' ')),
   'entity_type',e.entity_type,'entity_id',e.entity_id,'root_entity_type',e.root_entity_type,'root_entity_id',e.root_entity_id,'actor',e.actor_name,
   'location',b.name,'device',e.device_name,'reason',e.reason,'evidence_quality',case when coalesce((e.metadata->>'historical_reconstruction')::boolean,false) then 'Historical baseline' else 'Recorded event' end)), '[]') into raw
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
end $$;
