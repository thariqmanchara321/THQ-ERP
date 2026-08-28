-- FLEXI ERP V3.1 - Production + Transport/Service modules.

create table if not exists public.production_recipes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  tracking_code text,
  name text not null,
  output_variant_id uuid not null,
  output_quantity numeric(18,4) not null default 1 check(output_quantity>0),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_production_recipes_tracking on public.production_recipes(tenant_id,tracking_code) where tracking_code is not null;
create index if not exists idx_production_recipes_tenant on public.production_recipes(tenant_id,active,name);
alter table public.production_recipes enable row level security;
revoke all on public.production_recipes from anon,authenticated;

create table if not exists public.production_recipe_items (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.production_recipes(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  input_variant_id uuid not null,
  quantity numeric(18,4) not null check(quantity>0),
  waste_percent numeric(9,4) not null default 0 check(waste_percent>=0),
  unique(recipe_id,input_variant_id)
);
create index if not exists idx_production_recipe_items_recipe on public.production_recipe_items(recipe_id);
alter table public.production_recipe_items enable row level security;
revoke all on public.production_recipe_items from anon,authenticated;

create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  tracking_code text,
  recipe_id uuid not null references public.production_recipes(id) on delete restrict,
  run_number text not null,
  location_id uuid references public.business_locations(id) on delete set null,
  planned_batches numeric(18,4) not null check(planned_batches>0),
  status text not null default 'started' check(status in ('started','completed','cancelled')),
  notes text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  unique(tenant_id,run_number)
);
create unique index if not exists ux_production_runs_tracking on public.production_runs(tenant_id,tracking_code) where tracking_code is not null;
create index if not exists idx_production_runs_tenant on public.production_runs(tenant_id,started_at desc);
alter table public.production_runs enable row level security;
revoke all on public.production_runs from anon,authenticated;

create or replace function private.production_recipe_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'production_recipes','BOM'); end if; return new;
end $$;
drop trigger if exists trg_production_recipe_tracking on public.production_recipes;
create trigger trg_production_recipe_tracking before insert on public.production_recipes for each row execute function private.production_recipe_tracking();
drop trigger if exists trg_production_recipe_immutable on public.production_recipes;
create trigger trg_production_recipe_immutable before update of tracking_code on public.production_recipes for each row execute function private.prevent_tracking_code_change();

create or replace function private.production_run_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'production_runs','RUN'); end if;
  if new.run_number is null or trim(new.run_number)='' then new.run_number:='PROD-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(new.id::text,'-',''),1,5)); end if;
  return new;
end $$;
drop trigger if exists trg_production_run_tracking on public.production_runs;
create trigger trg_production_run_tracking before insert on public.production_runs for each row execute function private.production_run_tracking();
drop trigger if exists trg_production_run_immutable on public.production_runs;
create trigger trg_production_run_immutable before update of tracking_code on public.production_runs for each row execute function private.prevent_tracking_code_change();

create or replace function public.production_recipes_list(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'tracking_code',r.tracking_code,'name',r.name,'output_variant_id',r.output_variant_id,
    'output_quantity',r.output_quantity,'notes',r.notes,'active',r.active,
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'input_variant_id',i.input_variant_id,'quantity',i.quantity,'waste_percent',i.waste_percent) order by i.id) from public.production_recipe_items i where i.recipe_id=r.id),'[]'::jsonb)
  ) order by r.name),'[]'::jsonb) into v from public.production_recipes r where r.tenant_id=p_tenant_id;
  return v;
end $$;
grant execute on function public.production_recipes_list(uuid) to authenticated;

create or replace function public.production_recipe_save(
  p_tenant_id uuid,p_recipe_id uuid,p_name text,p_output_variant_id uuid,p_output_quantity numeric,p_notes text,p_active boolean,p_items jsonb
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; x jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'production.manage') then raise exception 'Permission denied'; end if;
  if trim(coalesce(p_name,''))='' or coalesce(p_output_quantity,0)<=0 then raise exception 'Invalid recipe'; end if;
  if p_recipe_id is null then
    insert into public.production_recipes(tenant_id,name,output_variant_id,output_quantity,notes,active)
    values(p_tenant_id,trim(p_name),p_output_variant_id,p_output_quantity,nullif(trim(p_notes),''),coalesce(p_active,true)) returning id into v_id;
  else
    update public.production_recipes set name=trim(p_name),output_variant_id=p_output_variant_id,output_quantity=p_output_quantity,notes=nullif(trim(p_notes),''),active=coalesce(p_active,true),updated_at=now()
    where id=p_recipe_id and tenant_id=p_tenant_id returning id into v_id;
    if v_id is null then raise exception 'Recipe not found'; end if;
    delete from public.production_recipe_items where recipe_id=v_id;
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception 'Recipe items must be array'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    if coalesce((x->>'quantity')::numeric,0)<=0 then continue; end if;
    insert into public.production_recipe_items(recipe_id,tenant_id,input_variant_id,quantity,waste_percent)
    values(v_id,p_tenant_id,(x->>'input_variant_id')::uuid,(x->>'quantity')::numeric,coalesce(nullif(x->>'waste_percent','')::numeric,0));
  end loop;
  perform private.business_audit_write(p_tenant_id,'save','production_recipe',v_id,null,null,jsonb_build_object('name',p_name));
  return v_id;
