-- FLEXI ERP V4 financial-integrity verification after return/void accounting.
do $$
begin
  if to_regprocedure('public.payments_pending_list_v4(uuid,uuid,integer)') is null then raise exception 'Missing payments_pending_list_v4'; end if;
  if to_regprocedure('public.accounting_get_summary_v4(uuid,date,date,uuid)') is null then raise exception 'Missing accounting_get_summary_v4'; end if;
  if to_regprocedure('private.v4_post_sales_return(uuid)') is null then raise exception 'Missing sales return accounting'; end if;
  if to_regprocedure('private.v4_post_purchase_return(uuid)') is null then raise exception 'Missing purchase return accounting'; end if;
  if not exists(select 1 from public.accounting_accounts where system_key='customer_credits') then raise exception 'Missing customer credit account'; end if;
  if not exists(select 1 from public.accounting_accounts where system_key='supplier_credits') then raise exception 'Missing supplier credit account'; end if;
end $$;
select 'FLEXI ERP V4 FINANCIAL INTEGRITY VERIFICATION PASSED' as status;
