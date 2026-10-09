
-- Audit reads the same effective journal lines as Accounting v702.
-- No financial writer, invoice, GST snapshot or historical event is changed.
create or replace function private.audit_access_v703(t uuid, loc uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(t) or not private.has_permission(t,'audit_center.view') then
  raise exception 'Audit access denied' using errcode='42501';
 end if;
 if loc is not null and not exists(select 1 from public.business_locations b where b.id=loc and b.tenant_id=t and private.reports_scope_v631(t,b.id,loc,'view')) then
  raise exception 'Store access denied' using errcode='42501';
 end if;
end $$;
revoke all on function private.audit_access_v703(uuid,uuid) from public,anon,authenticated;

create or replace function private.audit_workspace_v703(t uuid, k text, f date, z date, loc uuid, q text, severity text, lifecycle text, sort_key text, descending boolean, page_offset integer, page_limit integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare raw jsonb:='[]'; matched jsonb; paged jsonb; summary jsonb; tz text; lo timestamptz; hi timestamptz; n bigint; totals jsonb; checks jsonb;
begin
 perform private.audit_access_v703(t,loc);
 if f is null or z is null or f>z or page_offset<0 or page_limit<1 or page_limit>200 then raise exception 'Invalid audit query' using errcode='22023';end if;
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
   and (coalesce(severity,'')='' or a.severity=severity)
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
revoke all on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) from public,anon;
grant execute on function private.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) to authenticated;
create or replace function public.audit_workspace_v703(p_tenant_id uuid,p_view text,p_from date,p_to date,p_location_id uuid default null,p_query text default '',p_severity text default '',p_status text default '',p_sort_key text default 'date',p_sort_desc boolean default true,p_offset integer default 0,p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.audit_workspace_v703(p_tenant_id,p_view,p_from,p_to,p_location_id,p_query,p_severity,p_status,p_sort_key,p_sort_desc,p_offset,p_limit)
$$;
revoke all on function public.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) from public,anon;
grant execute on function public.audit_workspace_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer) to authenticated;

