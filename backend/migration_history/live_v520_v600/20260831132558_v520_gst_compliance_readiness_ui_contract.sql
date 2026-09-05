begin;

create or replace function public.gst_compliance_readiness_v520(p_tenant_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare v_setup jsonb; v_accounting jsonb; v_coverage jsonb; v_blockers jsonb:='[]'::jsonb;
 v_new_ready boolean; v_history_ready boolean; v_filing_data_ready boolean;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 v_setup:=public.gst_setup_health_v520(p_tenant_id);
 v_accounting:=public.gst_accounting_health_v520(p_tenant_id);
 v_coverage:=public.gst_snapshot_coverage_v520(p_tenant_id);

 v_new_ready:=coalesce((v_setup->>'setup_ready')::boolean,false) and coalesce((v_accounting->>'ready')::boolean,false);
 v_history_ready:=coalesce((v_coverage->>'legacy_unverified')::bigint,0)=0
   and coalesce((v_coverage->>'unclassified_documents')::bigint,0)=0
   and coalesce((v_coverage->>'legacy_source_hash_mismatches')::bigint,0)=0;
 v_filing_data_ready:=v_new_ready and v_history_ready;

 if not coalesce((v_setup->>'setup_ready')::boolean,false) then v_blockers:=v_blockers||jsonb_build_array('gst_setup_incomplete'); end if;
 if not coalesce((v_accounting->>'ready')::boolean,false) then v_blockers:=v_blockers||jsonb_build_array('gst_accounting_mapping_or_integrity_issue'); end if;
 if coalesce((v_coverage->>'unclassified_documents')::bigint,0)>0 then v_blockers:=v_blockers||jsonb_build_array('documents_without_gst_evidence'); end if;
 if coalesce((v_coverage->>'legacy_source_hash_mismatches')::bigint,0)>0 then v_blockers:=v_blockers||jsonb_build_array('legacy_evidence_source_hash_mismatch'); end if;
 if coalesce((v_coverage->>'legacy_unverified')::bigint,0)>0 then v_blockers:=v_blockers||jsonb_build_array('legacy_unverified_history_requires_review_or_migration'); end if;
 v_blockers:=v_blockers||jsonb_build_array('gsp_irp_provider_not_configured');

 return jsonb_build_object(
   'new_transaction_ready',v_new_ready,
   'transition_coverage_ready',coalesce((v_coverage->>'ready')::boolean,false),
   'historical_authoritative_complete',v_history_ready,
   'filing_data_ready',v_filing_data_ready,
   'provider_ready',false,
   'submission_ready',false,
   'blockers',v_blockers,
   'setup',v_setup,
   'accounting',v_accounting,
   'coverage',v_coverage
 );
end$$;

create or replace function public.gst_ui_contract_v520(p_tenant_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 return jsonb_build_object(
   'release','5.2.0-foundation',
   'workspace','GST & Compliance',
   'capabilities',jsonb_build_object(
     'view',private.gst_v520_has_access(p_tenant_id,'gst_compliance.view'),
     'calculate',private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate'),
     'manage',private.gst_v520_has_access(p_tenant_id,'gst_compliance.manage'),
     'configure',private.gst_v520_has_access(p_tenant_id,'gst_compliance.configure'),
     'reconcile',private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile'),
     'returns',private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns'),
     'submit',private.gst_v520_has_access(p_tenant_id,'gst_compliance.submit'),
     'einvoice',private.gst_v520_has_access(p_tenant_id,'gst_compliance.einvoice'),
     'ewaybill',private.gst_v520_has_access(p_tenant_id,'gst_compliance.ewaybill'),
     'cancel_irn',private.gst_v520_has_access(p_tenant_id,'gst_compliance.cancel_irn'),
     'period_lock',private.gst_v520_has_access(p_tenant_id,'gst_compliance.period_lock')
   ),
   'tabs',jsonb_build_array(
     jsonb_build_object('key','overview','label','Overview','rpc','gst_compliance_workspace_v520','permission','gst_compliance.view','enabled',true),
     jsonb_build_object('key','registrations','label','Registrations','list_rpc','gst_registrations_list_v520','save_rpc','gst_registration_save_v520','permission','gst_compliance.manage','enabled',true),
     jsonb_build_object('key','products','label','Product GST','list_rpc','gst_product_profiles_list_v520','save_rpc','gst_product_profile_save_v520','permission','gst_compliance.manage','enabled',true),
     jsonb_build_object('key','parties','label','Party GST','list_rpc','gst_party_profiles_list_v520','save_rpc','gst_party_profile_save_v520','permission','gst_compliance.manage','enabled',true),
     jsonb_build_object('key','transactions','label','GST Transactions','list_rpc','gst_documents_list_v520','detail_rpc','gst_document_evidence_v520','permission','gst_compliance.view','enabled',true),
     jsonb_build_object('key','tax_summary','label','Tax Summary','rpc','gst_period_summary_v520','permission','gst_compliance.view','enabled',true),
     jsonb_build_object('key','accounting','label','GST Accounting','health_rpc','gst_accounting_health_v520','control_rpc','gst_accounting_control_v520','permission','gst_compliance.reconcile','enabled',true),
     jsonb_build_object('key','returns','label','GST Returns','preview_rpc','gst_period_summary_v520','permission','gst_compliance.returns','enabled',true,'submission_enabled',false),
     jsonb_build_object('key','einvoice','label','E-Invoice','permission','gst_compliance.einvoice','enabled',false,'reason','provider_not_configured'),
     jsonb_build_object('key','ewaybill','label','E-Way Bill','permission','gst_compliance.ewaybill','enabled',false,'reason','provider_not_configured')
   ),
   'masters_rpc','gst_masters_v520',
   'readiness_rpc','gst_compliance_readiness_v520',
   'rules',jsonb_build_object(
     'tax_calculation','server_authoritative_only',
     'legacy_transactions','view_only_legacy_unverified',
     'new_v520_transactions','no_legacy_fallback',
     'provider_submission','disabled_until_gsp_irp_phase'
   )
 );
end$$;

create or replace function public.gst_compliance_workspace_v520(
 p_tenant_id uuid,
 p_from date,
 p_to date,
 p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 return jsonb_build_object(
   'stage','v5.2-compliance-workspace',
   'readiness',public.gst_compliance_readiness_v520(p_tenant_id),
   'dashboard',public.gst_dashboard_v520(p_tenant_id),
   'setup',public.gst_setup_health_v520(p_tenant_id),
   'coverage',public.gst_snapshot_coverage_v520(p_tenant_id),
   'accounting_health',public.gst_accounting_health_v520(p_tenant_id),
   'period',public.gst_period_summary_v520(p_tenant_id,p_from,p_to,p_location_id),
   'accounting_control',public.gst_accounting_control_v520(p_tenant_id,p_from,p_to,p_location_id),
   'provider',jsonb_build_object('connected',false,'einvoice',false,'ewaybill',false,'returns_submission',false,'mode','not_configured')
 );
end$$;

revoke all on function public.gst_compliance_readiness_v520(uuid) from public,anon;
revoke all on function public.gst_ui_contract_v520(uuid) from public,anon;
grant execute on function public.gst_compliance_readiness_v520(uuid) to authenticated,service_role;
grant execute on function public.gst_ui_contract_v520(uuid) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(245,'5.2.0-foundation','GST Compliance Readiness and UI Contract','Separates transition evidence coverage from authoritative historical completeness and provider submission readiness, and publishes the permission-aware GST workspace tab/RPC contract. Legacy evidence can no longer be mistaken for filing-ready authoritative evidence.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;