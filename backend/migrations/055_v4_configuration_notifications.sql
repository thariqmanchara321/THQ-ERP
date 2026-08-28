-- FLEXI ERP V4 custom-field management, attachment metadata APIs, printer profiles,
-- and automatically refreshed operational notifications.
begin;

create or replace function public.custom_fields_list_v4(p_tenant_id uuid,p_entity_type text default null)
returns setof public.custom_field_definitions
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select * from public.custom_field_definitions
  where tenant_id=p_tenant_id and (p_entity_type is null or p_entity_type='' or entity_type=p_entity_type)
  order by entity_type,sort_order,label;
end $$;
grant execute on function public.custom_fields_list_v4(uuid,text) to authenticated;

create or replace function public.custom_field_save_v4(
  p_tenant_id uuid,p_id uuid,p_entity_type text,p_field_key text,p_label text,p_field_type text,
  p_required boolean,p_searchable boolean,p_invoice_visible boolean,p_options jsonb,p_active boolean,p_sort_order integer
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if trim(coalesce(p_entity_type,''))='' or trim(coalesce(p_field_key,''))='' or trim(coalesce(p_label,''))='' then raise exception 'Entity, key and label are required';end if;
  if p_field_type not in('text','number','date','dropdown','checkbox','multi_select') then raise exception 'Invalid custom field type';end if;
  if p_id is null then
    insert into public.custom_field_definitions(tenant_id,entity_type,field_key,label,field_type,required,searchable,invoice_visible,options,active,sort_order)
    values(p_tenant_id,lower(trim(p_entity_type)),lower(regexp_replace(trim(p_field_key),'[^a-zA-Z0-9_]+','_','g')),trim(p_label),p_field_type,coalesce(p_required,false),coalesce(p_searchable,false),coalesce(p_invoice_visible,false),coalesce(p_options,'[]'::jsonb),coalesce(p_active,true),coalesce(p_sort_order,0)) returning id into v_id;
  else
    update public.custom_field_definitions set entity_type=lower(trim(p_entity_type)),field_key=lower(regexp_replace(trim(p_field_key),'[^a-zA-Z0-9_]+','_','g')),label=trim(p_label),field_type=p_field_type,required=coalesce(p_required,false),searchable=coalesce(p_searchable,false),invoice_visible=coalesce(p_invoice_visible,false),options=coalesce(p_options,'[]'::jsonb),active=coalesce(p_active,true),sort_order=coalesce(p_sort_order,0)
    where id=p_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Custom field not found';end if;
  return v_id;
end $$;
grant execute on function public.custom_field_save_v4(uuid,uuid,text,text,text,text,boolean,boolean,boolean,jsonb,boolean,integer) to authenticated;

create or replace function public.custom_field_values_get_v4(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(jsonb_object_agg(d.field_key,v.value),'{}'::jsonb) into v
  from public.custom_field_definitions d left join public.custom_field_values v on v.definition_id=d.id and v.entity_id=p_entity_id
  where d.tenant_id=p_tenant_id and d.entity_type=p_entity_type and d.active;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.custom_field_values_get_v4(uuid,text,uuid) to authenticated;

create or replace function public.custom_field_values_set_v4(p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_values jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare d record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for d in select * from public.custom_field_definitions where tenant_id=p_tenant_id and entity_type=p_entity_type and active loop
    if d.required and ((not (coalesce(p_values,'{}'::jsonb) ? d.field_key)) or nullif(trim(coalesce(p_values->>d.field_key,'')),'') is null) then raise exception 'Required custom field % is missing',d.label;end if;
    if coalesce(p_values,'{}'::jsonb) ? d.field_key then
      insert into public.custom_field_values(tenant_id,definition_id,entity_id,value,updated_by,updated_at)
      values(p_tenant_id,d.id,p_entity_id,p_values->d.field_key,auth.uid(),now())
      on conflict(definition_id,entity_id) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now();
    end if;
  end loop;
end $$;
grant execute on function public.custom_field_values_set_v4(uuid,text,uuid,jsonb) to authenticated;

create or replace function public.entity_attachments_list_v4(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns setof public.entity_attachments
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select * from public.entity_attachments where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id order by created_at desc;
end $$;
grant execute on function public.entity_attachments_list_v4(uuid,text,uuid) to authenticated;

create or replace function public.entity_attachment_register_v4(p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_file_name text,p_storage_path text,p_mime_type text,p_file_size bigint,p_visibility text default 'tenant')
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_visibility not in('tenant','restricted','private') then raise exception 'Invalid visibility';end if;
  insert into public.entity_attachments(tenant_id,entity_type,entity_id,file_name,storage_path,mime_type,file_size,visibility,uploaded_by)
  values(p_tenant_id,trim(p_entity_type),p_entity_id,trim(p_file_name),trim(p_storage_path),nullif(trim(coalesce(p_mime_type,'')),''),p_file_size,p_visibility,auth.uid()) returning id into v;return v;
end $$;
grant execute on function public.entity_attachment_register_v4(uuid,text,uuid,text,text,text,bigint,text) to authenticated;

create or replace function public.invoice_print_profiles_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_device_id uuid default null)
returns setof public.printer_profiles
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select * from public.printer_profiles where tenant_id=p_tenant_id and active
    and (p_location_id is null or location_id is null or location_id=p_location_id)
    and (p_device_id is null or device_id is null or device_id=p_device_id)
  order by case when device_id=p_device_id then 0 when location_id=p_location_id then 1 else 2 end,name;
end $$;
grant execute on function public.invoice_print_profiles_list_v4(uuid,uuid,uuid) to authenticated;

-- Refresh operational notification candidates. This is intentionally idempotent and only
-- inserts a new unread alert when an equivalent alert has not been created recently.
create or replace function private.v4_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare r record;begin
  -- Low stock per accessible branch.
  for r in
    select s.location_id,s.variant_id,p.name product_name,l.name location_name,coalesce(b.quantity,0) qty,coalesce(s.reorder_level,pv.reorder_level,0) reorder
    from public.location_product_settings s join public.product_variants pv on pv.id=s.variant_id join public.products p on p.id=pv.product_id join public.business_locations l on l.id=s.location_id
    left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
    where s.tenant_id=p_tenant_id and s.active and l.active and coalesce(s.reorder_level,pv.reorder_level,0)>0 and coalesce(b.quantity,0)<=coalesce(s.reorder_level,pv.reorder_level,0)
      and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,s.location_id,'view'))
    limit 100
  loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='stock' and n.entity_type='product_variant' and n.entity_id=r.variant_id and n.location_id=r.location_id and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'stock',case when r.qty<=0 then 'critical' else 'warning' end,'Low stock • '||r.product_name,r.location_name||': '||r.qty||' available (reorder '||r.reorder||')','product_variant',r.variant_id);
    end if;
  end loop;

  -- Overdue customer receivables.
  for r in
    select s.id,s.due_date,c.name,coalesce(o.location_id,null) location_id,
      greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0) balance
    from public.sales s join public.customers c on c.id=s.customer_id
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.due_date is not null and s.due_date<current_date and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      and (o.location_id is null or private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,o.location_id,'view'))
    order by s.due_date limit 100
  loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='receivable' and n.entity_type='sale' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'receivable','warning','Customer payment overdue',r.name||' • balance '||round(r.balance,2)||' • due '||r.due_date,'sale',r.id);
    end if;
  end loop;

  -- Tasks due/overdue assigned to the current user.
  for r in select id,title,due_at,location_id from public.business_tasks where tenant_id=p_tenant_id and assigned_to=p_user_id and status not in('done','cancelled') and due_at is not null and due_at<=now()+interval '24 hours' limit 100 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='task' and n.entity_type='task' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '12 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'task',case when r.due_at<now() then 'warning' else 'info' end,'Task due • '||r.title,'Due '||r.due_at,'task',r.id);
    end if;
  end loop;
end $$;
revoke all on function private.v4_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) order by created_at desc limit greatest(1,least(coalesce(p_limit,50),200));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

commit;
select 'Flexi ERP V4 custom fields, printing profiles and operational notifications ready' as status;
