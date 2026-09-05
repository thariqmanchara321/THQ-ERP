begin;

create or replace function public.gst_period_summary_v520(
 p_tenant_id uuid,
 p_from date,
 p_to date,
 p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare v_totals jsonb; v_rates jsonb; v_legacy jsonb;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 if p_from is null or p_to is null or p_to < p_from then raise exception 'Valid GST period is required'; end if;

 with s as (
   select x.*,
     case when x.source_type in('sales_return','purchase_return','credit_note') then -1::numeric else 1::numeric end as effect
   from public.gst_document_snapshots_v520 x
   where x.tenant_id=p_tenant_id
     and x.document_date between p_from and p_to
     and private.erp_document_scope_allowed(p_tenant_id,x.location_id,p_location_id,'view')
 ), a as (
   select
     count(*)::bigint documents,
     count(*) filter(where direction='outward')::bigint outward_documents,
     count(*) filter(where direction='inward')::bigint inward_documents,
     round(coalesce(sum(effect*taxable_total),0),2) net_taxable,
     round(coalesce(sum(effect*cgst_total),0),2) net_cgst,
     round(coalesce(sum(effect*sgst_total),0),2) net_sgst,
     round(coalesce(sum(effect*utgst_total),0),2) net_utgst,
     round(coalesce(sum(effect*igst_total),0),2) net_igst,
     round(coalesce(sum(effect*cess_total),0),2) net_cess,
     round(coalesce(sum(effect*tax_collected_total),0),2) net_supplier_or_customer_gst,
     round(coalesce(sum(effect*rcm_tax_payable_total),0),2) net_rcm_payable,
     round(coalesce(sum(effect*government_tax_total),0),2) net_government_tax,
     round(coalesce(sum(effect*grand_total),0),2) net_document_total,
     round(coalesce(sum(case when direction='outward' then effect*taxable_total else 0 end),0),2) outward_taxable,
     round(coalesce(sum(case when direction='outward' then effect*government_tax_total else 0 end),0),2) outward_tax,
     round(coalesce(sum(case when direction='outward' then effect*grand_total else 0 end),0),2) outward_total,
     round(coalesce(sum(case when direction='inward' then effect*taxable_total else 0 end),0),2) inward_taxable,
     round(coalesce(sum(case when direction='inward' then effect*tax_collected_total else 0 end),0),2) inward_supplier_gst,
     round(coalesce(sum(case when direction='inward' then effect*rcm_tax_payable_total else 0 end),0),2) inward_rcm_payable,
     round(coalesce(sum(case when direction='inward' then effect*grand_total else 0 end),0),2) inward_total
   from s
 ) select to_jsonb(a) into v_totals from a;

 with l as (
   select ls.applied_gst_rate rate,
     case when s.source_type in('sales_return','purchase_return','credit_note') then -1::numeric else 1::numeric end as effect,
     ls.taxable_value,ls.cgst,ls.sgst,ls.utgst,ls.igst,ls.cess,ls.rcm_tax_amount
   from public.gst_document_line_snapshots_v520 ls
   join public.gst_document_snapshots_v520 s on s.id=ls.snapshot_id and s.tenant_id=ls.tenant_id
   where s.tenant_id=p_tenant_id and s.document_date between p_from and p_to
     and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view')
 ), r as (
   select rate,
     round(sum(effect*taxable_value),2) taxable,
     round(sum(effect*cgst),2) cgst,
     round(sum(effect*sgst),2) sgst,
     round(sum(effect*utgst),2) utgst,
     round(sum(effect*igst),2) igst,
     round(sum(effect*cess),2) cess,
     round(sum(effect*rcm_tax_amount),2) rcm
   from l group by rate order by rate
 ) select coalesce(jsonb_agg(to_jsonb(r) order by rate),'[]'::jsonb) into v_rates from r;

 select jsonb_build_object(
   'count',count(*)::bigint,
   'taxable_total',round(coalesce(sum(legacy_taxable_total),0),2),
   'tax_total',round(coalesce(sum(legacy_tax_total),0),2),
   'grand_total',round(coalesce(sum(legacy_grand_total),0),2)
 ) into v_legacy
 from public.gst_legacy_document_markers_v520 m
 where m.tenant_id=p_tenant_id and m.document_date between p_from and p_to
   and private.erp_document_scope_allowed(p_tenant_id,m.location_id,p_location_id,'view');

 return jsonb_build_object('from',p_from,'to',p_to,'location_id',p_location_id,
   'authoritative',coalesce(v_totals,'{}'::jsonb),'rate_summary',coalesce(v_rates,'[]'::jsonb),
   'legacy_unverified',coalesce(v_legacy,'{}'::jsonb));
end$$;

create or replace function public.gst_documents_list_v520(
 p_tenant_id uuid,
 p_from date default null,
 p_to date default null,
 p_location_id uuid default null,
 p_source_type text default null,
 p_evidence_status text default 'all',
 p_query text default '',
 p_limit integer default 100,
 p_offset integer default 0
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare v_rows jsonb; v_total bigint; v_status text:=lower(trim(coalesce(p_evidence_status,'all'))); v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 if v_status not in('all','authoritative','legacy_unverified') then raise exception 'Invalid evidence status'; end if;
 if p_from is not null and p_to is not null and p_to < p_from then raise exception 'Invalid date range'; end if;

 with docs as (
   select s.tenant_id,s.source_type,s.source_id,s.source_number,s.document_number,s.document_date,s.location_id,
     'authoritative'::text evidence_status,s.direction,s.document_class,s.supply_type,s.place_of_supply_code,
     s.taxable_total,s.government_tax_total tax_total,s.rcm_tax_payable_total,s.grand_total,s.created_at evidence_at,s.snapshot_hash evidence_hash
   from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id
   union all
   select m.tenant_id,m.source_type,m.source_id,m.source_number,m.source_number,m.document_date,m.location_id,
     'legacy_unverified'::text,null::text,null::text,null::text,null::text,
     m.legacy_taxable_total,m.legacy_tax_total,0::numeric,m.legacy_grand_total,m.marked_at,m.source_hash
   from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id
 ), f as (
   select d.*,l.name location_name
   from docs d left join public.business_locations l on l.id=d.location_id and l.tenant_id=d.tenant_id
   where (p_from is null or d.document_date>=p_from) and (p_to is null or d.document_date<=p_to)
     and (p_source_type is null or d.source_type=p_source_type)
     and (v_status='all' or d.evidence_status=v_status)
     and private.erp_document_scope_allowed(p_tenant_id,d.location_id,p_location_id,'view')
     and (v_q='%%' or lower(coalesce(d.document_number,'')) like v_q or lower(coalesce(d.source_number,'')) like v_q or lower(coalesce(d.source_type,'')) like v_q)
 )
 select count(*) into v_total from f;

 with docs as (
   select s.tenant_id,s.source_type,s.source_id,s.source_number,s.document_number,s.document_date,s.location_id,
     'authoritative'::text evidence_status,s.direction,s.document_class,s.supply_type,s.place_of_supply_code,
     s.taxable_total,s.government_tax_total tax_total,s.rcm_tax_payable_total,s.grand_total,s.created_at evidence_at,s.snapshot_hash evidence_hash
   from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id
   union all
   select m.tenant_id,m.source_type,m.source_id,m.source_number,m.source_number,m.document_date,m.location_id,
     'legacy_unverified'::text,null::text,null::text,null::text,null::text,
     m.legacy_taxable_total,m.legacy_tax_total,0::numeric,m.legacy_grand_total,m.marked_at,m.source_hash
   from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id
 ), f as (
   select d.*,l.name location_name
   from docs d left join public.business_locations l on l.id=d.location_id and l.tenant_id=d.tenant_id
   where (p_from is null or d.document_date>=p_from) and (p_to is null or d.document_date<=p_to)
     and (p_source_type is null or d.source_type=p_source_type)
     and (v_status='all' or d.evidence_status=v_status)
     and private.erp_document_scope_allowed(p_tenant_id,d.location_id,p_location_id,'view')
     and (v_q='%%' or lower(coalesce(d.document_number,'')) like v_q or lower(coalesce(d.source_number,'')) like v_q or lower(coalesce(d.source_type,'')) like v_q)
   order by d.document_date desc,d.evidence_at desc
   limit greatest(1,least(coalesce(p_limit,100),500)) offset greatest(coalesce(p_offset,0),0)
 ) select coalesce(jsonb_agg(to_jsonb(f) order by document_date desc,evidence_at desc),'[]'::jsonb) into v_rows from f;
 return jsonb_build_object('total',v_total,'limit',greatest(1,least(coalesce(p_limit,100),500)),'offset',greatest(coalesce(p_offset,0),0),'rows',coalesce(v_rows,'[]'::jsonb));
end$$;

create or replace function public.gst_document_evidence_v520(
 p_tenant_id uuid,p_source_type text,p_source_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare v_snapshot jsonb; v_legacy jsonb; v_journal jsonb; v_location uuid;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
 select location_id into v_location from public.gst_document_snapshots_v520 where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id;
 if v_location is null then select location_id into v_location from public.gst_legacy_document_markers_v520 where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id; end if;
 if v_location is not null and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'view') then raise exception 'Location access denied'; end if;

 v_snapshot:=public.gst_snapshot_get_v520(p_tenant_id,p_source_type,p_source_id);
 if v_snapshot is not null then
   select jsonb_build_object('entry',to_jsonb(j),'lines',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (
       select jl.id,jl.party_type,jl.party_id,jl.description,jl.debit,jl.credit,a.system_key,a.account_code,a.name account_name
       from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id
       where jl.journal_entry_id=j.id order by jl.id) x),'[]'::jsonb)) into v_journal
   from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type=p_source_type and j.source_id=p_source_id and j.status='posted'
   order by j.created_at desc limit 1;
   return jsonb_build_object('evidence_status','authoritative','snapshot',v_snapshot,'journal',coalesce(v_journal,'{}'::jsonb));
 end if;

 v_legacy:=public.gst_legacy_marker_get_v520(p_tenant_id,p_source_type,p_source_id);
 if v_legacy is not null then
   select jsonb_build_object('entry',to_jsonb(j),'lines',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (
       select jl.id,jl.party_type,jl.party_id,jl.description,jl.debit,jl.credit,a.system_key,a.account_code,a.name account_name
       from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id
       where jl.journal_entry_id=j.id order by jl.id) x),'[]'::jsonb)) into v_journal
   from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type=p_source_type and j.source_id=p_source_id and j.status='posted'
   order by j.created_at desc limit 1;
   return jsonb_build_object('evidence_status','legacy_unverified','legacy',v_legacy,'journal',coalesce(v_journal,'{}'::jsonb));
 end if;
 return jsonb_build_object('evidence_status','missing','source_type',p_source_type,'source_id',p_source_id);
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
   'dashboard',public.gst_dashboard_v520(p_tenant_id),
   'setup',public.gst_setup_health_v520(p_tenant_id),
   'coverage',public.gst_snapshot_coverage_v520(p_tenant_id),
   'accounting_health',public.gst_accounting_health_v520(p_tenant_id),
   'period',public.gst_period_summary_v520(p_tenant_id,p_from,p_to,p_location_id),
   'accounting_control',public.gst_accounting_control_v520(p_tenant_id,p_from,p_to,p_location_id),
   'provider',jsonb_build_object('connected',false,'einvoice',false,'ewaybill',false,'returns_submission',false,'mode','not_configured')
 );
end$$;

revoke all on function public.gst_period_summary_v520(uuid,date,date,uuid) from public,anon;
revoke all on function public.gst_documents_list_v520(uuid,date,date,uuid,text,text,text,integer,integer) from public,anon;
revoke all on function public.gst_document_evidence_v520(uuid,text,uuid) from public,anon;
revoke all on function public.gst_compliance_workspace_v520(uuid,date,date,uuid) from public,anon;
grant execute on function public.gst_period_summary_v520(uuid,date,date,uuid) to authenticated,service_role;
grant execute on function public.gst_documents_list_v520(uuid,date,date,uuid,text,text,text,integer,integer) to authenticated,service_role;
grant execute on function public.gst_document_evidence_v520(uuid,text,uuid) to authenticated,service_role;
grant execute on function public.gst_compliance_workspace_v520(uuid,date,date,uuid) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(244,'5.2.0-foundation','GST Compliance Workspace Read APIs','Adds authoritative GST period summaries, evidence browser/detail with journal drill-down, signed return handling and a combined compliance workspace payload. Provider/GSP/IRP submission remains intentionally disabled.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;