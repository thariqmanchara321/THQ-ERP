-- FLEXI ERP V4 invoice/printing subsystem metadata.
begin;

create table if not exists public.printer_profiles(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid references public.business_locations(id) on delete cascade,device_id uuid references public.business_devices(id) on delete cascade,
  name text not null,paper_size text not null default '80mm' check(paper_size in('58mm','80mm','a4')),printer_name text,copies integer not null default 1 check(copies between 1 and 10),auto_print boolean not null default false,active boolean not null default true,settings jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create table if not exists public.invoice_print_events(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,entity_type text not null,entity_id uuid not null,invoice_number text,template_id uuid,printer_profile_id uuid references public.printer_profiles(id) on delete set null,
  action text not null check(action in('preview','print','pdf','email','whatsapp','reprint')),copy_number integer not null default 1,created_by uuid references auth.users(id),device_id uuid references public.business_devices(id),created_at timestamptz not null default now()
);
alter table public.printer_profiles enable row level security;alter table public.invoice_print_events enable row level security;revoke all on public.printer_profiles,public.invoice_print_events from anon,authenticated;

create or replace function public.invoice_print_profile_save_v4(p_tenant_id uuid,p_profile_id uuid,p_location_id uuid,p_device_id uuid,p_name text,p_paper_size text,p_printer_name text,p_copies integer,p_auto_print boolean,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_paper_size not in('58mm','80mm','a4') then raise exception 'Invalid paper size';end if;
  if p_profile_id is null then insert into public.printer_profiles(tenant_id,location_id,device_id,name,paper_size,printer_name,copies,auto_print,active) values(p_tenant_id,p_location_id,p_device_id,trim(p_name),p_paper_size,nullif(trim(coalesce(p_printer_name,'')),''),greatest(1,least(coalesce(p_copies,1),10)),coalesce(p_auto_print,false),coalesce(p_active,true)) returning id into v;
  else update public.printer_profiles set location_id=p_location_id,device_id=p_device_id,name=trim(p_name),paper_size=p_paper_size,printer_name=nullif(trim(coalesce(p_printer_name,'')),''),copies=greatest(1,least(coalesce(p_copies,1),10)),auto_print=coalesce(p_auto_print,false),active=coalesce(p_active,true) where id=p_profile_id and tenant_id=p_tenant_id returning id into v;end if;return v;
end $$;
grant execute on function public.invoice_print_profile_save_v4(uuid,uuid,uuid,uuid,text,text,text,integer,boolean,boolean) to authenticated;

create or replace function public.invoice_print_event_v4(p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_invoice_number text,p_template_id uuid,p_printer_profile_id uuid,p_action text,p_device_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  insert into public.invoice_print_events(tenant_id,entity_type,entity_id,invoice_number,template_id,printer_profile_id,action,copy_number,created_by,device_id)
  values(p_tenant_id,p_entity_type,p_entity_id,p_invoice_number,p_template_id,p_printer_profile_id,p_action,1+(select count(*) from public.invoice_print_events where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id and action in('print','reprint')),auth.uid(),p_device_id);
end $$;
grant execute on function public.invoice_print_event_v4(uuid,text,uuid,text,uuid,uuid,text,uuid) to authenticated;

commit;
select 'Flexi ERP V4 printing metadata ready' as status;
