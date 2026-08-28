-- FLEXI ERP V4 phase-2 foundations for Restaurant, Workshop and Production.
begin;

-- Restaurant extensions (only additive; existing restaurant order/KOT tables remain intact).
create table if not exists public.restaurant_order_modifiers(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,order_item_id uuid not null,modifier_name text not null,price_delta numeric not null default 0,quantity numeric not null default 1
);
create table if not exists public.restaurant_waiter_assignments(
  tenant_id uuid not null references public.tenants(id) on delete cascade,order_id uuid not null,user_id uuid not null references auth.users(id),assigned_at timestamptz not null default now(),primary key(tenant_id,order_id)
);
create table if not exists public.restaurant_table_events(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,order_id uuid,from_table_id uuid,to_table_id uuid,event_type text not null check(event_type in('transfer','merge','split')),note text,created_by uuid references auth.users(id),created_at timestamptz not null default now()
);

-- Workshop/Garage.
create table if not exists public.workshop_vehicles(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,customer_id uuid references public.customers(id) on delete set null,location_id uuid references public.business_locations(id),vehicle_number text not null,make text,model text,year integer,vin text,chassis_number text,odometer numeric,notes text,active boolean not null default true,created_at timestamptz not null default now(),unique(tenant_id,vehicle_number)
);
create table if not exists public.workshop_job_cards(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid not null references public.business_locations(id),vehicle_id uuid not null references public.workshop_vehicles(id),customer_id uuid references public.customers(id),job_number text not null,status text not null default 'open' check(status in('open','inspection','estimate','approved','in_progress','waiting_parts','ready','delivered','cancelled')),complaint text,inspection_notes text,estimated_amount numeric,estimated_delivery timestamptz,technician_user_id uuid references auth.users(id),sale_id uuid references public.sales(id),created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,job_number)
);
create table if not exists public.workshop_job_items(
  id uuid primary key default gen_random_uuid(),job_id uuid not null references public.workshop_job_cards(id) on delete cascade,item_type text not null check(item_type in('part','labour','note')),variant_id uuid references public.product_variants(id),description text not null,quantity numeric not null default 1,unit_price numeric not null default 0,technician_user_id uuid references auth.users(id),status text not null default 'planned'
);
create sequence if not exists public.workshop_job_number_seq;

-- Production phase 2 additive BOM/recipe and reservations.
create table if not exists public.production_boms(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,name text not null,output_variant_id uuid not null references public.product_variants(id),output_quantity numeric not null default 1,version integer not null default 1,active boolean not null default true,notes text,created_at timestamptz not null default now(),unique(tenant_id,name,version)
);
create table if not exists public.production_bom_items(
  id uuid primary key default gen_random_uuid(),bom_id uuid not null references public.production_boms(id) on delete cascade,variant_id uuid not null references public.product_variants(id),quantity numeric not null,wastage_percent numeric not null default 0,stage_name text
);
create table if not exists public.production_material_reservations(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid not null references public.business_locations(id),production_run_id uuid not null,variant_id uuid not null references public.product_variants(id),quantity numeric not null,status text not null default 'reserved' check(status in('reserved','consumed','released')),created_at timestamptz not null default now()
);

alter table public.restaurant_order_modifiers enable row level security;alter table public.restaurant_waiter_assignments enable row level security;alter table public.restaurant_table_events enable row level security;
alter table public.workshop_vehicles enable row level security;alter table public.workshop_job_cards enable row level security;alter table public.workshop_job_items enable row level security;alter table public.production_boms enable row level security;alter table public.production_bom_items enable row level security;alter table public.production_material_reservations enable row level security;
revoke all on public.restaurant_order_modifiers,public.restaurant_waiter_assignments,public.restaurant_table_events,public.workshop_vehicles,public.workshop_job_cards,public.workshop_job_items,public.production_boms,public.production_bom_items,public.production_material_reservations from anon,authenticated;

create or replace function public.workshop_job_create_v4(p_tenant_id uuid,p_location_id uuid,p_vehicle_id uuid,p_customer_id uuid,p_complaint text,p_estimated_delivery timestamptz,p_technician uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_id uuid:=gen_random_uuid();v_no text;begin perform private.v4_location_access(p_tenant_id,p_location_id,'operate');if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'workshop.manage') then raise exception 'Workshop permission required';end if;v_no:='JOB-'||lpad(nextval('public.workshop_job_number_seq')::text,6,'0');insert into public.workshop_job_cards(id,tenant_id,location_id,vehicle_id,customer_id,job_number,complaint,estimated_delivery,technician_user_id,created_by) values(v_id,p_tenant_id,p_location_id,p_vehicle_id,p_customer_id,v_no,trim(p_complaint),p_estimated_delivery,p_technician,auth.uid());return jsonb_build_object('job_id',v_id,'job_number',v_no);end $$;
grant execute on function public.workshop_job_create_v4(uuid,uuid,uuid,uuid,text,timestamptz,uuid) to authenticated;

commit;
select 'Flexi ERP V4 industry phase-2 foundations ready' as status;
