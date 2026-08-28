-- THQ ERP V4.8.2 — Barcode/QR label templates.
begin;
create table if not exists public.label_templates_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,code text not null,name text not null,
 paper_mode text not null default 'thermal' check(paper_mode in('thermal','a4')),width_mm numeric not null default 50 check(width_mm>0),height_mm numeric not null default 30 check(height_mm>0),
 columns integer not null default 1 check(columns between 1 and 6),show_business boolean not null default true,show_product boolean not null default true,show_price boolean not null default true,
 show_sku boolean not null default true,show_code_text boolean not null default true,code_mode text not null default 'barcode' check(code_mode in('barcode','qr')),
 is_default boolean not null default false,system_template boolean not null default false,active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(tenant_id,code));
create unique index if not exists ux_label_templates_v482_default on public.label_templates_v482(tenant_id) where is_default and active;
alter table public.label_templates_v482 enable row level security;
drop policy if exists label_templates_v482_read on public.label_templates_v482;
create policy label_templates_v482_read on public.label_templates_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.label_templates_v482 from authenticated;grant select on public.label_templates_v482 to authenticated;

create or replace function private.v482_seed_label_templates(p_tenant_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 insert into public.label_templates_v482(tenant_id,code,name,paper_mode,width_mm,height_mm,columns,code_mode,is_default,system_template) values
 (p_tenant_id,'THERMAL_50X30','Thermal 50 × 30 mm','thermal',50,30,1,'barcode',true,true),
 (p_tenant_id,'THERMAL_38X25','Thermal 38 × 25 mm','thermal',38,25,1,'barcode',false,true),
 (p_tenant_id,'A4_3COL','A4 • 3 Columns','a4',63,35,3,'barcode',false,true),
 (p_tenant_id,'QR_50X30','QR 50 × 30 mm','thermal',50,30,1,'qr',false,true)
 on conflict(tenant_id,code) do update set name=excluded.name,system_template=true;
end$$;
revoke all on function private.v482_seed_label_templates(uuid) from public;
do $$declare r record;begin for r in select t.id from public.tenants t loop perform private.v482_seed_label_templates(r.id);end loop;end$$;
create or replace function private.v482_seed_label_templates_trigger() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$begin perform private.v482_seed_label_templates(new.id);return new;end$$;
drop trigger if exists trg_v482_seed_label_templates on public.tenants;
create trigger trg_v482_seed_label_templates after insert on public.tenants for each row execute function private.v482_seed_label_templates_trigger();

create or replace function public.label_templates_v482(p_tenant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select to_jsonb(t) from public.label_templates_v482 t where t.tenant_id=p_tenant_id and t.active order by t.is_default desc,t.name;
end$$;
grant execute on function public.label_templates_v482(uuid) to authenticated;

create or replace function public.label_template_save_v482(p_tenant_id uuid,p_template_id uuid,p_code text,p_name text,p_paper_mode text,p_width_mm numeric,p_height_mm numeric,p_columns integer,p_show_business boolean,p_show_product boolean,p_show_price boolean,p_show_sku boolean,p_show_code_text boolean,p_code_mode text,p_is_default boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_id uuid;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if p_is_default then update public.label_templates_v482 set is_default=false,updated_at=now() where tenant_id=p_tenant_id;end if;
 if p_template_id is null then
  insert into public.label_templates_v482(tenant_id,code,name,paper_mode,width_mm,height_mm,columns,show_business,show_product,show_price,show_sku,show_code_text,code_mode,is_default,active)
  values(p_tenant_id,upper(trim(p_code)),trim(p_name),p_paper_mode,p_width_mm,p_height_mm,p_columns,p_show_business,p_show_product,p_show_price,p_show_sku,p_show_code_text,p_code_mode,p_is_default,p_active) returning id into v_id;
 else
  update public.label_templates_v482 set code=upper(trim(p_code)),name=trim(p_name),paper_mode=p_paper_mode,width_mm=p_width_mm,height_mm=p_height_mm,columns=p_columns,show_business=p_show_business,show_product=p_show_product,show_price=p_show_price,show_sku=p_show_sku,show_code_text=p_show_code_text,code_mode=p_code_mode,is_default=p_is_default,active=p_active,updated_at=now() where id=p_template_id and tenant_id=p_tenant_id returning id into v_id;
  if v_id is null then raise exception 'Label template not found';end if;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','label_template',v_id::text,'save');return v_id;
end$$;
grant execute on function public.label_template_save_v482(uuid,uuid,text,text,text,numeric,numeric,integer,boolean,boolean,boolean,boolean,boolean,text,boolean,boolean) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(132,'4.8.2','Pricing & Product Identification','Reusable thermal/A4 barcode and QR label templates.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 132 label printing applied' as status;
