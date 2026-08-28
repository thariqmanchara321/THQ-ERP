-- FLEXI ERP V4 final verification.
do $$
declare x text;
begin
  foreach x in array array[
    'location_stock_balances','location_stock_movements','location_product_settings','stock_transfers','stock_counts',
    'sales_returns','purchase_returns','transaction_corrections','cashier_shifts','cash_drawer_movements',
    'accounting_accounts','journal_entries','journal_lines','printer_profiles','business_export_runs',
    'notifications','business_tasks','approval_rules','custom_field_definitions','platform_app_releases','support_tickets'
  ] loop
    if to_regclass('public.'||x) is null then raise exception 'Missing V4 table: %',x;end if;
  end loop;

  foreach x in array array[
    'inventory_list_products_v4','inventory_create_product_v4','sales_create_v4','purchases_create_v4',
    'inventory_transfer_create_v4','inventory_stock_count_post_v4','sales_return_create_v4','purchase_return_create_v4',
    'cashier_shift_open_v4','accounting_register_v4','business_backup_export_v4','notifications_list_v4',
    'business_tasks_list_v4','approval_requests_list_v4','global_search_v4','dashboard_get_summary_v4','reports_get_summary_v4'
  ] loop
    if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=x) then
      raise exception 'Missing V4 function: %',x;
    end if;
  end loop;
end $$;
select 'FLEXI ERP V4 FINAL BACKEND VERIFICATION PASSED' as status;
