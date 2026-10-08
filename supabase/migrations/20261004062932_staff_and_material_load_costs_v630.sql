-- Staff, payroll, load costing, settlement and immutable delivery evidence.
-- Invoice creation continues through the authoritative GST writers.

insert into public.modules(key,name,description,category,sort_order,is_active,is_core)
values ('staff','Staff','Staff, attendance, wages, payroll, advances and statements','Operations',65,true,false)
on conflict(key) do update set name=excluded.name,description=excluded.description;
insert into public.permissions(key,module_key,name,description) values
 ('staff.view','staff','View staff','Staff records, attendance and statements'),
 ('staff.manage','staff','Manage staff','Staff profiles and attendance'),
 ('staff.payroll','staff','Post staff payroll and payments','Wages, salary, advances and settlement'),
 ('aggregate_yard.costs','aggregate_yard','Manage load costs','Post and settle linked load expenses'),
 ('sales.tax_override','sales','Adjust invoice tax','Validated, audited invoice-specific GST rate adjustments')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r cross join public.permissions p
where (r.key='owner' and p.key in('staff.view','staff.manage','staff.payroll','aggregate_yard.costs','sales.tax_override'))
   or (r.key='manager' and p.key in('staff.view','staff.manage','aggregate_yard.costs'))
   or (r.key='accountant' and p.key in('staff.view','staff.payroll','aggregate_yard.costs','sales.tax_override'))
   or (r.key='auditor' and p.key='staff.view')
on conflict do nothing;
insert into public.module_dependencies(module_key,depends_on_module_key)
values ('staff','accounting') on conflict do nothing;
insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'staff' from public.subscription_plan_modules where module_key='accounting'
on conflict do nothing;
insert into public.module_business_types(module_key,business_type)
select 'staff',business_type from public.module_business_types where module_key='accounting'
on conflict do nothing;
insert into public.business_template_modules(template_id,module_key)
select template_id,'staff' from public.business_template_modules where module_key='aggregate_yard'
on conflict do nothing;
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tenant_id,'staff',true from public.tenant_modules where module_key='aggregate_yard' and enabled
on conflict(tenant_id,module_key) do nothing;
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata)
select null,'client','staff','module','staff',p.id,'Staff','staff',65,true,false,'{}'::jsonb
from public.app_menu_nodes_v45 p where p.tenant_id is null and p.app_key='client' and p.node_key='operations'
on conflict do nothing;

create table if not exists public.staff_members_v630(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
 location_id uuid references public.business_locations(id), driver_id uuid references public.logistics_drivers_v61(id),
 staff_code text not null, name text not null check(length(trim(name))>0), phone text, address text,
 job_role text not null default 'staff', joined_on date not null default current_date, left_on date,
 wage_basis text not null default 'monthly' check(wage_basis in('monthly','daily','hourly','per_trip')),
 base_rate numeric not null default 0 check(base_rate between 0 and 1000000000),
 overtime_rate numeric not null default 0 check(overtime_rate between 0 and 1000000000),
 bank_name text, bank_account text, bank_ifsc text, emergency_contact text, notes text,
 active boolean not null default true, created_by uuid default auth.uid(), updated_by uuid default auth.uid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,staff_code),unique(tenant_id,driver_id),check(left_on is null or left_on>=joined_on)
);
create index if not exists staff_members_v630_location_idx on public.staff_members_v630(tenant_id,location_id,active);
create table if not exists public.staff_attendance_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,staff_id uuid not null,
 location_id uuid not null references public.business_locations(id),work_date date not null,
 status text not null check(status in('present','half_day','absent','paid_leave','unpaid_leave')),
 hours numeric not null default 0 check(hours between 0 and 24),overtime_hours numeric not null default 0 check(overtime_hours between 0 and 24),
 notes text,updated_by uuid default auth.uid(),updated_at timestamptz not null default now(),
 foreign key(tenant_id,staff_id) references public.staff_members_v630(tenant_id,id),unique(tenant_id,staff_id,work_date)
);
create index if not exists staff_attendance_v630_scope_idx on public.staff_attendance_v630(tenant_id,location_id,work_date);
create table if not exists public.staff_earnings_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,staff_id uuid not null,
 location_id uuid not null references public.business_locations(id),earning_date date not null,
 kind text not null check(kind in('payroll','bonus','load_wage')),
 period_from date,period_to date,units numeric not null check(units between 0 and 1000000000),
 rate numeric not null check(rate between 0 and 1000000000),allowances numeric not null default 0 check(allowances between 0 and 1000000000),
 deductions numeric not null default 0 check(deductions between 0 and 1000000000),
 gross_amount numeric not null check(gross_amount between 0 and 1000000000000),amount numeric not null check(amount between 0 and 1000000000000),
 load_cost_id uuid unique,request_id text not null,request_payload jsonb not null,
 journal_id uuid references public.journal_entries(id),notes text,created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 foreign key(tenant_id,staff_id) references public.staff_members_v630(tenant_id,id),unique(tenant_id,request_id),
 check(deductions<=gross_amount),check(period_from is null or period_to>=period_from)
);
create index if not exists staff_earnings_v630_statement_idx on public.staff_earnings_v630(tenant_id,staff_id,earning_date);
create index if not exists staff_earnings_v630_scope_idx on public.staff_earnings_v630(tenant_id,location_id,earning_date);
create table if not exists public.staff_payments_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,staff_id uuid not null,
 location_id uuid not null references public.business_locations(id),payment_date date not null,
 amount numeric not null check(amount>0 and amount<=1000000000000),advance_amount numeric not null default 0,
 payment_method text not null check(payment_method in('cash','bank','upi','card','cheque')),
 reference text,payee_snapshot text not null,notes text,request_id text not null,request_payload jsonb not null,
 journal_id uuid references public.journal_entries(id),created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 foreign key(tenant_id,staff_id) references public.staff_members_v630(tenant_id,id),unique(tenant_id,request_id),
 check(advance_amount between 0 and amount)
);
create index if not exists staff_payments_v630_statement_idx on public.staff_payments_v630(tenant_id,staff_id,payment_date);
create index if not exists staff_payments_v630_scope_idx on public.staff_payments_v630(tenant_id,location_id,payment_date);
create table if not exists public.staff_payment_allocations_v630(
 id uuid primary key default gen_random_uuid(),payment_id uuid not null references public.staff_payments_v630(id),
 earning_id uuid not null references public.staff_earnings_v630(id),amount numeric not null check(amount>0),
 from_advance boolean not null default false,journal_id uuid references public.journal_entries(id),
 created_at timestamptz not null default now(),unique(payment_id,earning_id)
);
create index if not exists staff_payment_allocations_v630_earning_idx on public.staff_payment_allocations_v630(earning_id);
create table if not exists public.material_load_costs_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),
 load_id uuid not null references public.aggregate_loads_v617(id),
 cost_kind text not null check(cost_kind in('driver_wage','staff_wage','vehicle_rent','diesel','loading','toll','freight','other')),
 description text not null check(length(trim(description))>0),payee text not null check(length(trim(payee))>0),
 staff_id uuid,staff_mode text not null default 'extra_wage' check(staff_mode in('extra_wage','salary_allocation')),
 quantity numeric not null default 1 check(quantity>0 and quantity<=1000000000),
 rate numeric not null check(rate>0 and rate<=1000000000000),amount numeric not null check(amount>0 and amount<=1000000000000),
 bill_amount numeric not null default 0 check(bill_amount between 0 and 1000000000000),
 billing_variant_id uuid references public.product_variants(id),
 receipt_reference text,notes text,status text not null default 'draft' check(status in('draft','posted','void')),
 initial_payment numeric not null default 0 check(initial_payment>=0 and initial_payment<=amount),
 payment_method text not null default 'cash' check(payment_method in('cash','bank','upi','card','cheque')),
 payment_reference text,staff_earning_id uuid references public.staff_earnings_v630(id),journal_id uuid references public.journal_entries(id),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(tenant_id,staff_id) references public.staff_members_v630(tenant_id,id),unique(tenant_id,id),
 check(bill_amount=0 or billing_variant_id is not null),check(staff_id is not null or staff_mode='extra_wage'),
 check(staff_mode<>'salary_allocation' or initial_payment=0)
);
create index if not exists material_load_costs_v630_load_idx on public.material_load_costs_v630(tenant_id,load_id,status);
create index if not exists material_load_costs_v630_staff_idx on public.material_load_costs_v630(tenant_id,staff_id);
do $$ begin
  alter table public.staff_earnings_v630 add constraint staff_earnings_v630_load_cost_fk foreign key(load_cost_id) references public.material_load_costs_v630(id);
exception when others then null;
end $$;
create table if not exists public.material_load_cost_payments_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,cost_id uuid not null,
 payment_date date not null,amount numeric not null check(amount>0 and amount<=1000000000000),
 payment_method text not null check(payment_method in('cash','bank','upi','card','cheque')),reference text,notes text,
 request_id text not null,request_payload jsonb not null,journal_id uuid not null references public.journal_entries(id),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 foreign key(tenant_id,cost_id) references public.material_load_costs_v630(tenant_id,id),unique(tenant_id,request_id)
);
create index if not exists material_load_cost_payments_v630_cost_idx on public.material_load_cost_payments_v630(cost_id);
create table if not exists public.material_load_delivery_v630(
 load_id uuid primary key references public.aggregate_loads_v617(id),tenant_id uuid not null references public.tenants(id),
 details jsonb not null default '{}'::jsonb,updated_by uuid default auth.uid(),updated_at timestamptz not null default now()
);
create table if not exists public.material_load_sale_snapshots_v630(
 sale_id uuid primary key references public.sales(id),tenant_id uuid not null references public.tenants(id),
 load_id uuid not null unique references public.aggregate_loads_v617(id),evidence jsonb not null,
 created_by uuid default auth.uid(),created_at timestamptz not null default now()
);
create index if not exists material_load_sale_snapshots_v630_tenant_idx on public.material_load_sale_snapshots_v630(tenant_id,sale_id);
create table if not exists public.material_load_requests_v630(
 tenant_id uuid not null references public.tenants(id),request_id text not null,payload jsonb not null,
 load_id uuid not null references public.aggregate_loads_v617(id),primary key(tenant_id,request_id)
);
create table if not exists public.workforce_audit_v630(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),
 staff_id uuid,load_id uuid,action text not null,before_data jsonb,after_data jsonb,
 actor_id uuid default auth.uid(),created_at timestamptz not null default now()
);
create index if not exists workforce_audit_v630_load_idx on public.workforce_audit_v630(tenant_id,load_id,created_at);
create index if not exists workforce_audit_v630_staff_idx on public.workforce_audit_v630(tenant_id,staff_id,created_at);

