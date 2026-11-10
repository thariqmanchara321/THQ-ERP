do $ddl$
declare r record;
begin
  for r in
    select p.oid::regprocedure sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'sales_create_v489','purchases_create_v489','expenses_create_v489',
      'gst_sale_create_v522','gst_pos_sale_create_v522','gst_purchase_create_v520',
      'gst_purchase_invoice_create_v520','gst_sales_return_create_v520','gst_purchase_return_create_v520',
      'purchase_invoice_create_v489','purchase_invoice_post_v484','supplier_payment_create_v484','customer_receive_payment_v471',
      'pricing_list_save_v482','pricing_rule_save_v482','customer_pricing_profile_set_v482'
    )
  loop
    execute format('revoke all on function %s from public, anon',r.sig);
    execute format('grant execute on function %s to authenticated, service_role',r.sig);
  end loop;
end
$ddl$;;
