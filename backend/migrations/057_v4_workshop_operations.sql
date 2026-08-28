-- FLEXI ERP V4 operational Workshop/Garage APIs.
begin;

do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description) values
      ('workshop.view','View Workshop','workshop','View vehicles and workshop job cards'),
      ('workshop.manage','Manage Workshop','workshop','Create/update vehicles and workshop job cards')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
      ('workshop.view','View Workshop','workshop'),
      ('workshop.manage','Manage Workshop','workshop')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r join public.permissions p on p.key in('workshop.view','workshop.manage')
where r.key='owner' and exists(select 1 from public.tenant_modules tm where tm.tenant_id=r.tenant_id and tm.enabled and tm.module_key='workshop')
on conflict do nothing;
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r join public.permissions p on p.key in('workshop.view','workshop.manage')
where r.key='manager' and exists(select 1 from public.tenant_modules tm where tm.tenant_id=r.tenant_id and tm.enabled and tm.module_key='workshop')
on conflict do nothing;

create or replace function public.workshop_vehicles_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_query text default null)
returns table(id uuid,vehicle_number text,make text,model text,year integer,vin text,chassis_number text,odometer numeric,notes text,active boolean,customer_id uuid,customer_name text,location_id uuid,location_code text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'workshop.view') and not private.erp_has_permission(p_tenant_id,'workshop.manage') then raise exception 'Workshop permission required';end if;
  return query select v.id,v.vehicle_number,v.make,v.model,v.year,v.vin,v.chassis_number,v.odometer,v.notes,v.active,v.customer_id,coalesce(c.name,''),v.location_id,coalesce(l.location_code,'')
  from public.workshop_vehicles v left join public.customers c on c.id=v.customer_id left join public.business_locations l on l.id=v.location_id
  where v.tenant_id=p_tenant_id and (p_location_id is null or v.location_id=p_location_id)
    and (v.location_id is null or private.erp_document_scope_allowed(p_tenant_id,v.location_id,p_location_id,'view'))
    and (trim(coalesce(p_query,''))='' or lower(v.vehicle_number) like q or lower(coalesce(v.make,'')) like q or lower(coalesce(v.model,'')) like q or lower(coalesce(v.vin,'')) like q or lower(coalesce(c.name,'')) like q)
  order by v.active desc,v.vehicle_number;
end $$;
grant execute on function public.workshop_vehicles_list_v4(uuid,uuid,text) to authenticated;

create or replace function public.workshop_vehicle_save_v4(p_tenant_id uuid,p_id uuid,p_location_id uuid,p_customer_id uuid,p_vehicle_number text,p_make text,p_model text,p_year integer,p_vin text,p_chassis text,p_odometer numeric,p_notes text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'workshop.manage') then raise exception 'Workshop manage permission required';end if;
  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if trim(coalesce(p_vehicle_number,''))='' then raise exception 'Vehicle number required';end if;
  if p_id is null then
    insert into public.workshop_vehicles(tenant_id,customer_id,location_id,vehicle_number,make,model,year,vin,chassis_number,odometer,notes,active)
    values(p_tenant_id,p_customer_id,p_location_id,upper(trim(p_vehicle_number)),nullif(trim(coalesce(p_make,'')),''),nullif(trim(coalesce(p_model,'')),''),p_year,nullif(trim(coalesce(p_vin,'')),''),nullif(trim(coalesce(p_chassis,'')),''),p_odometer,nullif(trim(coalesce(p_notes,'')),''),coalesce(p_active,true)) returning id into v_id;
  else
    update public.workshop_vehicles set customer_id=p_customer_id,location_id=p_location_id,vehicle_number=upper(trim(p_vehicle_number)),make=nullif(trim(coalesce(p_make,'')),''),model=nullif(trim(coalesce(p_model,'')),''),year=p_year,vin=nullif(trim(coalesce(p_vin,'')),''),chassis_number=nullif(trim(coalesce(p_chassis,'')),''),odometer=p_odometer,notes=nullif(trim(coalesce(p_notes,'')),''),active=coalesce(p_active,true)
    where id=p_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Vehicle not found';end if;return v_id;
end $$;
grant execute on function public.workshop_vehicle_save_v4(uuid,uuid,uuid,uuid,text,text,text,integer,text,text,numeric,text,boolean) to authenticated;

create or replace function public.workshop_jobs_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default null)
returns table(id uuid,job_number text,status text,vehicle_id uuid,vehicle_number text,customer_id uuid,customer_name text,complaint text,estimated_amount numeric,estimated_delivery timestamptz,technician_user_id uuid,technician_username text,location_id uuid,location_code text,created_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'workshop.view') and not private.erp_has_permission(p_tenant_id,'workshop.manage') then raise exception 'Workshop permission required';end if;
  return query select j.id,j.job_number,j.status,j.vehicle_id,v.vehicle_number,j.customer_id,coalesce(c.name,''),j.complaint,j.estimated_amount,j.estimated_delivery,j.technician_user_id,coalesce(u.username,''),j.location_id,coalesce(l.location_code,''),j.created_at
  from public.workshop_job_cards j join public.workshop_vehicles v on v.id=j.vehicle_id left join public.customers c on c.id=j.customer_id left join public.user_login_names u on u.user_id=j.technician_user_id left join public.business_locations l on l.id=j.location_id
  where j.tenant_id=p_tenant_id and (p_location_id is null or j.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    and (p_status is null or p_status='' or j.status=p_status)
    and (trim(coalesce(p_query,''))='' or lower(j.job_number) like q or lower(v.vehicle_number) like q or lower(coalesce(c.name,'')) like q or lower(coalesce(j.complaint,'')) like q)
  order by case j.status when 'ready' then 1 when 'in_progress' then 2 when 'waiting_parts' then 3 when 'open' then 4 else 5 end,j.created_at desc;
end $$;
grant execute on function public.workshop_jobs_list_v4(uuid,uuid,text,text) to authenticated;

create or replace function public.workshop_job_status_v4(p_tenant_id uuid,p_job_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'workshop.manage') then raise exception 'Workshop manage permission required';end if;
  if p_status not in('open','inspection','estimate','approved','in_progress','waiting_parts','ready','delivered','cancelled') then raise exception 'Invalid job status';end if;
  select location_id into v_loc from public.workshop_job_cards where id=p_job_id and tenant_id=p_tenant_id;if v_loc is null then raise exception 'Job not found';end if;perform private.v4_location_access(p_tenant_id,v_loc,'operate');
  update public.workshop_job_cards set status=p_status,inspection_notes=case when trim(coalesce(p_note,''))='' then inspection_notes else concat_ws(E'\n',inspection_notes,trim(p_note)) end,updated_at=now() where id=p_job_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.workshop_job_status_v4(uuid,uuid,text,text) to authenticated;

commit;
select 'Flexi ERP V4 Workshop operations ready' as status;
