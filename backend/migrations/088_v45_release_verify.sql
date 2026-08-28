-- THQ V4.5 release registration and verification.
begin;
insert into public.app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes,download_url)
select x.app_key,x.platform,'4.5.0',1,'released',false,false,'THQ V4.5 compact POS, returns, dynamic menus, Excel import, invoice designer and admin corrections',''
from (values('client','windows'),('client','android'),('client','web'),('pos','windows'),('pos','android'),('admin','web')) x(app_key,platform)
where to_regclass('public.app_releases') is not null
on conflict do nothing;
commit;

do $$ begin
  if to_regclass('public.app_menu_nodes_v45') is null then raise exception 'Missing V4.5 menu table';end if;
  if to_regprocedure('public.app_menu_tree_v45(uuid,text)') is null then raise exception 'Missing app_menu_tree_v45';end if;
  if to_regprocedure('public.platform_menu_node_save_v45(uuid,uuid,text,text,text,text,uuid,text,text,integer,boolean,boolean,jsonb)') is null then raise exception 'Missing platform menu editor';end if;
  if to_regprocedure('public.pos_terminal_day_v45(uuid,uuid,date)') is null then raise exception 'Missing V4.5 Terminal Daily';end if;
  if to_regprocedure('public.transaction_return_status_v45(uuid,text,uuid)') is null then raise exception 'Missing return status';end if;
  if to_regprocedure('public.returns_register_v45(uuid,date,date,uuid,text,text)') is null then raise exception 'Missing returns register';end if;
  if to_regprocedure('public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb)') is null then raise exception 'Missing Excel/bulk import RPC';end if;
  if to_regprocedure('public.tenant_invoice_template_save_v45(uuid,text,uuid,jsonb)') is null then raise exception 'Missing V4.5 invoice designer RPC';end if;
  if to_regprocedure('public.platform_transaction_detail_v45(uuid,text,uuid)') is null then raise exception 'Missing transaction detail RPC';end if;
  if to_regprocedure('public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text)') is null then raise exception 'Missing transaction correction RPC';end if;
end $$;
select 'THQ V4.5 verification passed' as status;
