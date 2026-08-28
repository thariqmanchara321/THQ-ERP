-- THQ ERP V4.8.2 — release contract.
begin;
create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json','resources',jsonb_build_array('sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'),'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','mobile_ready',true)
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.2','release','Pricing & Product Identification','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v482_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.price_lists_v482') is null then v_missing:=array_append(v_missing,'price_lists_v482');end if;
 if to_regclass('public.price_list_items_v482') is null then v_missing:=array_append(v_missing,'price_list_items_v482');end if;
 if to_regclass('public.customer_prices_v482') is null then v_missing:=array_append(v_missing,'customer_prices_v482');end if;
 if to_regclass('public.product_identifiers_v482') is null then v_missing:=array_append(v_missing,'product_identifiers_v482');end if;
 if to_regclass('public.label_templates_v482') is null then v_missing:=array_append(v_missing,'label_templates_v482');end if;
 if to_regprocedure('public.pricing_resolve_v482(uuid,uuid,uuid,uuid,numeric,uuid)') is null then v_missing:=array_append(v_missing,'pricing_resolve_v482');end if;
 if to_regprocedure('public.product_identifier_save_v482(uuid,uuid,uuid,text,text,uuid,text,boolean,boolean)') is null then v_missing:=array_append(v_missing,'product_identifier_save_v482');end if;
 if to_regprocedure('public.inventory_product_lookup_v482(uuid,text,uuid)') is null then v_missing:=array_append(v_missing,'inventory_product_lookup_v482');end if;
 if to_regprocedure('public.label_templates_v482(uuid)') is null then v_missing:=array_append(v_missing,'label_templates_v482');end if;
 if to_regprocedure('public.sales_create_v482(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v482');end if;
 if to_regprocedure('public.sales_get_detail_v482(uuid,uuid)') is null then v_missing:=array_append(v_missing,'sales_get_detail_v482');end if;
 if to_regprocedure('public.pricing_lists_v482(uuid)') is null then v_missing:=array_append(v_missing,'pricing_lists_v482');end if;
 if to_regprocedure('public.pricing_rule_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean)') is null then v_missing:=array_append(v_missing,'pricing_rule_save_v482');end if;
 if to_regprocedure('public.customer_price_save_v482(uuid,uuid,uuid,uuid,uuid,numeric,numeric,boolean)') is null then v_missing:=array_append(v_missing,'customer_price_save_v482');end if;
 if to_regprocedure('public.product_identifier_generate_v482(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'product_identifier_generate_v482');end if;
 if to_regprocedure('public.product_identifier_archive_v482(uuid,uuid)') is null then v_missing:=array_append(v_missing,'product_identifier_archive_v482');end if;
 if to_regprocedure('public.label_template_save_v482(uuid,uuid,text,text,text,numeric,numeric,integer,boolean,boolean,boolean,boolean,boolean,text,boolean,boolean)') is null then v_missing:=array_append(v_missing,'label_template_save_v482');end if;
 if to_regprocedure('private.v482_sync_legacy_identifiers(uuid,uuid)') is null then v_missing:=array_append(v_missing,'v482_sync_legacy_identifiers');end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='pricing_source') then v_missing:=array_append(v_missing,'sale_items.pricing_source');end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sale_items' and column_name='pricing_metadata') then v_missing:=array_append(v_missing,'sale_items.pricing_metadata');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.2','migration_no',134,'api_version','v1','label_printing',true);
end$$;
grant execute on function public.thq_v482_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(134,'4.8.2','Pricing & Product Identification','Retail/wholesale/dealer/contractor pricing, customer and quantity pricing, multiple product identifiers, QR/barcode generation and label printing.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 134 release contract applied' as status;
