-- FLEXI ERP V4
-- Branch-aware sale/purchase/product wrappers. Global proven engines remain the source of company-wide stock/cost.
begin;

create or replace function public.inventory_create_product_v4(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_name text,p_sku text,p_item_type text,p_description text,
  p_category_name text,p_brand_name text,p_barcode text,p_part_number text,p_cost_price numeric,p_selling_price numeric,
  p_list_price numeric,p_tax_rate numeric,p_reorder_level numeric,p_opening_stock numeric
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_result jsonb;v_variant uuid;v_sku text;begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Inventory manage permission required';end if;
  v_sku:=nullif(trim(coalesce(p_sku,'')),'');
  if v_sku is null then select public.inventory_next_sku(p_tenant_id) into v_sku; end if;
  select public.inventory_create_product(p_tenant_id,p_name,v_sku,p_item_type,p_description,p_category_name,p_brand_name,p_barcode,p_part_number,p_cost_price,p_selling_price,p_list_price,p_tax_rate,p_reorder_level,p_opening_stock) into v_result;
  begin v_variant:=coalesce(nullif(v_result->>'variant_id',''),nullif(v_result->>'id',''))::uuid; exception when others then v_variant:=null; end;
  if v_variant is null then select id into v_variant from public.product_variants where tenant_id=p_tenant_id and lower(sku)=lower(v_sku) order by created_at desc limit 1; end if;
  if v_variant is null then raise exception 'Could not resolve created product variant'; end if;
  perform public.inventory_location_assign_v4(p_tenant_id,p_location_id,v_variant,true,p_selling_price,p_reorder_level,null);
  if coalesce(p_opening_stock,0)<>0 then
    perform private.v4_location_stock_apply(p_tenant_id,p_location_id,v_variant,p_opening_stock,'opening','product',v_variant,null,'Opening stock',p_device_id,false);
  end if;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('variant_id',v_variant,'sku',v_sku,'location_id',p_location_id);
end $$;
grant execute on function public.inventory_create_product_v4(uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;

create or replace function public.sales_create_v4(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_result jsonb;v_sale_id uuid;v_ref text;x jsonb;v_variant uuid;v_qty numeric;v_item_type text;v_origin jsonb;begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_variant:=(x->>'variant_id')::uuid;v_qty:=coalesce((x->>'quantity')::numeric,0);
    select p.item_type into v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if v_item_type='stock' then
      if not exists(select 1 from public.location_product_settings where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant and active) then raise exception 'Product is not assigned to this store';end if;
      if coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant),0)<v_qty then raise exception 'Insufficient branch stock for %',coalesce(x->>'sku',v_variant::text);end if;
    end if;
  end loop;
  select public.sales_create(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes) into v_result;
  v_ref:=coalesce(v_result->>'sale_number',v_result->>'number');
  begin v_sale_id:=coalesce(nullif(v_result->>'sale_id',''),nullif(v_result->>'id',''))::uuid;exception when others then v_sale_id:=null;end;
  if v_sale_id is null then select id into v_sale_id from public.sales where tenant_id=p_tenant_id and sale_number=v_ref order by created_at desc limit 1;end if;
  if v_sale_id is null then raise exception 'Sale transaction could not be resolved';end if;
  perform public.document_origin_attach(p_tenant_id,'sale',v_sale_id,p_location_id,p_device_id);
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_variant:=(x->>'variant_id')::uuid;v_qty:=coalesce((x->>'quantity')::numeric,0);
    select p.item_type into v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if v_item_type='stock' then perform private.v4_location_stock_apply(p_tenant_id,p_location_id,v_variant,-v_qty,'sale','sale',v_sale_id,v_ref,'Sale',p_device_id,false); end if;
  end loop;
  begin v_origin:=public.document_origin_get(p_tenant_id,'sale',v_sale_id); exception when others then v_origin:='{}'::jsonb;end;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('sale_id',v_sale_id,'location_id',p_location_id,'device_id',p_device_id,'invoice_number',coalesce(v_origin->>'invoice_number',v_ref));
end $$;
grant execute on function public.sales_create_v4(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid) to authenticated;

create or replace function public.purchases_create_v4(
  p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,
  p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_result jsonb;v_purchase_id uuid;v_ref text;x jsonb;v_variant uuid;v_qty numeric;v_item_type text;v_origin jsonb;begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'purchases');
  select public.purchases_create(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes) into v_result;
  v_ref:=coalesce(v_result->>'purchase_number',v_result->>'number');
  begin v_purchase_id:=coalesce(nullif(v_result->>'purchase_id',''),nullif(v_result->>'id',''))::uuid;exception when others then v_purchase_id:=null;end;
  if v_purchase_id is null then select id into v_purchase_id from public.purchases where tenant_id=p_tenant_id and purchase_number=v_ref order by created_at desc limit 1;end if;
  if v_purchase_id is null then raise exception 'Purchase transaction could not be resolved';end if;
  perform public.document_origin_attach(p_tenant_id,'purchase',v_purchase_id,p_location_id,p_device_id);
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_variant:=(x->>'variant_id')::uuid;v_qty:=coalesce((x->>'quantity')::numeric,0);
    select p.item_type into v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if v_item_type='stock' then
      perform public.inventory_location_assign_v4(p_tenant_id,p_location_id,v_variant,true,null,null,null);
      perform private.v4_location_stock_apply(p_tenant_id,p_location_id,v_variant,v_qty,'purchase','purchase',v_purchase_id,v_ref,'Purchase',p_device_id,false);
    end if;
  end loop;
  begin v_origin:=public.document_origin_get(p_tenant_id,'purchase',v_purchase_id); exception when others then v_origin:='{}'::jsonb;end;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('purchase_id',v_purchase_id,'location_id',p_location_id,'device_id',p_device_id,'invoice_number',coalesce(v_origin->>'invoice_number',v_ref));
end $$;
grant execute on function public.purchases_create_v4(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid) to authenticated;

commit;
select 'Flexi ERP V4 branch transaction wrappers ready' as status;
