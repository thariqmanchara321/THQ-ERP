-- Final post-branding V4 verifier.
do $$ begin
  if to_regprocedure('public.tenant_business_location_save_v4(uuid,uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean)') is null then raise exception 'V4 location editor missing';end if;
  if to_regprocedure('public.document_origin_get(uuid,text,uuid)') is null then raise exception 'Invoice origin context missing';end if;
  if to_regprocedure('public.inventory_list_products_v4(uuid,uuid)') is null then raise exception 'Branch inventory API missing';end if;
  if to_regprocedure('public.inventory_location_movements_v4(uuid,uuid,uuid,integer)') is null then raise exception 'Branch movement history API missing';end if;
  if to_regprocedure('public.sales_create_v4(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid)') is null then raise exception 'Branch sales API missing';end if;
  if to_regprocedure('public.accounting_get_summary_v4(uuid,date,date,uuid)') is null then raise exception 'V4 accounting API missing';end if;
  if to_regprocedure('public.business_backup_export_v4(uuid)') is null then raise exception 'V4 backup export missing';end if;
end $$;
select 'FLEXI ERP V4 ABSOLUTE FINAL VERIFICATION PASSED' as status;
