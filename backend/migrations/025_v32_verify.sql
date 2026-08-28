-- FLEXI ERP V3.2 verification. Raises if any required backend object is missing.
do $$
declare n text;
begin
  foreach n in array array[
    'business_user_app_access','business_user_location_access','device_document_numbers','device_document_counters','tenant_code_counters'
  ] loop
    if to_regclass('public.'||n) is null then raise exception 'V3.2 missing table: %',n;end if;
  end loop;
  foreach n in array array[
    'client_runtime_context','sales_list_v32','purchases_list_v32','expenses_list_v32','reports_get_summary_v32','accounting_get_summary_v32','accounting_list_ledger_v32','global_search_v32','inventory_next_sku','tenant_user_management_context','tenant_user_access_set','platform_device_issue_activation_v32'
  ] loop
    if not exists(select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=n) then raise exception 'V3.2 missing function: %',n;end if;
  end loop;
end $$;
select 'V3.2 backend verification passed' as status;