insert into public.staff_members_v630(tenant_id,driver_id,staff_code,name,phone,job_role,wage_basis,joined_on,notes,active)
select d.tenant_id,d.id,'DRV-'||upper(left(d.id::text,8)),d.name,d.phone,'driver','per_trip',d.created_at::date,d.notes,d.active
from public.logistics_drivers_v61 d where exists(select 1 from public.tenant_modules m where m.tenant_id=d.tenant_id and m.module_key='staff' and m.enabled)
on conflict(tenant_id,driver_id) do nothing;

create or replace function private.staff_assert_v630(t uuid,permission text,location uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(t) then raise exception 'Tenant access required' using errcode='42501';end if;
 if not exists(select 1 from public.tenant_modules where tenant_id=t and module_key='staff' and enabled) then raise exception 'Staff module is not enabled' using errcode='42501';end if;
 if not private.erp_has_permission(t,permission) then raise exception 'Staff permission required: %',permission using errcode='42501';end if;
 if location is not null then perform private.v4_location_access(t,location,case when permission='staff.view' then 'view' else 'operate' end);end if;
end $$;

-- One endpoint for staff forms; each action enforces its own permission.
create or replace function public.staff_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;location uuid:=p_location_id;s uuid:=nullif(p_data->>'staff_id','')::uuid;
 member public.staff_members_v630%rowtype;old jsonb;result uuid;driver uuid;day date;start_day date;end_day date;
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
   'attendance',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('staff_name',x.name) order by a.work_date desc,x.name) from public.staff_attendance_v630 a join public.staff_members_v630 x on x.id=a.staff_id and x.tenant_id=a.tenant_id where a.tenant_id=t and (s is null or a.staff_id=s) and a.work_date between start_day and end_day and private.erp_document_scope_allowed(t,a.location_id,location,'view')),'[]'::jsonb),
   'earnings',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('staff_name',x.name,'paid_amount',private.staff_earning_paid_v630(e.id),'outstanding',e.amount-private.staff_earning_paid_v630(e.id)) order by e.earning_date desc,e.created_at desc) from public.staff_earnings_v630 e join public.staff_members_v630 x on x.id=e.staff_id and x.tenant_id=e.tenant_id where e.tenant_id=t and (s is null or e.staff_id=s) and e.earning_date between start_day and end_day and private.erp_document_scope_allowed(t,e.location_id,location,'view')),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('staff_name',x.name,'allocations',coalesce((select jsonb_agg(to_jsonb(a)) from public.staff_payment_allocations_v630 a where a.payment_id=p.id),'[]'::jsonb)) order by p.payment_date desc,p.created_at desc) from public.staff_payments_v630 p join public.staff_members_v630 x on x.id=p.staff_id and x.tenant_id=p.tenant_id where p.tenant_id=t and (s is null or p.staff_id=s) and p.payment_date between start_day and end_day and private.erp_document_scope_allowed(t,p.location_id,location,'view')),'[]'::jsonb),
   'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.workforce_audit_v630 a join public.staff_members_v630 x on x.id=a.staff_id and x.tenant_id=a.tenant_id where a.tenant_id=t and (s is null or a.staff_id=s) and a.created_at::date between start_day and end_day and (x.location_id is null or private.erp_document_scope_allowed(t,x.location_id,location,'view'))),'[]'::jsonb)
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
   old:=to_jsonb(member);driver:=member.driver_id;
   if member.location_id is distinct from location and exists(select 1 from public.staff_earnings_v630 where staff_id=s) then raise exception 'A staff member with earnings cannot move payroll location; retain their financial history';end if;
  else s:=coalesce(nullif(p_data->>'new_id','')::uuid,gen_random_uuid());if exists(select 1 from public.staff_members_v630 where id=s) then raise exception 'Staff ID already exists; refresh and edit that record';end if;end if;
  if coalesce(p_data->>'job_role','staff')='driver' then
   if driver is null then
    insert into public.logistics_drivers_v61(tenant_id,name,phone,license_number,notes,active) values(t,trim(p_data->>'name'),p_data->>'phone',p_data->>'license_number',p_data->>'notes',coalesce((p_data->>'active')::boolean,true)) returning id into driver;
   else update public.logistics_drivers_v61 set name=trim(p_data->>'name'),phone=p_data->>'phone',license_number=p_data->>'license_number',active=coalesce((p_data->>'active')::boolean,true),updated_at=now() where tenant_id=t and id=driver;end if;
  end if;
  insert into public.staff_members_v630(id,tenant_id,location_id,driver_id,staff_code,name,phone,address,job_role,joined_on,left_on,wage_basis,base_rate,overtime_rate,bank_name,bank_account,bank_ifsc,emergency_contact,notes,active)
  values(s,t,location,driver,coalesce(nullif(p_data->>'staff_code',''),member.staff_code,'STF-'||upper(left(s::text,8))),trim(p_data->>'name'),p_data->>'phone',p_data->>'address',coalesce(p_data->>'job_role','staff'),coalesce((p_data->>'joined_on')::date,current_date),(p_data->>'left_on')::date,coalesce(p_data->>'wage_basis','monthly'),coalesce((p_data->>'base_rate')::numeric,0),coalesce((p_data->>'overtime_rate')::numeric,0),p_data->>'bank_name',p_data->>'bank_account',p_data->>'bank_ifsc',p_data->>'emergency_contact',p_data->>'notes',coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set location_id=excluded.location_id,driver_id=excluded.driver_id,staff_code=excluded.staff_code,name=excluded.name,phone=excluded.phone,address=excluded.address,job_role=excluded.job_role,joined_on=excluded.joined_on,left_on=excluded.left_on,wage_basis=excluded.wage_basis,base_rate=excluded.base_rate,overtime_rate=excluded.overtime_rate,bank_name=excluded.bank_name,bank_account=excluded.bank_account,bank_ifsc=excluded.bank_ifsc,emergency_contact=excluded.emergency_contact,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now();
  insert into public.workforce_audit_v630(tenant_id,staff_id,action,before_data,after_data) values(t,s,'staff.save',old,(select to_jsonb(x) from public.staff_members_v630 x where id=s));
  return jsonb_build_object('staff_id',s);
 elsif p_action='attendance' then
  perform private.staff_assert_v630(t,'staff.manage',location);
  select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
  if not found or not member.active then raise exception 'Active staff member not found';end if;
  if member.location_id is not null and member.location_id<>location then raise exception 'Staff belongs to a different location';end if;
  day:=(p_data->>'date')::date;
  if day is null or day<member.joined_on or (member.left_on is not null and day>member.left_on) then raise exception 'Attendance date must be inside the employment period';end if;
  if exists(select 1 from public.staff_earnings_v630 where tenant_id=t and staff_id=s and kind='payroll' and day between period_from and period_to) then raise exception 'Attendance is locked for an already posted payroll period';end if;
  select to_jsonb(a) into old from public.staff_attendance_v630 a where tenant_id=t and staff_id=s and work_date=day;
  insert into public.staff_attendance_v630(tenant_id,staff_id,location_id,work_date,status,hours,overtime_hours,notes)
  values(t,s,location,day,p_data->>'status',coalesce((p_data->>'hours')::numeric,0),coalesce((p_data->>'overtime_hours')::numeric,0),p_data->>'notes')
  on conflict(tenant_id,staff_id,work_date) do update set status=excluded.status,hours=excluded.hours,overtime_hours=excluded.overtime_hours,notes=excluded.notes,updated_by=auth.uid(),updated_at=now() returning id into result;
  insert into public.workforce_audit_v630(tenant_id,staff_id,action,before_data,after_data) values(t,s,'attendance.save',old,(select to_jsonb(a) from public.staff_attendance_v630 a where id=result));
 elsif p_action='payroll' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_earning_post_v630(t,s,location,p_data);
 elsif p_action='payment' then
  perform private.staff_assert_v630(t,'staff.payroll',location);
  result:=private.staff_payment_post_v630(t,s,location,p_data);
 else raise exception 'Unknown staff action';
 end if;
 return jsonb_build_object('id',result,'recorded',true);
end $$;

create or replace function private.load_delivery_save_v630(t uuid,load uuid,data jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;old jsonb;start_meter numeric;end_meter numeric;depart timestamptz;arrive timestamptz;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 data:=jsonb_strip_nulls(data);
 if jsonb_typeof(data)<>'object' or octet_length(data::text)>64000 then raise exception 'Invalid delivery details';end if;
 start_meter:=nullif(data->>'odometer_start','')::numeric;end_meter:=nullif(data->>'odometer_end','')::numeric;
 depart:=nullif(data->>'dispatch_at','')::timestamptz;arrive:=nullif(data->>'delivered_at','')::timestamptz;
 if start_meter<0 or end_meter<0 or end_meter<start_meter or start_meter>1000000000 or end_meter>1000000000 then raise exception 'Check the start and end odometer readings';end if;
 if arrive<depart then raise exception 'Delivery time must follow departure';end if;
 select details into old from public.material_load_delivery_v630 where tenant_id=t and load_id=load;
 insert into public.material_load_delivery_v630(load_id,tenant_id,details) values(load,t,coalesce(old,'{}'::jsonb)||data)
 on conflict(load_id) do update set details=excluded.details,updated_by=auth.uid(),updated_at=now();
 insert into public.workforce_audit_v630(tenant_id,load_id,action,before_data,after_data) values(t,load,'delivery.save',old,coalesce(old,'{}'::jsonb)||data);
end $$;

create or replace function private.staff_earning_paid_v630(e uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp as $$
 select coalesce(sum(amount),0) from public.staff_payment_allocations_v630 where earning_id=e;
$$;

create or replace function private.staff_available_advance_v630(s uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp as $$
 select coalesce(sum(p.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a where a.payment_id=p.id and a.from_advance),0)),0) from public.staff_payments_v630 p where p.staff_id=s;
$$;

create or replace function private.load_cost_paid_v630(c uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp as $$
 select case when x.staff_mode='salary_allocation' then 0 when x.staff_earning_id is not null then private.staff_earning_paid_v630(x.staff_earning_id)
 else coalesce((select sum(p.amount) from public.material_load_cost_payments_v630 p where p.cost_id=x.id),0) end
 from public.material_load_costs_v630 x where x.id=c;
$$;

create or replace function private.load_sale_items_v630(t uuid,load uuid,items jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;extra jsonb;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
 if not found then raise exception 'Load not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,false);
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items)=0 then raise exception 'Invoice items are required';end if;
 if not exists(select 1 from jsonb_array_elements(items) x where (x->>'variant_id')::uuid=l.variant_id) then raise exception 'The invoice must include the load material';end if;
 if exists(select 1 from public.material_load_costs_v630 c join jsonb_array_elements(items) x on (x->>'variant_id')::uuid=c.billing_variant_id where c.tenant_id=t and c.load_id=load and c.status='posted' and c.bill_amount>0) then raise exception 'A load billing service is already an invoice product; select a separate billing service for the load charges';end if;
 select coalesce(jsonb_agg(jsonb_build_object('variant_id',c.billing_variant_id,'quantity',1,'unit_price',c.bill_amount,'discount_amount',0,'tax_rate',0,'invoice_description',c.description,'material_cost_ids',c.ids) order by c.description),'[]'::jsonb)
 into extra from (select billing_variant_id,sum(bill_amount) bill_amount,string_agg(description,'; ' order by created_at,id) description,jsonb_agg(id order by created_at,id) ids from public.material_load_costs_v630 where tenant_id=t and load_id=load and status='posted' and bill_amount>0 group by billing_variant_id) c;
 return items||extra;
end $$;

create or replace function public.client_sale_quote_v630(
 p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_items jsonb,p_location_id uuid,p_device_id uuid,
 p_supply_type text default null,p_place_of_supply_code text default null,p_charge_selections jsonb default '[]'::jsonb,p_load_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare items jsonb:=p_items;commercial jsonb;quote jsonb;base_subtotal numeric;load_charges numeric:=0;totals jsonb;rounding numeric;supply text;pos text;normalized jsonb;l public.aggregate_loads_v617%rowtype;
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied' using errcode='42501';end if;
 perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
 if p_load_id is not null then
  l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
  items:=private.load_sale_items_v630(p_tenant_id,p_load_id,items);
  select coalesce(sum(bill_amount),0) into load_charges from public.material_load_costs_v630 where tenant_id=p_tenant_id and load_id=p_load_id and status='posted';
 end if;
 if not public.sales_additional_charges_enabled_v611(p_tenant_id) and jsonb_array_length(p_charge_selections)>0 then raise exception 'Additional charges are disabled in Business Settings';end if;
 if private.gst_tax_mode_resolve_v520(p_tenant_id,p_sale_date)='non_gst' and exists(select 1 from jsonb_array_elements(items) x where coalesce((x->'thq_tax_override_v630'->>'gst_rate')::numeric,0)<>0) then raise exception 'A Non-GST invoice must have zero GST';end if;
 commercial:=private.sales_commercial_expand_v610(p_tenant_id,'sale',items,'none',0,p_charge_selections);
 normalized:=private.v481_normalize_items(p_tenant_id,private.v482_price_sale_items(p_tenant_id,p_customer_id,commercial->'items',p_location_id),'sale');
 supply:=private.gst_sale_supply_type_resolve_v520(p_tenant_id,p_customer_id,p_sale_date,p_supply_type);
 pos:=private.gst_sale_pos_resolve_v520(p_tenant_id,p_customer_id,p_location_id,p_sale_date,supply,normalized,p_place_of_supply_code);
 quote:=public.gst_quote_v520(p_tenant_id,p_location_id,'customer',p_customer_id,p_sale_date,supply,pos,normalized,0,0);
 if coalesce((quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'Invoice needs GST review: %',coalesce(quote->'errors','[]'::jsonb);end if;
 totals:=quote->'totals';rounding:=round(round((totals->>'grand_total')::numeric,0)-(totals->>'grand_total')::numeric,2);
 select sum((x->>'quantity')::numeric*(x->>'unit_price')::numeric) into base_subtotal from jsonb_array_elements(p_items) x;
 return jsonb_build_object('totals',totals||jsonb_build_object('subtotal',base_subtotal,'tax',(totals->>'tax_collected_total')::numeric,'before_round_off',(totals->>'grand_total')::numeric,'automatic_round_off',rounding,'grand_total',(totals->>'grand_total')::numeric+rounding),'classified_charge_total',load_charges+coalesce((commercial->>'classified_charge_total')::numeric,0),
  'gst',quote,'items',commercial->'items','charge_breakdown',commercial->'charge_breakdown','load_charge_total',load_charges);
end $$;

create or replace function public.aggregate_load_sale_create_v630(
 p_tenant_id uuid,p_load_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_payment_allocations jsonb,
 p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text,p_supply_type text,p_place_of_supply_code text,p_charge_selections jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;result jsonb;items jsonb;id uuid;
begin
 l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
 perform public.client_sale_quote_v630(p_tenant_id,p_customer_id,p_sale_date,p_items,p_location_id,p_device_id,p_supply_type,p_place_of_supply_code,p_charge_selections,p_load_id);
 perform private.load_costs_post_v630(p_tenant_id,p_load_id);
 items:=private.load_sale_items_v630(p_tenant_id,p_load_id,p_items);
 result:=public.aggregate_load_sale_create_v629(p_tenant_id,p_load_id,p_customer_id,p_sale_date,p_due_date,items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
 id:=(result->>'sale_id')::uuid;
 insert into public.material_load_sale_snapshots_v630(sale_id,tenant_id,load_id,evidence)
 values(id,p_tenant_id,p_load_id,private.load_evidence_v630(p_tenant_id,p_load_id)||jsonb_build_object('invoice_items_entered',p_items,'snapshot_at',now()))
 on conflict(sale_id) do nothing;
 return result||jsonb_build_object('load_costs_recorded',true);
end $$;

create or replace function public.sales_get_detail_v630(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;
begin
 result:=public.sales_get_detail_v628(p_tenant_id,p_sale_id);
 return result||jsonb_build_object('material_load',coalesce((select evidence from public.material_load_sale_snapshots_v630 where tenant_id=p_tenant_id and sale_id=p_sale_id),'{}'::jsonb));
end $$;

create or replace function public.reports_get_summary_v630(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;extra numeric;
begin
 result:=public.reports_get_summary_v4(p_tenant_id,p_from_date,p_to_date,p_location_id);
 select coalesce(sum(jl.debit-jl.credit),0) into extra from public.journal_entries j join public.journal_lines jl on jl.journal_entry_id=j.id join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
 where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from_date and p_to_date and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view') and a.account_type='expense' and a.system_key ~ '^(staff_salary_v630|yard_.*_v630)$';
 return result||jsonb_build_object('staff_and_load_expenses',extra,'expenses',coalesce((result->>'expenses')::numeric,0)+extra,'net_profit',coalesce((result->>'net_profit')::numeric,0)-extra);
end $$;
create or replace function private.load_cost_save_v630(t uuid,load uuid,costs jsonb,replace_draft boolean default true)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;c public.material_load_costs_v630%rowtype;member public.staff_members_v630%rowtype;
 x jsonb;v_cost_id uuid;staff uuid;variant uuid;amount numeric;quantity numeric;rate numeric;bill numeric;seen uuid[]:='{}';old jsonb;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,true);
 if l.status='cancelled' or l.direction='direct_delivery' then raise exception 'This load cannot accept costs';end if;
 if replace_draft and l.status='completed' then raise exception 'Confirmed costs are locked; add a new cost instead';end if;
 if jsonb_typeof(costs)<>'array' or jsonb_array_length(costs)>100 then raise exception 'Supply at most 100 cost lines';end if;
 for x in select value from jsonb_array_elements(costs) loop
  v_cost_id:=coalesce(nullif(x->>'id','')::uuid,gen_random_uuid());staff:=nullif(x->>'staff_id','')::uuid;variant:=nullif(x->>'billing_variant_id','')::uuid;
  quantity:=coalesce((x->>'quantity')::numeric,1);rate:=(x->>'rate')::numeric;amount:=round(quantity*rate,2);bill:=round(coalesce((x->>'bill_amount')::numeric,0),2);
  if v_cost_id=any(seen) then raise exception 'Duplicate cost line ID';end if;seen:=array_append(seen,v_cost_id);
  if amount is null or amount<=0 or amount>1000000000000 or quantity<=0 or bill<0 or bill>1000000000000 then raise exception 'Enter a valid quantity, rate and customer charge';end if;
  if nullif(trim(x->>'description'),'') is null then raise exception 'Cost description is required';end if;
  select * into c from public.material_load_costs_v630 where id=v_cost_id for update;
  if found and (c.tenant_id<>t or c.load_id<>load) then raise exception 'Cost belongs to a different load' using errcode='42501';end if;
  if found and c.status<>'draft' then raise exception 'A posted or void cost cannot be overwritten';end if;
  old:=case when c.id is null then null else to_jsonb(c) end;
  if (l.sale_id is not null or l.purchase_id is not null) and bill>0 then raise exception 'A linked invoice is immutable; subsequent costs must be internal';end if;
  if bill>0 and not exists(select 1 from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id where v.id=variant and v.tenant_id=t and v.status='active' and p.status='active' and p.item_type='service') then raise exception 'Select an active service product for the customer charge';end if;
  if l.direction<>'outbound' and bill>0 then raise exception 'Customer charges are available on dispatch loads only';end if;
  if staff is not null then
   if not exists(select 1 from public.tenant_modules where tenant_id=t and module_key='staff' and enabled) then raise exception 'Staff module is not enabled';end if;
   select * into member from public.staff_members_v630 where tenant_id=t and id=staff and active;
   if not found or (member.location_id is not null and member.location_id<>l.location_id) then raise exception 'Staff is inactive or belongs to a different store';end if;
   if x->>'cost_kind' not in('driver_wage','staff_wage') then raise exception 'Staff payees must use a wage cost type';end if;
   if x->>'staff_mode'='salary_allocation' and member.wage_basis<>'monthly' then raise exception 'Salary allocation requires a salaried staff member';end if;
  end if;
  insert into public.material_load_costs_v630(id,tenant_id,load_id,cost_kind,description,payee,staff_id,staff_mode,quantity,rate,amount,bill_amount,billing_variant_id,receipt_reference,notes,initial_payment,payment_method,payment_reference)
  values(v_cost_id,t,load,x->>'cost_kind',trim(x->>'description'),coalesce(member.name,nullif(trim(x->>'payee'),'')),staff,coalesce(x->>'staff_mode','extra_wage'),quantity,rate,amount,bill,variant,x->>'receipt_reference',x->>'notes',coalesce((x->>'initial_payment')::numeric,0),coalesce(x->>'payment_method','cash'),x->>'payment_reference')
  on conflict(id) do update set cost_kind=excluded.cost_kind,description=excluded.description,payee=excluded.payee,staff_id=excluded.staff_id,staff_mode=excluded.staff_mode,quantity=excluded.quantity,rate=excluded.rate,amount=excluded.amount,bill_amount=excluded.bill_amount,billing_variant_id=excluded.billing_variant_id,receipt_reference=excluded.receipt_reference,notes=excluded.notes,initial_payment=excluded.initial_payment,payment_method=excluded.payment_method,payment_reference=excluded.payment_reference,updated_at=now();
  insert into public.workforce_audit_v630(tenant_id,load_id,action,before_data,after_data) values(t,load,'cost.save',old,(select to_jsonb(z) from public.material_load_costs_v630 z where z.id=v_cost_id));
  member:=null;c:=null;
 end loop;
 if replace_draft then
  for c in select * from public.material_load_costs_v630 where tenant_id=t and load_id=load and status='draft' and not(id=any(seen)) for update loop
   update public.material_load_costs_v630 set status='void',updated_at=now() where id=c.id;
   insert into public.workforce_audit_v630(tenant_id,load_id,action,before_data,after_data) values(t,load,'cost.remove',to_jsonb(c),jsonb_build_object('status','void'));
  end loop;
 end if;
end $$;

create or replace function private.load_evidence_v630(t uuid,load uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;result jsonb;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
 if not found then raise exception 'Load not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,false);
 result:=public.aggregate_load_detail_v629(t,load);
 return result||jsonb_build_object(
  'location_name',(select name from public.business_locations where tenant_id=t and id=l.location_id),
  'legacy_freight_payments',coalesce((select jsonb_agg(to_jsonb(f) order by f.settled_at) from public.aggregate_freight_settlements_v620 f where f.tenant_id=t and f.load_id=load),'[]'::jsonb),
  'sale',coalesce((select to_jsonb(s) from public.sales s where s.tenant_id=t and s.id=l.sale_id),'{}'::jsonb),
  'customer_payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.tenant_id=t and p.sale_id=l.sale_id),'[]'::jsonb),
  'delivery',coalesce((select details from public.material_load_delivery_v630 where tenant_id=t and load_id=load),'{}'::jsonb),
  'costs',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('paid_amount',coalesce(private.load_cost_paid_v630(c.id),0),'outstanding',case when c.staff_mode='salary_allocation' or c.status<>'posted' then 0 else c.amount-coalesce(private.load_cost_paid_v630(c.id),0) end,'billing_service',(select p.name from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id where v.id=c.billing_variant_id and v.tenant_id=t)) order by c.created_at,c.id) from public.material_load_costs_v630 c where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('cost_description',c.description,'payee',c.payee) order by p.payment_date,p.created_at) from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id=p.cost_id and c.tenant_id=p.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'staff_payments',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'payment_date',p.payment_date,'amount',a.amount,'payment_method',p.payment_method,'reference',p.reference,'payee',p.payee_snapshot,'cost_id',c.id,'cost_description',c.description,'from_advance',a.from_advance,'journal_id',a.journal_id,'notes',p.notes) order by p.payment_date,p.created_at) from public.material_load_costs_v630 c join public.staff_payment_allocations_v630 a on a.earning_id=c.staff_earning_id join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=c.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_total',coalesce((select sum(amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'customer_charge_total',coalesce((select sum(bill_amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.workforce_audit_v630 a where a.tenant_id=t and a.load_id=load),'[]'::jsonb)
 );
end $$;

create or replace function public.material_load_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;load uuid:=nullif(p_data->>'load_id','')::uuid;location uuid:=p_location_id;
 l public.aggregate_loads_v617%rowtype;data jsonb:=coalesce(p_data->'load',p_data);result jsonb;prior public.material_load_requests_v630%rowtype;
 costs jsonb:=coalesce(p_data->'costs','[]'::jsonb);req text:=p_data->>'request_id';variant uuid;v_sku text;mode text;name text;
begin
 if p_action='context' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'driver_id',s.driver_id,'name',s.name,'phone',s.phone,'wage_basis',s.wage_basis,'base_rate',case when private.erp_has_permission(t,'staff.view') then s.base_rate else null end,'location_id',s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id=t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t,s.location_id,location,'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id=t and m.module_key='staff' and m.enabled)),'[]'::jsonb),
   'billing_services',coalesce((select jsonb_agg(jsonb_build_object('variant_id',v.id,'name',p.name,'tax_rate',p.tax_rate,'hsn_sac',g.hsn_sac,'taxability',g.taxability,'gst_rate',g.gst_rate,'validation_status',g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t,v.id,current_date)) g on true where v.tenant_id=t and v.status='active' and p.status='active' and p.item_type='service'),'[]'::jsonb),
   'tax_mode',private.gst_tax_mode_resolve_v520(t,current_date),'can_manage_costs',private.erp_has_permission(t,'aggregate_yard.costs'),
   'can_create_billing_service',private.erp_has_permission(t,'inventory.manage') and private.erp_has_permission(t,'gst_compliance.manage')
  );
 elsif p_action='billing_service' then
  perform private.yard_cost_assert_v630(t,location,true);
  name:=nullif(trim(data->>'name'),'');if name is null then raise exception 'Charge service name is required';end if;
  mode:=private.gst_tax_mode_resolve_v520(t,current_date);
  if mode='unconfigured' then raise exception 'Configure the business tax mode first';end if;
  if mode='non_gst' and coalesce((data->>'gst_rate')::numeric,0)<>0 then raise exception 'Non-GST charges must have zero GST';end if;
  if mode='gst_registered' and nullif(trim(data->>'hsn_sac'),'') is null then raise exception 'Select the correct SAC for this charge service';end if;
  v_sku:='YARD-SVC-'||upper(left(coalesce(nullif(data->>'new_id',''),gen_random_uuid()::text),12));
  if exists(select 1 from public.product_variants where tenant_id=t and sku=v_sku) then raise exception 'Charge service already exists; refresh the list';end if;
  result:=public.inventory_create_product_v481(p_tenant_id=>t,p_location_id=>location,p_device_id=>nullif(data->>'device_id','')::uuid,p_name=>name,p_sku=>v_sku,p_item_type=>'service',p_description=>coalesce(data->>'description',name),p_category_name=>'Load Charges',p_brand_name=>'',p_barcode=>'',p_part_number=>'',p_cost_price=>0,p_selling_price=>0,p_list_price=>null,p_tax_rate=>coalesce((data->>'gst_rate')::numeric,0),p_reorder_level=>0,p_opening_stock=>0,p_base_unit_code=>'PCS',p_units=>'[]'::jsonb);
  variant:=(result->>'variant_id')::uuid;
  if mode='gst_registered' then perform public.gst_product_profile_save_v520(t,variant,'service',data->>'hsn_sac',coalesce(data->>'taxability','taxable'),coalesce((data->>'gst_rate')::numeric,0),0,0,false,false,'Load charge service setup',current_date);end if;
  return jsonb_build_object('variant_id',variant,'recorded',true);
 elsif p_action='report' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  if coalesce((data->>'to')::date,current_date)<coalesce((data->>'from')::date,date_trunc('month',current_date)::date) then raise exception 'End date must follow start date';end if;
  return jsonb_build_object('loads',coalesce((select jsonb_agg(private.load_evidence_v630(t,x.id) order by x.load_date desc,x.load_number) from public.aggregate_loads_v617 x where x.tenant_id=t and x.direction<>'direct_delivery' and x.load_date between coalesce((data->>'from')::date,date_trunc('month',current_date)::date) and coalesce((data->>'to')::date,current_date) and private.erp_document_scope_allowed(t,x.location_id,location,'view') and (nullif(data->>'vehicle_id','') is null or x.vehicle_id=(data->>'vehicle_id')::uuid) and (nullif(data->>'driver_id','') is null or x.driver_id=(data->>'driver_id')::uuid)),'[]'::jsonb));
 end if;
 if p_action='create' then
  perform private.aggregate_yard_assert_manage_v617(t);
  if req is null or length(req)>256 then raise exception 'A stable load request ID is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text||':load:'||req,0));
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id=req;
  if found then if prior.payload<>p_data then raise exception 'Load retry has different data';end if;return jsonb_build_object('load_id',prior.load_id,'replayed',true);end if;
  result:=public.aggregate_load_create_v617(t,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  load:=(result->>'load_id')::uuid;
  select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
  perform private.v4_location_access(t,l.location_id,'operate');
  if jsonb_array_length(costs)>0 then perform private.load_cost_save_v630(t,load,costs);end if;
  perform private.load_delivery_save_v630(t,load,coalesce(p_data->'delivery','{}'::jsonb)||jsonb_build_object('driver_license_snapshot',(select license_number from public.logistics_drivers_v61 where id=l.driver_id and tenant_id=t)));
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,req,p_data,load);
  return result;
 end if;
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 if p_action='detail' then return private.load_evidence_v630(t,load);end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 if p_action='edit' then
  result:=public.aggregate_load_edit_v628(t,load,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  perform private.v4_location_access(t,(select location_id from public.aggregate_loads_v617 where id=load),'operate');
  if jsonb_array_length(costs)>0 or exists(select 1 from public.material_load_costs_v630 where load_id=load) then perform private.load_cost_save_v630(t,load,costs);end if;
  if p_data ? 'delivery' then perform private.load_delivery_save_v630(t,load,p_data->'delivery');end if;
 elsif p_action='confirm' then
  result:=public.aggregate_load_confirm_v628(t,load);perform private.load_costs_post_v630(t,load);
 elsif p_action='delivery' then perform private.load_delivery_save_v630(t,load,data);result:=jsonb_build_object('recorded',true);
 elsif p_action='payment' then result:=jsonb_build_object('payment_id',private.load_cost_payment_v630(t,(data->>'cost_id')::uuid,data));
 elsif p_action='add_cost' then
  perform private.load_cost_save_v630(t,load,jsonb_build_array(p_data->'cost'),false);
  if l.status='completed' then perform private.load_costs_post_v630(t,load);end if;
  result:=jsonb_build_object('recorded',true);
 elsif p_action='cancel' then
  if l.status='completed' or l.sale_id is not null or l.purchase_id is not null then raise exception 'Only an unconfirmed load can be cancelled. Confirmed costs and linked documents retain their financial history.';end if;
  result:=public.aggregate_load_status_v617(t,load,'cancelled',coalesce(p_data->>'reason','Cancelled before confirmation'));
 elsif p_action='delete' then
  if exists(select 1 from public.material_load_costs_v630 where tenant_id=t and load_id=load) or exists(select 1 from public.material_load_delivery_v630 where tenant_id=t and load_id=load) then raise exception 'This load has saved costs or delivery records. Cancel it to retain its history instead of deleting it.';end if;
  result:=public.aggregate_load_delete_v628(t,load);
 else raise exception 'Unknown material load action';end if;
 return result;
end $$;

create or replace function private.load_cost_payment_v630(t uuid,cost uuid,data jsonb)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare c public.material_load_costs_v630%rowtype;l public.aggregate_loads_v617%rowtype;p public.material_load_cost_payments_v630%rowtype;
 amount numeric:=round((data->>'amount')::numeric,2);method text:=coalesce(data->>'payment_method','cash');day date:=coalesce((data->>'date')::date,current_date);
 journal uuid;result uuid;req text:=data->>'request_id';
begin
 -- A load lock serializes confirmation and cost settlement; staff locks serialize wages.
 select x.* into l from public.aggregate_loads_v617 x join public.material_load_costs_v630 z on z.load_id=x.id and z.tenant_id=x.tenant_id where z.id=cost and x.tenant_id=t for update of x;
 if not found then raise exception 'Cost not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,true);
 select * into c from public.material_load_costs_v630 where tenant_id=t and id=cost for update;
 if c.status<>'posted' or c.staff_mode='salary_allocation' then raise exception 'Only a posted, unpaid cost can receive a payment';end if;
 if req is null or amount is null or amount<=0 or amount>1000000000000 then raise exception 'A positive payment and stable request ID are required';end if;
 if c.staff_earning_id is not null then return private.staff_payment_post_v630(t,c.staff_id,l.location_id,data,c.staff_earning_id);end if;
 select * into p from public.material_load_cost_payments_v630 where tenant_id=t and request_id=req;
 if found then if p.cost_id<>cost or p.request_payload<>data then raise exception 'Cost payment retry has different data';end if;return p.id;end if;
 if amount>c.amount-private.load_cost_paid_v630(cost) then raise exception 'Payment exceeds the unpaid load cost';end if;
 if method not in('cash','bank','upi','card','cheque') then raise exception 'Invalid payment method';end if;
 if method<>'cash' and nullif(trim(data->>'reference'),'') is null then raise exception 'Payment reference is required for non-cash payments';end if;
 result:=gen_random_uuid();
 journal:=private.v4_journal_create(t,l.location_id,day,'Load payment: '||c.description,'load_cost_payment',result,coalesce(data->>'reference',l.load_number),
  jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'load_costs_payable_v630'),'debit',amount),jsonb_build_object('account_id',private.workforce_account_v630(t,case when method='cheque' then 'bank' else method end),'credit',amount)));
 insert into public.material_load_cost_payments_v630(id,tenant_id,cost_id,payment_date,amount,payment_method,reference,notes,request_id,request_payload,journal_id)
 values(result,t,cost,day,amount,method,data->>'reference',data->>'notes',req,data,journal);
 insert into public.workforce_audit_v630(tenant_id,load_id,action,after_data) values(t,l.id,'cost.payment',(select to_jsonb(z) from public.material_load_cost_payments_v630 z where id=result));
 return result;
end $$;

create or replace function private.load_costs_post_v630(t uuid,load uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;c public.material_load_costs_v630%rowtype;journal uuid;earning uuid;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found or l.status<>'completed' then raise exception 'Confirm the load before posting its costs';end if;
 if exists(select 1 from public.material_load_costs_v630 where tenant_id=t and load_id=load and status='draft') then perform private.yard_cost_assert_v630(t,l.location_id,true);end if;
 for c in select * from public.material_load_costs_v630 where tenant_id=t and load_id=load and status='draft' order by staff_id nulls last,id for update loop
  earning:=null;journal:=null;
  if c.staff_mode='salary_allocation' then
   if not exists(select 1 from public.staff_members_v630 where tenant_id=t and id=c.staff_id and wage_basis='monthly') then raise exception 'Salary allocation requires a salaried staff member';end if;
  elsif c.staff_id is not null then
   earning:=private.staff_earning_post_v630(t,c.staff_id,l.location_id,jsonb_build_object('kind','load_wage','date',l.load_date,'units',c.quantity,'rate',c.rate,'notes',l.load_number||' - '||c.description,'request_id','load-cost:'||c.id),c.id);
   select journal_id into journal from public.staff_earnings_v630 where id=earning;
  else
   journal:=private.v4_journal_create(t,l.location_id,l.load_date,'Load cost: '||c.description,'load_cost',c.id,l.load_number,
    jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'yard_'||c.cost_kind||'_v630'),'debit',c.amount,'description',c.payee),jsonb_build_object('account_id',private.workforce_account_v630(t,'load_costs_payable_v630'),'credit',c.amount,'description',c.payee)));
  end if;
  update public.material_load_costs_v630 set status='posted',staff_earning_id=earning,journal_id=journal,updated_at=now() where id=c.id;
  if c.initial_payment>0 then perform private.load_cost_payment_v630(t,c.id,jsonb_build_object('amount',c.initial_payment,'date',l.load_date,'payment_method',c.payment_method,'reference',c.payment_reference,'notes',l.load_number||' initial cost payment','request_id','load-cost-payment:'||c.id));end if;
 end loop;
end $$;
create or replace function private.yard_cost_assert_v630(t uuid,location uuid,manage boolean default false)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 if manage then perform private.aggregate_yard_assert_manage_v617(t);else perform private.aggregate_yard_assert_view_v617(t);end if;
 perform private.v4_location_access(t,location,case when manage then 'operate' else 'view' end);
 if manage and not private.erp_has_permission(t,'aggregate_yard.costs') then raise exception 'Load cost manage permission required' using errcode='42501';end if;
end $$;
create or replace function private.workforce_account_v630(t uuid,k text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result uuid;typ text;label text;
begin
 perform private.v47_ensure_accounting_for_tenant(t);
 select id into result from public.accounting_accounts where tenant_id=t and system_key=k and active;
 if result is not null then return result;end if;
 typ:=case when k='staff_advance_v630' then 'asset' when k in('staff_payable_v630','load_costs_payable_v630') then 'liability' else 'expense' end;
 label:=case k when 'staff_advance_v630' then 'Staff advances' when 'staff_payable_v630' then 'Staff wages and salary payable' when 'load_costs_payable_v630' then 'Load cost creditors' when 'staff_salary_v630' then 'Staff salary and wages' else initcap(replace(replace(k,'_v630',''),'_',' ')) end;
 return private.gst_v520_ensure_account(t,'THQ-'||upper(k),label,typ,k,null,'Linked staff and material load accounting');
end $$;

create or replace function private.staff_earning_post_v630(t uuid,s uuid,location uuid,data jsonb,cost uuid default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare member public.staff_members_v630%rowtype;e public.staff_earnings_v630%rowtype;p record;allocation uuid;
 gross numeric;net numeric;u numeric;r numeric;bonus numeric;deduct numeric;remaining numeric;allocated numeric;
 journal uuid;day date:=coalesce((data->>'date')::date,current_date);kind text:=coalesce(data->>'kind','payroll');req text:=data->>'request_id';
begin
 select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
 if not found or not member.active then raise exception 'Active staff member not found';end if;
 if member.location_id is not null and member.location_id<>location then raise exception 'Staff member belongs to a different location';end if;
 perform private.v4_location_access(t,location,'operate');
 if req is null or length(req)>256 then raise exception 'A stable payroll request ID is required';end if;
 select * into e from public.staff_earnings_v630 where tenant_id=t and request_id=req;
 if found then if e.staff_id<>s or e.location_id<>location or e.request_payload<>data then raise exception 'Payroll retry has different data';end if;return e.id;end if;
 u:=coalesce((data->>'units')::numeric,1);r:=coalesce((data->>'rate')::numeric,member.base_rate);
 bonus:=coalesce((data->>'allowances')::numeric,0);deduct:=coalesce((data->>'deductions')::numeric,0);
 gross:=round(u*r+bonus,2);net:=round(gross-deduct,2);
 if u<0 or r<0 or bonus<0 or deduct<0 or gross>1000000000000 or net<=0 then raise exception 'Invalid salary, units, allowance or deduction amount';end if;
 if day<member.joined_on or (member.left_on is not null and day>member.left_on) then raise exception 'Earning date is outside the staff employment period';end if;
 if kind='payroll' then
  if nullif(data->>'period_from','') is null or nullif(data->>'period_to','') is null or (data->>'period_to')::date<(data->>'period_from')::date then raise exception 'A valid payroll period is required';end if;
  if exists(select 1 from public.staff_earnings_v630 where tenant_id=t and staff_id=s and kind='payroll' and period_from<=(data->>'period_to')::date and period_to>=(data->>'period_from')::date) then raise exception 'This staff payroll period overlaps an already posted payroll';end if;
  if member.wage_basis='per_trip' then raise exception 'Per-trip staff wages are recorded on their loads; use a bonus for additional earnings';end if;
 end if;
 insert into public.staff_earnings_v630(tenant_id,staff_id,location_id,earning_date,kind,period_from,period_to,units,rate,allowances,deductions,gross_amount,amount,load_cost_id,request_id,request_payload,notes)
 values(t,s,location,day,kind,(data->>'period_from')::date,(data->>'period_to')::date,u,r,bonus,deduct,gross,net,cost,req,data,data->>'notes') returning * into e;
 journal:=private.v4_journal_create(t,location,day,'Staff earning: '||member.name,'staff_earning',e.id,member.staff_code,
  jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_salary_v630'),'debit',net,'description',member.name),
   jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'credit',net,'party_type','staff','party_id',s)));
 update public.staff_earnings_v630 set journal_id=journal where id=e.id;
 remaining:=net;
 for p in select x.id,x.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a where a.payment_id=x.id and a.from_advance),0) available
  from public.staff_payments_v630 x where x.tenant_id=t and x.staff_id=s and x.location_id=location order by x.payment_date,x.created_at,x.id for update of x loop
  allocated:=least(remaining,p.available);
  if allocated>0 then
   insert into public.staff_payment_allocations_v630(payment_id,earning_id,amount,from_advance) values(p.id,e.id,allocated,true) returning id into allocation;
   journal:=private.v4_journal_create(t,location,day,'Apply staff advance: '||member.name,'staff_advance_apply',allocation,member.staff_code,
    jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'debit',allocated,'party_type','staff','party_id',s),jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_advance_v630'),'credit',allocated,'party_type','staff','party_id',s)));
   update public.staff_payment_allocations_v630 set journal_id=journal where id=allocation;
   remaining:=remaining-allocated;
  end if;
  exit when remaining<=0;
 end loop;
 insert into public.workforce_audit_v630(tenant_id,staff_id,action,after_data) values(t,s,'earning.post',(select to_jsonb(x) from public.staff_earnings_v630 x where id=e.id));
 return e.id;
