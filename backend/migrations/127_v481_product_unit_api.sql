-- THQ ERP V4.8.1 — product/unit configuration and enriched inventory APIs.
begin;

create or replace function public.inventory_product_units_v481(p_tenant_id uuid,p_variant_id uuid)
returns table(unit_id uuid,code text,name text,unit_group text,decimal_places integer,allow_fractional boolean,is_base boolean,allow_purchase boolean,allow_sale boolean,is_default_purchase boolean,is_default_sale boolean,conversion_to_base numeric,quantity_step numeric,sale_price numeric,purchase_cost numeric,cutting_allowed boolean,cutting_charge numeric,active boolean)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select u.id,u.code,u.name,u.unit_group,u.decimal_places,u.allow_fractional,pu.is_base,pu.allow_purchase,pu.allow_sale,pu.is_default_purchase,pu.is_default_sale,pu.conversion_to_base,pu.quantity_step,pu.sale_price,pu.purchase_cost,pu.cutting_allowed,pu.cutting_charge,pu.active
  from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id
  where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id order by pu.is_base desc,pu.is_default_sale desc,u.name;
end $$;
grant execute on function public.inventory_product_units_v481(uuid,uuid) to authenticated;

create or replace function public.inventory_product_units_save_v481(p_tenant_id uuid,p_variant_id uuid,p_base_unit_code text,p_units jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_unit uuid;v_base uuid;v_old_base uuid;v_code text;v_count int:=0;v_default_sale int:=0;v_default_purchase int:=0;v_requested_sale int:=0;v_requested_purchase int:=0;v_has_history boolean:=false;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
  if not exists(select 1 from public.product_variants pv where pv.id=p_variant_id and pv.tenant_id=p_tenant_id) then raise exception 'Product variant not found';end if;
  perform private.v481_seed_units(p_tenant_id);
  v_code:=upper(trim(coalesce(p_base_unit_code,'PCS')));
  select u.id into v_base from public.inventory_units_v481 u where u.tenant_id=p_tenant_id and u.code=v_code and u.active;
  if v_base is null then raise exception 'Base unit % not found',v_code;end if;
  select pu.unit_id into v_old_base from public.product_units_v481 pu where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.is_base and pu.active limit 1;
  if v_old_base is not null and v_old_base<>v_base then
    select exists(select 1 from public.location_stock_movements m where m.tenant_id=p_tenant_id and m.variant_id=p_variant_id)
        or exists(select 1 from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and abs(coalesce(b.quantity,0))>0.000001)
      into v_has_history;
    if v_has_history then raise exception 'Base inventory unit cannot be changed after stock/history exists. Add a conversion unit instead.';end if;
  end if;
  select count(*) filter(where coalesce((value->>'is_default_sale')::boolean,false) and coalesce((value->>'allow_sale')::boolean,true)),
         count(*) filter(where coalesce((value->>'is_default_purchase')::boolean,false) and coalesce((value->>'allow_purchase')::boolean,false))
    into v_requested_sale,v_requested_purchase
  from jsonb_array_elements(coalesce(p_units,'[]'::jsonb));
  if v_requested_sale>1 then raise exception 'Only one default sale unit is allowed';end if;
  if v_requested_purchase>1 then raise exception 'Only one default purchase unit is allowed';end if;

  -- Clear flags first; rows are preserved so historical IDs remain stable.
  update public.product_units_v481 set is_base=false,is_default_sale=false,is_default_purchase=false,active=false,updated_at=now() where tenant_id=p_tenant_id and variant_id=p_variant_id;
  insert into public.product_units_v481(tenant_id,variant_id,unit_id,is_base,allow_purchase,allow_sale,is_default_purchase,is_default_sale,conversion_to_base,quantity_step,active)
  values(p_tenant_id,p_variant_id,v_base,true,true,true,v_requested_purchase=0,v_requested_sale=0,1,coalesce((select case when allow_fractional then power(10::numeric,-least(decimal_places,3)) else 1 end from public.inventory_units_v481 where id=v_base),1),true)
  on conflict(tenant_id,variant_id,unit_id) do update set is_base=true,allow_purchase=true,allow_sale=true,is_default_purchase=(v_requested_purchase=0),is_default_sale=(v_requested_sale=0),conversion_to_base=1,quantity_step=case when excluded.quantity_step<=0 then 1 else excluded.quantity_step end,active=true,updated_at=now();

  for x in select value from jsonb_array_elements(coalesce(p_units,'[]'::jsonb)) loop
    v_unit:=null;
    if nullif(x->>'unit_id','') is not null then begin v_unit:=(x->>'unit_id')::uuid; exception when others then v_unit:=null; end; end if;
    if v_unit is null and nullif(trim(coalesce(x->>'code','')),'') is not null then select u.id into v_unit from public.inventory_units_v481 u where u.tenant_id=p_tenant_id and u.code=upper(trim(x->>'code')) and u.active;end if;
    if v_unit is null then raise exception 'Unknown unit in product conversion';end if;
    if v_unit=v_base then
      update public.product_units_v481 set
        quantity_step=coalesce(nullif(x->>'quantity_step','')::numeric,quantity_step),
        cutting_allowed=coalesce((x->>'cutting_allowed')::boolean,cutting_allowed),
        cutting_charge=coalesce(nullif(x->>'cutting_charge','')::numeric,cutting_charge),
        sale_price=nullif(x->>'sale_price','')::numeric,
        purchase_cost=nullif(x->>'purchase_cost','')::numeric,
        updated_at=now()
      where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;
      continue;
    end if;
    insert into public.product_units_v481(tenant_id,variant_id,unit_id,is_base,allow_purchase,allow_sale,is_default_purchase,is_default_sale,conversion_to_base,quantity_step,sale_price,purchase_cost,cutting_allowed,cutting_charge,active,settings)
    values(p_tenant_id,p_variant_id,v_unit,false,coalesce((x->>'allow_purchase')::boolean,false),coalesce((x->>'allow_sale')::boolean,true),coalesce((x->>'is_default_purchase')::boolean,false) and coalesce((x->>'allow_purchase')::boolean,false),coalesce((x->>'is_default_sale')::boolean,false) and coalesce((x->>'allow_sale')::boolean,true),coalesce(nullif(x->>'conversion_to_base','')::numeric,1),coalesce(nullif(x->>'quantity_step','')::numeric,1),nullif(x->>'sale_price','')::numeric,nullif(x->>'purchase_cost','')::numeric,coalesce((x->>'cutting_allowed')::boolean,false),coalesce(nullif(x->>'cutting_charge','')::numeric,0),coalesce((x->>'active')::boolean,true),coalesce(x->'settings','{}'::jsonb))
    on conflict(tenant_id,variant_id,unit_id) do update set allow_purchase=excluded.allow_purchase,allow_sale=excluded.allow_sale,is_default_purchase=excluded.is_default_purchase,is_default_sale=excluded.is_default_sale,conversion_to_base=excluded.conversion_to_base,quantity_step=excluded.quantity_step,sale_price=excluded.sale_price,purchase_cost=excluded.purchase_cost,cutting_allowed=excluded.cutting_allowed,cutting_charge=excluded.cutting_charge,active=excluded.active,settings=excluded.settings,updated_at=now();
  end loop;

  -- Guarantee one default sale/purchase among active allowed units; base is the fallback.
  select count(*) into v_default_sale from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active and allow_sale and is_default_sale;
  if v_default_sale=0 then update public.product_units_v481 set is_default_sale=true where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;end if;
  if v_default_sale>1 then raise exception 'Only one default sale unit is allowed';end if;
  select count(*) into v_default_purchase from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active and allow_purchase and is_default_purchase;
  if v_default_purchase=0 then update public.product_units_v481 set is_default_purchase=true where tenant_id=p_tenant_id and variant_id=p_variant_id and unit_id=v_base;end if;
  if v_default_purchase>1 then raise exception 'Only one default purchase unit is allowed';end if;

  insert into public.product_invoice_attributes_v45(tenant_id,variant_id,unit_code,updated_at,updated_by)
  values(p_tenant_id,p_variant_id,v_code,now(),auth.uid()) on conflict(tenant_id,variant_id) do update set unit_code=excluded.unit_code,updated_at=now(),updated_by=auth.uid();
  select count(*) into v_count from public.product_units_v481 where tenant_id=p_tenant_id and variant_id=p_variant_id and active;
  return jsonb_build_object('variant_id',p_variant_id,'base_unit_code',v_code,'active_units',v_count);
end $$;
grant execute on function public.inventory_product_units_save_v481(uuid,uuid,text,jsonb) to authenticated;

create or replace function public.inventory_create_product_v481(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_name text,p_sku text,p_item_type text,p_description text,
  p_category_name text,p_brand_name text,p_barcode text,p_part_number text,p_cost_price numeric,p_selling_price numeric,
  p_list_price numeric,p_tax_rate numeric,p_reorder_level numeric,p_opening_stock numeric,p_base_unit_code text default 'PCS',p_units jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_variant uuid;v_base_unit uuid;v_base_code text;begin
  v:=public.inventory_create_product_v4(p_tenant_id,p_location_id,p_device_id,p_name,p_sku,p_item_type,p_description,p_category_name,p_brand_name,p_barcode,p_part_number,p_cost_price,p_selling_price,p_list_price,p_tax_rate,p_reorder_level,p_opening_stock);
  v_variant:=nullif(v->>'variant_id','')::uuid;
  perform public.inventory_product_units_save_v481(p_tenant_id,v_variant,coalesce(nullif(trim(p_base_unit_code),''),case when p_item_type='service' then 'HR' else 'PCS' end),coalesce(p_units,'[]'::jsonb));
  select pu.unit_id,u.code into v_base_unit,v_base_code from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.is_base and pu.active limit 1;
  update public.location_stock_movements m set unit_id=v_base_unit,unit_code=v_base_code,conversion_to_base=1,display_quantity=m.base_quantity_delta
  where m.tenant_id=p_tenant_id and m.variant_id=v_variant and m.reference_type='product' and m.reference_id=v_variant and m.movement_type='opening' and m.unit_id is null;
  return v||jsonb_build_object('base_unit_code',upper(coalesce(nullif(trim(p_base_unit_code),''),case when p_item_type='service' then 'HR' else 'PCS' end)));
end $$;
grant execute on function public.inventory_create_product_v481(uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;

create or replace function public.inventory_list_products_v481(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_variant uuid;v_units jsonb;v_purchase_units jsonb;v_base jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select * from public.inventory_list_products_v4(p_tenant_id,p_location_id) loop
    begin v_variant:=nullif(r->>'variant_id','')::uuid; exception when others then v_variant:=null;end;
    if v_variant is null then return next r;continue;end if;
    select to_jsonb(x) into v_base from (select u.id unit_id,u.code,u.name,u.decimal_places,u.allow_fractional,pu.quantity_step,pu.cutting_allowed,pu.cutting_charge from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.is_base and pu.active limit 1) x;
    select coalesce(jsonb_agg(jsonb_build_object('unit_id',u.id,'code',u.code,'name',u.name,'decimal_places',u.decimal_places,'allow_fractional',u.allow_fractional,'conversion_to_base',pu.conversion_to_base,'quantity_step',pu.quantity_step,'sale_price',pu.sale_price,'purchase_cost',pu.purchase_cost,'cutting_allowed',pu.cutting_allowed,'cutting_charge',pu.cutting_charge,'is_default_sale',pu.is_default_sale,'is_default_purchase',pu.is_default_purchase,'allow_sale',pu.allow_sale,'allow_purchase',pu.allow_purchase,'is_base',pu.is_base,'active',pu.active) order by pu.is_default_sale desc,pu.is_base desc,u.name),'[]'::jsonb) into v_units
    from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.allow_sale;
    select coalesce(jsonb_agg(jsonb_build_object('unit_id',u.id,'code',u.code,'name',u.name,'decimal_places',u.decimal_places,'allow_fractional',u.allow_fractional,'conversion_to_base',pu.conversion_to_base,'quantity_step',pu.quantity_step,'sale_price',pu.sale_price,'purchase_cost',pu.purchase_cost,'cutting_allowed',pu.cutting_allowed,'cutting_charge',pu.cutting_charge,'is_default_sale',pu.is_default_sale,'is_default_purchase',pu.is_default_purchase,'allow_sale',pu.allow_sale,'allow_purchase',pu.allow_purchase,'is_base',pu.is_base,'active',pu.active) order by pu.is_default_purchase desc,pu.is_base desc,u.name),'[]'::jsonb) into v_purchase_units
    from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=v_variant and pu.active and pu.allow_purchase;
    return next r||jsonb_build_object('base_unit',coalesce(v_base,'{}'::jsonb),'sale_units',coalesce(v_units,'[]'::jsonb),'purchase_units',coalesce(v_purchase_units,'[]'::jsonb),'base_unit_code',coalesce(v_base->>'code',r->>'unit_code','PCS'),'unit_code',coalesce(v_base->>'code',r->>'unit_code','PCS'));
  end loop;return;
end $$;
grant execute on function public.inventory_list_products_v481(uuid,uuid) to authenticated;

create or replace function public.inventory_location_movements_v481(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select jsonb_build_object('movement_id',m.id,'movement_type',m.movement_type,'movement_group',m.movement_group,'quantity_delta',coalesce(m.display_quantity,m.quantity_delta),'base_quantity_delta',coalesce(m.base_quantity_delta,m.quantity_delta),'unit_code',m.unit_code,'conversion_to_base',coalesce(m.conversion_to_base,1),'balance_before',m.balance_before,'balance_after',m.balance_after,'unit_cost',m.unit_cost,'location_id',m.location_id,'location_name',l.name,'reference_type',m.reference_type,'reference_number',m.reference_number,'note',m.note,'occurred_at',m.created_at,'created_at',m.created_at)
  from public.location_stock_movements m join public.business_locations l on l.id=m.location_id
  where m.tenant_id=p_tenant_id and m.variant_id=p_variant_id and (p_location_id is null or m.location_id=p_location_id)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,m.location_id,'view'))
  order by m.created_at desc limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.inventory_location_movements_v481(uuid,uuid,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(127,'4.8.1','Inventory & Unit Engine','Product unit configuration, conversion API, unit-aware product creation/listing and enriched stock movement history.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 127 product unit API applied' as status;
