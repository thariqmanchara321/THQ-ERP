begin;
create or replace function public.gst_accounting_control_v520(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required';end if;
 with balances as (
  select a.system_key,private.gst_v520_account_family(a.system_key) family,
    round(coalesce(sum(case when j.id is null then 0 when a.account_type='asset' then l.debit-l.credit else l.credit-l.debit end),0),2) balance
  from public.accounting_accounts a left join public.journal_lines l on l.account_id=a.id left join public.journal_entries j on j.id=l.journal_entry_id and j.status='posted' and j.entry_date between p_from and p_to and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
  where a.tenant_id=p_tenant_id and private.gst_v520_account_family(a.system_key) is not null
  group by a.system_key,a.account_type
 ), f as (
  select family,jsonb_object_agg(system_key,balance order by system_key) components,round(sum(balance),2) total from balances group by family
 )
 select jsonb_object_agg(family,jsonb_build_object('components',components,'total',total)) into v from f;
 return coalesce(v,'{}'::jsonb)||jsonb_build_object('from',p_from,'to',p_to);
end $$;
revoke all on function public.gst_accounting_control_v520(uuid,date,date,uuid) from public,anon;
grant execute on function public.gst_accounting_control_v520(uuid,date,date,uuid) to authenticated,service_role;

create or replace function public.gst_accounting_health_v520(p_tenant_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare missing text[]:='{}';k text;mixed_input bigint;mixed_output bigint;mixed_rcm bigint;mixed_rcm_input bigint;orphan_component bigint;
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required';end if;
 foreach k in array array['input_cgst','input_sgst','input_utgst','input_igst','input_cess','rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess','output_cgst','output_sgst','output_utgst','output_igst','output_cess','rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable'] loop
  if not exists(select 1 from public.accounting_account_mappings m join public.accounting_accounts a on a.id=m.account_id where m.tenant_id=p_tenant_id and m.mapping_key=k and a.tenant_id=p_tenant_id and a.system_key=k and a.active) then missing:=array_append(missing,k);end if;
 end loop;
 select count(*) into mixed_input from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key='input_gst') and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key in('input_cgst','input_sgst','input_utgst','input_igst','input_cess'));
 select count(*) into mixed_output from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key='output_gst') and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key in('output_cgst','output_sgst','output_utgst','output_igst','output_cess'));
 select count(*) into mixed_rcm from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key='rcm_gst_payable') and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key in('rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable'));
 select count(*) into mixed_rcm_input from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key='rcm_input_gst') and exists(select 1 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id where l.journal_entry_id=j.id and a.system_key in('rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess'));
 select count(distinct j.id) into orphan_component from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id join public.accounting_accounts a on a.id=l.account_id where j.tenant_id=p_tenant_id and j.status='posted' and j.source_type in('sale','purchase','sales_return','purchase_return','purchase_invoice_v484') and a.system_key in('input_cgst','input_sgst','input_utgst','input_igst','input_cess','output_cgst','output_sgst','output_utgst','output_igst','output_cess','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable') and not exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.source_type=j.source_type and s.source_id=j.source_id);
 return jsonb_build_object('ready',cardinality(missing)=0 and mixed_input=0 and mixed_output=0 and mixed_rcm=0 and mixed_rcm_input=0 and orphan_component=0,'missing_mappings',to_jsonb(missing),'mixed_legacy_and_component_input_journals',mixed_input,'mixed_legacy_and_component_output_journals',mixed_output,'mixed_rcm_parent_and_component_journals',mixed_rcm,'mixed_rcm_input_parent_and_component_journals',mixed_rcm_input,'component_journals_without_authoritative_snapshot',orphan_component);
end $$;
revoke all on function public.gst_accounting_health_v520(uuid) from public,anon;
grant execute on function public.gst_accounting_health_v520(uuid) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(229,'5.2.0-foundation','GST Accounting Control & Health','Adds GST component control balances and integrity checks for missing mappings, legacy+component double posting, RCM parent/component mixing and component journals without authoritative GST snapshots.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;