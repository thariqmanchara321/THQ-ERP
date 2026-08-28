# Main V3.1 backend objects

## Identity
`user_login_names`, tenant `business_code`, `current_username()`.

## Tracking
`entity_tracking_counters` and immutable `tracking_code` fields on supported entities.

## Logging/audit
`app_error_logs`, `business_audit_log`, `app_error_log_write`, `app_error_logs_list`, business/platform audit viewers.

## Invoice
`invoice_templates`, `tenant_invoice_templates`, Admin template RPCs and tenant invoice assignment.

## Locations/devices
`business_locations`, `business_devices`, `document_origins`, `location_document_counters`, `location_document_numbers`.

## Production
`production_recipes`, `production_recipe_items`, `production_runs` and run RPCs.

## Transport service
`service_vehicles`, `service_jobs` and linked billing RPCs.

## Restaurant
`restaurant_tables`, `restaurant_orders`, `restaurant_order_items`, `restaurant_kots` and order/KOT/billing RPCs.

## Reporting
`location_business_summary`, `document_origin_get`, `entity_tracking_lookup`.
