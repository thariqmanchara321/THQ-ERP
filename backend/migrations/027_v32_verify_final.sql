-- FLEXI ERP V3.2 final verification. Read-only checks except no changes.
do $$
begin
  if to_regclass('public.business_user_app_access') is null then raise exception 'Missing business_user_app_access'; end if;
  if to_regclass('public.business_user_location_access') is null then raise exception 'Missing business_user_location_access'; end if;
  if to_regclass('public.device_document_numbers') is null then raise exception 'Missing device_document_numbers'; end if;
  if to_regclass('public.tenant_code_counters') is null then raise exception 'Missing tenant_code_counters'; end if;

  if to_regprocedure('public.inventory_next_sku(uuid)') is null then raise exception 'Missing inventory_next_sku'; end if;
  if to_regprocedure('public.client_runtime_context(uuid,uuid,text)') is null then raise exception 'Missing client_runtime_context'; end if;
  if to_regprocedure('public.platform_device_issue_activation_v32(uuid,uuid,text,text,text,text[],text)') is null then raise exception 'Missing platform_device_issue_activation_v32'; end if;
  if to_regprocedure('public.tenant_user_management_context(uuid)') is null then raise exception 'Missing tenant_user_management_context'; end if;
  if to_regprocedure('public.global_search_v32(uuid,text,integer)') is null then raise exception 'Missing global_search_v32'; end if;
  if to_regprocedure('public.sales_list_v32(uuid,uuid)') is null then raise exception 'Missing sales_list_v32'; end if;
  if to_regprocedure('public.purchases_list_v32(uuid,uuid)') is null then raise exception 'Missing purchases_list_v32'; end if;
  if to_regprocedure('public.expenses_list_v32(uuid,uuid,date,date)') is null then raise exception 'Missing expenses_list_v32'; end if;
  if to_regprocedure('public.reports_get_summary_v32(uuid,date,date,uuid)') is null then raise exception 'Missing reports_get_summary_v32'; end if;
  if to_regprocedure('public.accounting_get_summary_v32(uuid,date,date,uuid)') is null then raise exception 'Missing accounting_get_summary_v32'; end if;
  if to_regprocedure('public.dashboard_get_summary_v32(uuid,uuid)') is null then raise exception 'Missing dashboard_get_summary_v32'; end if;
  if to_regprocedure('public.payments_pending_list_v32(uuid,uuid,integer)') is null then raise exception 'Missing payments_pending_list_v32'; end if;

  if to_regprocedure('public.sales_create_v32(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid)') is null then raise exception 'Missing atomic sales_create_v32'; end if;
  if to_regprocedure('public.purchases_create_v32(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid)') is null then raise exception 'Missing atomic purchases_create_v32'; end if;
  if to_regprocedure('public.expenses_create_v32(uuid,uuid,date,text,text,numeric,numeric,text,text,text,uuid,uuid)') is null then raise exception 'Missing atomic expenses_create_v32'; end if;
  if to_regprocedure('public.customers_list_v32(uuid)') is null then raise exception 'Missing customers_list_v32'; end if;
  if to_regprocedure('public.suppliers_list_v32(uuid)') is null then raise exception 'Missing suppliers_list_v32'; end if;
end $$;

select 'Flexi ERP V3.2 backend verification passed' as status;
