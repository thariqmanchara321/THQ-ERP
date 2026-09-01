-- THQ ERP V4.8.8 — Mobile POS Foundation release contract.
begin;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.8','release','Mobile POS Foundation','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v488_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regprocedure('public.mobile_pos_terminal_context_v488(uuid,uuid)') is null then v_missing:=array_append(v_missing,'mobile_pos_terminal_context_v488');end if;
  if to_regprocedure('public.mobile_pos_sale_sync_v488(uuid,uuid,text,jsonb)') is null then v_missing:=array_append(v_missing,'mobile_pos_sale_sync_v488');end if;
  if to_regprocedure('public.mobile_pos_cache_manifest_v488(uuid,uuid)') is null then v_missing:=array_append(v_missing,'mobile_pos_cache_manifest_v488');end if;
  if to_regprocedure('public.mobile_pos_receipt_event_v488(uuid,uuid,text,text,text)') is null then v_missing:=array_append(v_missing,'mobile_pos_receipt_event_v488');end if;
  if to_regprocedure('public.mobile_pos_kot_create_v488(uuid,uuid,text,text,uuid,uuid,jsonb,text,boolean)') is null then v_missing:=array_append(v_missing,'mobile_pos_kot_create_v488');end if;
  if to_regprocedure('public.mobile_pos_sync_status_v488(uuid,uuid,integer)') is null then v_missing:=array_append(v_missing,'mobile_pos_sync_status_v488');end if;
  if to_regprocedure('public.mobile_pos_api_contract_v488(uuid,uuid)') is null then v_missing:=array_append(v_missing,'mobile_pos_api_contract_v488');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.8','migration_no',174,'api_version','v1','client_mobile',true,'mobile_pos',true,'offline_pos',true,'kot_groundwork',true);
end$$;
grant execute on function public.thq_v488_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(174,'4.8.8','Mobile POS Foundation','Phone-first POS billing, camera barcode/serial scan, customer selection, payments, system printing, offline queue/idempotent sync, POS terminal activation and KOT groundwork.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 174 release contract applied' as status;
