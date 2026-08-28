-- THQ V4.5 definitive final verifier after all V4.5 migrations.
do $$
begin
  if to_regclass('public.app_menu_nodes_v45') is null then raise exception 'Missing dynamic menu builder'; end if;
  if to_regprocedure('public.app_menu_tree_v45(uuid,text)') is null then raise exception 'Missing runtime menu tree'; end if;
  if to_regprocedure('public.platform_menu_node_save_v45(uuid,uuid,text,text,text,text,uuid,text,text,integer,boolean,boolean,jsonb)') is null then raise exception 'Missing menu editor'; end if;

  if to_regprocedure('public.pos_terminal_day_v45(uuid,uuid,date)') is null then raise exception 'Missing V4.5 Terminal Daily'; end if;
  if to_regprocedure('public.returns_register_v45(uuid,date,date,uuid,text,text)') is null then raise exception 'Missing returns register'; end if;
  if to_regprocedure('public.return_documents_search_v45(uuid,uuid,text,text,integer)') is null then raise exception 'Missing POS return document search'; end if;

  if to_regprocedure('public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing Excel product import'; end if;
  if to_regclass('public.product_invoice_attributes_v45') is null then raise exception 'Missing product invoice attributes'; end if;

  if to_regprocedure('public.tenant_invoice_templates_list_v45(uuid,text)') is null then raise exception 'Missing invoice template list'; end if;
  if to_regprocedure('public.tenant_invoice_template_clone_v45(uuid,uuid,text,text,jsonb)') is null then raise exception 'Missing invoice template clone'; end if;
  if to_regprocedure('public.tenant_invoice_template_update_v45(uuid,uuid,text,jsonb,boolean)') is null then raise exception 'Missing invoice template update'; end if;
  if to_regprocedure('public.tenant_invoice_template_assign_v45(uuid,text,uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing invoice store/terminal assignment'; end if;
  if to_regprocedure('public.tenant_invoice_template_get_v45(uuid,text,uuid,uuid)') is null then raise exception 'Missing invoice template resolver'; end if;

  if to_regprocedure('public.platform_transactions_list_v45(uuid,date,date,text,integer)') is null then raise exception 'Missing V4.5 Admin transaction list'; end if;
  if to_regprocedure('public.platform_transaction_detail_v45(uuid,text,uuid)') is null then raise exception 'Missing Admin transaction detail'; end if;
  if to_regprocedure('public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing Admin sale/purchase/expense correction'; end if;
  if to_regprocedure('public.platform_return_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing Admin return correction'; end if;
  if to_regprocedure('public.platform_payment_correct_v45(uuid,text,uuid,text,text,text)') is null then raise exception 'Missing Admin payment correction'; end if;

  if not exists(select 1 from public.modules where key='returns' and is_active) then raise exception 'Returns module inactive'; end if;
  if not exists(select 1 from public.ui_design_templates where key='client_thq_clean' and is_active) then raise exception 'Missing THQ Clean client theme'; end if;
  if not exists(select 1 from public.ui_design_templates where key='pos_thq_cashier' and is_active) then raise exception 'Missing THQ Cashier POS theme'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='client' and platform='web') then raise exception 'V4.5 Client/Web release missing'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='pos' and platform='windows') then raise exception 'V4.5 POS/Windows release missing'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='admin' and platform='web') then raise exception 'V4.5 Admin/Web release missing'; end if;
end $$;
select 'THQ V4.5 COMPLETE verification passed' as status;
