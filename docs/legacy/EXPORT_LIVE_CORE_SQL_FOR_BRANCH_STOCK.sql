-- Flexi ERP V3.1 - READ ONLY helper.
-- Run this later in Supabase SQL Editor and save the result before we make
-- inventory truly branch/location-aware. This does NOT change any data.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'inventory_adjust_stock',
    'inventory_create_product',
    'inventory_list_products',
    'inventory_get_product_detail',
    'inventory_list_stock_movements',
    'sales_create',
    'sales_get_detail',
    'purchases_create',
    'purchases_get_detail'
  )
order by p.proname, pg_get_function_identity_arguments(p.oid);
