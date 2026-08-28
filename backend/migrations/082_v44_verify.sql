-- FLEXI ERP V4.4 verification. Read-only checks.
do $$
begin
  -- POS completion
  if to_regclass('public.pos_held_sales') is null then raise exception 'Missing pos_held_sales';end if;
  if to_regclass('public.pos_device_preferences') is null then raise exception 'Missing pos_device_preferences';end if;
  if to_regprocedure('public.pos_printer_profiles_list_v44(uuid,uuid)') is null then raise exception 'Missing pos_printer_profiles_list_v44';end if;
  if to_regprocedure('public.pos_printer_profile_save_v44(uuid,uuid,uuid,text,text,text,text,text,integer,boolean,boolean,text,boolean,boolean,jsonb)') is null then raise exception 'Missing pos_printer_profile_save_v44';end if;
  if to_regprocedure('public.pos_device_preferences_get_v44(uuid,uuid)') is null then raise exception 'Missing pos_device_preferences_get_v44';end if;
  if to_regprocedure('public.pos_device_preferences_set_v44(uuid,uuid,jsonb)') is null then raise exception 'Missing pos_device_preferences_set_v44';end if;
  if to_regprocedure('public.pos_hold_sale_v44(uuid,uuid,uuid,text,jsonb)') is null then raise exception 'Missing pos_hold_sale_v44';end if;
  if to_regprocedure('public.pos_held_sales_list_v44(uuid,uuid)') is null then raise exception 'Missing pos_held_sales_list_v44';end if;
  if to_regprocedure('public.pos_held_sale_get_v44(uuid,uuid,uuid)') is null then raise exception 'Missing pos_held_sale_get_v44';end if;
  if to_regprocedure('public.pos_held_sale_delete_v44(uuid,uuid,uuid)') is null then raise exception 'Missing pos_held_sale_delete_v44';end if;

  -- Reports / exports
  if to_regclass('public.report_export_events') is null then raise exception 'Missing report_export_events';end if;
  if to_regprocedure('public.reports_export_dataset_v44(uuid,date,date,uuid)') is null then raise exception 'Missing reports_export_dataset_v44';end if;
  if to_regprocedure('public.report_export_log_v44(uuid,text,text,date,date,uuid,uuid)') is null then raise exception 'Missing report_export_log_v44';end if;

  -- Client invoice designer
  if to_regprocedure('public.tenant_invoice_templates_list_v44(uuid,text)') is null then raise exception 'Missing tenant invoice template list RPC';end if;
  if to_regprocedure('public.tenant_invoice_template_save_v44(uuid,text,uuid,jsonb)') is null then raise exception 'Missing tenant invoice designer RPC';end if;

  -- Platform transaction control
  if to_regprocedure('public.platform_transactions_list_v44(uuid,date,date,text,integer)') is null then raise exception 'Missing admin transaction list RPC';end if;
  if to_regprocedure('public.platform_transaction_void_v44(uuid,text,uuid,text)') is null then raise exception 'Missing admin transaction void RPC';end if;

  -- Barcode and division aggregation
  if to_regprocedure('public.inventory_barcode_lookup_v44(uuid,text,uuid)') is null then raise exception 'Missing barcode lookup RPC';end if;
  if to_regprocedure('public.division_overview_v44(uuid,date,date)') is null then raise exception 'Missing division overview RPC';end if;

  -- Ensure the V4.4 UI modules exist after upgrade.
  if not exists(select 1 from public.modules where key='invoice_templates') then raise exception 'Missing invoice_templates module';end if;
  if not exists(select 1 from public.modules where key='division_overview') then raise exception 'Missing division_overview module';end if;

  -- New printer profile fields used by the POS settings screen.
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='printer_profiles' and column_name='purpose') then raise exception 'printer_profiles.purpose missing';end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='printer_profiles' and column_name='cash_drawer_enabled') then raise exception 'printer_profiles.cash_drawer_enabled missing';end if;
end $$;
select 'Flexi ERP V4.4 verification passed' as status;
