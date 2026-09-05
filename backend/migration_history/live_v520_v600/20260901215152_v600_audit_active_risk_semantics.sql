create or replace function public.audit_center_summary_v600(
  p_tenant_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_from timestamptz := coalesce(p_from,date_trunc('day',now()));
  v_to timestamptz := coalesce(p_to,now());
  v_high bigint:=0; v_review bigint:=0; v_open bigint:=0; v_normal bigint:=0; v_total_roots bigint:=0;
  v_resolved bigint:=0; v_dismissed bigint:=0; v_explained bigint:=0; v_total_findings bigint:=0;
begin
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
    and (p_location_id is null or f.location_id=p_location_id);

  select count(distinct e.correlation_id) into v_total_roots
  from public.transaction_story_events_v600 e
  where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
    and (p_location_id is null or e.location_id=p_location_id);

  select count(*) into v_normal from (
    select distinct e.correlation_id
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
      and (p_location_id is null or e.location_id=p_location_id)
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
$$;

create or replace function public.audit_normal_transactions_v600(
  p_tenant_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
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
      and (p_location_id is null or e.location_id=p_location_id)
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
$$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (267,'6.0.0-build1','Audit Active-Risk Semantics','Audit Center High Risk and Needs Review cards now count active attention states only. Transactions whose findings are explained/resolved/dismissed return to the Normal feed while their immutable finding evidence remains available in lifecycle history. Summary exposes retained finding lifecycle counts separately.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;