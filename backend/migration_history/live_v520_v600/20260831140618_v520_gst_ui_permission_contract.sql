create or replace function public.gst_ui_contract_v520(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then
    raise exception 'GST compliance view permission required';
  end if;

  return jsonb_build_object(
    'release','5.2.0-foundation',
    'contract_version',4,
    'workspace','GST & Compliance',
    'bootstrap_rpc','gst_compliance_bootstrap_v520',
    'setup_lookup_rpc','gst_setup_lookups_v520',
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
    'form_options',jsonb_build_object(
      'registration_types',jsonb_build_array('regular','composition','casual','sez','isd','tcs','tds','non_resident','other'),
      'party_registration_types',jsonb_build_array('registered','unregistered','composition','sez','export','exempt'),
      'supply_kinds',jsonb_build_array('goods','service'),
      'taxability',jsonb_build_array('taxable','nil_rated','exempt','non_gst')
    ),
    'tabs',jsonb_build_array(
      jsonb_build_object(
        'key','overview','label','Overview','rpc','gst_compliance_workspace_v520',
        'permission','gst_compliance.view','enabled',true
      ),
      jsonb_build_object(
        'key','registrations','label','Registrations',
        'list_rpc','gst_registrations_list_v520',
        'save_rpc','gst_registration_save_v520',
        'config_rpc','gst_registration_config_v520',
        'location_map_rpc','gst_location_registration_set_v520',
        'lookup_rpc','gst_setup_lookups_v520',
        'location_mapping_required',true,
        'permission','gst_compliance.view',
        'write_permission','gst_compliance.configure',
        'enabled',true
      ),
      jsonb_build_object(
        'key','products','label','Product GST',
        'list_rpc','gst_product_profiles_list_v520',
        'save_rpc','gst_product_profile_save_v520',
        'lookup_rpc','gst_setup_lookups_v520',
        'permission','gst_compliance.view',
        'write_permission','gst_compliance.manage',
        'enabled',true
      ),
      jsonb_build_object(
        'key','parties','label','Party GST',
        'list_rpc','gst_party_profiles_list_v520',
        'save_rpc','gst_party_profile_save_v520',
        'lookup_rpc','gst_setup_lookups_v520',
        'permission','gst_compliance.view',
        'write_permission','gst_compliance.manage',
        'enabled',true
      ),
      jsonb_build_object(
        'key','transactions','label','GST Transactions',
        'list_rpc','gst_documents_list_v520',
        'detail_rpc','gst_document_evidence_v520',
        'permission','gst_compliance.view','enabled',true
      ),
      jsonb_build_object(
        'key','tax_summary','label','Tax Summary','rpc','gst_period_summary_v520',
        'permission','gst_compliance.view','enabled',true
      ),
      jsonb_build_object(
        'key','accounting','label','GST Accounting',
        'health_rpc','gst_accounting_health_v520',
        'control_rpc','gst_accounting_control_v520',
        'permission','gst_compliance.reconcile','enabled',true
      ),
      jsonb_build_object(
        'key','returns','label','GST Returns',
        'preview_rpc','gst_period_summary_v520',
        'permission','gst_compliance.returns','enabled',true,
        'submission_enabled',false
      ),
      jsonb_build_object(
        'key','einvoice','label','E-Invoice',
        'permission','gst_compliance.einvoice','enabled',false,
        'reason','provider_not_configured'
      ),
      jsonb_build_object(
        'key','ewaybill','label','E-Way Bill',
        'permission','gst_compliance.ewaybill','enabled',false,
        'reason','provider_not_configured'
      )
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
end;
$$;

revoke all on function public.gst_ui_contract_v520(uuid) from public,anon;
grant execute on function public.gst_ui_contract_v520(uuid) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(252,'5.2.0','GST Compliance UI Permission Contract','UI contract v4 separates read permission from registration/product/party write permissions and publishes canonical GST form option enums.')
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;