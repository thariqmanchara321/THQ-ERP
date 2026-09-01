-- THQ ERP v4.9.5 — universal searchable selectors and output audit.
begin;

create table if not exists public.document_output_events_v495(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  location_id uuid references public.business_locations(id) on delete set null,
  output_type text not null check(output_type in('print','pdf','xlsx','csv')),
  document_type text not null,
  document_id uuid,
  reference text,
  created_at timestamptz not null default now()
);
create index if not exists idx_document_output_events_v495 on public.document_output_events_v495(tenant_id,created_at desc);
alter table public.document_output_events_v495 enable row level security;
revoke all on public.document_output_events_v495 from anon,authenticated;

create or replace function public.document_output_log_v495(
  p_tenant_id uuid,p_output_type text,p_document_type text,p_document_id uuid default null,p_reference text default null,p_location_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_output_type not in('print','pdf','xlsx','csv') then raise exception 'Invalid output type';end if;
  insert into public.document_output_events_v495(tenant_id,user_id,location_id,output_type,document_type,document_id,reference)
  values(p_tenant_id,auth.uid(),p_location_id,p_output_type,trim(p_document_type),p_document_id,nullif(trim(coalesce(p_reference,'')),'')) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.document_output_log_v495(uuid,text,text,uuid,text,uuid) to authenticated;

create or replace function public.selector_search_v495(
  p_tenant_id uuid,p_entity text,p_query text default '',p_location_id uuid default null,p_limit integer default 50
) returns table(id uuid,label text,subtitle text,search_code text,match_rank integer)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:=lower(trim(coalesce(p_query,''))); lim integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_entity='customer' then
    return query
    select c.id,c.name,
      concat_ws(' • ',nullif(c.tracking_code,''),nullif(c.phone,''),nullif(c.tax_number,''))::text,
      concat_ws(' ',c.name,c.tracking_code,c.phone,c.email,c.tax_number)::text,
      case when q='' then 0 when lower(c.name) like q||'%' or lower(coalesce(c.tracking_code,'')) like q||'%' or lower(coalesce(c.phone,'')) like q||'%' then 0 else 1 end
    from public.customers c where c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
      and (q='' or lower(concat_ws(' ',c.name,c.tracking_code,c.phone,c.email,c.tax_number)) like '%'||q||'%')
    order by 5,c.name limit lim;
  elsif p_entity='supplier' then
    return query
    select s.id,s.name,
      concat_ws(' • ',nullif(s.tracking_code,''),nullif(s.phone,''),nullif(s.tax_number,''))::text,
      concat_ws(' ',s.name,s.tracking_code,s.phone,s.email,s.tax_number)::text,
      case when q='' then 0 when lower(s.name) like q||'%' or lower(coalesce(s.tracking_code,'')) like q||'%' or lower(coalesce(s.phone,'')) like q||'%' then 0 else 1 end
    from public.suppliers s where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active'
      and (q='' or lower(concat_ws(' ',s.name,s.tracking_code,s.phone,s.email,s.tax_number)) like '%'||q||'%')
    order by 5,s.name limit lim;
  elsif p_entity='product' then
    return query
    select pv.id,p.name,
      concat_ws(' • ',nullif(pv.sku,''),nullif(pv.barcode,''),nullif(pv.part_number,''))::text,
      concat_ws(' ',p.name,pv.variant_name,pv.sku,pv.barcode,pv.part_number)::text,
      case when q='' then 0 when lower(p.name) like q||'%' or lower(coalesce(pv.sku,'')) like q||'%' or lower(coalesce(pv.barcode,'')) like q||'%' or lower(coalesce(pv.part_number,'')) like q||'%' then 0 else 1 end
    from public.product_variants pv join public.products p on p.id=pv.product_id
    where p.tenant_id=p_tenant_id
      and (q='' or lower(concat_ws(' ',p.name,pv.variant_name,pv.sku,pv.barcode,pv.part_number)) like '%'||q||'%')
    order by 5,p.name,pv.sku limit lim;
  elsif p_entity='account' then
    return query
    select a.id,a.name,concat_ws(' • ',a.code,a.account_type)::text,concat_ws(' ',a.code,a.name,a.account_type)::text,
      case when q='' then 0 when lower(a.code) like q||'%' or lower(a.name) like q||'%' then 0 else 1 end
    from public.accounting_accounts a where a.tenant_id=p_tenant_id and a.active
      and (q='' or lower(concat_ws(' ',a.code,a.name,a.account_type)) like '%'||q||'%')
    order by 5,a.code limit lim;
  elsif p_entity='location' then
    return query
    select l.id,l.name,concat_ws(' • ',l.location_code,l.city,l.state)::text,concat_ws(' ',l.location_code,l.name,l.city,l.state,l.postal_code)::text,
      case when q='' then 0 when lower(l.location_code) like q||'%' or lower(l.name) like q||'%' then 0 else 1 end
    from public.business_locations l where l.tenant_id=p_tenant_id and l.active
      and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
      and (q='' or lower(concat_ws(' ',l.location_code,l.name,l.city,l.state,l.postal_code)) like '%'||q||'%')
    order by 5,l.location_code limit lim;
  else
    raise exception 'Unsupported selector entity %',p_entity;
  end if;
end $$;
grant execute on function public.selector_search_v495(uuid,text,text,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(200,'4.9.5','Search & Output API','Starts-with ranked selector search for products/parties/accounts/locations plus common print/download output auditing.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.5 migration 200 applied' as status;
