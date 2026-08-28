-- FLEXI ERP V3.1 - Tracking lookup, tenant audit viewer, per-location/merged summaries.

create or replace function public.business_locations_list(p_tenant_id uuid)
returns setof public.business_locations language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query select * from public.business_locations where tenant_id=p_tenant_id and active order by name;
end $$;
grant execute on function public.business_locations_list(uuid) to authenticated;

create or replace function public.entity_tracking_lookup(p_tenant_id uuid,p_tracking_code text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare x record;v_result jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if trim(coalesce(p_tracking_code,''))='' then return null;end if;
  for x in select * from (values
    ('products'),('product_variants'),('inventory_locations'),('customers'),('suppliers'),('purchases'),('sales'),('expenses'),
    ('business_locations'),('business_devices'),('production_recipes'),('production_runs'),('service_vehicles'),('service_jobs'),('restaurant_tables'),('restaurant_orders'),('restaurant_kots')
  ) v(table_name)
  loop
    if to_regclass('public.'||x.table_name) is null then continue;end if;
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=x.table_name and column_name='tracking_code') then continue;end if;
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=x.table_name and column_name='tenant_id') then continue;end if;
    execute format('select jsonb_build_object(''entity_type'',%L,''id'',id,''tracking_code'',tracking_code) from public.%I where tenant_id=$1 and upper(tracking_code)=upper($2) limit 1',x.table_name,x.table_name)
    into v_result using p_tenant_id,p_tracking_code;
    if v_result is not null then return v_result;end if;
  end loop;
  return null;
end $$;
grant execute on function public.entity_tracking_lookup(uuid,text) to authenticated;

create or replace function public.business_audit_log_list(p_tenant_id uuid,p_limit integer default 300)
returns setof public.business_audit_log language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'logs.view') then raise exception 'Permission denied';end if;
  return query select * from public.business_audit_log where tenant_id=p_tenant_id order by created_at desc limit greatest(1,least(coalesce(p_limit,300),2000));
end $$;
grant execute on function public.business_audit_log_list(uuid,integer) to authenticated;

create or replace function public.location_business_summary(
  p_tenant_id uuid,p_location_id uuid default null,p_from_date date default (current_date-interval '29 days')::date,p_to_date date default current_date
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_sales numeric:=0;v_purchases numeric:=0;v_expenses numeric:=0;v_count bigint:=0;v_locations jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(sum(s.grand_total),0),count(*) into v_sales,v_count
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and (p_location_id is null or o.location_id=p_location_id);
  select coalesce(sum(p.grand_total),0) into v_purchases from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  where p.tenant_id=p_tenant_id and p.purchase_date between p_from_date and p_to_date and coalesce(p.status,'') not in ('cancelled','void') and (p_location_id is null or o.location_id=p_location_id);
  select coalesce(sum(e.amount+coalesce(e.tax_amount,0)),0) into v_expenses from public.expenses e left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id
  where e.tenant_id=p_tenant_id and e.expense_date between p_from_date and p_to_date and coalesce(e.status,'posted') not in ('cancelled','void') and (p_location_id is null or o.location_id=p_location_id);
  select coalesce(jsonb_agg(jsonb_build_object('location_id',l.id,'location_code',l.location_code,'name',l.name,'tracking_code',l.tracking_code,'sales',coalesce(x.sales,0),'invoice_count',coalesce(x.invoice_count,0)) order by l.name),'[]'::jsonb)
  into v_locations from public.business_locations l left join (
    select o.location_id,sum(s.grand_total)::numeric sales,count(*)::bigint invoice_count from public.sales s join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') group by o.location_id
  ) x on x.location_id=l.id where l.tenant_id=p_tenant_id and l.active;
  return jsonb_build_object('sales',v_sales,'purchases',v_purchases,'expenses',v_expenses,'invoice_count',v_count,'locations',v_locations,'mode',case when p_location_id is null then 'merged' else 'location' end);
end $$;
grant execute on function public.location_business_summary(uuid,uuid,date,date) to authenticated;

create or replace function public.document_origin_get(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select jsonb_build_object(
    'location_id',o.location_id,'location_name',l.name,'location_code',l.location_code,'location_tracking_code',l.tracking_code,
    'local_number',n.local_number,'gstin',l.gstin,'phone',l.phone,'email',l.email,
    'address_line1',l.address_line1,'address_line2',l.address_line2,'city',l.city,'state',l.state,'postal_code',l.postal_code,'country',l.country,
    'device_id',o.device_id,'device_code',d.device_code,'device_name',d.name,'created_at',o.created_at
  )
  into v from public.document_origins o
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers n on n.entity_type=o.entity_type and n.entity_id=o.entity_id
  where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id;
  return v;
end $$;
grant execute on function public.document_origin_get(uuid,text,uuid) to authenticated;

select 'V3.1 tracking/location reports ready' as status;

-- Attach origin after an existing protected transaction RPC returns its document number.
create or replace function public.document_origin_attach_by_reference(
  p_tenant_id uuid,p_entity_type text,p_reference text,p_location_id uuid,p_device_id uuid default null
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if p_entity_type='sale' then select id into v_id from public.sales where tenant_id=p_tenant_id and sale_number=p_reference;
  elsif p_entity_type='purchase' then select id into v_id from public.purchases where tenant_id=p_tenant_id and purchase_number=p_reference;
  elsif p_entity_type='expense' then select id into v_id from public.expenses where tenant_id=p_tenant_id and expense_number=p_reference;
  else raise exception 'Unsupported entity type'; end if;
  if v_id is null then raise exception 'Document not found'; end if;
  perform public.document_origin_attach(p_tenant_id,p_entity_type,v_id,p_location_id,p_device_id);
  return v_id;
end $$;
grant execute on function public.document_origin_attach_by_reference(uuid,text,text,uuid,uuid) to authenticated;
