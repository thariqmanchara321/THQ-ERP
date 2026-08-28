-- FLEXI ERP V3.1 - verification only. Throws if a required object is missing.
do $$
declare x text;
begin
  foreach x in array array[
    'user_login_names',
    'business_locations',
    'business_devices',
    'document_origins',
    'location_document_counters',
    'location_document_numbers',
    'app_error_logs',
    'business_audit_log',
    'invoice_templates',
    'tenant_invoice_templates',
    'production_recipes',
    'production_recipe_items',
    'production_runs',
    'service_vehicles',
    'service_jobs',
    'restaurant_tables',
    'restaurant_orders',
    'restaurant_order_items',
    'restaurant_kots'
  ] loop
    if to_regclass('public.' || x) is null then
      raise exception 'Missing V3.1 table: %', x;
    end if;
  end loop;

  foreach x in array array[
    'current_username',
    'business_locations_list',
    'platform_business_locations_list',
    'platform_business_devices_list',
    'platform_device_issue_activation',
    'platform_device_revoke',
    'document_origin_attach',
    'document_origin_attach_by_reference',
    'document_origin_get',
    'location_business_summary',
    'entity_tracking_lookup',
    'business_audit_log_list',
    'production_recipes_list',
    'production_recipe_save',
    'production_runs_list',
    'production_run_execute',
    'service_vehicles_list',
    'service_vehicle_save',
    'service_jobs_list',
    'service_job_create',
    'service_job_link_sale_by_reference',
    'restaurant_tables_list',
    'restaurant_table_save',
    'restaurant_orders_list',
    'restaurant_order_create',
    'restaurant_kot_send',
    'restaurant_order_mark_billed_by_reference',
    'platform_username_lookup',
    'platform_usernames_list',
    'platform_admins_v3_list'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = x
    ) then
      raise exception 'Missing V3.1 function: %', x;
    end if;
  end loop;
end $$;

select 'V3.1 backend verification passed' as status;
