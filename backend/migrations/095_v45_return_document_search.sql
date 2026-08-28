-- THQ V4.5
-- Fast return-document lookup for POS. Searches invoice, party, product, SKU,
-- barcode and part number while keeping the terminal inside its store scope.
begin;

create or replace function public.return_documents_search_v45(
  p_tenant_id uuid,
  p_location_id uuid,
  p_type text default 'all',
  p_query text default '',
  p_limit integer default 200
)
returns table(
  entity_type text,
  entity_id uuid,
  document_number text,
  document_date date,
  party text,
  grand_total numeric,
  status text,
  return_status text,
  location_id uuid,
  device_id uuid,
  matched_product text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  q text := '%' || lower(trim(coalesce(p_query,''))) || '%';
  lim integer := greatest(1,least(coalesce(p_limit,200),500));
begin
  if p_type not in('all','sale','purchase') then raise exception 'Invalid return search type'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_location_id is null then raise exception 'POS return search requires a store/location'; end if;
  perform private.v4_location_access(p_tenant_id,p_location_id,'view');

  return query
  select z.entity_type,z.entity_id,z.document_number,z.document_date,z.party,z.grand_total,z.status,z.return_status,z.location_id,z.device_id,z.matched_product
  from (
    select
      'sale'::text as entity_type,
      s.id as entity_id,
      s.sale_number::text as document_number,
      s.sale_date as document_date,
      c.name::text as party,
      s.grand_total,
      s.status::text as status,
      coalesce(public.transaction_return_status_v45(p_tenant_id,'sale',s.id)->>'status','not_returned') as return_status,
      o.location_id,
      o.device_id,
      (
        select concat_ws(' • ',pr.name,pv.sku,nullif(pv.barcode,''),nullif(pv.part_number,''))
        from public.sale_items si
        join public.product_variants pv on pv.id=si.variant_id
        join public.products pr on pr.id=pv.product_id
        where si.sale_id=s.id
          and (
            trim(coalesce(p_query,''))='' or lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q or
            lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        order by si.id
        limit 1
      )::text as matched_product
    from public.sales s
    join public.customers c on c.id=s.customer_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where p_type in('all','sale')
      and s.tenant_id=p_tenant_id
      and o.location_id=p_location_id
      and coalesce(s.status,'') not in('void','cancelled')
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and (
        trim(coalesce(p_query,''))='' or
        lower(coalesce(s.sale_number,'')) like q or lower(coalesce(c.name,'')) like q or
        exists(
          select 1 from public.sale_items si
          join public.product_variants pv on pv.id=si.variant_id
          join public.products pr on pr.id=pv.product_id
          where si.sale_id=s.id and (
            lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q or
            lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        )
      )

    union all

    select
      'purchase'::text,
      p.id,
      p.purchase_number::text,
      p.purchase_date,
      sp.name::text,
      p.grand_total,
      p.status::text,
      coalesce(public.transaction_return_status_v45(p_tenant_id,'purchase',p.id)->>'status','not_returned'),
      o.location_id,
      o.device_id,
      (
        select concat_ws(' • ',pr.name,pv.sku,nullif(pv.barcode,''),nullif(pv.part_number,''))
        from public.purchase_items pi
        join public.product_variants pv on pv.id=pi.variant_id
        join public.products pr on pr.id=pv.product_id
        where pi.purchase_id=p.id
          and (
            trim(coalesce(p_query,''))='' or lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q or
            lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        order by pi.id
        limit 1
      )::text
    from public.purchases p
    join public.suppliers sp on sp.id=p.supplier_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p_type in('all','purchase')
      and p.tenant_id=p_tenant_id
      and o.location_id=p_location_id
      and coalesce(p.status,'') not in('void','cancelled')
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and (
        trim(coalesce(p_query,''))='' or
        lower(coalesce(p.purchase_number,'')) like q or
        lower(coalesce(p.supplier_invoice_number,'')) like q or
        lower(coalesce(sp.name,'')) like q or
        exists(
          select 1 from public.purchase_items pi
          join public.product_variants pv on pv.id=pi.variant_id
          join public.products pr on pr.id=pv.product_id
          where pi.purchase_id=p.id and (
            lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q or
            lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        )
      )
  ) z
  order by z.document_date desc,z.document_number desc
  limit lim;
end $$;

grant execute on function public.return_documents_search_v45(uuid,uuid,text,text,integer) to authenticated;

commit;
select 'THQ V4.5 return document search ready' as status;
