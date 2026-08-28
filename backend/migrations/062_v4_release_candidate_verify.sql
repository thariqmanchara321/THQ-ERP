-- Flexi ERP V4 release-candidate verifier.
do $$
declare v_anon integer;
begin
  if to_regprocedure('public.inventory_location_movements_v4(uuid,uuid,uuid,integer)') is null then raise exception 'Branch movement API missing';end if;
  if to_regprocedure('public.tenant_business_location_save_v4(uuid,uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean)') is null then raise exception 'Location identity editor missing';end if;
  if to_regprocedure('public.accounting_register_v4(uuid,text,date,date,uuid,text)') is null then raise exception 'Accounting register missing';end if;
  if to_regprocedure('public.business_backup_export_v4(uuid)') is null then raise exception 'Business backup missing';end if;
  select count(*) into v_anon
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and right(p.proname,3)='_v4'
    and has_function_privilege('anon',p.oid,'EXECUTE');
  if coalesce(v_anon,0)>0 then raise exception 'Security verification failed: anon can execute % V4 RPC(s)',v_anon;end if;
end $$;
select 'FLEXI ERP V4 RELEASE CANDIDATE VERIFICATION PASSED' as status;
