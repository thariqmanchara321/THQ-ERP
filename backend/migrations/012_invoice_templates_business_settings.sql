-- Flexi ERP V3: editable invoice templates + sample A4 and 80mm designs.
create table if not exists public.invoice_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  paper_type text not null check(paper_type in ('a4','80mm')),
  description text,
  config jsonb not null default '{}'::jsonb,
  sample_logo_key text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.invoice_templates enable row level security;
drop policy if exists invoice_templates_read on public.invoice_templates;
create policy invoice_templates_read on public.invoice_templates for select to authenticated using(is_active or private.platform_v2_is_admin());
revoke insert,update,delete on public.invoice_templates from authenticated;
grant select on public.invoice_templates to authenticated;

insert into public.invoice_templates(key,name,paper_type,description,config,sample_logo_key,is_system) values
('a4_classic_gst','A4 Classic GST','a4','Clean GST invoice for A4 printers',jsonb_build_object('show_logo',true,'show_gstin',true,'show_phone',true,'show_address',true,'show_hsn',true,'show_tax_breakup',true,'accent','indigo','footer','Thank you for your business'),'flexi_mark',true),
('a4_modern_gst','A4 Modern GST','a4','Modern A4 invoice with strong totals section',jsonb_build_object('show_logo',true,'show_gstin',true,'show_phone',true,'show_address',true,'show_hsn',true,'show_tax_breakup',true,'accent','teal','footer','Goods once sold are subject to store policy'),'flexi_store',true),
('80mm_compact_gst','80mm Compact GST','80mm','Compact thermal GST receipt',jsonb_build_object('show_logo',false,'show_gstin',true,'show_phone',true,'show_address',false,'show_hsn',false,'show_tax_breakup',true,'accent','mono','footer','Thank you • Visit again'),'flexi_mark',true),
('80mm_detailed','80mm Detailed','80mm','Detailed thermal receipt with item tax',jsonb_build_object('show_logo',false,'show_gstin',true,'show_phone',true,'show_address',true,'show_hsn',false,'show_tax_breakup',true,'accent','mono','footer','Computer generated invoice'),'flexi_store',true)
on conflict(key) do update set name=excluded.name,paper_type=excluded.paper_type,description=excluded.description,config=excluded.config,sample_logo_key=excluded.sample_logo_key,is_system=true,is_active=true;

create table if not exists public.tenant_invoice_templates (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  paper_type text not null check(paper_type in ('a4','80mm')),
  template_id uuid not null references public.invoice_templates(id),
  overrides jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key(tenant_id,paper_type)
);
alter table public.tenant_invoice_templates enable row level security;
drop policy if exists tenant_invoice_templates_read on public.tenant_invoice_templates;
create policy tenant_invoice_templates_read on public.tenant_invoice_templates for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.tenant_invoice_templates from authenticated;
grant select on public.tenant_invoice_templates to authenticated;

create or replace function public.platform_invoice_templates_list()
returns setof public.invoice_templates language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if; return query select * from public.invoice_templates order by paper_type,name; end $$;
grant execute on function public.platform_invoice_templates_list() to authenticated;

create or replace function public.platform_invoice_template_upsert(p_id uuid,p_key text,p_name text,p_paper_type text,p_description text,p_config jsonb,p_sample_logo_key text,p_is_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Permission denied'; end if;
  if p_paper_type not in ('a4','80mm') then raise exception 'Invalid paper type'; end if;
  if p_id is null then
    insert into public.invoice_templates(key,name,paper_type,description,config,sample_logo_key,is_system,is_active) values(trim(p_key),trim(p_name),p_paper_type,nullif(trim(p_description),''),coalesce(p_config,'{}'::jsonb),nullif(trim(p_sample_logo_key),''),false,p_is_active) returning id into v_id;
  else
    update public.invoice_templates set key=trim(p_key),name=trim(p_name),paper_type=p_paper_type,description=nullif(trim(p_description),''),config=coalesce(p_config,'{}'::jsonb),sample_logo_key=nullif(trim(p_sample_logo_key),''),is_active=p_is_active,updated_at=now() where id=p_id returning id into v_id;
  end if;
  perform private.platform_audit_write('invoice_template_upsert','invoice_template',v_id::text,null,jsonb_build_object('key',p_key,'paper_type',p_paper_type));
  return v_id;
end $$;
grant execute on function public.platform_invoice_template_upsert(uuid,text,text,text,text,jsonb,text,boolean) to authenticated;

create or replace function public.tenant_invoice_template_get(p_tenant_id uuid,p_paper_type text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select jsonb_build_object('id',it.id,'key',it.key,'name',it.name,'paper_type',it.paper_type,'config',it.config || coalesce(tit.overrides,'{}'::jsonb),'sample_logo_key',it.sample_logo_key)
  into v from public.tenant_invoice_templates tit join public.invoice_templates it on it.id=tit.template_id where tit.tenant_id=p_tenant_id and tit.paper_type=p_paper_type;
  if v is null then select jsonb_build_object('id',id,'key',key,'name',name,'paper_type',paper_type,'config',config,'sample_logo_key',sample_logo_key) into v from public.invoice_templates where paper_type=p_paper_type and is_active order by is_system desc,name limit 1; end if;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.tenant_invoice_template_get(uuid,text) to authenticated;

create or replace function public.platform_tenant_invoice_template_set(p_tenant_id uuid,p_paper_type text,p_template_id uuid,p_overrides jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  if not exists(select 1 from public.invoice_templates where id=p_template_id and paper_type=p_paper_type and is_active) then raise exception 'Template not found'; end if;
  insert into public.tenant_invoice_templates(tenant_id,paper_type,template_id,overrides,updated_at,updated_by) values(p_tenant_id,p_paper_type,p_template_id,coalesce(p_overrides,'{}'::jsonb),now(),auth.uid())
  on conflict(tenant_id,paper_type) do update set template_id=excluded.template_id,overrides=excluded.overrides,updated_at=now(),updated_by=auth.uid();
end $$;
grant execute on function public.platform_tenant_invoice_template_set(uuid,text,uuid,jsonb) to authenticated;
