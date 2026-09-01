-- THQ ERP V4.8.7 — Client Mobile release contract.
begin;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.7','release','Client Mobile','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v487_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regprocedure('public.mobile_client_context_v487(uuid,uuid)') is null then v_missing:=array_append(v_missing,'mobile_client_context_v487');end if;
  if to_regprocedure('public.mobile_client_dashboard_v487(uuid,uuid,date,uuid)') is null then v_missing:=array_append(v_missing,'mobile_client_dashboard_v487');end if;
  if to_regprocedure('public.mobile_sales_status_v487(uuid,uuid,uuid,integer)') is null then v_missing:=array_append(v_missing,'mobile_sales_status_v487');end if;
  if to_regprocedure('public.mobile_purchases_status_v487(uuid,uuid,uuid,integer)') is null then v_missing:=array_append(v_missing,'mobile_purchases_status_v487');end if;
  if to_regprocedure('public.mobile_inventory_status_v487(uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'mobile_inventory_status_v487');end if;
  if to_regprocedure('public.mobile_customer_outstanding_v487(uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'mobile_customer_outstanding_v487');end if;
  if to_regprocedure('public.mobile_supplier_outstanding_v487(uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'mobile_supplier_outstanding_v487');end if;
  if to_regprocedure('public.mobile_approvals_v487(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'mobile_approvals_v487');end if;
  if to_regprocedure('public.mobile_approval_decide_v487(uuid,uuid,text,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'mobile_approval_decide_v487');end if;
  if to_regprocedure('public.mobile_customer_payment_v487(uuid,uuid,uuid,numeric,text,text,text,uuid,text)') is null then v_missing:=array_append(v_missing,'mobile_customer_payment_v487');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.7','migration_no',166,'api_version','v1','client_mobile',true);
end$$;
grant execute on function public.thq_v487_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(166,'4.8.7','Client Mobile','Business dashboard, sales/purchases/inventory status, customer/supplier outstanding, reports, approvals, customer payment and store performance on mobile.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.7 migration 166 release contract applied' as status;
