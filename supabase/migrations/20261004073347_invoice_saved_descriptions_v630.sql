-- Reopened invoices use the same immutable product description shown in the quote.
-- Existing authorization, location scope and batch details remain in the base RPC.
create or replace function public.sales_get_detail_v630(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;items jsonb;
begin
 result:=public.sales_get_detail_v628(p_tenant_id,p_sale_id);
 select coalesce(jsonb_agg(x||case when saved.product_name is null then '{}'::jsonb else jsonb_build_object('product_name',saved.product_name,'hsn_sac',saved.hsn_sac,'sku',saved.sku) end order by ord),'[]'::jsonb)
 into items
 from jsonb_array_elements(coalesce(result->'items','[]'::jsonb)) with ordinality a(x,ord)
 left join lateral (
  select l.product_name,l.hsn_sac,l.sku
  from public.gst_document_line_snapshots_v520 l join public.gst_document_snapshots_v520 s on s.id=l.snapshot_id and s.tenant_id=l.tenant_id
  where s.tenant_id=p_tenant_id and s.source_type='sale' and s.source_id=p_sale_id
   and (l.source_line_id::text=x->>'item_id' or (l.source_line_id is null and l.variant_id::text=x->>'variant_id'))
  order by s.created_at desc,l.line_no limit 1
 ) saved on true;
 result:=jsonb_set(result,'{items}',items);
 return result||jsonb_build_object('material_load',coalesce((select evidence from public.material_load_sale_snapshots_v630 where tenant_id=p_tenant_id and sale_id=p_sale_id),'{}'::jsonb));
end $$;
