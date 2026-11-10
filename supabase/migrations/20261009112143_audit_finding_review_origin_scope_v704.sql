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
  select * into f from public.audit_findings_v600 where tenant_id=p_tenant_id and id=p_finding_id and private.audit_record_allowed_v704(p_tenant_id,'audit_findings_v600',to_jsonb(audit_findings_v600),null);
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
  from public.transaction_story_events_v600 e where e.tenant_id=p_tenant_id and e.correlation_id=f.correlation_id and private.audit_record_allowed_v704(p_tenant_id,'transaction_story_events_v600',to_jsonb(e),null);
  return jsonb_build_object('review_history',(select coalesce(jsonb_agg(jsonb_build_object('reviewed_at',a.created_at,'reviewer',u.username,'status',a.after_data->>'status','review_note',a.after_data->>'review_note','resolution_note',a.after_data->>'resolution_note') order by a.created_at),'[]') from public.business_audit_log a left join public.user_login_names u on u.user_id=a.user_id where a.tenant_id=p_tenant_id and a.entity_type='audit_finding' and a.entity_id=p_finding_id),'finding',to_jsonb(f),'sensitive_values_visible',v_sensitive,'transaction_story',v_events);
end;
$function$;
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
  select to_jsonb(x) into v_before from public.audit_findings_v600 x where x.tenant_id=p_tenant_id and x.id=p_finding_id and private.audit_record_allowed_v704(p_tenant_id,'audit_findings_v600',to_jsonb(x),null);
  if v_before is null then raise exception 'Audit finding not found'; end if;
  update public.audit_findings_v600 set status=p_status,reviewer_id=auth.uid(),reviewed_at=now(),
    review_note=case when v_resolve then review_note else coalesce(nullif(trim(p_note),''),review_note) end,
    resolution_note=case when v_resolve then coalesce(nullif(trim(p_note),''),resolution_note) else resolution_note end
  where tenant_id=p_tenant_id and id=p_finding_id returning * into f;
  perform private.business_audit_write(p_tenant_id,'audit_finding_reviewed','audit_finding',p_finding_id,f.entity_reference,v_before,to_jsonb(f));
  return to_jsonb(f);
end;
$function$;;