create or replace function private.audit_metric_weight_v703(m text,a text,s text,method text) returns numeric
language sql immutable set search_path='' as $$ select case
 when m='sales' and s='sales_revenue' then -1
 when m='cogs' and a='cogs' then 1
 when m='gross_profit' and s='sales_revenue' then -1 when m='gross_profit' and a='cogs' then -1
 when m='net_profit' and a in('income','cogs','expense') then -1
 when m='inventory_value' and s='inventory_asset' then 1
 when m='receivables' and s in('accounts_receivable','customer_credits') then 1
 when m='payables' and s in('accounts_payable','supplier_credits') then -1
 when m='cash' and method='cash' then 1
 when m='bank' and method='bank' then 1
 when m='upi' and method='upi' then 1 when m='card' and method='card' then 1
 when m='gst_payable' and (s like 'output\_%' escape '\' or s like 'input\_%' escape '\' or s like 'rcm\_%' escape '\') then -1
 else 0 end $$;
revoke all on function private.audit_metric_weight_v703(text,text,text,text) from public,anon,authenticated;

create or replace function private.explain_metric_v703(t uuid,m text,f date,z date,loc uuid,lim integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare raw jsonb;components jsonb;drivers jsonb;current_value numeric;previous_value numeric;change_value numeric;driver_sum numeric;pf date;pz date;balance_metric boolean;formula text;
begin
 perform private.audit_access_v703(t,loc);
 if not private.has_permission(t,'explain.view') then raise exception 'Explanation access denied' using errcode='42501';end if;
 if f is null or z is null or f>z or m not in('sales','cogs','gross_profit','net_profit','inventory_value','receivables','payables','cash','bank','upi','card','gst_payable') then raise exception 'Invalid metric query' using errcode='22023';end if;
 balance_metric:=m not in('sales','cogs','gross_profit','net_profit');pz:=f-1;pf:=pz-(z-f);
 select coalesce(jsonb_agg(x||jsonb_build_object('weight',private.audit_metric_weight_v703(m,x->>'account_type',x->>'system_key',x->>'money_method'))),'[]') into raw
 from private.accounting_lines_v702(t,z,loc) x where private.audit_metric_weight_v703(m,x->>'account_type',x->>'system_key',x->>'money_method')<>0;
 select coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where balance_metric or (x->>'date')::date>=f),0),
 coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where (x->>'date')::date<=pz and (balance_metric or (x->>'date')::date>=pf)),0) into current_value,previous_value from jsonb_array_elements(raw) x;
 change_value:=current_value-previous_value;
 select coalesce(jsonb_agg(jsonb_build_object('account_id',aid,'label',name,'code',code,'value',cur,'previous_value',prev,'change',cur-prev) order by code,aid),'[]') into components
 from(select x->>'account_id' aid,max(x->>'account_name') name,max(x->>'account_code') code,
  coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where balance_metric or (x->>'date')::date>=f),0) cur,
  coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where (x->>'date')::date<=pz and (balance_metric or (x->>'date')::date>=pf)),0) prev
 from jsonb_array_elements(raw) x group by x->>'account_id') c;
 select coalesce(jsonb_agg(jsonb_build_object('source_type',source,'label',initcap(replace(source,'_',' ')),'current_value',cur,'previous_value',prev,'impact',cur-prev) order by abs(cur-prev) desc,source),'[]') into drivers
 from(select x->>'source_type' source,
  coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where (x->>'date')::date>=f),0) cur,
  coalesce(sum(((x->>'debit')::numeric-(x->>'credit')::numeric)*(x->>'weight')::numeric) filter(where not balance_metric and (x->>'date')::date between pf and pz),0) prev
 from jsonb_array_elements(raw) x group by x->>'source_type') d where cur<>0 or prev<>0;
 -- Keep the complete driver bridge; it is source-grouped and never truncated.
 select coalesce(sum((x->>'impact')::numeric),0) into driver_sum from jsonb_array_elements(drivers) x;
 formula:=case m when 'gross_profit' then 'Sales revenue − cost of goods sold' when 'net_profit' then 'Income − cost of goods sold − expenses'
 when 'receivables' then 'Customer receivable debits less credits, including customer credits' when 'payables' then 'Supplier payable credits less debits, including supplier credits'
 when 'gst_payable' then 'Output and reverse-charge liabilities less input tax assets' else 'Sum of the linked account contributions below' end;
 return jsonb_build_object('metric',m,'label',case m when 'cogs' then 'Cost of goods sold' when 'gst_payable' then 'Net GST payable' else initcap(replace(m,'_',' ')) end,
 'value',current_value,'previous',jsonb_build_object('value',previous_value,'from',case when balance_metric then null else pf end,'to',pz),
 'change',change_value,'equation',formula,'kind',case when balance_metric then 'balance' else 'period' end,'components',components,'drivers',drivers,
 'driver_reconciliation',jsonb_build_object('sum',driver_sum,'expected_change',change_value,'reconciles',abs(driver_sum-change_value)<=0.005),
 'basis','Same effective ledger basis as Accounting v702. Archived accounts with history and compensating reversals are included.');
end $$;
revoke all on function private.explain_metric_v703(uuid,text,date,date,uuid,integer) from public,anon;
grant execute on function private.explain_metric_v703(uuid,text,date,date,uuid,integer) to authenticated;
create or replace function public.explain_metric_v703(p_tenant_id uuid,p_metric text,p_from date,p_to date,p_location_id uuid default null,p_driver_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$ select private.explain_metric_v703(p_tenant_id,p_metric,p_from,p_to,p_location_id,p_driver_limit) $$;
revoke all on function public.explain_metric_v703(uuid,text,date,date,uuid,integer) from public,anon;
grant execute on function public.explain_metric_v703(uuid,text,date,date,uuid,integer) to authenticated;

create or replace function private.audit_ledger_v703(t uuid,a uuid,f date,z date,loc uuid,q text,off integer,lim integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare raw jsonb;matched jsonb;paged jsonb;opening numeric;closing numeric;
begin
 perform private.audit_access_v703(t,loc);
 if f is null or z is null or f>z or off<0 or lim<1 or lim>200 then raise exception 'Invalid ledger query' using errcode='22023';end if;
 if not exists(select 1 from public.accounting_accounts where tenant_id=t and id=a) then raise exception 'Account unavailable' using errcode='42501';end if;
 select coalesce(jsonb_agg(x),'[]') into raw from private.accounting_rows_v702(t,'general_ledger',f,z,loc,jsonb_build_object('account_id',a)) x;
 select coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric) filter(where (x->>'date')::date<f),0),coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric),0) into opening,closing
 from private.accounting_lines_v702(t,z,loc) x where x->>'account_id'=a::text;
 select coalesce(jsonb_agg(value order by value->>'date',value->>'created_at',value->>'id'),'[]') into matched from jsonb_array_elements(raw) where private.accounting_search_v702(value,q);
 select coalesce(jsonb_agg(value order by ordinality),'[]') into paged from jsonb_array_elements(matched) with ordinality where ordinality>off and ordinality<=off+lim;
 return jsonb_build_object('rows',paged,'total_rows',jsonb_array_length(matched),'opening',opening,'closing',closing);
