-- FLEXI ERP V4 branch-aware Dashboard/Reports using location stock as physical source of truth.
begin;

create or replace function public.dashboard_get_summary_v4(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;v_low integer:=0;v_products integer:=0;
begin
  select public.dashboard_get_summary_v32(p_tenant_id,p_location_id) into v;
  select count(*) into v_products
  from public.location_product_settings s
  join public.business_locations l on l.id=s.location_id
  where s.tenant_id=p_tenant_id and s.active and l.active
    and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view');

  select count(*) into v_low
  from public.location_product_settings s
  join public.product_variants pv on pv.id=s.variant_id
  join public.business_locations l on l.id=s.location_id
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where s.tenant_id=p_tenant_id and s.active and l.active
    and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view')
    and coalesce(s.reorder_level,pv.reorder_level,0)>0
    and coalesce(b.quantity,0)<=coalesce(s.reorder_level,pv.reorder_level,0);

  return coalesce(v,'{}'::jsonb)||jsonb_build_object('product_count',v_products,'low_stock_count',v_low);
end $$;
grant execute on function public.dashboard_get_summary_v4(uuid,uuid) to authenticated;

create or replace function public.reports_get_summary_v4(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;v_stock numeric:=0;
begin
  select public.reports_get_summary_v32(p_tenant_id,p_from_date,p_to_date,p_location_id) into v;
  select coalesce(sum(coalesce(b.quantity,0)*coalesce(nullif(b.average_cost,0),pv.cost_price,0)),0)
  into v_stock
  from public.location_product_settings s
  join public.product_variants pv on pv.id=s.variant_id
  join public.business_locations l on l.id=s.location_id
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where s.tenant_id=p_tenant_id and s.active and l.active
    and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view');
  return coalesce(v,'{}'::jsonb)||jsonb_build_object('stock_value',v_stock);
end $$;
grant execute on function public.reports_get_summary_v4(uuid,date,date,uuid) to authenticated;

commit;
select 'Flexi ERP V4 branch-aware dashboard/report summaries ready' as status;
