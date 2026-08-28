-- Final V4 package verification.
do $$
begin
  if to_regprocedure('public.inventory_list_products_v4(uuid,uuid)') is null then raise exception 'Missing branch inventory'; end if;
  if to_regprocedure('public.sales_create_v4(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid)') is null then raise exception 'Missing branch-aware sales'; end if;
  if to_regprocedure('public.purchases_create_v4(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid)') is null then raise exception 'Missing branch-aware purchases'; end if;
  if to_regprocedure('public.payments_pending_list_v4(uuid,uuid,integer)') is null then raise exception 'Missing return-aware payments'; end if;
  if to_regprocedure('public.accounting_get_summary_v4(uuid,date,date,uuid)') is null then raise exception 'Missing V4 accounting summary'; end if;
  if to_regprocedure('public.business_backup_export_v4(uuid)') is null then raise exception 'Missing backup export'; end if;
  if to_regprocedure('public.global_search_v4(uuid,text,integer)') is null then raise exception 'Missing global search'; end if;
  if to_regprocedure('public.custom_fields_list_v4(uuid,text)') is null then raise exception 'Missing custom fields'; end if;
  if to_regprocedure('public.notifications_list_v4(uuid,integer)') is null then raise exception 'Missing notifications'; end if;
  if to_regprocedure('public.device_heartbeat_v4(uuid,uuid,text,text,text,integer,jsonb)') is null then raise exception 'Missing release/device heartbeat'; end if;
  if not exists(select 1 from public.accounting_accounts where system_key='accounts_receivable') then raise exception 'Default accounting chart incomplete'; end if;
  if not exists(select 1 from public.accounting_accounts where system_key='customer_credits') then raise exception 'Credit accounting incomplete'; end if;
end $$;
select 'FLEXI ERP V4 FINAL PACKAGE VERIFICATION PASSED' as status;
