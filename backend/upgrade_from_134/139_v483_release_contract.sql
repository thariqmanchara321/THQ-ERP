-- THQ ERP V4.8.3 — release contract.
begin;
create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json','resources',jsonb_build_array('sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates','tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'),'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3','mobile_ready',true)
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.3','release','Serial / Batch / Warranty','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v483_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.product_tracking_policies_v483') is null then v_missing:=array_append(v_missing,'product_tracking_policies_v483');end if;
 if to_regclass('public.inventory_serials_v483') is null then v_missing:=array_append(v_missing,'inventory_serials_v483');end if;
 if to_regclass('public.inventory_batches_v483') is null then v_missing:=array_append(v_missing,'inventory_batches_v483');end if;
 if to_regclass('public.inventory_batch_balances_v483') is null then v_missing:=array_append(v_missing,'inventory_batch_balances_v483');end if;
 if to_regclass('public.inventory_trace_events_v483') is null then v_missing:=array_append(v_missing,'inventory_trace_events_v483');end if;
 if to_regclass('public.product_warranties_v483') is null then v_missing:=array_append(v_missing,'product_warranties_v483');end if;
 if to_regprocedure('public.inventory_tracking_policy_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_tracking_policy_v483');end if;
 if to_regprocedure('public.inventory_tracking_policy_save_v483(uuid,uuid,text,boolean,integer,integer,boolean,boolean)') is null then v_missing:=array_append(v_missing,'inventory_tracking_policy_save_v483');end if;
 if to_regprocedure('public.inventory_tracking_register_opening_v483(uuid,uuid,uuid,jsonb,jsonb,text)') is null then v_missing:=array_append(v_missing,'inventory_tracking_register_opening_v483');end if;
 if to_regprocedure('public.inventory_list_products_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_list_products_v483');end if;
 if to_regprocedure('public.purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v483');end if;
 if to_regprocedure('public.sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v483');end if;
 if to_regprocedure('public.inventory_serial_search_v483(uuid,text,uuid,integer)') is null then v_missing:=array_append(v_missing,'inventory_serial_search_v483');end if;
 if to_regprocedure('public.inventory_batch_search_v483(uuid,text,uuid,integer)') is null then v_missing:=array_append(v_missing,'inventory_batch_search_v483');end if;
 if to_regprocedure('public.inventory_batch_history_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_batch_history_v483');end if;
 if to_regprocedure('public.inventory_serial_history_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_serial_history_v483');end if;
 if to_regprocedure('public.warranty_register_v483(uuid,text,text,integer,integer,uuid)') is null then v_missing:=array_append(v_missing,'warranty_register_v483');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.3','migration_no',139,'api_version','v1','serial_tracking',true,'batch_tracking',true,'warranty_tracking',true,'batch_fefo',true);
end$$;
grant execute on function public.thq_v483_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(139,'4.8.3','Serial / Batch / Warranty','Serial number tracking, batch/expiry tracking, warranty expiry, supplier/customer traceability, serial search and batch history.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 139 release contract applied' as status;
