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
security invoker
set search_path = public, private, pg_temp
as $$
declare
  v_from date := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to date := coalesce(p_to, current_date);
  v_limit integer := coalesce(p_document_limit, 50);
begin
  if p_tenant_id is null then
    raise exception 'Tenant is required';
  end if;

  if v_from > v_to then
    raise exception 'GST period start date cannot be after end date';
  end if;

  if v_limit < 1 or v_limit > 100 then
    raise exception 'GST bootstrap document limit must be between 1 and 100';
  end if;

  return jsonb_build_object(
    'release', '5.2.0-foundation',
    'contract_version', 1,
    'server_date', current_date,
    'period', jsonb_build_object(
      'from', v_from,
      'to', v_to,
      'location_id', p_location_id
    ),
    'rules', jsonb_build_object(
      'tax_calculation', 'server_authoritative_only',
      'legacy_transactions', 'view_only_legacy_unverified',
      'v520_failure_fallback', false,
      'provider_submission', false,
      'provider_phase', 'gsp_irp_not_started'
    ),
    'ui_contract', public.gst_ui_contract_v520(p_tenant_id),
    'workspace', public.gst_compliance_workspace_v520(
      p_tenant_id,
      v_from,
      v_to,
      p_location_id
    ),
    'masters', public.gst_masters_v520(p_tenant_id, v_to),
    'readiness', public.gst_compliance_readiness_v520(p_tenant_id),
    'documents', public.gst_documents_list_v520(
      p_tenant_id,
      v_from,
      v_to,
      p_location_id,
      null,
      'all',
      '',
      v_limit,
      0
    ),
    'defaults', jsonb_build_object(
      'document_limit', v_limit,
      'document_evidence_status', 'all',
      'document_query', '',
      'document_offset', 0
    )
  );
end;
$$;

revoke all on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) from public, anon;
grant execute on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) to authenticated, service_role;

comment on function public.gst_compliance_bootstrap_v520(uuid,date,date,uuid,integer) is
'THQ ERP v5.2 GST & Compliance screen bootstrap. Returns UI contract, workspace/readiness, masters and first transaction page in one call. Provider submission remains disabled.';