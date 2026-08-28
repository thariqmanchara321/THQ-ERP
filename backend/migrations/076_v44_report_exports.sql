-- FLEXI ERP V4.4
-- Export-safe report datasets for PDF / XLSX / print from Client and POS.
begin;

create table if not exists public.report_export_events(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  report_key text not null,
  format text not null,
  from_date date,
  to_date date,
  location_id uuid references public.business_locations(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.report_export_events enable row level security;
revoke all on public.report_export_events from anon,authenticated;

create or replace function public.reports_export_dataset_v44(
  p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_summary jsonb;v_sales jsonb;v_purchases jsonb;v_expenses jsonb;v_top_products jsonb;v_top_customers jsonb;v_gst jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Invalid report date range';end if;
  if p_location_id is not null and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'locations.view_all')
     and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'view') then raise exception 'Location access denied';end if;

  select public.reports_get_summary_v32(p_tenant_id,p_from,p_to,p_location_id) into v_summary;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_sales from public.sales_list_v32(p_tenant_id,p_location_id) x where x.sale_date between p_from and p_to;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_purchases from public.purchases_list_v32(p_tenant_id,p_location_id) x where x.purchase_date between p_from and p_to;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_expenses from public.expenses_list_v32(p_tenant_id,p_location_id,p_from,p_to) x;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_top_products from public.analytics_top_products_v4(p_tenant_id,p_from,p_to,p_location_id,100) x;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_top_customers from public.analytics_top_customers_v4(p_tenant_id,p_from,p_to,p_location_id,100) x;
  select public.gst_summary_v4(p_tenant_id,p_from,p_to,p_location_id) into v_gst;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,'from',p_from,'to',p_to,'location_id',p_location_id,
    'summary',coalesce(v_summary,'{}'::jsonb),'sales',v_sales,'purchases',v_purchases,
    'expenses',v_expenses,'top_products',v_top_products,'top_customers',v_top_customers,
    'gst',coalesce(v_gst,'{}'::jsonb)
  );
end $$;
grant execute on function public.reports_export_dataset_v44(uuid,date,date,uuid) to authenticated;

create or replace function public.report_export_log_v44(
  p_tenant_id uuid,p_report_key text,p_format text,p_from date,p_to date,p_location_id uuid,p_device_id uuid default null
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if lower(coalesce(p_format,'')) not in('pdf','xlsx','print','csv') then raise exception 'Invalid export format';end if;
  insert into public.report_export_events(tenant_id,report_key,format,from_date,to_date,location_id,device_id,created_by)
  values(p_tenant_id,coalesce(nullif(trim(p_report_key),''),'summary'),lower(p_format),p_from,p_to,p_location_id,p_device_id,auth.uid()) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.report_export_log_v44(uuid,text,text,date,date,uuid,uuid) to authenticated;

commit;
select 'Flexi ERP V4.4 report exports ready' as status;
