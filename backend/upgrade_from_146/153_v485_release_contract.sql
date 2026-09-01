-- THQ ERP V4.8.5 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP',
  'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
  'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
  'minimum_app_version','4.8.5','release','Warehouse & Transfers','api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v485_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regclass('public.stock_transfer_allocations_v485') is null then v_missing:=array_append(v_missing,'stock_transfer_allocations_v485');end if;
  if to_regclass('public.stock_transfer_history_v485') is null then v_missing:=array_append(v_missing,'stock_transfer_history_v485');end if;
  if to_regprocedure('public.warehouse_locations_v485(uuid)') is null then v_missing:=array_append(v_missing,'warehouse_locations_v485');end if;
  if to_regprocedure('public.warehouse_inventory_v485(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'warehouse_inventory_v485');end if;
  if to_regprocedure('public.inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_request_v485');end if;
  if to_regprocedure('public.inventory_transfer_decide_v485(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_decide_v485');end if;
  if to_regprocedure('public.inventory_transfer_cancel_v485(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_cancel_v485');end if;
  if to_regprocedure('public.inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_dispatch_v485');end if;
  if to_regprocedure('public.inventory_transfer_receive_v485(uuid,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_transfer_receive_v485');end if;
  if to_regprocedure('public.inventory_transfers_list_v485(uuid,uuid,text,text,integer)') is null then v_missing:=array_append(v_missing,'inventory_transfers_list_v485');end if;
  if to_regprocedure('public.inventory_transfer_detail_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_detail_v485');end if;
  if to_regprocedure('public.inventory_transfer_history_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_history_v485');end if;
  if to_regprocedure('public.inventory_transfer_tracking_options_v485(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_transfer_tracking_options_v485');end if;
  if to_regprocedure('public.inventory_stock_count_snapshot_v485(uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_stock_count_snapshot_v485');end if;
  if to_regprocedure('public.inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text)') is null then v_missing:=array_append(v_missing,'inventory_stock_count_post_v485');end if;
  if to_regprocedure('public.stock_counts_list_v485(uuid,uuid,date,date,integer)') is null then v_missing:=array_append(v_missing,'stock_counts_list_v485');end if;
  if to_regprocedure('public.stock_count_detail_v485(uuid,uuid)') is null then v_missing:=array_append(v_missing,'stock_count_detail_v485');end if;
  if to_regprocedure('public.inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer)') is null then v_missing:=array_append(v_missing,'inventory_stock_reconciliation_v485');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.5','migration_no',153,'api_version','v1',
    'warehouse_locations',true,'stock_transfer_request',true,'transfer_approval',true,'dispatch',true,'in_transit',true,'receive',true,
    'transfer_history',true,'serial_batch_transfer',true,'stock_count',true,'stock_reconciliation',true
  );
end$$;
grant execute on function public.thq_v485_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(153,'4.8.5','Warehouse & Transfers','Warehouse locations, tracked-safe stock transfer request/approval/dispatch/in-transit/receive/history, physical stock counts and stock reconciliation.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 153 release contract applied' as status;
