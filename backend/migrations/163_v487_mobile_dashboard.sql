-- THQ ERP V4.8.7 — mobile business dashboard.
begin;
create or replace function public.mobile_client_dashboard_v487(
  p_tenant_id uuid,p_device_id uuid,p_day date default current_date,p_location_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_bound uuid;v_location uuid;v_base jsonb;v_attention jsonb;v_approvals bigint:=0;v_pr bigint:=0;v_po bigint:=0;v_recv numeric:=0;v_pay numeric:=0;v_store record;
begin
  v_bound:=private.v487_client_mobile_location(p_tenant_id,p_device_id);
  v_location:=coalesce(p_location_id,case when private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') then null else v_bound end);
  if v_location is not null and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'view') then raise exception 'Location access denied';end if;
  if v_location is null then
    v_base:=public.mobile_business_summary_v480(p_tenant_id,coalesce(p_day,current_date));
  else
    select * into v_store from public.mobile_store_status_v480(p_tenant_id,coalesce(p_day,current_date)) x where x.location_id=v_location;
    v_base:=jsonb_build_object('day',coalesce(p_day,current_date),'sales',coalesce(v_store.sales_total,0),'returns',coalesce(v_store.returns_total,0),'net_sales',coalesce(v_store.net_sales,0),'gross_profit',coalesce(v_store.gross_profit,0),'invoice_count',coalesce(v_store.invoice_count,0),'stores',case when v_store.location_id is null then '[]'::jsonb else jsonb_build_array(to_jsonb(v_store)) end);
  end if;
  v_attention:=public.business_attention_summary_v480(p_tenant_id,v_location,30);
  select count(*) into v_approvals from public.approval_requests a where a.tenant_id=p_tenant_id and a.status='pending';
  select count(*) into v_pr from public.purchase_requests_v484 r where r.tenant_id=p_tenant_id and r.status='submitted' and (v_location is null or r.location_id=v_location) and private.erp_document_scope_allowed(p_tenant_id,r.location_id,v_location,'view');
  select count(*) into v_po from public.purchase_orders_v480 o where o.tenant_id=p_tenant_id and o.status='submitted' and (v_location is null or o.location_id=v_location) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,v_location,'view');
  select coalesce(sum(x.total_outstanding),0) into v_recv from public.customer_credit_intelligence_v480(p_tenant_id,v_location,'',5000) x;
  select coalesce(sum(x.total_outstanding),0) into v_pay from public.mobile_supplier_outstanding_v487(p_tenant_id,p_device_id,v_location,'',5000) x;
  return v_base||jsonb_build_object(
    'attention',v_attention,'location_id',v_location,'customer_outstanding',round(v_recv,2),'supplier_outstanding',round(v_pay,2),
    'pending_approvals',v_approvals+v_pr+v_po,'generic_approvals',v_approvals,'purchase_request_approvals',v_pr,'purchase_order_approvals',v_po
  );
end$$;
grant execute on function public.mobile_client_dashboard_v487(uuid,uuid,date,uuid) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(163,'4.8.7','Client Mobile','Mobile business dashboard with sales, store performance, attention, outstanding and approval KPIs.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.7 migration 163 mobile dashboard applied' as status;
