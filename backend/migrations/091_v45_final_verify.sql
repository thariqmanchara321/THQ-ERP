-- THQ V4.5 final verifier.
do $$ begin
  if to_regclass('public.app_menu_nodes_v45') is null then raise exception 'Missing dynamic navigation';end if;
  if to_regprocedure('public.app_menu_tree_v45(uuid,text)') is null then raise exception 'Missing client/POS menu tree';end if;
  if to_regprocedure('public.pos_terminal_day_v45(uuid,uuid,date)') is null then raise exception 'Missing return-aware Terminal Daily';end if;
  if to_regprocedure('public.returns_register_v45(uuid,date,date,uuid,text,text)') is null then raise exception 'Missing return register';end if;
  if to_regprocedure('public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing store-aware bulk import';end if;
  if to_regprocedure('public.tenant_invoice_templates_list_v45(uuid,text)') is null then raise exception 'Missing tenant invoice list V4.5';end if;
  if to_regprocedure('public.tenant_invoice_template_clone_v45(uuid,uuid,text,text,jsonb)') is null then raise exception 'Missing invoice duplicate/create';end if;
  if to_regprocedure('public.tenant_invoice_template_get_v45(uuid,text,uuid,uuid)') is null then raise exception 'Missing location-aware invoice template resolver';end if;
  if to_regprocedure('public.platform_transaction_detail_v45(uuid,text,uuid)') is null then raise exception 'Missing admin transaction detail';end if;
  if to_regprocedure('public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing admin transaction correction';end if;
  if to_regprocedure('public.platform_payment_correct_v45(uuid,text,uuid,text,text,text)') is null then raise exception 'Missing admin payment correction';end if;
  if to_regprocedure('public.platform_parties_list_v45(uuid,text,text)') is null then raise exception 'Missing admin party selector';end if;
end $$;
select 'THQ V4.5 final verification passed' as status;