end $$;

create or replace function private.staff_payment_post_v630(t uuid,s uuid,location uuid,data jsonb,target_earning uuid default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare member public.staff_members_v630%rowtype;p public.staff_payments_v630%rowtype;e record;
 amount numeric:=round((data->>'amount')::numeric,2);remaining numeric;allocated numeric;allocated_total numeric:=0;lines jsonb:='[]';
 req text:=data->>'request_id';method text:=coalesce(data->>'payment_method','cash');day date:=coalesce((data->>'date')::date,current_date);journal uuid;
begin
 select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
 if not found then raise exception 'Staff member not found';end if;
 if member.location_id is not null and member.location_id<>location then raise exception 'Staff member belongs to a different location';end if;
 perform private.v4_location_access(t,location,'operate');
 if req is null or length(req)>256 or amount is null or amount<=0 or amount>1000000000000 then raise exception 'A positive payment and stable request ID are required';end if;
 select * into p from public.staff_payments_v630 where tenant_id=t and request_id=req;
 if found then if p.staff_id<>s or p.location_id<>location or p.request_payload<>data then raise exception 'Staff payment retry has different data';end if;return p.id;end if;
 if method not in('cash','bank','upi','card','cheque') then raise exception 'Invalid payment method';end if;
 if method<>'cash' and nullif(trim(data->>'reference'),'') is null then raise exception 'Payment reference is required for non-cash payments';end if;
 if target_earning is not null and not exists(select 1 from public.staff_earnings_v630 x where x.tenant_id=t and x.staff_id=s and x.id=target_earning and x.amount-private.staff_earning_paid_v630(x.id)>=amount) then raise exception 'Load wage payment exceeds the unpaid wage';end if;
 insert into public.staff_payments_v630(tenant_id,staff_id,location_id,payment_date,amount,payment_method,reference,payee_snapshot,notes,request_id,request_payload)
 values(t,s,location,day,amount,method,data->>'reference',member.name,data->>'notes',req,data) returning * into p;
 remaining:=amount;
 for e in select x.id,x.amount-private.staff_earning_paid_v630(x.id) outstanding from public.staff_earnings_v630 x
  where x.tenant_id=t and x.staff_id=s and x.location_id=location and (target_earning is null or x.id=target_earning)
  order by x.earning_date,x.created_at,x.id for update of x loop
  allocated:=least(remaining,e.outstanding);
  if allocated>0 then insert into public.staff_payment_allocations_v630(payment_id,earning_id,amount) values(p.id,e.id,allocated);remaining:=remaining-allocated;allocated_total:=allocated_total+allocated;end if;
  exit when remaining<=0;
 end loop;
 update public.staff_payments_v630 set advance_amount=remaining where id=p.id;
 if allocated_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'debit',allocated_total,'party_type','staff','party_id',s));end if;
 if remaining>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_advance_v630'),'debit',remaining,'party_type','staff','party_id',s));end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,case when method='cheque' then 'bank' else method end),'credit',amount));
 journal:=private.v4_journal_create(t,location,day,'Staff payment: '||member.name,'staff_payment',p.id,coalesce(data->>'reference',member.staff_code),lines);
 update public.staff_payments_v630 set journal_id=journal where id=p.id;
 update public.staff_payment_allocations_v630 set journal_id=journal where payment_id=p.id and not from_advance;
 insert into public.workforce_audit_v630(tenant_id,staff_id,action,after_data) values(t,s,'payment.post',(select to_jsonb(x) from public.staff_payments_v630 x where id=p.id));
 return p.id;
