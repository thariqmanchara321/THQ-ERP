-- THQ ERP V4.8.1 — unit-aware sale/purchase transaction wrappers. Existing quantity columns remain BASE quantity.
begin;

alter table public.sale_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric,
 add column if not exists entered_unit_price numeric;
alter table public.purchase_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric,
 add column if not exists entered_unit_cost numeric;

alter table public.sales_return_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric;
alter table public.purchase_return_items
 add column if not exists entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
 add column if not exists entered_unit_code text,
 add column if not exists entered_quantity numeric,
 add column if not exists conversion_to_base numeric;

create or replace function private.v481_normalize_line(p_tenant_id uuid,p_item jsonb,p_mode text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_variant uuid;v_unit uuid;v_factor numeric:=1;v_qty numeric;v_price numeric;v_code text;v_step numeric:=1;v_fractional boolean:=false;begin
  v_variant:=nullif(p_item->>'variant_id','')::uuid;v_qty:=coalesce(nullif(p_item->>'quantity','')::numeric,0);
  if v_qty<=0 then raise exception 'Quantity must be greater than zero';end if;
  if nullif(p_item->>'unit_id','') is not null then v_unit:=(p_item->>'unit_id')::uuid;end if;
  if v_unit is null then select pu.unit_id into v_unit from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and ((p_mode='sale' and pu.is_default_sale) or (p_mode='purchase' and pu.is_default_purchase)) limit 1;end if;
  if v_unit is null then select pu.unit_id into v_unit from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.is_base limit 1;end if;
  select pu.conversion_to_base,u.code,pu.quantity_step,u.allow_fractional into v_factor,v_code,v_step,v_fractional
  from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id
  where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.unit_id=v_unit and pu.active
    and ((p_mode='sale' and pu.allow_sale) or (p_mode='purchase' and pu.allow_purchase));
  if v_factor is null then raise exception 'Selected unit is not enabled for this product';end if;
  v_step:=greatest(coalesce(v_step,1),0.000001);
  if not coalesce(v_fractional,false) and v_qty<>trunc(v_qty) then raise exception 'Unit % only allows whole quantities',v_code;end if;
  if abs((v_qty/v_step)-round(v_qty/v_step))>0.000001 then raise exception 'Quantity for unit % must use increments of %',v_code,v_step;end if;
  v_price:=coalesce(nullif(p_item->>case when p_mode='sale' then 'unit_price' else 'unit_cost' end,'')::numeric,0);
  if p_mode='sale' then
    return p_item||jsonb_build_object('quantity',v_qty*v_factor,'unit_price',case when v_factor=0 then v_price else v_price/v_factor end,'_entered_quantity',v_qty,'_entered_unit_id',v_unit,'_entered_unit_code',v_code,'_conversion_to_base',v_factor,'_entered_unit_price',v_price);
  end if;
  return p_item||jsonb_build_object('quantity',v_qty*v_factor,'unit_cost',case when v_factor=0 then v_price else v_price/v_factor end,'_entered_quantity',v_qty,'_entered_unit_id',v_unit,'_entered_unit_code',v_code,'_conversion_to_base',v_factor,'_entered_unit_cost',v_price);
end $$;
revoke all on function private.v481_normalize_line(uuid,jsonb,text) from public;

create or replace function private.v481_normalize_items(p_tenant_id uuid,p_items jsonb,p_mode text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v jsonb:='[]'::jsonb;v_total int;v_distinct int;begin
  select count(*),count(distinct value->>'variant_id') into v_total,v_distinct from jsonb_array_elements(coalesce(p_items,'[]'::jsonb));
  if v_total<>v_distinct then raise exception 'A product variant can appear only once per unit-aware transaction';end if;
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop v:=v||jsonb_build_array(private.v481_normalize_line(p_tenant_id,x,p_mode));end loop;
  return v;
end $$;
revoke all on function private.v481_normalize_items(uuid,jsonb,text) from public;

create or replace function public.sales_create_v481(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_items jsonb;v jsonb;v_sale uuid;x jsonb;v_variant uuid;begin
  v_items:=private.v481_normalize_items(p_tenant_id,p_items,'sale');
  v:=public.sales_create_v47(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
  v_sale:=nullif(v->>'sale_id','')::uuid;
  if v_sale is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      v_variant:=(x->>'variant_id')::uuid;
      update public.sale_items si set entered_unit_id=nullif(x->>'_entered_unit_id','')::uuid,entered_unit_code=x->>'_entered_unit_code',entered_quantity=(x->>'_entered_quantity')::numeric,conversion_to_base=(x->>'_conversion_to_base')::numeric,entered_unit_price=(x->>'_entered_unit_price')::numeric
      where si.sale_id=v_sale and si.variant_id=v_variant;
      update public.location_stock_movements m set unit_id=nullif(x->>'_entered_unit_id','')::uuid,unit_code=x->>'_entered_unit_code',display_quantity=-abs((x->>'_entered_quantity')::numeric),conversion_to_base=(x->>'_conversion_to_base')::numeric,metadata=m.metadata||jsonb_build_object('entered_unit_price',(x->>'_entered_unit_price')::numeric)
      where m.tenant_id=p_tenant_id and m.reference_type='sale' and m.reference_id=v_sale and m.variant_id=v_variant and m.movement_type='sale';
    end loop;
  end if;return v;
end $$;
grant execute on function public.sales_create_v481(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.purchases_create_v481(
 p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_items jsonb;v jsonb;v_purchase uuid;x jsonb;v_variant uuid;begin
  v_items:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
  v:=public.purchases_create_v47(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,v_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
  v_purchase:=nullif(v->>'purchase_id','')::uuid;
  if v_purchase is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      v_variant:=(x->>'variant_id')::uuid;
      update public.purchase_items pi set entered_unit_id=nullif(x->>'_entered_unit_id','')::uuid,entered_unit_code=x->>'_entered_unit_code',entered_quantity=(x->>'_entered_quantity')::numeric,conversion_to_base=(x->>'_conversion_to_base')::numeric,entered_unit_cost=(x->>'_entered_unit_cost')::numeric where pi.purchase_id=v_purchase and pi.variant_id=v_variant;
      update public.location_stock_movements m set unit_id=nullif(x->>'_entered_unit_id','')::uuid,unit_code=x->>'_entered_unit_code',display_quantity=abs((x->>'_entered_quantity')::numeric),conversion_to_base=(x->>'_conversion_to_base')::numeric,metadata=m.metadata||jsonb_build_object('entered_unit_cost',(x->>'_entered_unit_cost')::numeric)
      where m.tenant_id=p_tenant_id and m.reference_type='purchase' and m.reference_id=v_purchase and m.variant_id=v_variant and m.movement_type='purchase';
    end loop;
  end if;return v;
end $$;
grant execute on function public.purchases_create_v481(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

-- Prefer the actual transaction unit on invoice/detail APIs while base quantity remains the accounting/inventory truth.
create or replace function public.sales_get_detail_v32(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;v_items jsonb;begin
  select o.location_id into v_loc from public.document_origins o where o.entity_type='sale' and o.entity_id=p_sale_id and o.tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.sales_get_detail(p_tenant_id,p_sale_id);
  select coalesce(jsonb_agg(i.value||jsonb_build_object(
    'hsn_sac',a.hsn_sac,
    'unit_code',coalesce(si.entered_unit_code,nullif(i.value->>'unit_code',''),a.unit_code),
    'quantity',coalesce(si.entered_quantity,(i.value->>'quantity')::numeric),
    'base_quantity',coalesce(si.quantity,(i.value->>'quantity')::numeric),
    'unit_price',coalesce(si.entered_unit_price,(i.value->>'unit_price')::numeric),
    'conversion_to_base',coalesce(si.conversion_to_base,1),
    'preferred_supplier_name',a.preferred_supplier_name
  )),'[]'::jsonb) into v_items
  from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value)
  left join public.sale_items si on si.sale_id=p_sale_id and si.variant_id=nullif(i.value->>'variant_id','')::uuid
  left join public.product_invoice_attributes_v45 a on a.tenant_id=p_tenant_id and a.variant_id=nullif(i.value->>'variant_id','')::uuid;
  return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end $$;
grant execute on function public.sales_get_detail_v32(uuid,uuid) to authenticated;

create or replace function public.purchases_get_detail_v32(p_tenant_id uuid,p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;v_items jsonb;begin
  select o.location_id into v_loc from public.document_origins o where o.entity_type='purchase' and o.entity_id=p_purchase_id and o.tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.purchases_get_detail(p_tenant_id,p_purchase_id);
  select coalesce(jsonb_agg(i.value||jsonb_build_object(
    'unit_code',coalesce(pi.entered_unit_code,nullif(i.value->>'unit_code','')),
    'quantity',coalesce(pi.entered_quantity,(i.value->>'quantity')::numeric),
    'base_quantity',coalesce(pi.quantity,(i.value->>'quantity')::numeric),
    'unit_cost',coalesce(pi.entered_unit_cost,(i.value->>'unit_cost')::numeric),
    'conversion_to_base',coalesce(pi.conversion_to_base,1)
  )),'[]'::jsonb) into v_items
  from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value)
  left join public.purchase_items pi on pi.purchase_id=p_purchase_id and pi.variant_id=nullif(i.value->>'variant_id','')::uuid;
  return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end $$;
grant execute on function public.purchases_get_detail_v32(uuid,uuid) to authenticated;

-- Unit-aware return wrappers accept the quantity in the unit shown on the original document,
-- convert it back to base quantity for the proven return engine, then preserve entered-unit metadata.
create or replace function public.sales_return_create_v481(
  p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_items jsonb:='[]'::jsonb;v_si public.sale_items%rowtype;v_entered numeric;v_factor numeric;v_step numeric:=1;v_fractional boolean:=false;v jsonb;v_return uuid;begin
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select si.* into v_si from public.sale_items si where si.id=(x->>'sale_item_id')::uuid and si.sale_id=p_sale_id;
    if not found then raise exception 'Sale item not found';end if;
    v_entered:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_entered<=0 then raise exception 'Return quantity must be positive';end if;
    v_factor:=coalesce(nullif(v_si.conversion_to_base,0),1);
    if v_si.entered_unit_id is not null then
      select pu.quantity_step,u.allow_fractional into v_step,v_fractional from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_si.variant_id and pu.unit_id=v_si.entered_unit_id;
      v_step:=greatest(coalesce(v_step,1),0.000001);
      if not coalesce(v_fractional,false) and v_entered<>trunc(v_entered) then raise exception 'Return unit % only allows whole quantities',coalesce(v_si.entered_unit_code,'');end if;
      if abs((v_entered/v_step)-round(v_entered/v_step))>0.000001 then raise exception 'Return quantity for unit % must use increments of %',coalesce(v_si.entered_unit_code,''),v_step;end if;
    end if;
    v_items:=v_items||jsonb_build_array(x||jsonb_build_object('quantity',v_entered*v_factor,'_entered_quantity',v_entered,'_unit_id',v_si.entered_unit_id,'_unit_code',coalesce(v_si.entered_unit_code,''),'_conversion_to_base',v_factor));
  end loop;
  v:=public.sales_return_create_v47(p_tenant_id,p_sale_id,v_items,p_reason,p_device_id,p_request_id);
  v_return:=nullif(v->>'return_id','')::uuid;
  if v_return is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      update public.sales_return_items ri set
        entered_unit_id=nullif(x->>'_unit_id','')::uuid,
        entered_unit_code=nullif(x->>'_unit_code',''),
        entered_quantity=(x->>'_entered_quantity')::numeric,
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where ri.sales_return_id=v_return and ri.sale_item_id=(x->>'sale_item_id')::uuid;
      update public.location_stock_movements m set
        unit_id=nullif(x->>'_unit_id','')::uuid,
        unit_code=nullif(x->>'_unit_code',''),
        display_quantity=abs((x->>'_entered_quantity')::numeric),
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where m.tenant_id=p_tenant_id and m.reference_type='sales_return' and m.reference_id=v_return
        and m.variant_id=(select si.variant_id from public.sale_items si where si.id=(x->>'sale_item_id')::uuid)
        and m.movement_type in('sale_return','sales_return');
    end loop;
  end if;
  return v;
end $$;
grant execute on function public.sales_return_create_v481(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v481(
  p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_items jsonb:='[]'::jsonb;v_pi public.purchase_items%rowtype;v_entered numeric;v_factor numeric;v_step numeric:=1;v_fractional boolean:=false;v jsonb;v_return uuid;begin
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select pi.* into v_pi from public.purchase_items pi where pi.id=(x->>'purchase_item_id')::uuid and pi.purchase_id=p_purchase_id;
    if not found then raise exception 'Purchase item not found';end if;
    v_entered:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_entered<=0 then raise exception 'Return quantity must be positive';end if;
    v_factor:=coalesce(nullif(v_pi.conversion_to_base,0),1);
    if v_pi.entered_unit_id is not null then
      select pu.quantity_step,u.allow_fractional into v_step,v_fractional from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_pi.variant_id and pu.unit_id=v_pi.entered_unit_id;
      v_step:=greatest(coalesce(v_step,1),0.000001);
      if not coalesce(v_fractional,false) and v_entered<>trunc(v_entered) then raise exception 'Return unit % only allows whole quantities',coalesce(v_pi.entered_unit_code,'');end if;
      if abs((v_entered/v_step)-round(v_entered/v_step))>0.000001 then raise exception 'Return quantity for unit % must use increments of %',coalesce(v_pi.entered_unit_code,''),v_step;end if;
    end if;
    v_items:=v_items||jsonb_build_array(x||jsonb_build_object('quantity',v_entered*v_factor,'_entered_quantity',v_entered,'_unit_id',v_pi.entered_unit_id,'_unit_code',coalesce(v_pi.entered_unit_code,''),'_conversion_to_base',v_factor));
  end loop;
  v:=public.purchase_return_create_v47(p_tenant_id,p_purchase_id,v_items,p_reason,p_device_id,p_request_id);
  v_return:=nullif(v->>'return_id','')::uuid;
  if v_return is not null then
    for x in select value from jsonb_array_elements(v_items) loop
      update public.purchase_return_items ri set
        entered_unit_id=nullif(x->>'_unit_id','')::uuid,
        entered_unit_code=nullif(x->>'_unit_code',''),
        entered_quantity=(x->>'_entered_quantity')::numeric,
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where ri.purchase_return_id=v_return and ri.purchase_item_id=(x->>'purchase_item_id')::uuid;
      update public.location_stock_movements m set
        unit_id=nullif(x->>'_unit_id','')::uuid,
        unit_code=nullif(x->>'_unit_code',''),
        display_quantity=-abs((x->>'_entered_quantity')::numeric),
        conversion_to_base=(x->>'_conversion_to_base')::numeric
      where m.tenant_id=p_tenant_id and m.reference_type='purchase_return' and m.reference_id=v_return
        and m.variant_id=(select pi.variant_id from public.purchase_items pi where pi.id=(x->>'purchase_item_id')::uuid)
        and m.movement_type='purchase_return';
    end loop;
  end if;
  return v;
end $$;
grant execute on function public.purchase_return_create_v481(uuid,uuid,jsonb,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(128,'4.8.1','Inventory & Unit Engine','Unit-aware sales and purchases preserve entered units/quantities while existing quantity columns remain canonical base quantities for stock, returns and accounting.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 128 unit transactions applied' as status;
