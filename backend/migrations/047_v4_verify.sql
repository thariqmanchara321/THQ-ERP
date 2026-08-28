-- FLEXI ERP V4 final backend verification.
do $$
declare x text;begin
  foreach x in array array[
    'location_product_settings','location_stock_balances','location_stock_movements','stock_transfers','stock_transfer_items','stock_counts','stock_count_items',
    'transaction_corrections','sales_returns','sales_return_items','purchase_returns','purchase_return_items','cashier_shifts','cash_drawer_movements',
    'accounting_accounts','accounting_account_mappings','journal_entries','journal_lines','printer_profiles','invoice_print_events','business_export_runs',
    'notifications','business_tasks','entity_attachments','approval_rules','approval_requests','custom_field_definitions','custom_field_values','user_saved_views','user_preferences_v4','support_tickets','platform_app_releases','device_app_status','workshop_vehicles','workshop_job_cards','production_boms'
  ] loop if to_regclass('public.'||x) is null then raise exception 'V4 verification failed: missing table %',x;end if;end loop;
  foreach x in array array[
    'inventory_list_products_v4','inventory_create_product_v4','inventory_adjust_stock_v4','sales_create_v4','purchases_create_v4','inventory_transfer_create_v4','inventory_stock_count_post_v4',
    'sales_return_create_v4','purchase_return_create_v4','sales_void_v4','purchase_void_v4','cashier_shift_open_v4','cashier_shift_close_v4','accounting_accounts_list_v4','accounting_account_save_v4','accounting_register_v4','business_backup_export_v4','client_runtime_context_v4','global_search_v4'
  ] loop if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=x) then raise exception 'V4 verification failed: missing function %',x;end if;end loop;
end $$;
select 'FLEXI ERP V4 BACKEND VERIFICATION PASSED' as status;
