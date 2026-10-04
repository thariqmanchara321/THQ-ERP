-- Separate attendance from Staff without deleting historical or financial data.
update public.modules set description='Staff profiles, wages, payroll, advances and statements' where key='staff';
update public.permissions set description='Staff profiles, balances and financial statements' where key='staff.view';
update public.permissions set description='Create and edit staff profiles' where key='staff.manage';
insert into public.modules(key,name,description,category,sort_order,is_active,is_core,is_beta)
values('attendance','Attendance','Independent attendance module planned for a later release','Operations',66,false,false,true)
on conflict(key) do nothing;

CREATE OR REPLACE FUNCTION public.staff_workspace_v630(p_tenant_id uuid, p_action text, p_data jsonb DEFAULT '{}'::jsonb, p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare t uuid:=p_tenant_id;location uuid:=p_location_id;s uuid:=nullif(p_data->>'staff_id','')::uuid;
 member public.staff_members_v630%rowtype;old jsonb;result uuid;driver uuid;start_day date;end_day date;
begin
 if p_action in('list','detail','report') then
  perform private.staff_assert_v630(t,'staff.view',location);
  start_day:=coalesce((p_data->>'from')::date,date_trunc('month',current_date)::date);
  end_day:=coalesce((p_data->>'to')::date,current_date);
  if end_day<start_day then raise exception 'End date must follow start date';end if;
  if s is not null then
   select * into member from public.staff_members_v630 where tenant_id=t and id=s;
   if not found then raise exception 'Staff member not found';end if;
   if member.location_id is not null then perform private.v4_location_access(t,member.location_id,'view');end if;
  end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object(
    'license_number',(select license_number from public.logistics_drivers_v61 d where d.tenant_id=t and d.id=x.driver_id),
    'earned',coalesce((select sum(e.amount) from public.staff_earnings_v630 e where e.tenant_id=t and e.staff_id=x.id and private.erp_document_scope_allowed(t,e.location_id,location,'view')),0),
    'paid',coalesce((select sum(p.amount) from public.staff_payments_v630 p where p.tenant_id=t and p.staff_id=x.id and private.erp_document_scope_allowed(t,p.location_id,location,'view')),0),
    'outstanding',coalesce((select sum(e.amount-private.staff_earning_paid_v630(e.id)) from public.staff_earnings_v630 e where e.tenant_id=t and e.staff_id=x.id and private.erp_document_scope_allowed(t,e.location_id,location,'view')),0),
    'advance_balance',coalesce((select sum(p.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a where a.payment_id=p.id and a.from_advance),0)) from public.staff_payments_v630 p where p.tenant_id=t and p.staff_id=x.id and private.erp_document_scope_allowed(t,p.location_id,location,'view')),0)
   ) order by x.active desc,x.name) from public.staff_members_v630 x where x.tenant_id=t and (s is null or x.id=s) and (x.location_id is null or private.erp_document_scope_allowed(t,x.location_id,location,'view'))),'[]'::jsonb),
   'load_allocations',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('load_number',l.load_number,'load_date',l.load_date)) from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id where c.tenant_id=t and c.staff_mode='salary_allocation' and c.status='posted' and (s is null or c.staff_id=s) and l.load_date between start_day and end_day and private.erp_document_scope_allowed(t,l.location_id,location,'view')),'[]'::jsonb),
   'earnings',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('staff_name',x.name,'paid_amount',private.staff_earning_paid_v630(e.id),'outstanding',e.amount-private.staff_earning_paid_v630(e.id)) order by e.earning_date desc,e.created_at desc) from public.staff_earnings_v630 e join public.staff_members_v630 x on x.id=e.staff_id and x.tenant_id=e.tenant_id where e.tenant_id=t and (s is null or e.staff_id=s) and e.earning_date between start_day and end_day and private.erp_document_scope_allowed(t,e.location_id,location,'view')),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('staff_name',x.name,'allocations',coalesce((select jsonb_agg(to_jsonb(a)) from public.staff_payment_allocations_v630 a where a.payment_id=p.id),'[]'::jsonb)) order by p.payment_date desc,p.created_at desc) from public.staff_payments_v630 p join public.staff_members_v630 x on x.id=p.staff_id and x.tenant_id=p.tenant_id where p.tenant_id=t and (s is null or p.staff_id=s) and p.payment_date between start_day and end_day and private.erp_document_scope_allowed(t,p.location_id,location,'view')),'[]'::jsonb),
   'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.workforce_audit_v630 a join public.staff_members_v630 x on x.id=a.staff_id and x.tenant_id=a.tenant_id where a.tenant_id=t and a.action not like 'attendance.%' and (s is null or a.staff_id=s) and a.created_at::date between start_day and end_day and (x.location_id is null or private.erp_document_scope_allowed(t,x.location_id,location,'view'))),'[]'::jsonb)
  );
 end if;
 if p_action='save' then
  perform private.staff_assert_v630(t,'staff.manage',location);
  if location is null then raise exception 'Select a location to save staff';end if;
  if nullif(trim(p_data->>'name'),'') is null then raise exception 'Staff name is required';end if;
  if s is not null then
   select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
   if not found then raise exception 'Staff member not found';end if;
   if member.location_id is not null then perform private.v4_location_access(t,member.location_id,'operate');end if;
   old:=to_jsonb(member)||jsonb_build_object('license_number',(select license_number from public.logistics_drivers_v61 where tenant_id=t and id=member.driver_id));driver:=member.driver_id;
   if member.location_id is distinct from location and exists(select 1 from public.staff_earnings_v630 where staff_id=s) then raise exception 'A staff member with earnings cannot move payroll location; retain their financial history';end if;
  else s:=coalesce(nullif(p_data->>'new_id','')::uuid,gen_random_uuid());if exists(select 1 from public.staff_members_v630 where id=s) then raise exception 'Staff ID already exists; refresh and edit that record';end if;end if;
  if coalesce(p_data->>'job_role','staff')='driver' then
   if driver is null then
    insert into public.logistics_drivers_v61(tenant_id,name,phone,license_number,notes,active) values(t,trim(p_data->>'name'),p_data->>'phone',p_data->>'license_number',p_data->>'notes',coalesce((p_data->>'active')::boolean,true)) returning id into driver;
   else update public.logistics_drivers_v61 set name=trim(p_data->>'name'),phone=p_data->>'phone',license_number=p_data->>'license_number',active=coalesce((p_data->>'active')::boolean,true),updated_at=now() where tenant_id=t and id=driver;end if;
  end if;
  if driver is not null and coalesce(p_data->>'job_role','staff')<>'driver' then update public.logistics_drivers_v61 set name=trim(p_data->>'name'),phone=p_data->>'phone',active=false,updated_at=now() where tenant_id=t and id=driver;end if;
  insert into public.staff_members_v630(id,tenant_id,location_id,driver_id,staff_code,name,phone,address,job_role,joined_on,left_on,wage_basis,base_rate,overtime_rate,bank_name,bank_account,bank_ifsc,emergency_contact,notes,active)
  values(s,t,location,driver,coalesce(nullif(p_data->>'staff_code',''),member.staff_code,'STF-'||upper(left(s::text,8))),trim(p_data->>'name'),p_data->>'phone',p_data->>'address',coalesce(p_data->>'job_role','staff'),coalesce((p_data->>'joined_on')::date,current_date),(p_data->>'left_on')::date,coalesce(p_data->>'wage_basis','monthly'),coalesce((p_data->>'base_rate')::numeric,0),coalesce((p_data->>'overtime_rate')::numeric,0),p_data->>'bank_name',p_data->>'bank_account',p_data->>'bank_ifsc',p_data->>'emergency_contact',p_data->>'notes',coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set location_id=excluded.location_id,driver_id=excluded.driver_id,staff_code=excluded.staff_code,name=excluded.name,phone=excluded.phone,address=excluded.address,job_role=excluded.job_role,joined_on=excluded.joined_on,left_on=excluded.left_on,wage_basis=excluded.wage_basis,base_rate=excluded.base_rate,overtime_rate=excluded.overtime_rate,bank_name=excluded.bank_name,bank_account=excluded.bank_account,bank_ifsc=excluded.bank_ifsc,emergency_contact=excluded.emergency_contact,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now();
  insert into public.workforce_audit_v630(tenant_id,staff_id,action,before_data,after_data) values(t,s,'staff.save',old,(select to_jsonb(x)||jsonb_build_object('license_number',p_data->>'license_number') from public.staff_members_v630 x where id=s));
  return jsonb_build_object('staff_id',s);
 elsif p_action='attendance' then
  perform private.staff_assert_v630(t,'staff.manage',location);
  raise exception 'Attendance is a separate module and is not available yet' using errcode='0A000';
 elsif p_action='payroll' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_earning_post_v630(t,s,location,p_data);
 elsif p_action='payment' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_payment_post_v630(t,s,location,p_data);
 else raise exception 'Unknown staff action';
 end if;
 return jsonb_build_object('id',result,'recorded',true);
end $function$;

CREATE OR REPLACE FUNCTION public.reports_export_dataset_v630(p_tenant_id uuid, p_from date, p_to date, p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare result jsonb;loads jsonb:='[]';staff jsonb:='{}';
begin
 result:=public.reports_export_dataset_v44(p_tenant_id,p_from,p_to,p_location_id);
 if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='aggregate_yard' and enabled) and (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'aggregate_yard.view')) then
  loads:=public.material_load_workspace_v630(p_tenant_id,'report',jsonb_build_object('from',p_from,'to',p_to),p_location_id)->'loads';
 end if;
 if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='staff' and enabled) and private.erp_has_permission(p_tenant_id,'staff.view') then
  staff:=public.staff_workspace_v630(p_tenant_id,'report',jsonb_build_object('from',p_from,'to',p_to),p_location_id);
 end if;
 return result||jsonb_build_object('summary',public.reports_get_summary_v630(p_tenant_id,p_from,p_to,p_location_id),
  'material_loads',loads,
  'load_costs',coalesce((select jsonb_agg(c.value||jsonb_build_object('load_number',l.value->>'load_number','load_date',l.value->>'load_date','vehicle_registration',l.value->>'vehicle_registration','driver_name',l.value->>'driver_name')) from jsonb_array_elements(loads) l(value) cross join lateral jsonb_array_elements(l.value->'costs') c(value)),'[]'::jsonb),
  'staff',coalesce(staff->'staff','[]'::jsonb),'staff_earnings',coalesce(staff->'earnings','[]'::jsonb),'staff_payments',coalesce(staff->'payments','[]'::jsonb));
end $function$;

revoke all on function public.staff_workspace_v630(uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.staff_workspace_v630(uuid,text,jsonb,uuid) to authenticated;
revoke all on function public.reports_export_dataset_v630(uuid,date,date,uuid) from public,anon;
grant execute on function public.reports_export_dataset_v630(uuid,date,date,uuid) to authenticated;
