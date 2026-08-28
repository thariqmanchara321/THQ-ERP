-- THQ V4.5 final verification. Read-only checks after migrations 083-096.
do $$
begin
  -- Dynamic Client/POS navigation and nesting.
  if to_regclass('public.app_menu_nodes_v45') is null then raise exception 'Missing app_menu_nodes_v45'; end if;
  if to_regprocedure('public.app_menu_tree_v45(uuid,text)') is null then raise exception 'Missing app_menu_tree_v45'; end if;
  if to_regprocedure('public.platform_menu_nodes_v45_list(uuid,text)') is null then raise exception 'Missing platform_menu_nodes_v45_list'; end if;
  if to_regprocedure('public.platform_menu_copy_default_v45(uuid,text)') is null then raise exception 'Missing platform_menu_copy_default_v45'; end if;
  if to_regprocedure('public.platform_menu_node_save_v45(uuid,uuid,text,text,text,text,uuid,text,text,integer,boolean,boolean,jsonb)') is null then raise exception 'Missing platform_menu_node_save_v45'; end if;
  if to_regprocedure('public.platform_menu_node_delete_v45(uuid)') is null then raise exception 'Missing platform_menu_node_delete_v45'; end if;

  -- Return-aware terminal/reporting workflows.
  if to_regprocedure('public.transaction_return_status_v45(uuid,text,uuid)') is null then raise exception 'Missing transaction_return_status_v45'; end if;
  if to_regprocedure('public.pos_terminal_day_v45(uuid,uuid,date)') is null then raise exception 'Missing pos_terminal_day_v45'; end if;
  if to_regprocedure('public.returns_register_v45(uuid,date,date,uuid,text,text)') is null then raise exception 'Missing returns_register_v45'; end if;
  if to_regprocedure('public.return_documents_search_v45(uuid,uuid,text,text,integer)') is null then raise exception 'Missing return_documents_search_v45'; end if;

  -- Excel inventory import and invoice attributes.
  if to_regprocedure('public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing inventory_bulk_create_products_v45'; end if;
  if to_regclass('public.product_invoice_attributes_v45') is null then raise exception 'Missing product_invoice_attributes_v45'; end if;

  -- Client invoice designer.
  if to_regprocedure('public.tenant_invoice_templates_list_v45(uuid,text)') is null then raise exception 'Missing tenant_invoice_templates_list_v45'; end if;
  if to_regprocedure('public.tenant_invoice_template_clone_v45(uuid,uuid,text,text,jsonb)') is null then raise exception 'Missing tenant_invoice_template_clone_v45'; end if;
  if to_regprocedure('public.tenant_invoice_template_update_v45(uuid,uuid,text,jsonb,boolean)') is null then raise exception 'Missing tenant_invoice_template_update_v45'; end if;
  if to_regprocedure('public.tenant_invoice_template_save_v45(uuid,text,uuid,jsonb)') is null then raise exception 'Missing tenant_invoice_template_save_v45'; end if;
  if to_regprocedure('public.tenant_invoice_template_assign_v45(uuid,text,uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing tenant_invoice_template_assign_v45'; end if;
  if to_regprocedure('public.tenant_invoice_template_get_v45(uuid,text,uuid,uuid)') is null then raise exception 'Missing tenant_invoice_template_get_v45'; end if;
  if to_regclass('public.tenant_invoice_template_assignments_v45') is null then raise exception 'Missing tenant_invoice_template_assignments_v45'; end if;

  -- Super Admin correction centre.
  if to_regprocedure('public.platform_transaction_detail_v45(uuid,text,uuid)') is null then raise exception 'Missing platform_transaction_detail_v45'; end if;
  if to_regprocedure('public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing platform_transaction_correct_v45'; end if;
  if to_regprocedure('public.platform_parties_list_v45(uuid,text,text)') is null then raise exception 'Missing platform_parties_list_v45'; end if;
  if to_regprocedure('public.platform_payment_correct_v45(uuid,text,uuid,text,text,text)') is null then raise exception 'Missing platform_payment_correct_v45'; end if;

  -- Required modules/themes and release registration.
  if not exists(select 1 from public.modules where key='returns' and is_active) then raise exception 'Returns module is not active'; end if;
  if not exists(select 1 from public.ui_design_templates where key='client_thq_clean' and is_active) then raise exception 'Missing THQ Clean client UI preset'; end if;
  if not exists(select 1 from public.ui_design_templates where key='pos_thq_cashier' and is_active) then raise exception 'Missing THQ Cashier POS UI preset'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='client' and platform='web') then raise exception 'THQ V4.5 client/web release not registered'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='pos' and platform='windows') then raise exception 'THQ V4.5 POS/windows release not registered'; end if;
  if not exists(select 1 from public.platform_app_releases where version='4.5.0' and build_number=1 and app_key='admin' and platform='web') then raise exception 'THQ V4.5 admin/web release not registered'; end if;
end $$;

select 'THQ V4.5 COMPLETE verification passed' as status;
