-- THQ ERP v4.8.9 — runtime compatibility and stabilization guardrails.
begin;

-- Keep all rounded document adjustments within the UI/accounting contract.
do $$ begin
  if not exists(select 1 from pg_constraint where conname='sales_round_off_v489_check') then
    alter table public.sales add constraint sales_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='purchases_round_off_v489_check') then
    alter table public.purchases add constraint purchases_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='expenses_round_off_v489_check') then
    alter table public.expenses add constraint expenses_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='purchase_invoice_round_off_v489_check') then
    alter table public.purchase_invoices_v484 add constraint purchase_invoice_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='restaurant_order_items_conversion_v489_check') then
    alter table public.restaurant_order_items add constraint restaurant_order_items_conversion_v489_check check(conversion_to_base>0);
  end if;
end $$;

create index if not exists idx_restaurant_orders_ops_v489
  on public.restaurant_orders(tenant_id,location_id,status,opened_at desc);
create index if not exists idx_purchase_invoices_ops_v489
  on public.purchase_invoices_v484(tenant_id,location_id,status,due_date,invoice_date desc);
create index if not exists idx_pos_offline_sync_ops_v489
  on public.pos_offline_sync_v486(tenant_id,location_id,status,updated_at desc);

-- A source/runtime audit endpoint. It deliberately reports missing baseline objects instead
-- of failing deployment, because the earliest ERP core tables/RPCs predate this migration set.
create or replace function public.erp_runtime_health_v489(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_required_functions text[]:=array[
    'current_user_is_platform_admin',
    'customers_create','customers_update','suppliers_create','suppliers_update',
    'inventory_list_products','inventory_get_product_detail','inventory_create_product','inventory_update_product',
    'platform_create_business','platform_get_business_modules','platform_get_business_permissions',
    'platform_get_business_roles','platform_list_modules','platform_update_role_permissions',
    'sales_create_v489','purchases_create_v489','expenses_create_v489','expenses_update_v489',
    'inventory_product_units_v481','inventory_product_units_save_v481','pricing_resolve_v482',
    'purchase_invoice_create_v489','purchase_invoice_post_v484','purchase_order_decide_v484','operations_pipeline_v489',
    'sales_add_payment_v47','restaurant_order_create_v32','restaurant_order_bill_v489','restaurant_operations_summary_v489','pos_offline_sale_sync_v486',
    'mobile_client_context_v487','mobile_client_dashboard_v487','mobile_approvals_v487','mobile_customer_payment_v487',
    'mobile_pos_terminal_context_v488','mobile_pos_sale_sync_v488','mobile_pos_cache_manifest_v488','mobile_pos_sync_status_v488',
    'thq_backend_contract_v47','thq_api_contract_v480'
  ];
  v_required_tables text[]:=array[
    'tenants','tenant_memberships','tenant_modules','tenant_settings','modules','roles','role_permissions','user_roles',
    'products','product_variants','customers','suppliers',
    'sales','sale_items','purchases','purchase_items','expenses','business_locations','business_devices',
    'inventory_units_v481','product_units_v481','price_lists_v482','restaurant_orders','restaurant_order_items',
    'purchase_invoices_v484','pos_offline_sync_v486','thq_schema_releases'
  ];
  v_missing_functions text[]:='{}'::text[];v_missing_tables text[]:='{}'::text[];
  v text;v_release jsonb;v_pipeline jsonb:='{}'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  foreach v in array v_required_functions loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v
    ) then v_missing_functions:=array_append(v_missing_functions,v);end if;
  end loop;
  foreach v in array v_required_tables loop
    if to_regclass('public.'||v) is null then v_missing_tables:=array_append(v_missing_tables,v);end if;
  end loop;
  select jsonb_build_object(
    'schema_version',schema_version,'migration_no',migration_no,'release_name',release_name
  ) into v_release from public.thq_schema_releases order by migration_no desc limit 1;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='operations_pipeline_v489') then
    begin v_pipeline:=public.operations_pipeline_v489(p_tenant_id,null); exception when others then v_pipeline:=jsonb_build_object('error',sqlerrm);end;
  end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing_functions)=0 and cardinality(v_missing_tables)=0,
    'missing_functions',to_jsonb(v_missing_functions),'missing_tables',to_jsonb(v_missing_tables),
    'release',coalesce(v_release,'{}'::jsonb),'operations',v_pipeline,
    'pricing_engine','v4.8.2-authoritative','unit_engine','v4.8.1','tracking_engine','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile','v4.8.7','mobile_pos','v4.8.8','stabilization','v4.8.9'
  );
end $$;
grant execute on function public.erp_runtime_health_v489(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(178,'4.8.9','Stabilization & Operations','Runtime compatibility audit, round-off constraints and operational indexes for critical cross-module workflows.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 178 runtime hardening applied' as status;
