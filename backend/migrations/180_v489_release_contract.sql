-- THQ ERP v4.8.9 — Stabilization & Operations release contract.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.8.9',
   'release','Stabilization & Operations',
   'api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v489_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_baseline text;
  v_baseline_required text[]:=array[
    'current_user_is_platform_admin',
    'customers_create','customers_update','suppliers_create','suppliers_update',
    'inventory_list_products','inventory_get_product_detail','inventory_create_product','inventory_update_product',
    'platform_create_business','platform_get_business_modules','platform_get_business_permissions',
    'platform_get_business_roles','platform_list_modules','platform_update_role_permissions'
  ];
begin
  -- These RPCs are part of the original ERP bootstrap and predate migration 001.
  -- A release must report them if the live Supabase project is missing one.
  foreach v_baseline in array v_baseline_required loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_baseline
    ) then v_missing:=array_append(v_missing,'baseline.'||v_baseline);end if;
  end loop;
  if to_regclass('public.tenants') is null then v_missing:=array_append(v_missing,'baseline.tenants');end if;
  if to_regclass('public.tenant_memberships') is null then v_missing:=array_append(v_missing,'baseline.tenant_memberships');end if;
  if to_regclass('public.tenant_modules') is null then v_missing:=array_append(v_missing,'baseline.tenant_modules');end if;
  if to_regclass('public.tenant_settings') is null then v_missing:=array_append(v_missing,'baseline.tenant_settings');end if;
  if to_regclass('public.modules') is null then v_missing:=array_append(v_missing,'baseline.modules');end if;
  if to_regclass('public.roles') is null then v_missing:=array_append(v_missing,'baseline.roles');end if;
  if to_regclass('public.role_permissions') is null then v_missing:=array_append(v_missing,'baseline.role_permissions');end if;
  if to_regclass('public.user_roles') is null then v_missing:=array_append(v_missing,'baseline.user_roles');end if;
  if to_regprocedure('public.operations_pipeline_v489(uuid,uuid)') is null then v_missing:=array_append(v_missing,'operations_pipeline_v489');end if;
  if to_regprocedure('public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v489');end if;
  if to_regprocedure('public.purchases_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v489');end if;
  if to_regprocedure('public.expenses_create_v489(uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'expenses_create_v489');end if;
  if to_regprocedure('public.expenses_update_v489(uuid,uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text)') is null then v_missing:=array_append(v_missing,'expenses_update_v489');end if;
  if to_regprocedure('public.purchase_invoice_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,text)') is null then v_missing:=array_append(v_missing,'purchase_invoice_create_v489');end if;
  if to_regprocedure('public.purchase_order_decide_v484(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'purchase_order_decide_v484');end if;
  if to_regprocedure('public.sales_add_payment_v47(uuid,uuid,numeric,text,text,text,text)') is null then v_missing:=array_append(v_missing,'sales_add_payment_v47');end if;
  if to_regprocedure('public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb)') is null then v_missing:=array_append(v_missing,'restaurant_order_create_v32');end if;
  if to_regprocedure('public.restaurant_order_bill_v489(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric)') is null then v_missing:=array_append(v_missing,'restaurant_order_bill_v489');end if;
  if to_regprocedure('public.restaurant_operations_summary_v489(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'restaurant_operations_summary_v489');end if;
  if to_regprocedure('public.erp_runtime_health_v489(uuid)') is null then v_missing:=array_append(v_missing,'erp_runtime_health_v489');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sales' and column_name='round_off') then v_missing:=array_append(v_missing,'sales.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchases' and column_name='round_off') then v_missing:=array_append(v_missing,'purchases.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='expenses' and column_name='round_off') then v_missing:=array_append(v_missing,'expenses.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchase_invoices_v484' and column_name='round_off') then v_missing:=array_append(v_missing,'purchase_invoices_v484.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='restaurant_order_items' and column_name='unit_id') then v_missing:=array_append(v_missing,'restaurant_order_items.unit_id');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='restaurant_order_items' and column_name='conversion_to_base') then v_missing:=array_append(v_missing,'restaurant_order_items.conversion_to_base');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),
    'schema_version','4.8.9','migration_no',180,'api_version','v1',
    'operations_intelligence',true,'product_units_in_add_edit',true,'billing_unit_selection',true,
    'authoritative_pricing',true,'round_off',true,'purchasing_v2_stabilized',true,
    'receivables_responsive',true,'restaurant_v2',true,'subscription_module_dropdown',true,
    'client_mobile_analyzer_fixes',true,'runtime_audit',true
  );
end $$;
grant execute on function public.thq_v489_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(180,'4.8.9','Stabilization & Operations','End-to-end stabilization release: units in product add/edit and billing, authoritative pricing, explicit round-off, Purchasing V2 fixes, responsive receivables, Restaurant V2, subscription module picker and runtime audit.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 180 release contract applied' as status;
