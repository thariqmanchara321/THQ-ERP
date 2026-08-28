-- THQ V4.5
-- Optional invoice/import attributes that do not disturb the proven V4 product schema.
begin;

create table if not exists public.product_invoice_attributes_v45(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  unit_code text,
  hsn_sac text,
  preferred_supplier_name text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key(tenant_id,variant_id)
);
alter table public.product_invoice_attributes_v45 enable row level security;
drop policy if exists product_invoice_attributes_v45_read on public.product_invoice_attributes_v45;
create policy product_invoice_attributes_v45_read on public.product_invoice_attributes_v45
for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.product_invoice_attributes_v45 from authenticated;
grant select on public.product_invoice_attributes_v45 to authenticated;

create or replace function public.inventory_bulk_create_products_v45(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_rows jsonb
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  x jsonb;v_success int:=0;v_failed int:=0;v_errors jsonb:='[]'::jsonb;v_created jsonb:='[]'::jsonb;
  v_result jsonb;v_row int:=1;v_variant uuid;
begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Inventory manage permission required';
  end if;
  for x in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_row:=v_row+1;
    begin
      if trim(coalesce(x->>'name',''))='' then raise exception 'Product name is required'; end if;
      v_result:=public.inventory_create_product_v4(
        p_tenant_id,p_location_id,p_device_id,x->>'name',nullif(trim(coalesce(x->>'sku','')),''),
        coalesce(nullif(trim(coalesce(x->>'item_type','')),''),'stock'),x->>'description',
        nullif(trim(coalesce(x->>'category','')),''),nullif(trim(coalesce(x->>'brand','')),''),
        nullif(trim(coalesce(x->>'barcode','')),''),nullif(trim(coalesce(x->>'part_number','')),''),
        coalesce(nullif(x->>'cost_price','')::numeric,0),coalesce(nullif(x->>'selling_price','')::numeric,0),
        coalesce(nullif(x->>'list_price','')::numeric,0),coalesce(nullif(x->>'tax_rate','')::numeric,0),
        coalesce(nullif(x->>'reorder_level','')::numeric,0),coalesce(nullif(x->>'opening_stock','')::numeric,0)
      );
      v_variant:=nullif(v_result->>'variant_id','')::uuid;
      if v_variant is not null then
        insert into public.product_invoice_attributes_v45(
          tenant_id,variant_id,unit_code,hsn_sac,preferred_supplier_name,metadata,updated_at,updated_by
        ) values(
          p_tenant_id,v_variant,nullif(trim(coalesce(x->>'unit','')),''),nullif(trim(coalesce(x->>'hsn_sac','')),''),
          nullif(trim(coalesce(x->>'supplier','')),''),
          jsonb_build_object('source','bulk_import_v45','store_code',nullif(trim(coalesce(x->>'store_code','')),'')),now(),auth.uid()
        ) on conflict(tenant_id,variant_id) do update set
          unit_code=excluded.unit_code,hsn_sac=excluded.hsn_sac,preferred_supplier_name=excluded.preferred_supplier_name,
          metadata=public.product_invoice_attributes_v45.metadata||excluded.metadata,updated_at=now(),updated_by=auth.uid();
      end if;
      v_success:=v_success+1;
      v_created:=v_created||jsonb_build_array(jsonb_build_object(
        'row',v_row,'name',x->>'name','sku',v_result->>'sku','variant_id',v_result->>'variant_id',
        'hsn_sac',x->>'hsn_sac','unit',x->>'unit'
      ));
    exception when others then
      v_failed:=v_failed+1;
      v_errors:=v_errors||jsonb_build_array(jsonb_build_object('row',v_row,'name',coalesce(x->>'name',''),'error',sqlerrm));
    end;
  end loop;
  perform private.business_audit_write(
    p_tenant_id,'inventory.bulk_import','inventory',null,null,p_location_id,
    jsonb_build_object('success_count',v_success,'failed_count',v_failed,'device_id',p_device_id,'format','xlsx')
  );
  return jsonb_build_object('success_count',v_success,'failed_count',v_failed,'errors',v_errors,'created',v_created,'location_id',p_location_id);
end $$;
grant execute on function public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb) to authenticated;

-- Keep the original proven detail engine, then enrich its JSON with V4.5 invoice fields.
create or replace function public.sales_get_detail_v32(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_loc uuid;v jsonb;v_items jsonb;
begin
  select location_id into v_loc from public.document_origins
  where entity_type='sale' and entity_id=p_sale_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied'; end if;
  v:=public.sales_get_detail(p_tenant_id,p_sale_id);
  select coalesce(jsonb_agg(
      i.value || jsonb_build_object(
        'hsn_sac',a.hsn_sac,
        'unit_code',coalesce(nullif(i.value->>'unit_code',''),a.unit_code),
        'preferred_supplier_name',a.preferred_supplier_name
      )
    ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value)
  left join public.product_invoice_attributes_v45 a
    on a.tenant_id=p_tenant_id and a.variant_id=nullif(i.value->>'variant_id','')::uuid;
  return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end $$;
grant execute on function public.sales_get_detail_v32(uuid,uuid) to authenticated;

commit;
select 'THQ V4.5 product invoice attributes ready' as status;
