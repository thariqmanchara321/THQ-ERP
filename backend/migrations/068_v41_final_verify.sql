-- FLEXI ERP V4.1 final stabilization verification.
do $$
begin
  if to_regprocedure('public.sales_list_v32(uuid,uuid)') is null then raise exception 'Missing corrected sales list'; end if;
  if to_regprocedure('public.purchases_list_v32(uuid,uuid)') is null then raise exception 'Missing corrected purchases list'; end if;
  if to_regprocedure('public.accounting_register_v4(uuid,text,date,date,uuid,text)') is null then raise exception 'Missing corrected accounting register'; end if;
  if to_regprocedure('public.accounting_statement_v41(uuid,text,date,date,uuid)') is null then raise exception 'Missing accounting statements'; end if;
  if to_regclass('public.business_divisions') is null then raise exception 'Missing business divisions'; end if;
  if to_regprocedure('public.platform_list_businesses_v41()') is null then raise exception 'Missing V4.1 business list'; end if;
  if to_regprocedure('public.platform_business_prepare_delete_v41(uuid,text)') is null then raise exception 'Missing protected business delete preparation'; end if;
  if to_regprocedure('public.pos_terminal_day_v41(uuid,uuid,date)') is null then raise exception 'Missing terminal daily'; end if;
  if not exists(select 1 from public.modules where key='terminal_day' and is_active) then raise exception 'Terminal Daily module is not active'; end if;
  if has_function_privilege('anon','public.platform_business_archive_v41(uuid,text)','EXECUTE') then raise exception 'Archive RPC exposed to anon'; end if;
  if has_function_privilege('anon','public.platform_business_prepare_delete_v41(uuid,text)','EXECUTE') then raise exception 'Delete preparation RPC exposed to anon'; end if;
  if has_function_privilege('anon','public.accounting_statement_v41(uuid,text,date,date,uuid)','EXECUTE') then raise exception 'Accounting statement RPC exposed to anon'; end if;
end $$;
select 'FLEXI ERP V4.1 STABILIZATION VERIFICATION PASSED' as status;
