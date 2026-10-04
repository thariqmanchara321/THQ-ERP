begin;
-- Append captured batch allocations to existing authorized detail responses.
-- Prices and quantities in the posted invoice are never recalculated.
create or replace function public.sales_get_detail_v628(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,private,pg_temp as $function$
declare result jsonb; items jsonb;
begin
  result:=public.sales_get_detail_v520(p_tenant_id,p_sale_id);
  select coalesce(jsonb_agg(x||jsonb_build_object('batch_allocations',coalesce((
    select jsonb_agg(jsonb_build_object(
      'batch_number',coalesce(e.metadata->>'batch_number',b.batch_number),
      'quality_label',e.metadata->>'quality_label',
      'quantity',e.quantity,
      'base_unit_code',si.unit_code,
      'rate',coalesce(nullif(e.metadata->>'selling_price_base','')::numeric,si.unit_price)
    ) order by e.created_at,e.id)
    from inventory_trace_events_v483 e
    join sale_items si on si.id=e.sale_item_id and si.tenant_id=e.tenant_id
    left join inventory_batches_v483 b on b.id=e.batch_id and b.tenant_id=e.tenant_id
    where e.tenant_id=p_tenant_id and e.sale_id=p_sale_id
      and e.sale_item_id=(x->>'item_id')::uuid and e.event_type='sale' and e.batch_id is not null
  ),'[]'::jsonb)) order by ord),'[]'::jsonb) into items
  from jsonb_array_elements(coalesce(result->'items','[]'::jsonb)) with ordinality a(x,ord);
  return jsonb_set(result,'{items}',items);
end $function$;

create or replace function public.purchases_get_detail_v628(p_tenant_id uuid,p_purchase_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,private,pg_temp as $function$
declare result jsonb; items jsonb;
begin
  result:=public.purchases_get_detail_v520(p_tenant_id,p_purchase_id);
  select coalesce(jsonb_agg(x||jsonb_build_object('batch_allocations',coalesce((
    select jsonb_agg(jsonb_build_object(
      'batch_number',coalesce(e.metadata->>'batch_number',b.batch_number),
      'quality_label',e.metadata->>'quality_label',
      'quantity',e.quantity,
      'base_unit_code',pi.unit_code,
      'rate',coalesce(nullif(e.metadata->>'purchase_cost_base','')::numeric,pi.unit_cost)
    ) order by e.created_at,e.id)
    from inventory_trace_events_v483 e
    join purchase_items pi on pi.id=e.purchase_item_id and pi.tenant_id=e.tenant_id
    left join inventory_batches_v483 b on b.id=e.batch_id and b.tenant_id=e.tenant_id
    where e.tenant_id=p_tenant_id and e.purchase_id=p_purchase_id
      and e.purchase_item_id=(x->>'item_id')::uuid and e.event_type='purchase' and e.batch_id is not null
  ),'[]'::jsonb)) order by ord),'[]'::jsonb) into items
  from jsonb_array_elements(coalesce(result->'items','[]'::jsonb)) with ordinality a(x,ord);
  return jsonb_set(result,'{items}',items);
end $function$;
revoke all on function public.sales_get_detail_v628(uuid,uuid) from public,anon;
grant execute on function public.sales_get_detail_v628(uuid,uuid) to authenticated,service_role;
revoke all on function public.purchases_get_detail_v628(uuid,uuid) from public,anon;
grant execute on function public.purchases_get_detail_v628(uuid,uuid) to authenticated,service_role;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(332,'6.2.8-batch-document-detail','Captured Batch Invoice Detail',
  'Makes captured batch/quality quantities and rates available in invoice details and printing; preserves posted document values and existing authorization.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,
  release_name=excluded.release_name,notes=excluded.notes;
commit;
