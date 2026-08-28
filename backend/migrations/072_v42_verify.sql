-- FLEXI ERP V4.2 verification. Fails fast if the V4.2 contract is incomplete.
begin;
do $$
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='business_locations' and column_name='hierarchy_role') then raise exception 'V4.2 hierarchy role missing';end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='stock_transfers' and column_name='reservation_applied') then raise exception 'V4.2 transfer reservation flag missing';end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='stock_transfer_items' and column_name='dispatched_quantity') then raise exception 'V4.2 dispatched quantity missing';end if;
  if to_regprocedure('public.business_location_tree_v42(uuid)') is null then raise exception 'V4.2 location tree RPC missing';end if;
  if to_regprocedure('public.tenant_locations_devices_list_v42(uuid)') is null then raise exception 'V4.2 location/device directory RPC missing';end if;
  if to_regprocedure('public.tenant_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,text,boolean)') is null then raise exception 'V4.2 tenant location save RPC missing';end if;
  if to_regprocedure('public.platform_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,boolean)') is null then raise exception 'V4.2 platform location save RPC missing';end if;
  if to_regprocedure('public.client_runtime_context_v4(uuid,uuid,text)') is null then raise exception 'V4.2 runtime context contract missing';end if;
  if to_regprocedure('public.inventory_transfer_create_v42(uuid,uuid,uuid,jsonb,text)') is null then raise exception 'V4.2 transfer create RPC missing';end if;
  if to_regprocedure('public.inventory_transfer_approve_v42(uuid,uuid)') is null then raise exception 'V4.2 transfer approve RPC missing';end if;
  if to_regprocedure('public.inventory_transfer_reject_v42(uuid,uuid,text)') is null then raise exception 'V4.2 transfer reject RPC missing';end if;
  if to_regprocedure('public.inventory_transfer_cancel_v42(uuid,uuid,text)') is null then raise exception 'V4.2 transfer cancel RPC missing';end if;
  if to_regprocedure('public.inventory_transfers_list_v42(uuid,uuid,integer)') is null then raise exception 'V4.2 transfer list RPC missing';end if;
  if to_regprocedure('public.inventory_transfer_detail_v42(uuid,uuid)') is null then raise exception 'V4.2 transfer detail RPC missing';end if;
  if to_regprocedure('public.inventory_transfer_dispatch_v4(uuid,uuid,uuid)') is null then raise exception 'V4.2 transfer dispatch contract missing';end if;
  if to_regprocedure('public.inventory_transfer_receive_v4(uuid,uuid,uuid)') is null then raise exception 'V4.2 transfer receive contract missing';end if;
  if to_regprocedure('public.inventory_location_stock_summary_v42(uuid,uuid)') is null then raise exception 'V4.2 stock summary RPC missing';end if;
  if to_regprocedure('public.inventory_location_overview_v42(uuid)') is null then raise exception 'V4.2 location overview RPC missing';end if;
  if to_regprocedure('public.inventory_stock_integrity_v42(uuid)') is null then raise exception 'V4.2 stock integrity RPC missing';end if;
  if exists(
    select t.id from public.tenants t
    left join public.business_locations l on l.tenant_id=t.id and l.hierarchy_role='main_store'
    group by t.id having count(l.id)<>1
  ) then raise exception 'A business has an invalid MAIN location count';end if;
  if exists(select 1 from public.business_locations where hierarchy_role='main_store' and (parent_location_id is not null or not active or sort_order<>0)) then raise exception 'A MAIN location is not canonical';end if;
end $$;
commit;
select 'Flexi ERP V4.2 verification passed' as status;