end $$;
grant execute on function public.production_recipe_save(uuid,uuid,text,uuid,numeric,text,boolean,jsonb) to authenticated;

create or replace function public.production_runs_list(p_tenant_id uuid,p_limit integer default 200)
returns table(id uuid,tracking_code text,run_number text,recipe_id uuid,recipe_name text,location_id uuid,location_name text,planned_batches numeric,status text,notes text,started_at timestamptz,completed_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query select pr.id,pr.tracking_code,pr.run_number,pr.recipe_id,r.name,pr.location_id,l.name,pr.planned_batches,pr.status,pr.notes,pr.started_at,pr.completed_at
  from public.production_runs pr join public.production_recipes r on r.id=pr.recipe_id left join public.business_locations l on l.id=pr.location_id
  where pr.tenant_id=p_tenant_id order by pr.started_at desc limit greatest(1,least(coalesce(p_limit,200),1000));
end $$;
grant execute on function public.production_runs_list(uuid,integer) to authenticated;

create or replace function public.production_run_start(p_tenant_id uuid,p_recipe_id uuid,p_location_id uuid,p_batches numeric,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_run text;v_tracking text;v_recipe public.production_recipes%rowtype;v_items jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'production.run') and not private.erp_has_permission(p_tenant_id,'production.manage') then raise exception 'Permission denied'; end if;
  if coalesce(p_batches,0)<=0 then raise exception 'Batch quantity must be positive'; end if;
  select * into v_recipe from public.production_recipes where id=p_recipe_id and tenant_id=p_tenant_id and active;
  if v_recipe.id is null then raise exception 'Recipe not found'; end if;
  insert into public.production_runs(id,tenant_id,recipe_id,run_number,location_id,planned_batches,notes,created_by)
  values(v_id,p_tenant_id,p_recipe_id,'',p_location_id,p_batches,nullif(trim(p_notes),''),auth.uid()) returning run_number,tracking_code into v_run,v_tracking;
  select coalesce(jsonb_agg(jsonb_build_object('variant_id',i.input_variant_id,'quantity',i.quantity*p_batches*(1+i.waste_percent/100))),'[]'::jsonb)
  into v_items from public.production_recipe_items i where i.recipe_id=p_recipe_id;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by) values(p_tenant_id,'production_run',v_id,p_location_id,auth.uid()) on conflict do nothing;
  return jsonb_build_object('run_id',v_id,'run_number',v_run,'tracking_code',v_tracking,'output_variant_id',v_recipe.output_variant_id,'output_quantity',v_recipe.output_quantity*p_batches,'raw_materials',v_items);
end $$;
grant execute on function public.production_run_start(uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.production_run_complete(p_tenant_id uuid,p_run_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'production.run') and not private.erp_has_permission(p_tenant_id,'production.manage') then raise exception 'Permission denied'; end if;
  update public.production_runs set status='completed',completed_at=now() where id=p_run_id and tenant_id=p_tenant_id and status='started';
  if not found then raise exception 'Production run not found or already closed'; end if;
  perform private.business_audit_write(p_tenant_id,'complete','production_run',p_run_id,null,null,'{}'::jsonb);
end $$;
grant execute on function public.production_run_complete(uuid,uuid) to authenticated;

-- Transport / taxi / truck service records.
create table if not exists public.service_vehicles (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,tracking_code text,
  registration_number text not null,vehicle_type text,make_model text,capacity numeric(18,4),capacity_unit text,driver_name text,driver_phone text,active boolean not null default true,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,registration_number)
);
create unique index if not exists ux_service_vehicles_tracking on public.service_vehicles(tenant_id,tracking_code) where tracking_code is not null;
alter table public.service_vehicles enable row level security;revoke all on public.service_vehicles from anon,authenticated;

