-- FLEXI ERP V4 final post-package verification.
do $$
begin
  if to_regclass('public.location_stock_balances') is null then raise exception 'Missing V4 branch stock balances'; end if;
  if to_regclass('public.stock_transfers') is null then raise exception 'Missing stock transfers'; end if;
  if to_regclass('public.stock_counts') is null then raise exception 'Missing stock counts'; end if;
  if to_regclass('public.sales_returns') is null or to_regclass('public.purchase_returns') is null then raise exception 'Missing return tables'; end if;
  if to_regclass('public.cashier_shifts') is null then raise exception 'Missing cashier shifts'; end if;
  if to_regclass('public.accounting_accounts') is null or to_regclass('public.journal_entries') is null then raise exception 'Missing V4 accounting'; end if;
  if to_regprocedure('public.sales_create_v4(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid)') is null then raise exception 'Missing sales_create_v4'; end if;
  if to_regprocedure('public.purchases_create_v4(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid)') is null then raise exception 'Missing purchases_create_v4'; end if;
  if to_regprocedure('public.inventory_stock_count_post_v4(uuid,uuid,jsonb,text,uuid)') is null then raise exception 'Missing stock count RPC'; end if;
  if to_regprocedure('public.accounting_accounts_list_v4(uuid)') is null then raise exception 'Missing accounting account RPC'; end if;
  if to_regprocedure('public.accounting_mappings_list_v4(uuid)') is null then raise exception 'Missing accounting mapping RPC'; end if;
  if to_regprocedure('public.business_backup_export_v4(uuid)') is null then raise exception 'Missing complete backup RPC'; end if;
  if to_regprocedure('public.global_search_v4(uuid,text,integer)') is null then raise exception 'Missing global search'; end if;
  if to_regprocedure('public.device_heartbeat_v4(uuid,uuid,text,text,text,integer,jsonb)') is null then raise exception 'Missing device heartbeat'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sales' and column_name='created_by') then raise exception 'Missing sales actor attribution'; end if;
end $$;
select 'FLEXI ERP V4 COMPLETE BACKEND VERIFICATION PASSED' as status;
