-- FLEXI ERP V4.4
-- Client-owner invoice template management and customization.
begin;


-- V4.4 moves invoice design into the Client owner/settings experience.
-- Keep the module available to every existing business/plan; authorization is
-- still enforced by settings.manage / owner checks inside the write RPC.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select t.id,'invoice_templates',true from public.tenants t where coalesce(t.status,'active') <> 'deleted'
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.subscription_plan_modules(plan_id,module_key)
select id,'invoice_templates' from public.subscription_plans
on conflict do nothing;

create or replace function public.tenant_invoice_templates_list_v44(p_tenant_id uuid,p_paper_type text default null)
returns table(
  template_id uuid,template_key text,template_name text,paper_type text,description text,
  base_config jsonb,selected boolean,overrides jsonb,effective_config jsonb,sample_logo_key text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select it.id,it.key::text,it.name::text,it.paper_type::text,it.description::text,it.config,
    (tit.template_id=it.id),coalesce(tit.overrides,'{}'::jsonb),it.config||coalesce(tit.overrides,'{}'::jsonb),it.sample_logo_key::text
  from public.invoice_templates it
  left join public.tenant_invoice_templates tit on tit.tenant_id=p_tenant_id and tit.paper_type=it.paper_type
  where it.is_active and (p_paper_type is null or it.paper_type=p_paper_type)
  order by it.paper_type,(tit.template_id=it.id) desc,it.is_system desc,it.name;
end $$;
grant execute on function public.tenant_invoice_templates_list_v44(uuid,text) to authenticated;

create or replace function public.tenant_invoice_template_save_v44(
  p_tenant_id uuid,p_paper_type text,p_template_id uuid,p_overrides jsonb
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_paper_type not in('a4','80mm') then raise exception 'Invalid paper type';end if;
  if not exists(select 1 from public.invoice_templates where id=p_template_id and paper_type=p_paper_type and is_active) then raise exception 'Invoice template not found';end if;
  insert into public.tenant_invoice_templates(tenant_id,paper_type,template_id,overrides,updated_at,updated_by)
  values(p_tenant_id,p_paper_type,p_template_id,coalesce(p_overrides,'{}'::jsonb),now(),auth.uid())
  on conflict(tenant_id,paper_type) do update set template_id=excluded.template_id,overrides=excluded.overrides,updated_at=now(),updated_by=auth.uid();
  perform private.business_audit_write(p_tenant_id,'invoice_template.save','invoice_template',p_template_id,p_paper_type,null,jsonb_build_object('paper_type',p_paper_type,'overrides',coalesce(p_overrides,'{}'::jsonb)));
end $$;
grant execute on function public.tenant_invoice_template_save_v44(uuid,text,uuid,jsonb) to authenticated;

commit;
select 'Flexi ERP V4.4 client invoice designer ready' as status;
