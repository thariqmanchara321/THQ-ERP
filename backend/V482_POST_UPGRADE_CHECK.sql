-- THQ ERP V4.8.2 — post-upgrade verification
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_api_contract_v480() as api_contract;
select public.thq_v482_release_verify() as release_verification;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 130 and 134
order by migration_no;

select
  to_regclass('public.price_lists_v482') is not null as price_lists_ready,
  to_regclass('public.customer_prices_v482') is not null as customer_prices_ready,
  to_regclass('public.product_identifiers_v482') is not null as product_identifiers_ready,
  to_regclass('public.label_templates_v482') is not null as label_templates_ready,
  to_regprocedure('public.pricing_resolve_v482(uuid,uuid,uuid,uuid,numeric,uuid)') is not null as pricing_resolver_ready,
  to_regprocedure('public.sales_create_v482(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is not null as authoritative_sales_ready,
  to_regprocedure('public.inventory_product_lookup_v482(uuid,text,uuid)') is not null as unified_product_lookup_ready;
