-- THQ ERP V4.8.4 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.4','release','Purchasing V2','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v484_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.purchase_requests_v484') is null then v_missing:=array_append(v_missing,'purchase_requests_v484');end if;
 if to_regclass('public.purchase_request_items_v484') is null then v_missing:=array_append(v_missing,'purchase_request_items_v484');end if;
 if to_regclass('public.goods_receipts_v484') is null then v_missing:=array_append(v_missing,'goods_receipts_v484');end if;
 if to_regclass('public.goods_receipt_items_v484') is null then v_missing:=array_append(v_missing,'goods_receipt_items_v484');end if;
 if to_regclass('public.purchase_invoices_v484') is null then v_missing:=array_append(v_missing,'purchase_invoices_v484');end if;
 if to_regclass('public.purchase_invoice_items_v484') is null then v_missing:=array_append(v_missing,'purchase_invoice_items_v484');end if;
 if to_regclass('public.supplier_payments_v484') is null then v_missing:=array_append(v_missing,'supplier_payments_v484');end if;
 if to_regclass('public.supplier_ledger_entries_v484') is null then v_missing:=array_append(v_missing,'supplier_ledger_entries_v484');end if;
 if to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_create_v484');end if;
 if to_regprocedure('public.purchase_request_status_v484(uuid,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_status_v484');end if;
 if to_regprocedure('public.purchase_order_create_v484(uuid,uuid,uuid,jsonb,date,text,uuid)') is null then v_missing:=array_append(v_missing,'purchase_order_create_v484');end if;
 if to_regprocedure('public.purchase_order_decide_v484(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'purchase_order_decide_v484');end if;
 if to_regprocedure('public.goods_receipt_create_v484(uuid,uuid,date,jsonb,text,text)') is null then v_missing:=array_append(v_missing,'goods_receipt_create_v484');end if;
 if to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'goods_receipt_post_v484');end if;
 if to_regprocedure('public.purchase_invoice_create_v484(uuid,uuid,text,date,date,jsonb,numeric,text)') is null then v_missing:=array_append(v_missing,'purchase_invoice_create_v484');end if;
 if to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is null then v_missing:=array_append(v_missing,'purchase_invoice_post_v484');end if;
 if to_regprocedure('public.supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text)') is null then v_missing:=array_append(v_missing,'supplier_payment_create_v484');end if;
 if to_regprocedure('public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid)') is null then v_missing:=array_append(v_missing,'suppliers_get_statement_v484');end if;
 if to_regprocedure('public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_price_history_v484');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.4','migration_no',146,'api_version','v1','purchase_request',true,'purchase_order_approval',true,'grn',true,'partial_receiving',true,'damaged_rejected_receiving',true,'purchase_invoice',true,'supplier_payment',true,'supplier_ledger',true,'purchase_price_history',true);
end$$;
grant execute on function public.thq_v484_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(146,'4.8.4','Purchasing V2','Purchase Request, Purchase Order approval, GRN/partial/damaged/rejected receiving, Purchase Invoice, Supplier Payment/Ledger and Purchase Price History.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 146 release contract applied' as status;
