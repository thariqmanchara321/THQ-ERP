-- THQ ERP V4.8.6 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP',
  'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
  'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
  'minimum_app_version','4.8.6','release','Offline POS','api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v486_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regclass('public.pos_offline_sync_v486') is null then v_missing:=array_append(v_missing,'pos_offline_sync_v486');end if;
  if to_regprocedure('public.pos_offline_sale_sync_v486(uuid,uuid,uuid,text,jsonb)') is null then v_missing:=array_append(v_missing,'pos_offline_sale_sync_v486');end if;
  if to_regprocedure('public.pos_offline_sync_list_v486(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'pos_offline_sync_list_v486');end if;
  if to_regprocedure('public.pos_offline_sync_summary_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_sync_summary_v486');end if;
  if to_regprocedure('public.pos_offline_product_cache_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_product_cache_v486');end if;
  if to_regprocedure('public.pos_offline_customer_cache_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_customer_cache_v486');end if;
  if to_regprocedure('public.pos_offline_available_serials_v486(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'pos_offline_available_serials_v486');end if;
  if to_regprocedure('public.pos_offline_cache_manifest_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_cache_manifest_v486');end if;
  if to_regprocedure('public.pos_offline_api_contract_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_api_contract_v486');end if;
  if to_regprocedure('public.pos_offline_request_lookup_v486(uuid,text)') is null then v_missing:=array_append(v_missing,'pos_offline_request_lookup_v486');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.6','migration_no',160,'api_version','v1',
    'local_pos_database',true,'offline_billing',true,'offline_invoice_queue',true,'automatic_sync',true,'safe_retry_idempotency',true,
    'offline_product_customer_cache',true,'serial_cache',true,'sync_status_conflicts',true,'price_tax_conflict_protection',true
  );
end$$;
grant execute on function public.thq_v486_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(160,'4.8.6','Offline POS','Local-first POS billing, SQLite queue/cache, automatic idempotent sync, offline product/customer/serial cache, and conflict handling.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 160 release contract applied' as status;
