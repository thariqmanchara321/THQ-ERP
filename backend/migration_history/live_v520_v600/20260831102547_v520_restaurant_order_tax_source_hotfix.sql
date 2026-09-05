create or replace function public.restaurant_order_create_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_order_type text,p_table_id uuid,p_customer_id uuid,
  p_preparation_minutes integer,p_chef_note text,p_delivery_address text,p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_id uuid:=gen_random_uuid();
  v_order text;v_track text;
  x jsonb;v_priced jsonb;v_norm jsonb;
  v_variant uuid;v_unit uuid;v_qty numeric;v_factor numeric;v_unit_price numeric;v_tax numeric;
  v_discount numeric;v_source text;v_price_list uuid;v_price_name text;
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','operate');
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'restaurant.order')
     and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then
    raise exception 'Restaurant order permission denied';
  end if;
  if p_order_type not in ('dine_in','takeaway','delivery') then raise exception 'Invalid order type';end if;
  if p_order_type='dine_in' and p_table_id is null then raise exception 'Choose a table';end if;
  if p_table_id is not null and not exists(
    select 1 from public.restaurant_tables t
    where t.id=p_table_id and t.tenant_id=p_tenant_id and t.location_id=p_location_id and t.active
  ) then raise exception 'Choose a table from this store';end if;
  if p_customer_id is not null and not exists(
    select 1 from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
  ) then raise exception 'Customer is not available';end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Add at least one item';
  end if;

  v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);

  insert into public.restaurant_orders(
    id,tenant_id,location_id,device_id,order_number,order_type,table_id,customer_id,
    preparation_minutes,chef_note,delivery_address,created_by
  ) values(
    v_id,p_tenant_id,p_location_id,p_device_id,'',p_order_type,p_table_id,p_customer_id,
    greatest(coalesce(p_preparation_minutes,15),0),nullif(trim(p_chef_note),''),nullif(trim(p_delivery_address),''),auth.uid()
  ) returning order_number,tracking_code into v_order,v_track;

  for x in select value from jsonb_array_elements(v_priced) loop
    v_norm:=private.v481_normalize_line(p_tenant_id,x,'sale');
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_unit:=nullif(v_norm->>'_entered_unit_id','')::uuid;
    v_qty:=coalesce(nullif(v_norm->>'_entered_quantity','')::numeric,0);
    v_factor:=coalesce(nullif(v_norm->>'_conversion_to_base','')::numeric,1);
    v_unit_price:=coalesce(nullif(v_norm->>'_entered_unit_price','')::numeric,0);
    v_discount:=greatest(coalesce(nullif(x->>'discount_amount','')::numeric,0),0);
    v_source:=nullif(x->>'_pricing_source','');
    v_price_list:=nullif(x->>'_price_list_id','')::uuid;
    v_price_name:=nullif(x->>'_price_list_name','');

    -- Operational compatibility only.  GST v5.2 never treats this order-time
    -- tax_rate as authoritative; final tax comes from the immutable GST quote.
    select coalesce(p.tax_rate,0) into v_tax
    from public.product_variants pv
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then raise exception 'Product is not available for this business';end if;
    if v_discount > v_qty*v_unit_price then raise exception 'Restaurant item discount exceeds line value';end if;

    insert into public.restaurant_order_items(
      order_id,tenant_id,variant_id,quantity,unit_id,conversion_to_base,unit_price,
      discount_amount,tax_rate,item_note,pricing_source,price_list_id,pricing_metadata
    ) values(
      v_id,p_tenant_id,v_variant,v_qty,v_unit,v_factor,v_unit_price,
      v_discount,v_tax,nullif(trim(x->>'item_note'),''),coalesce(v_source,'product_price'),v_price_list,
      jsonb_strip_nulls(jsonb_build_object('price_list_name',v_price_name,'resolved_at',now(),'engine','v4.8.2'))
    );
  end loop;

  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by)
  values(p_tenant_id,'restaurant_order',v_id,p_location_id,p_device_id,auth.uid())
  on conflict do nothing;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','restaurant_order',v_id::text,'create');
  return jsonb_build_object('order_id',v_id,'order_number',v_order,'tracking_code',v_track,'pricing_engine','v4.8.2','restaurant_engine','v4.8.9');
end
$$;