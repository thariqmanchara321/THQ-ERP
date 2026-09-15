-- THQ ERP v6.1.1: product classification masters + simplified global additional charges.

create or replace function public.inventory_product_classifications_v611(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare v_categories jsonb; v_brands jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'name',name,'code',code
  ) order by name),'[]'::jsonb)
  into v_categories
  from public.product_categories
  where tenant_id=p_tenant_id and is_active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'name',name,'code',code
  ) order by name),'[]'::jsonb)
  into v_brands
  from public.product_brands
  where tenant_id=p_tenant_id and is_active;

  return jsonb_build_object(
    'categories',v_categories,
    'brands',v_brands
  );
end;
$$;

create or replace function public.inventory_product_classification_add_v611(
  p_tenant_id uuid,
  p_kind text,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_kind text:=lower(trim(coalesce(p_kind,'')));
  v_name text:=trim(coalesce(p_name,''));
  v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'inventory.manage permission required';
  end if;
  if v_kind not in ('category','brand') then
    raise exception 'Classification kind must be category or brand';
  end if;
  if v_name='' then
    raise exception 'Name is required';
  end if;

  if v_kind='category' then
    select id into v_id
    from public.product_categories
    where tenant_id=p_tenant_id and lower(name)=lower(v_name)
    limit 1;

    if v_id is null then
      insert into public.product_categories(tenant_id,name,is_active)
      values(p_tenant_id,v_name,true)
      returning id into v_id;
    else
      update public.product_categories
      set name=v_name,is_active=true,updated_at=now()
      where id=v_id and tenant_id=p_tenant_id;
    end if;
  else
    select id into v_id
    from public.product_brands
    where tenant_id=p_tenant_id and lower(name)=lower(v_name)
    limit 1;

    if v_id is null then
      insert into public.product_brands(tenant_id,name,is_active)
      values(p_tenant_id,v_name,true)
      returning id into v_id;
    else
      update public.product_brands
      set name=v_name,is_active=true,updated_at=now()
      where id=v_id and tenant_id=p_tenant_id;
    end if;
  end if;

  return jsonb_build_object('id',v_id,'kind',v_kind,'name',v_name);
end;
$$;

revoke all on function public.inventory_product_classifications_v611(uuid)
from public;
grant execute on function public.inventory_product_classifications_v611(uuid)
to authenticated,service_role;

revoke all on function public.inventory_product_classification_add_v611(uuid,text,text)
from public;
grant execute on function public.inventory_product_classification_add_v611(uuid,text,text)
to authenticated,service_role;

update public.sales_charge_catalog_v610
set auto_apply_dine_in=false,
    auto_apply_takeaway=false,
    auto_apply_delivery=false,
    updated_at=now()
where auto_apply_dine_in or auto_apply_takeaway or auto_apply_delivery;

update public.product_charge_rules_v610
set active=false,updated_at=now()
where active;

create or replace function public.sales_charge_catalog_put_pos_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_charge_id uuid,
  p_code text,
  p_name text,
  p_charge_kind text,
  p_service_variant_id uuid,
  p_default_quantity numeric,
  p_auto_dine_in boolean,
  p_auto_takeaway boolean,
  p_auto_delivery boolean,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Manage permission required';
  end if;

  perform private.sales_charge_catalog_assert_v610(
    p_tenant_id,p_service_variant_id
  );

  if p_charge_id is null then
    insert into public.sales_charge_catalog_v610(
      tenant_id,code,name,charge_kind,service_variant_id,default_quantity,
      auto_apply_dine_in,auto_apply_takeaway,auto_apply_delivery,active
    ) values (
      p_tenant_id,upper(trim(p_code)),trim(p_name),
      lower(trim(p_charge_kind)),p_service_variant_id,
      greatest(coalesce(p_default_quantity,1),0.000001),
      false,false,false,coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.sales_charge_catalog_v610
    set code=upper(trim(p_code)),
        name=trim(p_name),
        charge_kind=lower(trim(p_charge_kind)),
        service_variant_id=p_service_variant_id,
        default_quantity=greatest(coalesce(p_default_quantity,1),0.000001),
        auto_apply_dine_in=false,
        auto_apply_takeaway=false,
        auto_apply_delivery=false,
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_charge_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Additional charge not found';
  end if;
  return v_id;
end;
$$;

create or replace function private.v482_price_sale_items(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_location_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  x jsonb;
  v_out jsonb:='[]'::jsonb;
  v_variant uuid;
  v_unit uuid;
  v_qty numeric;
  v_price jsonb;
  v_charge_id uuid;
  v_override numeric;
begin
  for x in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_unit:=nullif(x->>'unit_id','')::uuid;
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);

    if v_variant is null or v_qty<=0 then
      raise exception 'Valid product and quantity are required';
    end if;

    v_price:=private.pricing_resolve_v482_internal(
      p_tenant_id,v_variant,p_customer_id,v_unit,v_qty,p_location_id
    );

    v_charge_id:=nullif(x->>'commercial_charge_id','')::uuid;
    if v_charge_id is not null then
      if not exists(
        select 1
        from public.sales_charge_catalog_v610 c
        where c.id=v_charge_id
          and c.tenant_id=p_tenant_id
          and c.service_variant_id=v_variant
          and c.active
      ) then
        raise exception 'Invalid additional-charge price override';
      end if;

      v_override:=nullif(x->>'unit_price','')::numeric;
      if v_override is null or v_override<0 then
        raise exception 'Additional charge amount cannot be negative';
      end if;

      v_price:=v_price||jsonb_build_object(
        'unit_price',v_override,
        'source','additional_charge_override'
      );
    end if;

    v_out:=v_out||jsonb_build_array(
      x||jsonb_build_object(
        'unit_id',v_price->>'unit_id',
        'unit_price',(v_price->>'unit_price')::numeric,
        '_pricing_source',v_price->>'source',
        '_price_list_id',v_price->>'price_list_id',
        '_price_list_name',v_price->>'price_list_name'
      )
    );
  end loop;
  return v_out;
end;
$$;

create or replace function private.sales_commercial_expand_v610(
  p_tenant_id uuid,
  p_order_type text,
  p_items jsonb,
  p_discount_type text default 'none',
  p_discount_value numeric default 0,
  p_charge_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order_type text:=lower(trim(coalesce(p_order_type,'sale')));
  v_discount_type text:=lower(trim(coalesce(p_discount_type,'none')));
  v_discount_value numeric:=greatest(coalesce(p_discount_value,0),0);
  v_items jsonb:='[]'::jsonb;
  v_charge_items jsonb:='[]'::jsonb;
  v_breakdown jsonb:='[]'::jsonb;
  v_line jsonb;
  v_count integer;
  v_index integer:=0;
  v_qty numeric;
  v_price numeric;
  v_existing_discount numeric;
  v_line_net numeric;
  v_base_net numeric:=0;
  v_doc_discount numeric:=0;
  v_alloc numeric:=0;
  v_remaining numeric:=0;
  v_charge_total numeric:=0;
  v_subtotal numeric:=0;
  v_discount_total numeric:=0;
  v_tax numeric:=0;
  v_taxable numeric:=0;
begin
  if v_order_type='counter' then v_order_type:='sale'; end if;
  if v_order_type not in('sale','dine_in','takeaway','delivery') then
    raise exception 'Invalid commercial order type %',v_order_type;
  end if;
  if v_discount_type not in('none','fixed','percent') then
    raise exception 'Invalid document discount type %',v_discount_type;
  end if;
  if v_discount_type='percent' and v_discount_value>100 then
    raise exception 'Document discount percent cannot exceed 100';
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Commercial quote requires at least one item';
  end if;
  if jsonb_typeof(coalesce(p_charge_selections,'[]'::jsonb))<>'array' then
    raise exception 'Additional charge selections must be an array';
  end if;

  v_count:=jsonb_array_length(p_items);

  for v_line in
    select value from jsonb_array_elements(p_items)
  loop
    v_qty:=greatest(
      coalesce(nullif(v_line->>'quantity','')::numeric,0),0
    );
    v_price:=greatest(
      coalesce(nullif(v_line->>'unit_price','')::numeric,0),0
    );
    v_existing_discount:=greatest(
      coalesce(nullif(v_line->>'discount_amount','')::numeric,0),0
    );
    v_line_net:=greatest(v_qty*v_price-v_existing_discount,0);
    v_base_net:=v_base_net+v_line_net;
  end loop;

  if v_discount_type='fixed' then
    v_doc_discount:=least(v_discount_value,v_base_net);
  elsif v_discount_type='percent' then
    v_doc_discount:=round(v_base_net*v_discount_value/100,6);
  else
    v_doc_discount:=0;
  end if;

  v_remaining:=v_doc_discount;

  for v_line in
    select value from jsonb_array_elements(p_items)
  loop
    v_index:=v_index+1;
    v_qty:=greatest(
      coalesce(nullif(v_line->>'quantity','')::numeric,0),0
    );
    v_price:=greatest(
      coalesce(nullif(v_line->>'unit_price','')::numeric,0),0
    );
    v_existing_discount:=greatest(
      coalesce(nullif(v_line->>'discount_amount','')::numeric,0),0
    );
    v_line_net:=greatest(v_qty*v_price-v_existing_discount,0);

    if v_remaining>0 and v_line_net>0 and v_base_net>0 then
      if v_index=v_count then
        v_alloc:=least(v_remaining,v_line_net);
      else
        v_alloc:=least(
          round(v_doc_discount*v_line_net/v_base_net,6),
          v_remaining,
          v_line_net
        );
      end if;
    else
      v_alloc:=0;
    end if;

    v_items:=v_items||jsonb_build_array(
      v_line||jsonb_build_object(
        'discount_amount',round(v_existing_discount+v_alloc,6)
      )
    );
    v_remaining:=greatest(v_remaining-v_alloc,0);
  end loop;

  with manual as (
    select
      nullif(s.value->>'charge_id','')::uuid charge_id,
      greatest(
        coalesce(nullif(s.value->>'quantity','')::numeric,1),0
      ) quantity,
      case
        when nullif(s.value->>'amount','') is null then null
        else greatest((s.value->>'amount')::numeric,0)
      end amount
    from jsonb_array_elements(
      coalesce(p_charge_selections,'[]'::jsonb)
    ) s(value)
    where jsonb_typeof(s.value)='object'
      and nullif(s.value->>'charge_id','') is not null
  ),
  rows as (
    select
      c.id charge_id,
      c.code,
      c.name,
      c.charge_kind,
      c.service_variant_id,
      m.quantity,
      case
        when m.amount is not null and m.quantity>0
          then m.amount/m.quantity
        else pv.selling_price
      end unit_price,
      p.tax_rate,
      p.tax_code
    from manual m
    join public.sales_charge_catalog_v610 c
      on c.id=m.charge_id
     and c.tenant_id=p_tenant_id
     and c.active
    join public.product_variants pv
      on pv.id=c.service_variant_id
     and pv.tenant_id=c.tenant_id
     and pv.status='active'
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
     and p.status='active'
     and p.item_type='service'
    where m.quantity>0
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'variant_id',service_variant_id,
      'quantity',quantity,
      'unit_price',unit_price,
      'discount_amount',0,
      'tax_rate',tax_rate,
      'commercial_charge_id',charge_id,
      'commercial_charge_kind',charge_kind,
      'commercial_charge_code',code
    ) order by name,code),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'charge_id',charge_id,
      'code',code,
      'name',name,
      'kind',charge_kind,
      'variant_id',service_variant_id,
      'quantity',quantity,
      'unit_price',unit_price,
      'tax_rate',tax_rate,
      'tax_code',tax_code,
      'taxable_value',round(quantity*unit_price,2),
      'tax_amount',round(quantity*unit_price*tax_rate/100,2),
      'line_total',round(quantity*unit_price*(1+tax_rate/100),2),
      'sources',jsonb_build_array('manual')
    ) order by name,code),'[]'::jsonb),
    coalesce(sum(quantity*unit_price),0)
  into v_charge_items,v_breakdown,v_charge_total
  from rows;

  v_items:=v_items||v_charge_items;

  select
    coalesce(sum(
      greatest(
        coalesce(nullif(x.value->>'quantity','')::numeric,0),0
      ) *
      greatest(
        coalesce(nullif(x.value->>'unit_price','')::numeric,0),0
      )
    ),0),
    coalesce(sum(
      greatest(
        coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0
      )
    ),0),
    coalesce(sum(greatest(
      greatest(
        coalesce(nullif(x.value->>'quantity','')::numeric,0),0
      ) *
      greatest(
        coalesce(nullif(x.value->>'unit_price','')::numeric,0),0
      ) -
      greatest(
        coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0
      ),
      0
    )),0),
    coalesce(sum(
      greatest(
        greatest(
          coalesce(nullif(x.value->>'quantity','')::numeric,0),0
        ) *
        greatest(
          coalesce(nullif(x.value->>'unit_price','')::numeric,0),0
        ) -
        greatest(
          coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0
        ),
        0
      ) *
      greatest(
        coalesce(nullif(x.value->>'tax_rate','')::numeric,0),0
      ) / 100
    ),0)
  into v_subtotal,v_discount_total,v_taxable,v_tax
  from jsonb_array_elements(v_items)x(value);

  return jsonb_build_object(
    'order_type',v_order_type,
    'discount_type',v_discount_type,
    'discount_value',v_discount_value,
    'document_discount_total',round(v_doc_discount,2),
    'classified_charge_total',round(v_charge_total,2),
    'charge_breakdown',v_breakdown,
    'items',v_items,
    'totals',jsonb_build_object(
      'subtotal',round(v_subtotal,2),
      'discount',round(v_discount_total,2),
      'taxable',round(v_taxable,2),
      'tax',round(v_tax,2),
      'before_round_off',round(v_taxable+v_tax,2),
      'automatic_round_off',
        round(round(v_taxable+v_tax,0)-(v_taxable+v_tax),2),
      'grand_total',round(
        v_taxable+v_tax+
        round(round(v_taxable+v_tax,0)-(v_taxable+v_tax),2),
        2
      )
    )
  );
end;
$$;
