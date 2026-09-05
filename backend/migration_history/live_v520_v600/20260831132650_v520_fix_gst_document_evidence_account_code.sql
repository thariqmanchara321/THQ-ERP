begin;
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
       select jl.id,jl.party_type,jl.party_id,jl.description,jl.debit,jl.credit,a.system_key,a.code account_code,a.name account_name
       from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id
       where jl.journal_entry_id=j.id order by jl.id) x),'[]'::jsonb)) into v_journal
   from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type=p_source_type and j.source_id=p_source_id and j.status='posted'
   order by j.created_at desc limit 1;
   return jsonb_build_object('evidence_status','authoritative','snapshot',v_snapshot,'journal',coalesce(v_journal,'{}'::jsonb));
 end if;

 v_legacy:=public.gst_legacy_marker_get_v520(p_tenant_id,p_source_type,p_source_id);
 if v_legacy is not null then
   select jsonb_build_object('entry',to_jsonb(j),'lines',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (
       select jl.id,jl.party_type,jl.party_id,jl.description,jl.debit,jl.credit,a.system_key,a.code account_code,a.name account_name
       from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id
       where jl.journal_entry_id=j.id order by jl.id) x),'[]'::jsonb)) into v_journal
   from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type=p_source_type and j.source_id=p_source_id and j.status='posted'
   order by j.created_at desc limit 1;
   return jsonb_build_object('evidence_status','legacy_unverified','legacy',v_legacy,'journal',coalesce(v_journal,'{}'::jsonb));
 end if;
 return jsonb_build_object('evidence_status','missing','source_type',p_source_type,'source_id',p_source_id);
end$$;
revoke all on function public.gst_document_evidence_v520(uuid,text,uuid) from public,anon;
grant execute on function public.gst_document_evidence_v520(uuid,text,uuid) to authenticated,service_role;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(246,'5.2.0-foundation','GST Evidence Drill-down Fix','Corrects GST evidence journal drill-down to use accounting_accounts.code while preserving authenticated-only access and fixed search path.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;