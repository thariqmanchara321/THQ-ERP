create or replace function public.gst_setup_lookups_v520(
  p_tenant_id uuid,
  p_kind text default 'all',
  p_query text default '',
  p_limit integer default 200
) returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind,'all')));
  v_query text := lower(trim(coalesce(p_query,'')));
  v_like text := '%'||lower(trim(coalesce(p_query,'')))||'%';
  v_limit integer := greatest(1,least(coalesce(p_limit,200),500));
  v_locations jsonb := '[]'::jsonb;
  v_products jsonb := '[]'::jsonb;
  v_customers jsonb := '[]'::jsonb;
  v_suppliers jsonb := '[]'::jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then
    raise exception 'GST compliance view permission required';
  end if;

  if v_kind not in ('all','locations','products','customers','suppliers') then
    raise exception 'Unsupported GST setup lookup kind %',v_kind;
  end if;

  if v_kind in ('all','products','customers','suppliers')
     and not private.gst_v520_has_access(p_tenant_id,'gst_compliance.manage') then
    raise exception 'GST compliance manage permission required';
  end if;

  if v_kind in ('all','locations') then
    select coalesce(jsonb_agg(x.row_json order by x.location_name),'[]'::jsonb)
      into v_locations
    from (
      select l.name as location_name,
             jsonb_build_object(
               'id',l.id,
               'name',l.name,
               'location_type',l.location_type,
               'active',l.active,
               'registration_id',gm.registration_id,
               'gstin',gr.gstin,
               'registration_legal_name',gr.legal_name,
               'registration_state_code',gr.state_code,
               'mapping_effective_from',gm.effective_from
             ) as row_json
      from public.business_locations l
      left join lateral (
        select m.registration_id,m.effective_from
        from public.gst_location_registrations_v520 m
        where m.tenant_id=l.tenant_id
          and m.location_id=l.id
          and current_date between m.effective_from and coalesce(m.effective_to,'infinity'::date)
        order by m.effective_from desc,m.created_at desc
        limit 1
      ) gm on true
      left join public.gst_registrations_v520 gr
        on gr.tenant_id=l.tenant_id and gr.id=gm.registration_id
      where l.tenant_id=p_tenant_id
        and l.active
        and (
          coalesce(auth.role(),'')='service_role'
          or private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id,'locations.manage_all')
          or private.erp_has_permission(p_tenant_id,'locations.view_all')
          or private.erp_user_location_allowed(p_tenant_id,l.id,'view',auth.uid())
        )
        and (v_query='' or lower(l.name) like v_like)
      order by l.name
      limit v_limit
    ) x;
  end if;

  if v_kind in ('all','products') then
    select coalesce(jsonb_agg(x.row_json order by x.product_name,x.variant_name),'[]'::jsonb)
      into v_products
    from (
      select p.name as product_name,pv.name as variant_name,
             jsonb_build_object(
               'variant_id',pv.id,
               'product_id',p.id,
               'product_name',p.name,
               'variant_name',pv.name,
               'sku',pv.sku,
               'item_type',p.item_type,
               'configured',gp.id is not null,
               'profile_id',gp.id,
               'supply_kind',gp.supply_kind,
               'hsn_sac',gp.hsn_sac,
               'taxability',gp.taxability,
               'gst_rate',gp.gst_rate,
               'cess_rate',gp.cess_rate,
               'cess_per_unit',gp.cess_per_unit,
               'tax_inclusive',gp.tax_inclusive,
               'reverse_charge',gp.reverse_charge,
               'validation_status',gp.validation_status,
               'effective_from',gp.effective_from
             ) as row_json
      from public.product_variants pv
      join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
      left join lateral (
        select g.*
        from public.gst_product_tax_profiles_v520 g
        where g.tenant_id=pv.tenant_id
          and g.variant_id=pv.id
          and current_date between g.effective_from and coalesce(g.effective_to,'infinity'::date)
        order by g.active desc,g.effective_from desc,g.created_at desc
        limit 1
      ) gp on true
      where pv.tenant_id=p_tenant_id
        and pv.status='active'
        and p.status='active'
        and (
          v_query=''
          or lower(p.name) like v_like
          or lower(coalesce(pv.name,'')) like v_like
          or lower(coalesce(pv.sku,'')) like v_like
          or lower(coalesce(gp.hsn_sac,'')) like v_like
        )
      order by p.name,pv.name
      limit v_limit
    ) x;
  end if;

  if v_kind in ('all','customers') then
    select coalesce(jsonb_agg(x.row_json order by x.party_name),'[]'::jsonb)
      into v_customers
    from (
      select c.name as party_name,
             jsonb_build_object(
               'party_id',c.id,
               'party_type','customer',
               'party_name',c.name,
               'configured',gp.id is not null,
               'profile_id',gp.id,
               'registration_type',gp.registration_type,
               'gstin',gp.gstin,
               'legal_name',gp.legal_name,
               'trade_name',gp.trade_name,
               'state_code',gp.state_code,
               'place_of_supply_code',gp.place_of_supply_code,
               'validation_status',gp.validation_status,
               'effective_from',gp.effective_from
             ) as row_json
      from public.customers c
      left join lateral (
        select g.*
        from public.gst_party_registrations_v520 g
        where g.tenant_id=c.tenant_id
          and g.party_type='customer'
          and g.party_id=c.id
          and current_date between g.effective_from and coalesce(g.effective_to,'infinity'::date)
        order by g.active desc,g.is_default desc,g.effective_from desc,g.created_at desc
        limit 1
      ) gp on true
      where c.tenant_id=p_tenant_id
        and c.status='active'
        and (
          v_query=''
          or lower(c.name) like v_like
          or lower(coalesce(gp.gstin,'')) like v_like
          or lower(coalesce(gp.legal_name,'')) like v_like
        )
      order by c.name
      limit v_limit
    ) x;
  end if;

  if v_kind in ('all','suppliers') then
    select coalesce(jsonb_agg(x.row_json order by x.party_name),'[]'::jsonb)
      into v_suppliers
    from (
      select s.name as party_name,
             jsonb_build_object(
               'party_id',s.id,
               'party_type','supplier',
               'party_name',s.name,
               'configured',gp.id is not null,
               'profile_id',gp.id,
               'registration_type',gp.registration_type,
               'gstin',gp.gstin,
               'legal_name',gp.legal_name,
               'trade_name',gp.trade_name,
               'state_code',gp.state_code,
               'place_of_supply_code',gp.place_of_supply_code,
               'validation_status',gp.validation_status,
               'effective_from',gp.effective_from
             ) as row_json
      from public.suppliers s
      left join lateral (
        select g.*
        from public.gst_party_registrations_v520 g
        where g.tenant_id=s.tenant_id
          and g.party_type='supplier'
          and g.party_id=s.id
          and current_date between g.effective_from and coalesce(g.effective_to,'infinity'::date)
        order by g.active desc,g.is_default desc,g.effective_from desc,g.created_at desc
        limit 1
      ) gp on true
      where s.tenant_id=p_tenant_id
        and s.status='active'
        and (
          v_query=''
          or lower(s.name) like v_like
          or lower(coalesce(gp.gstin,'')) like v_like
          or lower(coalesce(gp.legal_name,'')) like v_like
        )
      order by s.name
      limit v_limit
    ) x;
  end if;

  return jsonb_build_object(
    'kind',v_kind,
    'query',trim(coalesce(p_query,'')),
    'limit',v_limit,
    'locations',v_locations,
    'products',v_products,
    'customers',v_customers,
    'suppliers',v_suppliers
  );
end;
$$;

revoke all on function public.gst_setup_lookups_v520(uuid,text,text,integer) from public,anon;
grant execute on function public.gst_setup_lookups_v520(uuid,text,text,integer) to authenticated,service_role;

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
    'contract_version',3,
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
        'permission','gst_compliance.manage','enabled',true
      ),
      jsonb_build_object(
        'key','products','label','Product GST',
        'list_rpc','gst_product_profiles_list_v520',
        'save_rpc','gst_product_profile_save_v520',
        'lookup_rpc','gst_setup_lookups_v520',
        'permission','gst_compliance.manage','enabled',true
      ),
      jsonb_build_object(
        'key','parties','label','Party GST',
        'list_rpc','gst_party_profiles_list_v520',
        'save_rpc','gst_party_profile_save_v520',
        'lookup_rpc','gst_setup_lookups_v520',
        'permission','gst_compliance.manage','enabled',true
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
values(251,'5.2.0','GST Compliance UI Setup Lookups','Read-only, permission-scoped setup lookup API for GST location, product, customer and supplier configuration; UI contract v3.')
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;