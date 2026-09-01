-- THQ ERP v5.0.0 — milestone database verification.
begin;
create or replace function public.thq_v500_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare miss text[]:='{}'; n text; req text[]:=array[
'finance_reconciliation_v500','financial_years_list_v500','finance_voucher_post_v500','bank_accounts_list_v500','bank_statement_list_v500','recurring_expenses_process_v500','journal_center_list_v500','journal_center_detail_v500','journal_reverse_v500',
'customer_crm_profile_v500','customer_groups_list_v500','purchase_quotations_list_v500','supplier_performance_v500','reorder_suggestions_v500','reports_catalog_v500','returns_report_v500','reports_center_data_v500','dashboard_business_intelligence_v500','business_tasks_list_v495','notifications_list_v4','thq_v500_capabilities'];begin
 foreach n in array req loop if to_regprocedure('public.'||n||case n when 'thq_v500_capabilities' then '()' else null end) is null and not exists(select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=n) then miss:=array_append(miss,n);end if;end loop;
 if not exists(select 1 from public.thq_schema_releases where migration_no=208 and schema_version='5.0.0') then miss:=array_append(miss,'migration.208');end if;
 return jsonb_build_object('ready',cardinality(miss)=0,'missing',to_jsonb(miss),'schema_version','5.0.0','migration_no',210,'build',24,'capabilities',public.thq_v500_capabilities());
end $$;
grant execute on function public.thq_v500_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(209,'5.0.0','Milestone Verification','Database contract verifier for finance, CRM, purchasing intelligence, reports, tasks/notifications and BI.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 209 applied' as status;
