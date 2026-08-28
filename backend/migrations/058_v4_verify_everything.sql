-- Absolute final verifier for the V4 distribution.
do $$ begin
  if to_regprocedure('public.workshop_vehicles_list_v4(uuid,uuid,text)') is null then raise exception 'Workshop API missing';end if;
  if to_regprocedure('public.custom_field_save_v4(uuid,uuid,text,text,text,text,boolean,boolean,boolean,jsonb,boolean,integer)') is null then raise exception 'Custom fields API missing';end if;
  if to_regprocedure('public.invoice_print_profiles_list_v4(uuid,uuid,uuid)') is null then raise exception 'Printing profile API missing';end if;
  if to_regprocedure('public.accounting_get_summary_v4(uuid,date,date,uuid)') is null then raise exception 'Accounting summary missing';end if;
  if to_regprocedure('public.payments_pending_list_v4(uuid,uuid,integer)') is null then raise exception 'Payment center missing';end if;
end $$;
select 'FLEXI ERP V4 DISTRIBUTION VERIFICATION PASSED' as status;
