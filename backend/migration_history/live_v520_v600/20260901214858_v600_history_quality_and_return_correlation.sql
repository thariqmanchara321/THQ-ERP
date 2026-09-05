alter function public.transaction_explain_v600(uuid,text,uuid,integer) rename to transaction_explain_core_v600;
revoke all on function public.transaction_explain_core_v600(uuid,text,uuid,integer) from public,anon,authenticated;

create or replace function public.transaction_explain_v600(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
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
    where e.tenant_id=p_tenant_id and (
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
$$;
revoke all on function public.transaction_explain_v600(uuid,text,uuid,integer) from public,anon;
grant execute on function public.transaction_explain_v600(uuid,text,uuid,integer) to authenticated;

create or replace function public.transaction_history_v600(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_limit integer default 250
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v jsonb;
begin
  v:=public.transaction_explain_v600(p_tenant_id,p_entity_type,p_entity_id,p_limit);
  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'requested_entity',v->'requested_entity',
    'transaction_root',v->'transaction_root',
    'tracking_quality',v->'tracking_quality',
    'historical_notice',v->'historical_notice',
    'story_counts',v->'story_counts',
    'sensitive_values_visible',v->'sensitive_values_visible',
    'events',v->'transaction_story'
  );
end;
$$;
revoke all on function public.transaction_history_v600(uuid,text,uuid,integer) from public,anon;
grant execute on function public.transaction_history_v600(uuid,text,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (265,'6.0.0-build1','History Quality + Return Correlation','Correctly distinguishes native v6 events from reconstructed historical baselines, exposes event-level evidence quality/metadata, and includes sale-return correlation chains (such as return journals/stock movements) in the parent sale Why/History timeline without rewriting existing hash chains.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;