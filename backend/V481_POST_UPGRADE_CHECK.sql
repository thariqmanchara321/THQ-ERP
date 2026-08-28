-- THQ ERP V4.8.1 post-upgrade checks. Safe/read-only.
select public.thq_backend_contract_v47() as backend_contract;
select public.thq_api_contract_v480() as api_contract;
select public.thq_v481_release_verify() as v481_release_verify;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 125 and 129
order by migration_no;

select
  to_regclass('public.inventory_units_v481') is not null as units_table,
  to_regclass('public.product_units_v481') is not null as product_units_table,
  to_regprocedure('public.inventory_movement_history_v481(uuid,uuid,uuid,text,timestamptz,timestamptz,integer)') is not null as movement_history_rpc,
  to_regprocedure('public.sales_create_v481(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is not null as sales_v481_rpc,
  to_regprocedure('public.purchases_create_v481(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is not null as purchases_v481_rpc,
  to_regprocedure('public.sales_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is not null as sales_return_v481_rpc,
  to_regprocedure('public.purchase_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is not null as purchase_return_v481_rpc;

select code,name,unit_group,decimal_places,allow_fractional
from public.inventory_units_v481
where tenant_id=(select id from public.tenants order by created_at limit 1)
  and code in('PCS','M','KG','L','BOX','COIL')
order by code;