create table if not exists public.service_jobs (
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,tracking_code text,job_number text not null,
  location_id uuid references public.business_locations(id) on delete set null,customer_id uuid,vehicle_id uuid references public.service_vehicles(id) on delete set null,
  service_date date not null default current_date,from_location text,to_location text,distance_km numeric(18,3) not null default 0,
  quantity numeric(18,4) not null default 0,quantity_unit text,rate numeric(18,2) not null default 0,total_amount numeric(18,2) not null default 0,
  notes text,status text not null default 'completed' check(status in ('planned','in_progress','completed','cancelled')),sale_id uuid,
  created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,job_number)
);
create unique index if not exists ux_service_jobs_tracking on public.service_jobs(tenant_id,tracking_code) where tracking_code is not null;
create index if not exists idx_service_jobs_tenant_date on public.service_jobs(tenant_id,service_date desc);
alter table public.service_jobs enable row level security;revoke all on public.service_jobs from anon,authenticated;

create or replace function private.service_vehicle_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'service_vehicles','VEH'); end if; return new; end $$;
drop trigger if exists trg_service_vehicle_tracking on public.service_vehicles;create trigger trg_service_vehicle_tracking before insert on public.service_vehicles for each row execute function private.service_vehicle_tracking();
create or replace function private.service_job_tracking() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if new.tracking_code is null then new.tracking_code:=private.next_tracking_code(new.tenant_id,'service_jobs','JOB'); end if; if new.job_number is null or trim(new.job_number)='' then new.job_number:='JOB-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(new.id::text,'-',''),1,5)); end if; return new; end $$;
drop trigger if exists trg_service_job_tracking on public.service_jobs;create trigger trg_service_job_tracking before insert on public.service_jobs for each row execute function private.service_job_tracking();

create or replace function public.service_vehicles_list(p_tenant_id uuid)
returns setof public.service_vehicles language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if; return query select * from public.service_vehicles where tenant_id=p_tenant_id order by active desc,registration_number; end $$;
grant execute on function public.service_vehicles_list(uuid) to authenticated;