end $$;

-- Extend the existing registered GST quote with a permission-checked line override.
CREATE OR REPLACE FUNCTION public.gst_document_quote_registered_v520(p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric DEFAULT 0, p_round_off numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 d date:=coalesce(p_document_date,current_date);kind text:=lower(trim(coalesce(p_document_kind,'')));supply text:=upper(trim(coalesce(p_supply_type,case when lower(trim(coalesce(p_document_kind,'')))='purchase' then 'B2B' else 'B2C' end)));v_party_type text;
 loc public.business_locations%rowtype;reg public.gst_registrations_v520%rowtype;reg_cfg public.gst_registration_versions_v520%rowtype;party public.gst_party_registrations_v520%rowtype;
 supplier_state text;recipient_state text;pos text:=nullif(trim(coalesce(p_place_of_supply_code,'')),'');local_uses_utgst boolean:=false;interstate boolean;zero_rated boolean:=false;without_payment boolean:=false;deemed_export boolean:=false;composition_supplier boolean:=false;document_class text:='tax_invoice';
 x jsonb;prof public.gst_product_tax_profiles_v520%rowtype;variant uuid;prod record;qty numeric;price numeric;discount numeric;gross numeric;taxable numeric;v_rate numeric;cess_rate numeric;cess_unit numeric;fixed_cess numeric;applied_rate numeric;applied_cess_rate numeric;applied_cess_unit numeric;
 raw_cgst numeric;raw_sgst numeric;raw_utgst numeric;raw_igst numeric;raw_cess numeric;cgst numeric;sgst numeric;utgst numeric;igst numeric;cess numeric;rcm_cgst numeric;rcm_sgst numeric;rcm_utgst numeric;rcm_igst numeric;rcm_cess numeric;collected_tax numeric;rcm_tax numeric;line_total numeric;line_total_sum numeric:=0;calculation_rounding numeric;calculation_rounding_total numeric:=0;
 lines jsonb:='[]'::jsonb;subtotal numeric:=0;discount_total numeric:=0;taxable_total numeric:=0;cgst_total numeric:=0;sgst_total numeric:=0;utgst_total numeric:=0;igst_total numeric:=0;cess_total numeric:=0;rcm_cgst_total numeric:=0;rcm_sgst_total numeric:=0;rcm_utgst_total numeric:=0;rcm_igst_total numeric:=0;rcm_cess_total numeric:=0;grand numeric;
 warnings text[]:='{}';errors text[]:='{}';profile_source text;profile_status text;hsn text;taxability text;inclusive boolean;rcm boolean;supply_kind text;local_tax_name text;ready boolean;has_service boolean:=false;has_rcm boolean:=false;party_required boolean:=false;party_valid boolean:=false;rate_valid boolean;
begin
 if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required';end if;
 if kind not in('sale','purchase') then raise exception 'GST document kind must be sale or purchase';end if;
 v_party_type:=case when kind='sale' then 'customer' else 'supplier' end;
 if supply not in('B2B','B2C','SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP','IMPG','IMPS') then raise exception 'Invalid GST supply type';end if;
 if kind='sale' and supply in('IMPG','IMPS') then raise exception 'Import supply types are purchase-only';end if;
 if kind='purchase' and supply in('EXPWP','EXPWOP','DEXP') then raise exception 'Export/deemed-export supply types are sale-only';end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'GST quote requires at least one item';end if;
 if coalesce(p_additional_charges,0)<0 then raise exception 'Additional charges cannot be negative';end if;
 if abs(coalesce(p_round_off,0))>1.000001 then raise exception 'Round-off cannot exceed 1.00 in either direction';end if;
 select * into loc from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active;
 if not found then raise exception 'Active location not found';end if;
 select r.* into reg from public.gst_location_registrations_v520 m join public.gst_registrations_v520 r on r.id=m.registration_id and r.tenant_id=m.tenant_id where m.tenant_id=p_tenant_id and m.location_id=p_location_id and d between m.effective_from and coalesce(m.effective_to,'infinity'::date) order by m.effective_from desc limit 1;
 if reg.id is null then errors:=array_append(errors,'Location is not mapped to a GST registration for the document date');
 else
  select v.* into reg_cfg from public.gst_registration_versions_v520 v where v.tenant_id=p_tenant_id and v.registration_id=reg.id and d between v.effective_from and coalesce(v.effective_to,'infinity'::date) and v.active order by v.effective_from desc limit 1;
  if reg_cfg.id is null then errors:=array_append(errors,'Mapped GST registration has no active configuration version for the document date');end if;
 end if;
 if p_party_id is not null then
  select * into party from public.gst_party_registrations_v520 g where g.tenant_id=p_tenant_id and g.party_type=v_party_type and g.party_id=p_party_id and g.active and d between g.effective_from and coalesce(g.effective_to,'infinity'::date) order by g.effective_from desc,g.created_at desc limit 1;
  if party.id is null then warnings:=array_append(warnings,'Party has no normalized GST profile for the document date');end if;
 end if;
 if kind='sale' then
  supplier_state:=reg.state_code;recipient_state:=party.state_code;
  if recipient_state is null and p_party_id is not null then select public.gst_state_code_resolve_v520(c.state) into recipient_state from public.customers c where c.id=p_party_id and c.tenant_id=p_tenant_id;end if;
  composition_supplier:=coalesce(reg_cfg.registration_type,reg.registration_type)='composition';
 else
  supplier_state:=party.state_code;
  if supplier_state is null and p_party_id is not null then select public.gst_state_code_resolve_v520(s.state) into supplier_state from public.suppliers s where s.id=p_party_id and s.tenant_id=p_tenant_id;end if;
  recipient_state:=reg.state_code;composition_supplier:=coalesce(party.registration_type,'')='composition';
 end if;
 if kind='sale' and supply in('EXPWP','EXPWOP') then pos:='96';zero_rated:=true;without_payment:=supply='EXPWOP';party_required:=false;
 elsif kind='sale' and supply in('SEZWP','SEZWOP') then pos:=coalesce(pos,party.place_of_supply_code,party.state_code);zero_rated:=true;without_payment:=supply='SEZWOP';party_required:=true;
 elsif kind='sale' and supply='DEXP' then deemed_export:=true;pos:=coalesce(pos,party.place_of_supply_code,party.state_code,recipient_state);party_required:=true;
 elsif kind='purchase' and supply in('IMPG','IMPS') then pos:=coalesce(pos,recipient_state);party_required:=false;
 else
  if pos is null then pos:=case when kind='sale' then coalesce(party.place_of_supply_code,party.state_code,recipient_state) else coalesce(recipient_state,party.place_of_supply_code) end;end if;
 end if;
 if supplier_state is null and not(kind='purchase' and supply in('IMPG','IMPS')) then errors:=array_append(errors,'Supplier GST state is unresolved');end if;
 if recipient_state is null and kind='purchase' then errors:=array_append(errors,'Recipient/THQ GST state is unresolved');end if;
 if pos is null then errors:=array_append(errors,'Place of Supply is unresolved');end if;
 if pos is not null and not exists(select 1 from public.gst_state_master_v520 s where s.code=pos and s.active) then errors:=array_append(errors,'Place of Supply code is not an active GST state/special code');end if;
 party_required:=party_required or supply in('B2B','SEZWP','SEZWOP');
 party_valid:=party.id is not null and party.validation_status in('local_validated','provider_validated','not_applicable');
 if party_required and not party_valid then errors:=array_append(errors,'Normalized GST party profile is required for this supply type');end if;
 if kind='sale' and supply='B2B' and coalesce(party.registration_type,'') not in('registered','composition','sez') then errors:=array_append(errors,'B2B sale requires a registered recipient GST profile');end if;
 if kind='sale' and supply in('SEZWP','SEZWOP') and coalesce(party.registration_type,'')<>'sez' then errors:=array_append(errors,'SEZ supply requires an SEZ recipient profile');end if;
 if kind='purchase' and supply='B2B' and p_party_id is null then errors:=array_append(errors,'B2B purchase requires a supplier');end if;
 if kind='purchase' and supply in('IMPG','IMPS') then interstate:=true;
 elsif kind='sale' and supply in('SEZWP','SEZWOP','EXPWP','EXPWOP') then interstate:=true;
 else interstate:=case when supplier_state is null or pos is null then null else supplier_state<>pos end;
 end if;
 select coalesce(s.uses_utgst,false) into local_uses_utgst from public.gst_state_master_v520 s where s.code=supplier_state;
 local_tax_name:=case when local_uses_utgst then 'UTGST' else 'SGST' end;
 if composition_supplier then
  document_class:='bill_of_supply';
  if kind='sale' and interstate is true then errors:=array_append(errors,'Composition taxpayer cannot use this outward inter-State tax calculation path');end if;
  if kind='sale' and supply in('SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') then errors:=array_append(errors,'Composition taxpayer cannot use export/SEZ/deemed-export tax invoice path');end if;
 end if;
 for x in select value from jsonb_array_elements(p_items) loop
  begin variant:=(x->>'variant_id')::uuid;qty:=coalesce(nullif(x->>'quantity','')::numeric,0);price:=coalesce(nullif(x->>'unit_price','')::numeric,nullif(x->>'unit_cost','')::numeric,0);discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);exception when others then raise exception 'Invalid GST quote item';end;
  if variant is null or qty<=0 or price<0 or discount<0 then raise exception 'GST quote item has invalid product/quantity/price/discount';end if;
  select p.id product_id,p.name,p.item_type,p.tax_rate,pv.name variant_name,pv.sku,a.hsn_sac legacy_hsn into prod from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id left join public.product_invoice_attributes_v45 a on a.tenant_id=pv.tenant_id and a.variant_id=pv.id where pv.id=variant and pv.tenant_id=p_tenant_id and pv.status='active' and p.status='active';
  if not found then raise exception 'GST quote product is invalid or inactive';end if;
  select * into prof from private.gst_profile_for_variant_v520(p_tenant_id,variant,d);
  if prof.id is null then
   v_rate:=coalesce(prod.tax_rate,0);cess_rate:=0;cess_unit:=0;inclusive:=false;rcm:=false;taxability:='taxable';hsn:=prod.legacy_hsn;supply_kind:=case when prod.item_type='service' then 'service' else 'goods' end;profile_source:='legacy_product';profile_status:='review_required';warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');errors:=array_append(errors,'Product '||prod.sku||' has no validated GST profile; review and validate the product GST profile before compliance posting');
  else
   v_rate:=prof.gst_rate;cess_rate:=prof.cess_rate;cess_unit:=prof.cess_per_unit;inclusive:=prof.tax_inclusive;rcm:=prof.reverse_charge;taxability:=prof.taxability;hsn:=prof.hsn_sac;supply_kind:=prof.supply_kind;profile_source:=prof.source;profile_status:=prof.validation_status;
   if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');errors:=array_append(errors,'Product '||prod.sku||' GST profile requires review and validation before compliance posting');end if;
  end if;
  -- An invoice-specific adjustment never changes the product's master GST profile.
  if x ? 'thq_tax_override_v630' then
   if kind<>'sale' or not private.erp_has_permission(p_tenant_id,'sales.tax_override') then raise exception 'Invoice tax adjustment permission required' using errcode='42501';end if;
   if jsonb_typeof(x->'thq_tax_override_v630')<>'object' then raise exception 'Invalid invoice tax adjustment';end if;
   v_rate:=(x->'thq_tax_override_v630'->>'gst_rate')::numeric;
   if v_rate is null or v_rate<0 or v_rate>100 then raise exception 'Invoice GST rate must be between 0 and 100';end if;
   profile_source:='invoice_override_v630';
  end if;
  if supply_kind='service' then has_service:=true;end if;if rcm then has_rcm:=true;end if;
  if hsn is null then errors:=array_append(errors,'Product '||prod.sku||' is missing HSN/SAC');end if;
  rate_valid:=taxability<>'taxable' or exists(select 1 from public.gst_tax_rate_master_v520 tr where tr.rate=v_rate and tr.active and d between tr.effective_from and coalesce(tr.effective_to,'infinity'::date));
  if not rate_valid then errors:=array_append(errors,'Product '||prod.sku||' GST rate is not in the active GST rate master for the document date');end if;
  gross:=round(qty*price,4);if discount>gross then raise exception 'GST quote discount exceeds line value';end if;gross:=gross-discount;
  applied_rate:=v_rate;applied_cess_rate:=cess_rate;applied_cess_unit:=cess_unit;
  if taxability<>'taxable' or without_payment or(composition_supplier and not rcm) then applied_rate:=0;applied_cess_rate:=0;applied_cess_unit:=0;end if;
  fixed_cess:=round(qty*applied_cess_unit,4);
  if rcm and inclusive then warnings:=array_append(warnings,'Product '||prod.sku||' is reverse-charge and tax-inclusive; price is treated as taxable value because recipient liability is not collected by supplier');end if;
  if inclusive and not rcm and(applied_rate+applied_cess_rate)>0 then
   if gross<fixed_cess then raise exception 'Tax-inclusive line value is lower than fixed cess';end if;
   taxable:=round((gross-fixed_cess)*100/(100+applied_rate+applied_cess_rate),4);
  else taxable:=round(gross,4);end if;
  raw_cgst:=0;raw_sgst:=0;raw_utgst:=0;raw_igst:=0;raw_cess:=round(taxable*applied_cess_rate/100+fixed_cess,2);
  if applied_rate>0 then
   if interstate is true then raw_igst:=round(taxable*applied_rate/100,2);
   elsif interstate is false then raw_cgst:=round(taxable*(applied_rate/2)/100,2);if local_uses_utgst then raw_utgst:=round(taxable*(applied_rate/2)/100,2);else raw_sgst:=round(taxable*(applied_rate/2)/100,2);end if;
   end if;
  end if;
  if rcm then cgst:=0;sgst:=0;utgst:=0;igst:=0;cess:=0;rcm_cgst:=raw_cgst;rcm_sgst:=raw_sgst;rcm_utgst:=raw_utgst;rcm_igst:=raw_igst;rcm_cess:=raw_cess;
  else cgst:=raw_cgst;sgst:=raw_sgst;utgst:=raw_utgst;igst:=raw_igst;cess:=raw_cess;rcm_cgst:=0;rcm_sgst:=0;rcm_utgst:=0;rcm_igst:=0;rcm_cess:=0;end if;
  collected_tax:=cgst+sgst+utgst+igst+cess;rcm_tax:=rcm_cgst+rcm_sgst+rcm_utgst+rcm_igst+rcm_cess;
  line_total:=case when inclusive and not rcm then round(gross,2) else round(taxable+collected_tax,2) end;calculation_rounding:=round(line_total-round(taxable+collected_tax,2),2);line_total_sum:=line_total_sum+line_total;calculation_rounding_total:=calculation_rounding_total+calculation_rounding;
  subtotal:=subtotal+round(qty*price,4);discount_total:=discount_total+discount;taxable_total:=taxable_total+taxable;cgst_total:=cgst_total+cgst;sgst_total:=sgst_total+sgst;utgst_total:=utgst_total+utgst;igst_total:=igst_total+igst;cess_total:=cess_total+cess;rcm_cgst_total:=rcm_cgst_total+rcm_cgst;rcm_sgst_total:=rcm_sgst_total+rcm_sgst;rcm_utgst_total:=rcm_utgst_total+rcm_utgst;rcm_igst_total:=rcm_igst_total+rcm_igst;rcm_cess_total:=rcm_cess_total+rcm_cess;
  lines:=lines||jsonb_build_array(jsonb_build_object('variant_id',variant,'product_id',prod.product_id,'product_name',coalesce(nullif(trim(x->>'invoice_description'),''),prod.name),'variant_name',prod.variant_name,'sku',prod.sku,'supply_kind',supply_kind,'hsn_sac',hsn,'quantity',qty,'unit_price',price,'discount',discount,'taxability',taxability,'tax_inclusive',inclusive,'reverse_charge',rcm,'gst_rate',v_rate,'applied_gst_rate',applied_rate,'cess_rate',cess_rate,'applied_cess_rate',applied_cess_rate,'cess_per_unit',cess_unit,'applied_cess_per_unit',applied_cess_unit,'taxable_value',round(taxable,2),'cgst',cgst,'sgst',sgst,'utgst',utgst,'igst',igst,'cess',cess,'tax_amount',round(collected_tax,2),'rcm_cgst',rcm_cgst,'rcm_sgst',rcm_sgst,'rcm_utgst',rcm_utgst,'rcm_igst',rcm_igst,'rcm_cess',rcm_cess,'rcm_tax_amount',round(rcm_tax,2),'rcm_liability_party',case when rcm then case when kind='sale' then 'recipient' else 'thq' end else null end,'line_total',line_total,'calculation_rounding',calculation_rounding,'profile_source',profile_source,'profile_status',profile_status));
 end loop;
 if has_rcm and kind='sale' and (party.id is null or party.registration_type not in('registered','composition','sez')) then errors:=array_append(errors,'Outward reverse-charge supply requires a normalized registered recipient GST profile');end if;if has_service and p_place_of_supply_code is null and supply not in('EXPWP','EXPWOP','SEZWP','SEZWOP','IMPS') then errors:=array_append(errors,'Service supply requires explicit Place of Supply until service-specific place-of-supply rules are configured');end if;
 if coalesce(p_additional_charges,0)<>0 then errors:=array_append(errors,'Additional charges must be tax-classified before GST compliance posting; unclassified additional charges are not tax-calculated');end if;
 grand:=round(line_total_sum+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);
 ready:=cardinality(errors)=0 and reg.id is not null and reg_cfg.id is not null and not exists(select 1 from jsonb_array_elements(lines) j(value) where j.value->>'profile_status'='review_required');
 return jsonb_build_object('engine','gst_v520_document_1','document_kind',kind,'document_class',document_class,'document_date',d,'supply_type',supply,'supplier_registration_id',case when kind='sale' then reg.id else null end,'supplier_gstin',case when kind='sale' then reg.gstin else party.gstin end,'supplier_state_code',supplier_state,'recipient_registration_id',case when kind='purchase' then reg.id else null end,'recipient_gstin',case when kind='purchase' then reg.gstin else party.gstin end,'recipient_state_code',recipient_state,'party_profile_id',party.id,'place_of_supply_code',pos,'interstate',interstate,'local_tax_name',local_tax_name,'zero_rated',zero_rated,'without_payment',without_payment,'deemed_export',deemed_export,'composition_supplier',composition_supplier,'lines',lines,'totals',jsonb_build_object('subtotal',round(subtotal,2),'discount',round(discount_total,2),'taxable_value',round(taxable_total,2),'cgst',round(cgst_total,2),'sgst',round(sgst_total,2),'utgst',round(utgst_total,2),'igst',round(igst_total,2),'cess',round(cess_total,2),'tax_collected_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total,2),'rcm_cgst',round(rcm_cgst_total,2),'rcm_sgst',round(rcm_sgst_total,2),'rcm_utgst',round(rcm_utgst_total,2),'rcm_igst',round(rcm_igst_total,2),'rcm_cess',round(rcm_cess_total,2),'rcm_tax_payable_total',round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'thq_rcm_tax_payable_total',case when kind='purchase' then round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2) else 0 end,'recipient_rcm_tax_payable_total',case when kind='sale' then round(rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2) else 0 end,'government_tax_total',round(cgst_total+sgst_total+utgst_total+igst_total+cess_total+rcm_cgst_total+rcm_sgst_total+rcm_utgst_total+rcm_igst_total+rcm_cess_total,2),'additional_charges',round(coalesce(p_additional_charges,0),2),'round_off',round(coalesce(p_round_off,0),2),'calculation_rounding',round(calculation_rounding_total,2),'grand_total',grand),'ready_for_compliance',ready,'warnings',to_jsonb(warnings),'errors',to_jsonb(errors));
end $function$;


CREATE OR REPLACE FUNCTION private.v482_price_sale_items(p_tenant_id uuid, p_customer_id uuid, p_items jsonb, p_location_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  x jsonb;
  v_out jsonb:='[]'::jsonb;
  v_variant uuid;
  v_unit uuid;
  v_qty numeric;
  v_price jsonb;
  v_charge_id uuid;
  v_override numeric;
  v_batch_price jsonb;
begin
  for x in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_unit:=nullif(x->>'unit_id','')::uuid;
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);

    if v_variant is null or v_qty<=0 then
      raise exception 'Valid product and quantity are required';
    end if;

    v_price:=private.pricing_resolve_v482_internal(
      p_tenant_id,v_variant,p_customer_id,v_unit,v_qty,p_location_id
    );

    if jsonb_typeof(coalesce(x->'batches','[]'::jsonb))='array'
       and jsonb_array_length(coalesce(x->'batches','[]'::jsonb))>0 then
      v_batch_price:=private.v628_batch_price_override(
        p_tenant_id,
        v_variant,
        x->'batches',
        nullif(v_price->>'unit_id','')::uuid,
        coalesce(nullif(v_price->>'unit_price','')::numeric,0)
      );

      if coalesce((v_batch_price->>'batch_specific')::boolean,false) then
        v_price:=v_price||jsonb_build_object(
          'unit_price',(v_batch_price->>'unit_price')::numeric,
          'source','batch_price'
        );
      end if;
    end if;

    v_charge_id:=nullif(x->>'commercial_charge_id','')::uuid;
    if v_charge_id is not null then
      if not exists(
        select 1
        from public.sales_charge_catalog_v610 c
        where c.id=v_charge_id
          and c.tenant_id=p_tenant_id
          and c.service_variant_id=v_variant
          and c.active
      ) then
        raise exception 'Invalid additional-charge price override';
      end if;
      v_override:=nullif(x->>'unit_price','')::numeric;
      if v_override is null or v_override<0 then
        raise exception 'Additional charge amount cannot be negative';
      end if;
      v_price:=v_price||jsonb_build_object(
        'unit_price',v_override,
        'source','additional_charge_override'
      );
    end if;

    if coalesce((x->>'thq_manual_price_v630')::boolean,false) then
      if not(private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'sales.manage')) then raise exception 'Sales rate adjustment permission required' using errcode='42501';end if;
      v_override:=(x->>'unit_price')::numeric;
      if v_override is null or v_override<0 or v_override>1000000000000 then raise exception 'Invalid edited selling rate';end if;
      v_price:=v_price||jsonb_build_object('unit_price',v_override,'source','invoice_rate_v630');
    end if;
    if x ? 'material_cost_ids' then
      if jsonb_typeof(x->'material_cost_ids')<>'array' or jsonb_array_length(x->'material_cost_ids')=0 then raise exception 'Invalid load charge evidence';end if;
      if (select count(distinct value) from jsonb_array_elements_text(x->'material_cost_ids'))<>jsonb_array_length(x->'material_cost_ids') then raise exception 'Duplicate load cost references';end if;
      if exists(select 1 from jsonb_array_elements_text(x->'material_cost_ids') ids(value) left join public.material_load_costs_v630 c on c.id=ids.value::uuid and c.tenant_id=p_tenant_id where c.id is null or c.status<>'posted' or c.bill_amount<=0 or c.billing_variant_id<>v_variant) then raise exception 'Invalid load charge reference';end if;
      if (select count(distinct c.load_id) from public.material_load_costs_v630 c where c.tenant_id=p_tenant_id and c.id in(select value::uuid from jsonb_array_elements_text(x->'material_cost_ids')))<>1 then raise exception 'Load charges must belong to one load';end if;
      if exists(select 1 from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id where c.tenant_id=p_tenant_id and c.id in(select value::uuid from jsonb_array_elements_text(x->'material_cost_ids')) and (l.location_id<>p_location_id or l.customer_id is distinct from p_customer_id or l.status<>'completed')) then raise exception 'Load charge does not match the sale customer and location';end if;
      select sum(c.bill_amount) into v_override from public.material_load_costs_v630 c where c.tenant_id=p_tenant_id and c.id in(select value::uuid from jsonb_array_elements_text(x->'material_cost_ids'));
      if v_qty<>1 or (x->>'unit_price')::numeric<>v_override then raise exception 'Load charge amount differs from recorded charges';end if;
      v_price:=v_price||jsonb_build_object('unit_price',v_override,'source','load_charge_v630');
    end if;
    v_out:=v_out||jsonb_build_array(
      x||jsonb_build_object(
        'unit_id',v_price->>'unit_id',
        'unit_price',(v_price->>'unit_price')::numeric,
        '_pricing_source',v_price->>'source',
        '_price_list_id',v_price->>'price_list_id',
        '_price_list_name',v_price->>'price_list_name'
      )
    );
  end loop;

  return v_out;
end
$function$
;


CREATE OR REPLACE FUNCTION public.gst_client_sale_create_v630(p_tenant_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_payment_allocations jsonb, p_notes text, p_location_id uuid, p_device_id uuid, p_request_id text, p_supply_type text, p_place_of_supply_code text, p_charge_selections jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
begin
 perform public.client_sale_quote_v630(p_tenant_id,p_customer_id,p_sale_date,p_items,p_location_id,p_device_id,p_supply_type,p_place_of_supply_code,p_charge_selections,null);
 return public.gst_client_sale_create_v611(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
end $function$;

-- These tables are intentionally accessible only through their guarded RPCs.
do $security$
declare relation text;f record;
begin
 foreach relation in array array['staff_members_v630','staff_attendance_v630','staff_earnings_v630','staff_payments_v630','staff_payment_allocations_v630','material_load_costs_v630','material_load_cost_payments_v630','material_load_delivery_v630','material_load_sale_snapshots_v630','material_load_requests_v630','workforce_audit_v630'] loop
  execute format('alter table public.%I enable row level security',relation);
  execute format('revoke all on public.%I from public,anon,authenticated',relation);
  execute format('grant all on public.%I to service_role',relation);
  execute format('drop policy if exists rpc_only on public.%I',relation);
  execute format('create policy rpc_only on public.%I for all to authenticated using(false) with check(false)',relation);
 end loop;
 for f in select p.oid::regprocedure as signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.proname like '%_v630' and n.nspname in('public','private') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end $security$;
