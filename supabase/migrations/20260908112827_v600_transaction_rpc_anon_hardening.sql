-- THQ ERP v6.0
-- Remove anonymous execution from transaction and pricing writer RPCs.

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'customer_pricing_profile_set_v482',
        'customer_receive_payment_v471',
        'expenses_create_v489',
        'gst_pos_sale_create_v522',
        'gst_purchase_create_v520',
        'gst_purchase_invoice_create_v520',
        'gst_purchase_return_create_v520',
        'gst_sale_create_v522',
        'gst_sales_return_create_v520',
        'pricing_list_save_v482',
        'pricing_rule_save_v482',
        'purchase_invoice_create_v489',
        'purchase_invoice_post_v484',
        'purchases_create_v489',
        'sales_create_v489',
        'supplier_payment_create_v484'
      )
  loop
    execute format('revoke execute on function %s from public, anon',r.fn);
    execute format('grant execute on function %s to authenticated, service_role',r.fn);
  end loop;
end
$$;