end $$;
revoke all on function private.audit_ledger_v703(uuid,uuid,date,date,uuid,text,integer,integer) from public,anon;
grant execute on function private.audit_ledger_v703(uuid,uuid,date,date,uuid,text,integer,integer) to authenticated;
create or replace function public.audit_ledger_v703(p_tenant_id uuid,p_account_id uuid,p_from date,p_to date,p_location_id uuid default null,p_query text default '',p_offset integer default 0,p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$ select private.audit_ledger_v703(p_tenant_id,p_account_id,p_from,p_to,p_location_id,p_query,p_offset,p_limit) $$;
revoke all on function public.audit_ledger_v703(uuid,uuid,date,date,uuid,text,integer,integer) from public,anon;
grant execute on function public.audit_ledger_v703(uuid,uuid,date,date,uuid,text,integer,integer) to authenticated;

CREATE OR REPLACE FUNCTION public.audit_center_summary_v600(p_tenant_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_from timestamptz := coalesce(p_from,date_trunc('day',now()));
  v_to timestamptz := coalesce(p_to,now());
  v_high bigint:=0; v_review bigint:=0; v_open bigint:=0; v_normal bigint:=0; v_total_roots bigint:=0;
  v_resolved bigint:=0; v_dismissed bigint:=0; v_explained bigint:=0; v_total_findings bigint:=0;
begin
  perform private.audit_access_v703(p_tenant_id,p_location_id);
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;

  select
    count(*) filter(where severity='high_risk' and status in ('open','under_review','escalated')),
    count(*) filter(where severity='needs_review' and status in ('open','under_review','escalated')),
    count(*) filter(where status in ('open','under_review','escalated')),
    count(*) filter(where status='resolved'),
    count(*) filter(where status='dismissed'),
    count(*) filter(where status='explained'),
    count(*)
  into v_high,v_review,v_open,v_resolved,v_dismissed,v_explained,v_total_findings
  from public.audit_findings_v600 f
  where f.tenant_id=p_tenant_id and f.detected_at>=v_from and f.detected_at<=v_to
    and private.reports_scope_v631(p_tenant_id,f.location_id,p_location_id,'view');

  select count(distinct e.correlation_id) into v_total_roots
  from public.transaction_story_events_v600 e
  where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
    and private.reports_scope_v631(p_tenant_id,e.location_id,p_location_id,'view');

  select count(*) into v_normal from (
    select distinct e.correlation_id
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
      and private.reports_scope_v631(p_tenant_id,e.location_id,p_location_id,'view')
      and not exists (
        select 1 from public.audit_findings_v600 f
        where f.tenant_id=e.tenant_id and f.correlation_id=e.correlation_id
          and f.detected_at>=v_from and f.detected_at<=v_to
          and f.status in ('open','under_review','escalated')
      )
  ) q;

  return jsonb_build_object(
    'from',v_from,'to',v_to,'location_id',p_location_id,
    'high_risk',coalesce(v_high,0),
    'needs_review',coalesce(v_review,0),
    'normal',coalesce(v_normal,0),
    'open_attention',coalesce(v_open,0),
    'transaction_roots',coalesce(v_total_roots,0),
    'finding_lifecycle',jsonb_build_object(
      'total',coalesce(v_total_findings,0),
      'resolved',coalesce(v_resolved,0),
      'dismissed',coalesce(v_dismissed,0),
      'explained',coalesce(v_explained,0)
    ),
    'category_rule','High Risk and Needs Review count only active attention states: open, under_review, escalated. Normal means no active finding in the selected period. Resolved, dismissed and explained evidence remains retained in history.'
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.audit_findings_list_v600(p_tenant_id uuid, p_severity text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_location_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin
  perform private.audit_access_v703(p_tenant_id,p_location_id);
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id,f.severity,f.risk_score,f.rule_code,f.title,f.description,f.status,f.detected_at,
      f.entity_type,f.entity_id,f.entity_reference,f.location_id,f.device_id,f.actor_user_id,f.reviewer_id,f.reviewed_at,f.review_note,f.resolution_note,
      e.actor_name,e.device_name,e.device_code,e.source_app,e.root_entity_type,e.root_entity_id
    from public.audit_findings_v600 f
    join public.transaction_story_events_v600 e on e.id=f.source_event_id and e.tenant_id=f.tenant_id
    where f.tenant_id=p_tenant_id
      and (p_severity is null or f.severity=p_severity)
      and (p_status is null or f.status=p_status)
      and (p_from is null or f.detected_at>=p_from)
      and (p_to is null or f.detected_at<=p_to)
      and private.reports_scope_v631(p_tenant_id,f.location_id,p_location_id,'view')
    order by f.detected_at desc
    limit greatest(1,least(coalesce(p_limit,200),1000))
  ) q;
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.audit_finding_detail_v600(p_tenant_id uuid, p_finding_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.audit_findings_v600%rowtype; v_sensitive boolean; v_events jsonb;
begin
  perform private.audit_access_v703(p_tenant_id,null);
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select * into f from public.audit_findings_v600 where tenant_id=p_tenant_id and id=p_finding_id and private.reports_scope_v631(p_tenant_id,location_id,null,'view');
  if not found then raise exception 'Audit finding not found'; end if;
  v_sensitive := private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence',e.event_sequence,'id',e.id,'action',e.action,'event_time',e.event_time,'entity_type',e.entity_type,'entity_id',e.entity_id,'entity_reference',e.entity_reference,
    'actor',jsonb_build_object('user_id',e.actor_user_id,'name',e.actor_name,'roles',e.actor_role_keys),
    'device',jsonb_build_object('id',e.device_id,'name',e.device_name,'code',e.device_code,'app',e.source_app),'location_id',e.location_id,
    'changed_fields',e.changed_fields,'before',case when v_sensitive then e.before_data else null end,'after',case when v_sensitive then e.after_data else null end,
    'reason',e.reason,'approval',jsonb_build_object('request_id',e.approval_request_id,'approved_by',e.approved_by,'approved_at',e.approved_at,'note',e.approval_note),
    'related_entities',e.related_entities,'event_hash',e.event_hash
  ) order by e.event_sequence),'[]'::jsonb) into v_events
  from public.transaction_story_events_v600 e where e.tenant_id=p_tenant_id and e.correlation_id=f.correlation_id and private.reports_scope_v631(p_tenant_id,e.location_id,null,'view');
  return jsonb_build_object('finding',to_jsonb(f),'sensitive_values_visible',v_sensitive,'transaction_story',v_events);
end;
$function$;


CREATE OR REPLACE FUNCTION public.audit_normal_transactions_v600(p_tenant_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_location_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin
  perform private.audit_access_v703(p_tenant_id,p_location_id);
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.last_event_at desc),'[]'::jsonb) into v_result
  from (
    select distinct on (e.correlation_id)
      e.correlation_id,e.root_entity_type,e.root_entity_id,e.entity_reference,e.event_time as last_event_at,e.action as last_action,
      e.actor_user_id,e.actor_name,e.location_id,e.device_id,e.device_name,e.device_code,e.source_app,
      case when coalesce((e.metadata->>'historical_reconstruction')::boolean,false) then 'historical_reconstructed_baseline' else 'native_v600_event' end as evidence_quality
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id
      and (p_from is null or e.event_time>=p_from)
      and (p_to is null or e.event_time<=p_to)
      and private.reports_scope_v631(p_tenant_id,e.location_id,p_location_id,'view')
      and not exists (
        select 1 from public.audit_findings_v600 f
        where f.tenant_id=e.tenant_id and f.correlation_id=e.correlation_id
          and (p_from is null or f.detected_at>=p_from)
          and (p_to is null or f.detected_at<=p_to)
          and f.status in ('open','under_review','escalated')
      )
    order by e.correlation_id,e.event_sequence desc
    limit greatest(1,least(coalesce(p_limit,200),1000))
  ) q;
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.transaction_explain_core_v600(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_event_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type text:=lower(trim(coalesce(p_entity_type,'')));
  v_root_type text;
  v_root_id uuid;
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
    select jsonb_build_object('entity_type',v_type,'entity_id',p_entity_id) into v_current;
  end if;

  if v_current is null then raise exception 'Transaction not found'; end if;
  if auth.uid() is null or not private.reports_scope_v631(p_tenant_id,nullif(v_current->>'location_id','')::uuid,null,'view') then
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
  where a.tenant_id=p_tenant_id and (
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
    where m.tenant_id=p_tenant_id and (
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
    where s.tenant_id=p_tenant_id and (
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
    where l.tenant_id=p_tenant_id and (
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


CREATE OR REPLACE FUNCTION public.transaction_explain_v600(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_event_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_base jsonb;
  v_root_type text;
  v_root_id uuid;
  v_root_corr uuid;
  v_story jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_native integer:=0;
  v_historical integer:=0;
  v_quality text;
  v_notice text;
begin
  v_base:=public.transaction_explain_core_v600(p_tenant_id,p_entity_type,p_entity_id,p_event_limit);
  v_root_type:=v_base#>>'{transaction_root,type}';
  v_root_id:=(v_base#>>'{transaction_root,id}')::uuid;
  v_root_corr:=(v_base#>>'{transaction_root,correlation_id}')::uuid;

  with candidate as (
    select e.*,
      coalesce((e.metadata->>'historical_reconstruction')::boolean,false) as is_historical
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,e.location_id,null,'view') and (
      e.correlation_id=v_root_corr
      or (
        v_root_type='sale' and e.correlation_id in (
          select extensions.uuid_generate_v5(
            extensions.uuid_ns_url(),
            'thq:v600:'||p_tenant_id::text||':sales_return:'||sr.id::text
          )
          from public.sales_returns sr
          where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id
        )
      )
    )
    order by e.event_time,e.event_sequence
    limit greatest(1,least(coalesce(p_event_limit,500),2000))
  )
  select count(*),
    count(*) filter(where not is_historical),
    count(*) filter(where is_historical),
    coalesce(jsonb_agg(jsonb_build_object(
      'sequence',event_sequence,'id',id,'correlation_id',correlation_id,'action',action,'event_time',event_time,
      'entity_type',entity_type,'entity_id',entity_id,'entity_reference',entity_reference,
      'actor',jsonb_build_object('user_id',actor_user_id,'name',actor_name,'roles',actor_role_keys),
      'location_id',location_id,'device',jsonb_build_object('id',device_id,'name',device_name,'code',device_code,'app',source_app),
      'changed_fields',changed_fields,
      'before',case when (v_base->>'sensitive_values_visible')::boolean then before_data else null end,
      'after',case when (v_base->>'sensitive_values_visible')::boolean then after_data else null end,
      'reason',reason,
      'approval',jsonb_build_object('request_id',approval_request_id,'approved_by',approved_by,'approved_at',approved_at,'note',approval_note),
      'source_module',source_module,'source_function',source_function,'related_entities',related_entities,
      'evidence_quality',case when is_historical then 'historical_reconstructed_baseline' else 'native_v600_event' end,
      'metadata',metadata,
      'integrity',jsonb_build_object('previous_hash',previous_event_hash,'event_hash',event_hash)
    ) order by event_time,event_sequence),'[]'::jsonb)
  into v_total,v_native,v_historical,v_story
  from candidate;

  if v_native>0 and v_historical>0 then
    v_quality:='enhanced_v600_with_historical_baseline';
    v_notice:='Native v6.0 events are available from the upgrade point forward. Earlier baseline entries are reconstructed only from records that already existed and are explicitly labeled; missing pre-v6 edits are not inferred.';
  elsif v_native>0 then
    v_quality:='enhanced_v600';
    v_notice:='Native v6.0 Transaction Story evidence is available for this transaction.';
  elsif v_historical>0 then
    v_quality:='historical_reconstructed_baseline';
    v_notice:='Historical transaction: baseline events were reconstructed from records that actually existed at upgrade time. They do not represent a complete pre-v6 edit history, and missing actor/reason/device changes are not fabricated.';
  else
    v_quality:=coalesce(v_base->>'tracking_quality','historical_baseline_only');
    v_notice:=v_base->>'historical_notice';
  end if;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_base,'{transaction_story}',v_story,true),
      '{tracking_quality}',to_jsonb(v_quality),true
    ),
    '{historical_notice}',to_jsonb(v_notice),true
  ) || jsonb_build_object('story_counts',jsonb_build_object('total',v_total,'native_v600',v_native,'historical_baseline',v_historical));
end;
$function$;


create or replace function private.audit_journal_v703(t uuid,i uuid,loc uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb; d date;
begin
 perform private.audit_access_v703(t,loc);
 select entry_date into d from public.journal_entries j where tenant_id=t and id=i and private.reports_scope_v631(t,j.location_id,loc,'view');
 if d is null then raise exception 'Journal unavailable' using errcode='42501';end if;
 select x into r from private.accounting_rows_v702(t,'journal',d,d,loc,'{}') x where x->>'id'=i::text;
 return r;
end $$;
revoke all on function private.audit_journal_v703(uuid,uuid,uuid) from public,anon;
grant execute on function private.audit_journal_v703(uuid,uuid,uuid) to authenticated;
create or replace function public.audit_journal_v703(p_tenant_id uuid,p_journal_id uuid,p_location_id uuid default null) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.audit_journal_v703(p_tenant_id,p_journal_id,p_location_id) $$;
revoke all on function public.audit_journal_v703(uuid,uuid,uuid) from public,anon;
grant execute on function public.audit_journal_v703(uuid,uuid,uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.audit_finding_review_v600(p_tenant_id uuid, p_finding_id uuid, p_status text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.audit_findings_v600%rowtype; v_before jsonb; v_resolve boolean;
begin
  perform private.audit_access_v703(p_tenant_id,null);
  if nullif(trim(p_note),'') is null then raise exception 'A review note is required' using errcode='22023';end if;
  if p_status not in ('open','under_review','explained','resolved','escalated','dismissed') then raise exception 'Invalid audit finding status'; end if;
  v_resolve:=p_status in ('resolved','escalated','dismissed');
  if v_resolve then
    if not private.has_permission(p_tenant_id,'audit_center.resolve') then raise exception 'Permission denied' using errcode='42501'; end if;
  elsif not private.has_permission(p_tenant_id,'audit_center.review') then raise exception 'Permission denied' using errcode='42501'; end if;
  select to_jsonb(x) into v_before from public.audit_findings_v600 x where x.tenant_id=p_tenant_id and x.id=p_finding_id and private.reports_scope_v631(p_tenant_id,x.location_id,null,'view');
  if v_before is null then raise exception 'Audit finding not found'; end if;
  update public.audit_findings_v600 set status=p_status,reviewer_id=auth.uid(),reviewed_at=now(),
    review_note=case when v_resolve then review_note else coalesce(nullif(trim(p_note),''),review_note) end,
    resolution_note=case when v_resolve then coalesce(nullif(trim(p_note),''),resolution_note) else resolution_note end
  where tenant_id=p_tenant_id and id=p_finding_id returning * into f;
  perform private.business_audit_write(p_tenant_id,'audit_finding_reviewed','audit_finding',p_finding_id,f.entity_reference,v_before,to_jsonb(f));
  return to_jsonb(f);
end;
$function$;
