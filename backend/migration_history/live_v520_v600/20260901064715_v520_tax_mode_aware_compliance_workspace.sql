-- THQ ERP v5.2 migration 254
-- Make compliance readiness/workspace/UI mode-aware after migration 253.

create or replace function public.gst_compliance_readiness_v520(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,current_date);
  v_setup jsonb;
  v_accounting jsonb;
  v_coverage jsonb;
  v_blockers jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_new_ready boolean:=false;
  v_history_ready boolean:=false;
  v_filing_data_ready boolean:=false;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then
    raise exception 'GST compliance view permission required';
  end if;

  v_accounting:=public.gst_accounting_health_v520(p_tenant_id);
  v_coverage:=public.gst_snapshot_coverage_v520(p_tenant_id);
  v_history_ready:=coalesce((v_coverage->>'legacy_unverified')::bigint,0)=0
    and coalesce((v_coverage->>'unclassified_documents')::bigint,0)=0
    and coalesce((v_coverage->>'legacy_source_hash_mismatches')::bigint,0)=0;

  if v_mode='unconfigured' then
    v_setup:=jsonb_build_object(
      'stage','v5.2-tax-mode-selection',
      'tax_mode','unconfigured',
      'tax_mode_configured',false,
      'gst_setup_required',null,
      'setup_ready',false,
      'notes','Choose GST Registered or Non-GST before v5.2 transactions are enabled.'
    );
    v_blockers:=v_blockers||jsonb_build_array('tax_mode_unconfigured');
    if not coalesce((v_accounting->>'ready')::boolean,false) then
      v_blockers:=v_blockers||jsonb_build_array('gst_accounting_mapping_or_integrity_issue');
    end if;

  elsif v_mode='non_gst' then
    v_setup:=jsonb_build_object(
      'stage','v5.2-non-gst',
      'tax_mode','non_gst',
      'tax_mode_configured',true,
      'gst_applicable',false,
      'gst_setup_required',false,
      'setup_ready',true,
      'registrations',0,
      'mapped_locations',0,
      'unmapped_locations',0,
      'tax_profiles',0,
      'profiles_missing_hsn_sac',0,
      'profiles_review_required',0,
      'party_gst_profiles',0,
      'provider_connected',false,
      'provider_applicable',false,
      'einvoice_live',false,
      'ewaybill_live',false,
      'returns_live',false,
      'notes','Business is configured as Non-GST. GST registration, GST rates, HSN/SAC readiness and GSP/IRP provider setup are not required for new v5.2 transactions.'
    );
    v_new_ready:=coalesce((v_accounting->>'ready')::boolean,false);
    if not v_new_ready then
      v_blockers:=v_blockers||jsonb_build_array('accounting_mapping_or_integrity_issue');
    end if;
    if not v_history_ready then
      v_warnings:=v_warnings||jsonb_build_array('legacy_history_remains_legacy_unverified');
    end if;

  else
    -- GST-registered mode retains the original strict GST readiness rules.
    v_setup:=public.gst_setup_health_v520(p_tenant_id);
    v_new_ready:=coalesce((v_setup->>'setup_ready')::boolean,false)
      and coalesce((v_accounting->>'ready')::boolean,false);
    v_filing_data_ready:=v_new_ready and v_history_ready;

    if not coalesce((v_setup->>'setup_ready')::boolean,false) then
      v_blockers:=v_blockers||jsonb_build_array('gst_setup_incomplete');
    end if;
    if not coalesce((v_accounting->>'ready')::boolean,false) then
      v_blockers:=v_blockers||jsonb_build_array('gst_accounting_mapping_or_integrity_issue');
    end if;
    if coalesce((v_coverage->>'unclassified_documents')::bigint,0)>0 then
      v_blockers:=v_blockers||jsonb_build_array('documents_without_gst_evidence');
    end if;
    if coalesce((v_coverage->>'legacy_source_hash_mismatches')::bigint,0)>0 then
      v_blockers:=v_blockers||jsonb_build_array('legacy_evidence_source_hash_mismatch');
    end if;
    if coalesce((v_coverage->>'legacy_unverified')::bigint,0)>0 then
      v_blockers:=v_blockers||jsonb_build_array('legacy_unverified_history_requires_review_or_migration');
    end if;
    v_blockers:=v_blockers||jsonb_build_array('gsp_irp_provider_not_configured');
  end if;

  return jsonb_build_object(
    'tax_mode',v_mode,
    'tax_mode_configured',v_mode<>'unconfigured',
    'gst_applicable',v_mode='gst_registered',
    'gst_setup_required',case when v_mode='gst_registered' then true when v_mode='non_gst' then false else null end,
    'new_transaction_ready',v_new_ready,
    'transition_coverage_ready',coalesce((v_coverage->>'ready')::boolean,false),
    'historical_authoritative_complete',v_history_ready,
    'filing_applicable',v_mode='gst_registered',
    'filing_data_ready',case when v_mode='gst_registered' then v_filing_data_ready else false end,
    'provider_applicable',v_mode='gst_registered',
    'provider_ready',false,
    'submission_ready',false,
    'blockers',v_blockers,
    'warnings',v_warnings,
    'setup',v_setup,
    'accounting',v_accounting,
    'coverage',v_coverage
  );
end
$function$;

revoke all on function public.gst_compliance_readiness_v520(uuid) from public, anon;
grant execute on function public.gst_compliance_readiness_v520(uuid) to authenticated;

