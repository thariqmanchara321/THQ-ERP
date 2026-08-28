-- THQ ERP V4.8.0
-- Release hardening and final contract.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.8.0',
    'release','Operational Intelligence & Connectivity',
    'api_version','v1'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v480_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_missing text[]:='{}'::text[];begin
  if to_regclass('public.thq_sync_state_v480') is null then v_missing:=array_append(v_missing,'thq_sync_state_v480');end if;
  if to_regclass('public.purchase_orders_v480') is null then v_missing:=array_append(v_missing,'purchase_orders_v480');end if;
  if to_regprocedure('public.thq_sync_versions_v480(uuid)') is null then v_missing:=array_append(v_missing,'thq_sync_versions_v480');end if;
  if to_regprocedure('public.inventory_intelligence_v480(uuid,uuid,integer,text,integer)') is null then v_missing:=array_append(v_missing,'inventory_intelligence_v480');end if;
  if to_regprocedure('public.customer_credit_intelligence_v480(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'customer_credit_intelligence_v480');end if;
  if to_regprocedure('public.supplier_payables_intelligence_v480(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'supplier_payables_intelligence_v480');end if;
  if to_regprocedure('public.purchase_reorder_suggestions_v480(uuid,uuid,integer,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_reorder_suggestions_v480');end if;
  if to_regprocedure('public.purchase_order_create_v480(uuid,uuid,uuid,jsonb,date,text)') is null then v_missing:=array_append(v_missing,'purchase_order_create_v480');end if;
  if to_regprocedure('public.mobile_business_summary_v480(uuid,date)') is null then v_missing:=array_append(v_missing,'mobile_business_summary_v480');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.0','migration_no',124,'api_version','v1');
end $$;
grant execute on function public.thq_v480_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(124,'4.8.0','Operational Intelligence & Connectivity','Final V4.8.0 release contract: THQ API v1, synchronization, operational intelligence, purchase planning and mobile-ready read contracts.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 124 release contract applied' as status;
