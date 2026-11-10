create or replace function public.gst_ui_contract_v520(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v jsonb;
  v_mode_obj jsonb;
  v_mode text;
  v_tabs jsonb:='[]'::jsonb;
  t jsonb;
  k text;
begin
  v:=public.gst_ui_contract_base_v520(p_tenant_id);
  v_mode_obj:=public.gst_tax_mode_get_v520(p_tenant_id,current_date);
  v_mode:=coalesce(v_mode_obj->>'tax_mode','unconfigured');

  for t in select value from jsonb_array_elements(coalesce(v->'tabs','[]'::jsonb)) loop
    k:=coalesce(t->>'key','');

    if k='returns' then
      t:=t || jsonb_build_object(
        'enabled',true,
        'submission_enabled',true,
        'workspace_rpc','gst_returns_workspace_v600',
        'gstr1_preview_rpc','gst_gstr1_preview_v600',
        'gstr1a_preview_rpc','gst_gstr1a_preview_v600',
        'gstr3b_preview_rpc','gst_gstr3b_preview_v600',
        'gstr2b_reconciliation_rpc','gst_gstr2b_reconciliation_v600',
        'period_ensure_rpc','gst_return_period_ensure_v600',
        'period_list_rpc','gst_return_periods_list_v600',
        'period_action_rpc','gst_return_period_action_v600',
        'gstr1_submit_rpc','gst_gstr1_submit_queue_v600',
        'gstr3b_submit_rpc','gst_gstr3b_submit_queue_v600',
        'gstr2b_fetch_rpc','gst_gstr2b_fetch_queue_v600',
        'ims_fetch_rpc','gst_ims_fetch_queue_v600',
        'turnover_get_rpc','gst_turnover_profile_get_v600',
        'turnover_save_rpc','gst_turnover_profile_save_v600'
      );
    elsif k='einvoice' then
      t:=t || jsonb_build_object(
        'enabled',true,
        'reason',null,
        'preview_rpc','gst_einvoice_preview_v600',
        'queue_rpc','gst_einvoice_queue_v600',
        'status_rpc','gst_provider_status_v600',
        'cancel_rpc','gst_irn_cancel_queue_v600',
        'retry_rpc','gst_provider_job_retry_v600',
        'connection_status_rpc','gst_provider_connection_status_v600'
      );
    elsif k='ewaybill' then
      t:=t || jsonb_build_object(
        'enabled',true,
        'reason',null,
        'preview_rpc','gst_ewaybill_preview_v600',
        'queue_rpc','gst_ewaybill_queue_v600',
        'status_rpc','gst_provider_status_v600',
        'cancel_rpc','gst_ewaybill_cancel_queue_v600',
        'retry_rpc','gst_provider_job_retry_v600',
        'connection_status_rpc','gst_provider_connection_status_v600'
      );
    end if;

    if v_mode='non_gst' and k in ('registrations','products','parties','tax_summary','accounting','returns','einvoice','ewaybill') then
      t:=jsonb_set(t,'{enabled}','false'::jsonb,true)
          || jsonb_build_object('reason','not_applicable_non_gst');
    end if;

    v_tabs:=v_tabs||jsonb_build_array(t);
  end loop;

  v:=jsonb_set(v,'{tabs}',v_tabs,true);
  v:=coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'release','6.0-gst-compliance',
    'contract_version',7,
    'tax_mode',v_mode_obj,
    'tax_mode_rpc','gst_tax_mode_get_v520',
    'tax_mode_save_rpc','gst_tax_mode_set_v520',
    'gst_compliance_required',v_mode='gst_registered'
  );
  v:=jsonb_set(v,'{form_options}',coalesce(v->'form_options','{}'::jsonb)||jsonb_build_object(
    'business_tax_modes',jsonb_build_array('gst_registered','non_gst')
  ),true);
  v:=jsonb_set(v,'{rules}',coalesce(v->'rules','{}'::jsonb)||jsonb_build_object(
    'tenant_tax_mode_required',true,
    'non_gst_invoice_class','commercial_invoice',
    'non_gst_gst_amounts_zero',true,
    'non_gst_returns_follow_original_document_tax_mode',true,
    'non_gst_gst_setup_required',false,
    'non_gst_provider_required',false,
    'provider_submission','provider_adapter_required',
    'provider_credentials_location','edge_function_environment',
    'provider_fail_closed',true,
    'non_gst_hidden_tabs',jsonb_build_array('registrations','products','parties','tax_summary','accounting','returns','einvoice','ewaybill')
  ),true);
  return v;
end
$function$;

create or replace function public.gst_compliance_bootstrap_v520(
  p_tenant_id uuid,
  p_from date default null,
  p_to date default null,
  p_location_id uuid default null,
  p_document_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_from date:=coalesce(p_from,date_trunc('month',current_date)::date);
  v_to date:=coalesce(p_to,current_date);
  v_limit integer:=coalesce(p_document_limit,50);
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,current_date);
begin
  if p_tenant_id is null then raise exception 'Tenant is required'; end if;
  if v_from>v_to then raise exception 'GST period start date cannot be after end date'; end if;
  if v_limit<1 or v_limit>100 then raise exception 'GST bootstrap document limit must be between 1 and 100'; end if;

  return jsonb_build_object(
    'release','6.0-gst-compliance',
    'contract_version',3,
    'server_date',current_date,
    'tax_mode',v_mode,
    'period',jsonb_build_object('from',v_from,'to',v_to,'location_id',p_location_id),
    'rules',jsonb_build_object(
      'tax_calculation','server_authoritative_only',
      'tenant_tax_mode_required',true,
      'gst_applicable',v_mode='gst_registered',
      'legacy_transactions','view_only_legacy_unverified',
      'v520_failure_fallback',false,
      'provider_submission',true,
      'provider_phase','provider_adapter_ready',
      'provider_fail_closed',true,
      'provider_credentials_location','edge_function_environment'
    ),
    'ui_contract',public.gst_ui_contract_v520(p_tenant_id),
    'workspace',public.gst_compliance_workspace_v520(p_tenant_id,v_from,v_to,p_location_id),
    'masters',public.gst_masters_v520(p_tenant_id,v_to),
    'readiness',public.gst_compliance_readiness_v520(p_tenant_id),
    'documents',public.gst_documents_list_v520(p_tenant_id,v_from,v_to,p_location_id,null,'all','',v_limit,0),
    'defaults',jsonb_build_object(
      'document_limit',v_limit,'document_evidence_status','all','document_query','','document_offset',0,
      'tax_mode',v_mode
    )
  );
end
$function$;

revoke all on function public.gst_ui_contract_v520(uuid) from public,anon;
grant execute on function public.gst_ui_contract_v520(uuid) to authenticated;
revoke all on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) from public,anon;
grant execute on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) to authenticated;