create or replace function public.service_vehicle_save(p_tenant_id uuid,p_vehicle_id uuid,p_registration_number text,p_vehicle_type text,p_make_model text,p_capacity numeric,p_capacity_unit text,p_driver_name text,p_driver_phone text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;if not private.erp_has_permission(p_tenant_id,'transport_service.manage') then raise exception 'Permission denied'; end if;
  if p_vehicle_id is null then insert into public.service_vehicles(tenant_id,registration_number,vehicle_type,make_model,capacity,capacity_unit,driver_name,driver_phone,active) values(p_tenant_id,upper(trim(p_registration_number)),nullif(trim(p_vehicle_type),''),nullif(trim(p_make_model),''),p_capacity,nullif(trim(p_capacity_unit),''),nullif(trim(p_driver_name),''),nullif(trim(p_driver_phone),''),coalesce(p_active,true)) returning id into v_id;
  else update public.service_vehicles set registration_number=upper(trim(p_registration_number)),vehicle_type=nullif(trim(p_vehicle_type),''),make_model=nullif(trim(p_make_model),''),capacity=p_capacity,capacity_unit=nullif(trim(p_capacity_unit),''),driver_name=nullif(trim(p_driver_name),''),driver_phone=nullif(trim(p_driver_phone),''),active=coalesce(p_active,true),updated_at=now() where id=p_vehicle_id and tenant_id=p_tenant_id returning id into v_id; end if;
  if v_id is null then raise exception 'Vehicle not found'; end if;return v_id;
end $$;
grant execute on function public.service_vehicle_save(uuid,uuid,text,text,text,numeric,text,text,text,boolean) to authenticated;

create or replace function public.service_jobs_list(p_tenant_id uuid,p_limit integer default 300)
returns table(id uuid,tracking_code text,job_number text,service_date date,location_id uuid,location_name text,customer_id uuid,customer_name text,vehicle_id uuid,registration_number text,from_location text,to_location text,distance_km numeric,quantity numeric,quantity_unit text,rate numeric,total_amount numeric,notes text,status text,sale_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query select j.id,j.tracking_code,j.job_number,j.service_date,j.location_id,l.name,j.customer_id,c.name,j.vehicle_id,v.registration_number,j.from_location,j.to_location,j.distance_km,j.quantity,j.quantity_unit,j.rate,j.total_amount,j.notes,j.status,j.sale_id
  from public.service_jobs j left join public.business_locations l on l.id=j.location_id left join public.customers c on c.id=j.customer_id left join public.service_vehicles v on v.id=j.vehicle_id
  where j.tenant_id=p_tenant_id order by j.service_date desc,j.created_at desc limit greatest(1,least(coalesce(p_limit,300),2000));
end $$;
grant execute on function public.service_jobs_list(uuid,integer) to authenticated;

create or replace function public.service_job_create(p_tenant_id uuid,p_location_id uuid,p_customer_id uuid,p_vehicle_id uuid,p_service_date date,p_from_location text,p_to_location text,p_distance_km numeric,p_quantity numeric,p_quantity_unit text,p_rate numeric,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid:=gen_random_uuid();v_job text;v_tracking text;v_total numeric; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;if not private.erp_has_permission(p_tenant_id,'transport_service.create') and not private.erp_has_permission(p_tenant_id,'transport_service.manage') then raise exception 'Permission denied'; end if;
  v_total:=round(coalesce(p_quantity,0)*coalesce(p_rate,0),2);
  insert into public.service_jobs(id,tenant_id,job_number,location_id,customer_id,vehicle_id,service_date,from_location,to_location,distance_km,quantity,quantity_unit,rate,total_amount,notes,created_by)
  values(v_id,p_tenant_id,'',p_location_id,p_customer_id,p_vehicle_id,coalesce(p_service_date,current_date),nullif(trim(p_from_location),''),nullif(trim(p_to_location),''),coalesce(p_distance_km,0),coalesce(p_quantity,0),nullif(trim(p_quantity_unit),''),coalesce(p_rate,0),v_total,nullif(trim(p_notes),''),auth.uid()) returning job_number,tracking_code into v_job,v_tracking;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by) values(p_tenant_id,'service_job',v_id,p_location_id,auth.uid()) on conflict do nothing;
  return jsonb_build_object('job_id',v_id,'job_number',v_job,'tracking_code',v_tracking,'total_amount',v_total);
end $$;
grant execute on function public.service_job_create(uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text) to authenticated;

create or replace function public.service_job_link_sale(p_tenant_id uuid,p_job_id uuid,p_sale_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;if not private.erp_has_permission(p_tenant_id,'transport_service.create') and not private.erp_has_permission(p_tenant_id,'transport_service.manage') then raise exception 'Permission denied'; end if;
  if not exists(select 1 from public.sales where id=p_sale_id and tenant_id=p_tenant_id) then raise exception 'Sale not found'; end if;
  update public.service_jobs set sale_id=p_sale_id,status='completed',updated_at=now() where id=p_job_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.service_job_link_sale(uuid,uuid,uuid) to authenticated;

select 'V3.1 production/service ready' as status;

-- Atomic production posting through the already-existing protected inventory adjustment engine.
-- If any raw-material deduction or finished-good addition fails, PostgreSQL rolls the whole call back.
create or replace function public.production_run_execute(
  p_tenant_id uuid,p_recipe_id uuid,p_location_id uuid,p_batches numeric,p_notes text
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_run jsonb;v_run_id uuid;v_run_number text;v_output uuid;v_output_qty numeric;x jsonb;begin
  v_run:=public.production_run_start(p_tenant_id,p_recipe_id,p_location_id,p_batches,p_notes);
  v_run_id:=(v_run->>'run_id')::uuid;v_run_number:=v_run->>'run_number';v_output:=(v_run->>'output_variant_id')::uuid;v_output_qty:=(v_run->>'output_quantity')::numeric;
  for x in select * from jsonb_array_elements(v_run->'raw_materials') loop
    perform public.inventory_adjust_stock(p_tenant_id,(x->>'variant_id')::uuid,-((x->>'quantity')::numeric),'Production raw material • '||v_run_number);
  end loop;
  perform public.inventory_adjust_stock(p_tenant_id,v_output,v_output_qty,'Production finished goods • '||v_run_number);
  perform public.production_run_complete(p_tenant_id,v_run_id);
  return v_run || jsonb_build_object('status','completed');
end $$;
grant execute on function public.production_run_execute(uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.service_job_link_sale_by_reference(p_tenant_id uuid,p_job_id uuid,p_sale_number text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_sale_id uuid;begin
  select id into v_sale_id from public.sales where tenant_id=p_tenant_id and sale_number=p_sale_number;
  if v_sale_id is null then raise exception 'Sale not found';end if;
  perform public.service_job_link_sale(p_tenant_id,p_job_id,v_sale_id);
end $$;
grant execute on function public.service_job_link_sale_by_reference(uuid,uuid,text) to authenticated;