create or replace function public.gst_compliance_workspace_v520(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,current_date);
  v_readiness jsonb;
  v_setup jsonb;
  v_dashboard jsonb;
  v_provider jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then
    raise exception 'GST compliance view permission required';
  end if;

  v_readiness:=public.gst_compliance_readiness_v520(p_tenant_id);
  v_setup:=coalesce(v_readiness->'setup','{}'::jsonb);

  if v_mode='non_gst' then
    v_dashboard:=jsonb_build_object(
      'stage','non_gst',
      'tax_mode','non_gst',
      'provider_status','not_applicable',
      'exceptions',jsonb_build_object(
        'irn_failed',0,
        'irn_pending',0,
        'gstin_errors',0,
        'missing_hsn_sac',0,
        'ewaybill_missing',0,
        'itc_mismatch',0,
        'product_profiles_review',0
      ),
      'message','GST is not applicable for this business. New v5.2 transactions remain authoritative with zero GST.'
    );
    v_provider:=jsonb_build_object(
      'connected',false,'applicable',false,'einvoice',false,'ewaybill',false,
      'returns_submission',false,'mode','not_applicable_non_gst'
    );
  elsif v_mode='unconfigured' then
    v_dashboard:=jsonb_build_object(
      'stage','tax_mode_selection_required',
      'tax_mode','unconfigured',
      'provider_status','not_configured',
      'exceptions','{}'::jsonb,
      'message','Choose GST Registered or Non-GST to enable v5.2 transactions.'
    );
    v_provider:=jsonb_build_object(
      'connected',false,'applicable',null,'einvoice',false,'ewaybill',false,
      'returns_submission',false,'mode','waiting_for_tax_mode'
    );
  else
    v_dashboard:=public.gst_dashboard_v520(p_tenant_id);
    v_provider:=jsonb_build_object(
      'connected',false,'applicable',true,'einvoice',false,'ewaybill',false,
      'returns_submission',false,'mode','not_configured'
    );
  end if;

  return jsonb_build_object(
    'stage',case when v_mode='non_gst' then 'v5.2-non-gst-workspace'
                 when v_mode='unconfigured' then 'v5.2-tax-mode-selection'
                 else 'v5.2-compliance-workspace' end,
    'tax_mode',v_mode,
    'gst_applicable',v_mode='gst_registered',
    'readiness',v_readiness,
    'dashboard',v_dashboard,
    'setup',v_setup,
    'coverage',public.gst_snapshot_coverage_v520(p_tenant_id),
    'accounting_health',public.gst_accounting_health_v520(p_tenant_id),
    'period',public.gst_period_summary_v520(p_tenant_id,p_from,p_to,p_location_id),
    'accounting_control',public.gst_accounting_control_v520(p_tenant_id,p_from,p_to,p_location_id),
    'provider',v_provider
  );
end
$function$;

revoke all on function public.gst_compliance_workspace_v520(uuid,date,date,uuid) from public, anon;
grant execute on function public.gst_compliance_workspace_v520(uuid,date,date,uuid) to authenticated;

-- Mode-aware visibility while keeping all tab definitions present for client contract validation.
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
begin
  v:=public.gst_ui_contract_base_v520(p_tenant_id);
  v_mode_obj:=public.gst_tax_mode_get_v520(p_tenant_id,current_date);
  v_mode:=coalesce(v_mode_obj->>'tax_mode','unconfigured');

  for t in select value from jsonb_array_elements(coalesce(v->'tabs','[]'::jsonb)) loop
    if v_mode='non_gst' and coalesce(t->>'key','') in ('registrations','products','parties','tax_summary','accounting','returns','einvoice','ewaybill') then
      t:=jsonb_set(t,'{enabled}','false'::jsonb,true)
          || jsonb_build_object('reason','not_applicable_non_gst');
    end if;
    v_tabs:=v_tabs||jsonb_build_array(t);
  end loop;

  v:=jsonb_set(v,'{tabs}',v_tabs,true);
  v:=coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'contract_version',6,
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
    'non_gst_hidden_tabs',jsonb_build_array('registrations','products','parties','tax_summary','accounting','returns','einvoice','ewaybill')
  ),true);
  return v;
end
$function$;

revoke all on function public.gst_ui_contract_v520(uuid) from public, anon;
grant execute on function public.gst_ui_contract_v520(uuid) to authenticated;

-- Surface the mode directly in bootstrap rules/defaults as well.
create or replace function public.gst_compliance_bootstrap_v520(
  p_tenant_id uuid,
  p_from date default null,
  p_to date default null,
  p_location_id uuid default null,
  p_document_limit integer default 50
) returns jsonb
language plpgsql
stable
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
    'release','5.2.0-foundation',
    'contract_version',2,
    'server_date',current_date,
    'tax_mode',v_mode,
    'period',jsonb_build_object('from',v_from,'to',v_to,'location_id',p_location_id),
    'rules',jsonb_build_object(
      'tax_calculation','server_authoritative_only',
      'tenant_tax_mode_required',true,
      'gst_applicable',v_mode='gst_registered',
      'legacy_transactions','view_only_legacy_unverified',
      'v520_failure_fallback',false,
      'provider_submission',false,
      'provider_phase','gsp_irp_not_started'
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

revoke all on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) from public, anon;
grant execute on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
select 254,'5.2.0','Tax-Mode Aware GST Compliance Workspace',
       'Makes GST readiness, workspace, dashboard and UI visibility aware of GST Registered vs Non-GST vs unconfigured mode. Non-GST no longer reports GSTIN/HSN/GSP setup as blockers while retaining authoritative v5.2 transaction evidence.'
where not exists(select 1 from public.thq_schema_releases where migration_no=254);
