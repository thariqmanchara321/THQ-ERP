-- THQ V4.5 comprehensive final verifier.
do $$ begin
  if to_regclass('public.app_menu_nodes_v45') is null then raise exception 'Missing dynamic menu builder'; end if;
  if to_regclass('public.tenant_invoice_template_assignments_v45') is null then raise exception 'Missing store/terminal invoice assignments'; end if;
  if to_regprocedure('public.app_menu_tree_v45(uuid,text)') is null then raise exception 'Missing runtime menu tree'; end if;
  if to_regprocedure('public.platform_menu_node_save_v45(uuid,uuid,text,text,text,text,uuid,text,text,integer,boolean,boolean,jsonb)') is null then raise exception 'Missing menu editor'; end if;
  if to_regprocedure('public.pos_terminal_day_v45(uuid,uuid,date)') is null then raise exception 'Missing V4.5 Terminal Daily'; end if;
  if to_regprocedure('public.returns_register_v45(uuid,date,date,uuid,text,text)') is null then raise exception 'Missing return register'; end if;
  if to_regprocedure('public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing Excel product import endpoint'; end if;
  if to_regprocedure('public.tenant_invoice_template_assign_v45(uuid,text,uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing invoice assignment'; end if;
  if to_regprocedure('public.tenant_invoice_template_get_v45(uuid,text,uuid,uuid)') is null then raise exception 'Missing location/terminal invoice resolver'; end if;
  if to_regprocedure('public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing audited transaction correction'; end if;
  if to_regprocedure('public.platform_payment_correct_v45(uuid,text,uuid,text,text,text)') is null then raise exception 'Missing payment correction'; end if;
  if not exists(select 1 from public.modules where key='returns' and is_active) then raise exception 'Returns module is not active'; end if;
  if not exists(select 1 from public.ui_design_templates where key='client_thq_clean' and is_active) then raise exception 'Missing THQ Clean client theme'; end if;
  if not exists(select 1 from public.ui_design_templates where key='pos_thq_cashier' and is_active) then raise exception 'Missing THQ Cashier POS theme'; end if;
end $$;
select 'THQ V4.5 COMPLETE verification passed' as status;
