-- THQ ERP V4.8.1 — release contract, sync hooks and verification.
begin;

-- Unit and location metadata are master-data changes and should refresh Client/POS catalog/config.
do $$ declare r record;v_name text;begin
  for r in select * from (values ('inventory_units_v481','catalogue'),('product_units_v481','catalogue')) x(table_name,domain) loop
    v_name:='trg_v481_sync_'||r.table_name;
    execute format('drop trigger if exists %I on public.%I',v_name,r.table_name);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.thq_sync_row_trigger_v480(%L)',v_name,r.table_name,r.domain);
  end loop;
end $$;


-- Extend THQ API v1 contract with the inventory/unit resources introduced in V4.8.1.
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','inventory-intelligence','inventory-movements','units','product-units',
      'customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'
    ),
    'core_financial_posting','direct_hardened_rpc','mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.1','release','Inventory & Unit Engine','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v481_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
  if to_regclass('public.inventory_units_v481') is null then v_missing:=array_append(v_missing,'inventory_units_v481');end if;
  if to_regclass('public.product_units_v481') is null then v_missing:=array_append(v_missing,'product_units_v481');end if;
  if to_regclass('public.location_stock_movements') is null then v_missing:=array_append(v_missing,'location_stock_movements');end if;
  if to_regprocedure('public.inventory_units_list_v481(uuid,boolean)') is null then v_missing:=array_append(v_missing,'inventory_units_list_v481');end if;
  if to_regprocedure('public.inventory_product_units_v481(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_product_units_v481');end if;
  if to_regprocedure('public.inventory_product_units_save_v481(uuid,uuid,text,jsonb)') is null then v_missing:=array_append(v_missing,'inventory_product_units_save_v481');end if;
  if to_regprocedure('public.inventory_list_products_v481(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_list_products_v481');end if;
  if to_regprocedure('public.inventory_movement_history_v481(uuid,uuid,uuid,text,timestamptz,timestamptz,integer)') is null then v_missing:=array_append(v_missing,'inventory_movement_history_v481');end if;
  if to_regprocedure('public.sales_create_v481(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v481');end if;
  if to_regprocedure('public.purchases_create_v481(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v481');end if;
  if to_regprocedure('public.sales_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_return_create_v481');end if;
  if to_regprocedure('public.purchase_return_create_v481(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'purchase_return_create_v481');end if;
  if to_regprocedure('public.inventory_unit_save_v481(uuid,uuid,text,text,text,integer,boolean,boolean)') is null then v_missing:=array_append(v_missing,'inventory_unit_save_v481');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='location_stock_movements' and column_name='base_quantity_delta') then v_missing:=array_append(v_missing,'location_stock_movements.base_quantity_delta');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='location_stock_movements' and column_name='balance_after') then v_missing:=array_append(v_missing,'location_stock_movements.balance_after');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='entered_unit_id') then v_missing:=array_append(v_missing,'sale_items.entered_unit_id');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchase_items' and column_name='entered_unit_id') then v_missing:=array_append(v_missing,'purchase_items.entered_unit_id');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.1','migration_no',129,'api_version','v1','inventory_model','base-unit movement ledger');
end $$;
grant execute on function public.thq_v481_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(129,'4.8.1','Inventory & Unit Engine','Universal movement ledger, multi-unit conversion, decimal/cutting-ready sale quantities and generalized operational location types.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 129 release contract applied' as status;
