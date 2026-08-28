-- FLEXI ERP V4.1 final security and verification.
begin;

revoke all on function public.platform_divisions_list_v41() from public,anon;
revoke all on function public.platform_division_save_v41(uuid,text,text,boolean) from public,anon;
revoke all on function public.platform_division_assign_business_v41(uuid,uuid,text) from public,anon;
revoke all on function public.platform_division_remove_business_v41(uuid) from public,anon;
revoke all on function public.platform_list_businesses_v41() from public,anon;
revoke all on function public.platform_business_archive_v41(uuid,text) from public,anon;
revoke all on function public.pos_terminal_day_v41(uuid,uuid,date) from public,anon;

-- Authenticated grants are explicit after revocation.
grant execute on function public.platform_divisions_list_v41() to authenticated;
grant execute on function public.platform_division_save_v41(uuid,text,text,boolean) to authenticated;
grant execute on function public.platform_division_assign_business_v41(uuid,uuid,text) to authenticated;
grant execute on function public.platform_division_remove_business_v41(uuid) to authenticated;
grant execute on function public.platform_list_businesses_v41() to authenticated;
grant execute on function public.platform_business_archive_v41(uuid,text) to authenticated;
grant execute on function public.pos_terminal_day_v41(uuid,uuid,date) to authenticated;


revoke all on function public.platform_business_prepare_delete_v41(uuid,text) from public,anon;
grant execute on function public.platform_business_prepare_delete_v41(uuid,text) to authenticated;
commit;

do $$
begin
  if to_regclass('public.business_divisions') is null then raise exception 'Missing business divisions';end if;
  if to_regclass('public.business_division_members') is null then raise exception 'Missing division members';end if;
  if to_regprocedure('public.purchases_list_v32(uuid,uuid)') is null then raise exception 'Missing corrected purchase list';end if;
  if to_regprocedure('public.accounting_register_v4(uuid,text,date,date,uuid,text)') is null then raise exception 'Missing corrected accounting register';end if;
  if to_regprocedure('public.pos_terminal_day_v41(uuid,uuid,date)') is null then raise exception 'Missing terminal daily';end if;
  if to_regprocedure('public.platform_list_businesses_v41()') is null then raise exception 'Missing V4.1 business list';end if;
end $$;

select 'FLEXI ERP V4.1 STABILIZATION BACKEND VERIFICATION PASSED' as status;
