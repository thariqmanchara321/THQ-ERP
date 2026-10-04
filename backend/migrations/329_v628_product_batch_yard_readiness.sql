begin;

alter table public.inventory_batches_v483
  add column if not exists quality_label text,
  add column if not exists purchase_cost_base numeric,
  add column if not exists selling_price_base numeric;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='inventory_batches_v483_purchase_cost_nonnegative'
      and conrelid='public.inventory_batches_v483'::regclass
  ) then
    alter table public.inventory_batches_v483
      add constraint inventory_batches_v483_purchase_cost_nonnegative
      check(purchase_cost_base is null or purchase_cost_base>=0);
  end if;
  if not exists(
    select 1 from pg_constraint
    where conname='inventory_batches_v483_selling_price_nonnegative'
      and conrelid='public.inventory_batches_v483'::regclass
  ) then
    alter table public.inventory_batches_v483
      add constraint inventory_batches_v483_selling_price_nonnegative
      check(selling_price_base is null or selling_price_base>=0);
  end if;
end
$$;

update public.inventory_batches_v483 b
set purchase_cost_base=pi.unit_cost,
    updated_at=greatest(b.updated_at,now())
from public.purchase_items pi
where b.first_purchase_item_id=pi.id
  and b.tenant_id=pi.tenant_id
  and b.purchase_cost_base is null
  and pi.unit_cost is not null
  and pi.unit_cost>=0;

CREATE OR REPLACE FUNCTION public.inventory_update_product_v628(p_tenant_id uuid, p_variant_id uuid, p_name text, p_description text, p_category_name text, p_brand_name text, p_sku text, p_barcode text, p_part_number text, p_cost_price numeric, p_selling_price numeric, p_list_price numeric, p_tax_rate numeric, p_reorder_level numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_old_selling numeric;
  v_result jsonb;
  v_synced integer:=0;
begin
  if not private.has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select selling_price
  into v_old_selling
  from public.product_variants
  where id=p_variant_id
    and tenant_id=p_tenant_id
  for update;

  if not found then
    raise exception 'Product not found';
  end if;

  v_result:=public.inventory_update_product(
    p_tenant_id,p_variant_id,p_name,p_description,p_category_name,p_brand_name,
    p_sku,p_barcode,p_part_number,p_cost_price,p_selling_price,p_list_price,
    p_tax_rate,p_reorder_level
  );

  update public.location_product_settings
  set selling_price=p_selling_price,
      updated_at=now()
  where tenant_id=p_tenant_id
    and variant_id=p_variant_id
    and (
      selling_price is null
      or abs(selling_price-coalesce(v_old_selling,0))<=0.000001
    );

  get diagnostics v_synced=row_count;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'master_cost_price',p_cost_price,
    'master_selling_price',p_selling_price,
    'location_prices_synced',v_synced
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.aggregate_vehicle_driver_save_v628(p_tenant_id uuid, p_vehicle_id uuid, p_driver_name text, p_driver_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_before public.service_vehicles%rowtype;
  v_after public.service_vehicles%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_before
  from public.service_vehicles
  where id=p_vehicle_id
    and tenant_id=p_tenant_id
    and active
  for update;

  if v_before.id is null then
    raise exception 'Truck not found';
  end if;

  update public.service_vehicles
  set driver_name=nullif(trim(coalesce(p_driver_name,'')),''),
      driver_phone=nullif(trim(coalesce(p_driver_phone,'')),''),
      updated_at=now()
  where id=p_vehicle_id
    and tenant_id=p_tenant_id
  returning * into v_after;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate.vehicle.driver.update',
    'service_vehicle',
    v_after.id,
    v_after.registration_number,
    jsonb_build_object(
      'driver_name',v_before.driver_name,
      'driver_phone',v_before.driver_phone
    ),
    jsonb_build_object(
      'driver_name',v_after.driver_name,
      'driver_phone',v_after.driver_phone
    )
  );

  return jsonb_build_object(
    'success',true,
    'vehicle_id',v_after.id,
    'registration_number',v_after.registration_number,
    'driver_name',v_after.driver_name,
    'driver_phone',v_after.driver_phone
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.aggregate_yard_batch_profile_save_v628(p_tenant_id uuid, p_batch_id uuid, p_quality_label text, p_selling_price_base numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_before public.inventory_batches_v483%rowtype;
  v_after public.inventory_batches_v483%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if p_selling_price_base is not null and p_selling_price_base<0 then
    raise exception 'Batch selling rate cannot be negative';
  end if;

  select *
  into v_before
  from public.inventory_batches_v483
  where id=p_batch_id
    and tenant_id=p_tenant_id
  for update;

  if v_before.id is null then
    raise exception 'Batch not found';
  end if;

  update public.inventory_batches_v483
  set quality_label=nullif(trim(coalesce(p_quality_label,'')),''),
      selling_price_base=p_selling_price_base,
      updated_at=now()
  where id=p_batch_id
    and tenant_id=p_tenant_id
  returning * into v_after;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate.batch.profile.update',
    'inventory_batch',
    v_after.id,
    v_after.batch_number,
    jsonb_build_object(
      'quality_label',v_before.quality_label,
      'selling_price_base',v_before.selling_price_base
    ),
    jsonb_build_object(
      'quality_label',v_after.quality_label,
      'selling_price_base',v_after.selling_price_base
    )
  );

  return jsonb_build_object(
    'success',true,
    'batch_id',v_after.id,
    'batch_number',v_after.batch_number,
    'quality_label',v_after.quality_label,
    'selling_price_base',v_after.selling_price_base
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.v628_batch_price_override(p_tenant_id uuid, p_variant_id uuid, p_batches jsonb, p_unit_id uuid, p_standard_unit_price numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  x jsonb;
  v_factor numeric:=1;
  v_standard_base numeric:=0;
  v_total_qty numeric:=0;
  v_weighted numeric:=0;
  v_qty numeric;
  v_batch_id uuid;
  v_batch_number text;
  v_batch_rate numeric;
  v_effective_rate numeric;
  v_any_specific boolean:=false;
begin
  if jsonb_typeof(coalesce(p_batches,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_batches,'[]'::jsonb))=0 then
    return jsonb_build_object(
      'unit_price',coalesce(p_standard_unit_price,0),
      'source',null,
      'batch_specific',false
    );
  end if;

  select pu.conversion_to_base
  into v_factor
  from public.product_units_v481 pu
  where pu.tenant_id=p_tenant_id
    and pu.variant_id=p_variant_id
    and pu.unit_id=p_unit_id
    and pu.active
  limit 1;

  if v_factor is null or v_factor<=0 then
    raise exception 'Selected unit conversion is not available for batch pricing';
  end if;

  v_standard_base:=coalesce(p_standard_unit_price,0)/v_factor;

  for x in select value
           from jsonb_array_elements(coalesce(p_batches,'[]'::jsonb))
  loop
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_qty<=0 then
      raise exception 'Selected batch quantity must be positive';
    end if;

    v_batch_id:=null;
    v_batch_number:=trim(coalesce(x->>'batch_number',''));

    if nullif(x->>'batch_id','') is not null then
      v_batch_id:=(x->>'batch_id')::uuid;
    elsif v_batch_number<>'' then
      select b.id
      into v_batch_id
      from public.inventory_batches_v483 b
      where b.tenant_id=p_tenant_id
        and b.variant_id=p_variant_id
        and lower(trim(b.batch_number))=lower(v_batch_number)
      limit 1;
    end if;

    if v_batch_id is null then
      raise exception 'Selected batch was not found for this product';
    end if;

    select b.selling_price_base
    into v_batch_rate
    from public.inventory_batches_v483 b
    where b.id=v_batch_id
      and b.tenant_id=p_tenant_id
      and b.variant_id=p_variant_id;

    if not found then
      raise exception 'Selected batch does not belong to this product';
    end if;

    if v_batch_rate is not null then
      v_any_specific:=true;
    end if;

    v_effective_rate:=coalesce(v_batch_rate,v_standard_base);
    v_weighted:=v_weighted+(v_qty*v_effective_rate);
    v_total_qty:=v_total_qty+v_qty;
  end loop;

  if v_total_qty<=0 then
    return jsonb_build_object(
      'unit_price',coalesce(p_standard_unit_price,0),
      'source',null,
      'batch_specific',false
    );
  end if;

  return jsonb_build_object(
    'unit_price',
      case
        when v_any_specific
        then round((v_weighted/v_total_qty)*v_factor,4)
        else coalesce(p_standard_unit_price,0)
      end,
    'source',case when v_any_specific then 'batch_price' else null end,
    'batch_specific',v_any_specific
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.v482_price_sale_items(p_tenant_id uuid, p_customer_id uuid, p_items jsonb, p_location_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  x jsonb;
  v_out jsonb:='[]'::jsonb;
  v_variant uuid;
  v_unit uuid;
  v_qty numeric;
  v_price jsonb;
  v_charge_id uuid;
  v_override numeric;
  v_batch_price jsonb;
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

    if jsonb_typeof(coalesce(x->'batches','[]'::jsonb))='array'
       and jsonb_array_length(coalesce(x->'batches','[]'::jsonb))>0 then
      v_batch_price:=private.v628_batch_price_override(
        p_tenant_id,
        v_variant,
        x->'batches',
        nullif(v_price->>'unit_id','')::uuid,
        coalesce(nullif(v_price->>'unit_price','')::numeric,0)
      );

      if coalesce((v_batch_price->>'batch_specific')::boolean,false) then
        v_price:=v_price||jsonb_build_object(
          'unit_price',(v_batch_price->>'unit_price')::numeric,
          'source','batch_price'
        );
      end if;
    end if;

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
end
$function$;

CREATE OR REPLACE FUNCTION private.v483_apply_purchase_trace(p_tenant_id uuid, p_purchase_id uuid, p_supplier_id uuid, p_location_id uuid, p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  x jsonb;
  v_mode text;
  v_variant uuid;
  v_qty numeric;
  v_item_id uuid;
  v_serials jsonb;
  v_batches jsonb;
  v_count numeric;
  v_sum numeric;
  s jsonb;
  v_serial text;
  b jsonb;
  v_batch text;
  v_bqty numeric;
  v_mfg date;
  v_exp date;
  v_batch_id uuid;
  v_serial_id uuid;
  v_ref text;
  v_require boolean;
  v_seen_serials text[];
  v_seen_batches text[];
  v_quality text;
  v_purchase_cost numeric;
  v_selling_price numeric;
begin
  if exists(
    select 1
    from public.inventory_trace_events_v483
    where tenant_id=p_tenant_id
      and purchase_id=p_purchase_id
  ) then
    return;
  end if;

  select purchase_number
  into v_ref
  from public.purchases
  where tenant_id=p_tenant_id
    and id=p_purchase_id;

  for x in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    v_variant:=(x->>'variant_id')::uuid;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    if v_mode='none' then
      continue;
    end if;

    v_seen_serials:='{}'::text[];
    v_seen_batches:='{}'::text[];
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);

    select id
    into v_item_id
    from public.purchase_items
    where purchase_id=p_purchase_id
      and variant_id=v_variant
    limit 1;

    if v_item_id is null then
      raise exception 'Purchase line not found for tracked product';
    end if;

    if v_mode='serial' then
      if v_qty<>trunc(v_qty) then
        raise exception
          'Serial-tracked product % requires whole base units',v_variant;
      end if;

      v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);
      select count(*)::numeric
      into v_count
      from jsonb_array_elements(v_serials);

      if v_count<>v_qty then
        raise exception
          'Provide exactly % serial numbers for tracked purchase line',v_qty;
      end if;

      for s in select value from jsonb_array_elements(v_serials)
      loop
        v_serial:=trim(coalesce(
          case when jsonb_typeof(s)='string'
               then s#>>'{}'
               else s->>'serial_number'
          end,''
        ));

        if v_serial='' then
          raise exception 'Serial number cannot be blank';
        end if;

        if lower(v_serial)=any(v_seen_serials) then
          raise exception 'Duplicate serial number % on tracked purchase line',
            v_serial;
        end if;

        v_seen_serials:=array_append(v_seen_serials,lower(v_serial));

        insert into public.inventory_serials_v483(
          tenant_id,variant_id,serial_number,status,current_location_id,
          supplier_id,purchase_id,purchase_item_id,received_at,created_by
        )
        values(
          p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,now(),auth.uid()
        )
        returning id into v_serial_id;

        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,
          supplier_id,purchase_id,purchase_item_id,reference_number,
          source_key,created_by
        )
        values(
          p_tenant_id,v_variant,v_serial_id,'purchase',1,p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,v_ref,
          'purchase:'||p_purchase_id::text||':serial:'||v_serial_id::text,
          auth.uid()
        );
      end loop;
    else
      v_batches:=coalesce(x->'batches','[]'::jsonb);

      select coalesce(
        sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0
      )
      into v_sum
      from jsonb_array_elements(v_batches);

      if abs(v_sum-v_qty)>0.000001 then
        raise exception
          'Batch quantities must total base quantity %; received %',v_qty,v_sum;
      end if;

      select require_batch_expiry
      into v_require
      from public.product_tracking_policies_v483
      where tenant_id=p_tenant_id
        and variant_id=v_variant;

      for b in select value from jsonb_array_elements(v_batches)
      loop
        v_batch:=trim(coalesce(b->>'batch_number',''));
        v_bqty:=coalesce(nullif(b->>'quantity','')::numeric,0);
        v_mfg:=nullif(b->>'manufactured_on','')::date;
        v_exp:=nullif(b->>'expiry_on','')::date;
        v_quality:=nullif(trim(coalesce(b->>'quality_label','')),'');
        v_purchase_cost:=coalesce(
          nullif(b->>'purchase_cost_base','')::numeric,
          nullif(x->>'unit_cost','')::numeric
        );
        v_selling_price:=nullif(b->>'selling_price_base','')::numeric;

        if v_batch='' or v_bqty<=0 then
          raise exception
            'Each batch requires a batch number and positive quantity';
        end if;
        if lower(v_batch)=any(v_seen_batches) then
          raise exception 'Duplicate batch % on tracked purchase line',v_batch;
        end if;
        v_seen_batches:=array_append(v_seen_batches,lower(v_batch));

        if coalesce(v_require,false) and v_exp is null then
          raise exception 'Expiry date is required for batch %',v_batch;
        end if;
        if v_purchase_cost is not null and v_purchase_cost<0 then
          raise exception 'Batch purchase cost cannot be negative';
        end if;
        if v_selling_price is not null and v_selling_price<0 then
          raise exception 'Batch selling rate cannot be negative';
        end if;

        insert into public.inventory_batches_v483(
          tenant_id,variant_id,batch_number,manufactured_on,expiry_on,
          supplier_id,first_purchase_id,first_purchase_item_id,
          quality_label,purchase_cost_base,selling_price_base,created_by
        )
        values(
          p_tenant_id,v_variant,v_batch,v_mfg,v_exp,
          p_supplier_id,p_purchase_id,v_item_id,
          v_quality,v_purchase_cost,v_selling_price,auth.uid()
        )
        on conflict(tenant_id,variant_id,lower(trim(batch_number)))
        do update set
          manufactured_on=coalesce(
            public.inventory_batches_v483.manufactured_on,
            excluded.manufactured_on
          ),
          expiry_on=coalesce(
            public.inventory_batches_v483.expiry_on,
            excluded.expiry_on
          ),
          supplier_id=coalesce(
            public.inventory_batches_v483.supplier_id,
            excluded.supplier_id
          ),
          quality_label=coalesce(
            public.inventory_batches_v483.quality_label,
            excluded.quality_label
          ),
          purchase_cost_base=coalesce(
            public.inventory_batches_v483.purchase_cost_base,
            excluded.purchase_cost_base
          ),
          selling_price_base=coalesce(
            excluded.selling_price_base,
            public.inventory_batches_v483.selling_price_base
          ),
          status='active',
          updated_at=now()
        returning id into v_batch_id;

        if exists(
          select 1
          from public.inventory_batches_v483
          where id=v_batch_id
            and (
              (
                manufactured_on is not null
                and v_mfg is not null
                and manufactured_on<>v_mfg
              )
              or (
                expiry_on is not null
                and v_exp is not null
                and expiry_on<>v_exp
              )
            )
        ) then
          raise exception
            'Batch % already exists with different manufacture/expiry dates',
            v_batch;
        end if;

        insert into public.inventory_batch_balances_v483(
          tenant_id,batch_id,location_id,quantity
        )
        values(p_tenant_id,v_batch_id,p_location_id,v_bqty)
        on conflict(tenant_id,batch_id,location_id)
        do update set
          quantity=public.inventory_batch_balances_v483.quantity
                   +excluded.quantity,
          updated_at=now();

        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,
          supplier_id,purchase_id,purchase_item_id,reference_number,
          source_key,metadata,created_by
        )
        values(
          p_tenant_id,v_variant,v_batch_id,'purchase',v_bqty,p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,v_ref,
          'purchase:'||p_purchase_id::text||':item:'||v_item_id::text||
            ':batch:'||v_batch_id::text,
          jsonb_build_object(
            'quality_label',v_quality,
            'purchase_cost_base',v_purchase_cost,
            'selling_price_base',v_selling_price
          ),
          auth.uid()
        );
      end loop;
    end if;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION public.inventory_batch_search_v483(p_tenant_id uuid, p_query text DEFAULT ''::text, p_location_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id)
     or not private.v483_trace_view_allowed(p_tenant_id) then
    raise exception 'Traceability view permission required';
  end if;

  return query
  select jsonb_build_object(
    'batch_id',b.id,
    'batch_number',b.batch_number,
    'quality_label',b.quality_label,
    'purchase_cost_base',b.purchase_cost_base,
    'selling_price_base',b.selling_price_base,
    'status',b.status,
    'variant_id',b.variant_id,
    'product_name',p.name,
    'variant_name',pv.name,
    'sku',pv.sku,
    'manufactured_on',b.manufactured_on,
    'expiry_on',b.expiry_on,
    'expired',b.expiry_on is not null and b.expiry_on<current_date,
    'supplier_id',b.supplier_id,
    'supplier_name',sup.name,
    'purchase_id',b.first_purchase_id,
    'purchase_number',pur.purchase_number,
    'quantity',coalesce(sum(bb.quantity),0),
    'reserved_quantity',coalesce(sum(bb.reserved_quantity),0),
    'damaged_quantity',coalesce(sum(bb.damaged_quantity),0),
    'available_quantity',coalesce(sum(
      greatest(
        bb.quantity
        -coalesce(bb.reserved_quantity,0)
        -coalesce(bb.damaged_quantity,0),
        0
      )
    ),0),
    'locations',coalesce(
      jsonb_agg(
        distinct jsonb_build_object(
          'location_id',bb.location_id,
          'location_name',l.name,
          'quantity',bb.quantity,
          'reserved_quantity',bb.reserved_quantity,
          'damaged_quantity',bb.damaged_quantity,
          'available_quantity',greatest(
            bb.quantity
            -coalesce(bb.reserved_quantity,0)
            -coalesce(bb.damaged_quantity,0),
            0
          )
        )
      ) filter(where bb.location_id is not null),
      '[]'::jsonb
    )
  )
  from public.inventory_batches_v483 b
  join public.product_variants pv
    on pv.id=b.variant_id
   and pv.tenant_id=b.tenant_id
  join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
  left join public.inventory_batch_balances_v483 bb
    on bb.tenant_id=b.tenant_id
   and bb.batch_id=b.id
   and private.erp_document_scope_allowed(
     p_tenant_id,bb.location_id,p_location_id,'view'
   )
  left join public.business_locations l
    on l.id=bb.location_id
  left join public.suppliers sup
    on sup.id=b.supplier_id
  left join public.purchases pur
    on pur.id=b.first_purchase_id
  where b.tenant_id=p_tenant_id
    and (
      exists(
        select 1
        from public.inventory_batch_balances_v483 ab
        where ab.tenant_id=b.tenant_id
          and ab.batch_id=b.id
          and private.erp_document_scope_allowed(
            p_tenant_id,ab.location_id,p_location_id,'view'
          )
      )
      or exists(
        select 1
        from public.inventory_trace_events_v483 ae
        where ae.tenant_id=b.tenant_id
          and ae.batch_id=b.id
          and private.erp_document_scope_allowed(
            p_tenant_id,ae.location_id,p_location_id,'view'
          )
      )
    )
    and (
      trim(coalesce(p_query,''))=''
      or lower(b.batch_number) like q
      or lower(coalesce(b.quality_label,'')) like q
      or lower(coalesce(p.name,'')) like q
      or lower(coalesce(pv.sku,'')) like q
      or lower(coalesce(sup.name,'')) like q
      or exists(
        select 1
        from public.inventory_trace_events_v483 e
        left join public.customers c on c.id=e.customer_id
        left join public.sales s on s.id=e.sale_id
        left join public.purchases pp on pp.id=e.purchase_id
        where e.tenant_id=b.tenant_id
          and e.batch_id=b.id
          and private.erp_document_scope_allowed(
            p_tenant_id,e.location_id,p_location_id,'view'
          )
          and (
            lower(coalesce(c.name,'')) like q
            or lower(coalesce(s.sale_number,'')) like q
            or lower(coalesce(pp.purchase_number,'')) like q
            or lower(coalesce(e.reference_number,'')) like q
          )
      )
    )
  group by
    b.id,p.name,pv.name,pv.sku,sup.name,pur.purchase_number
  order by b.updated_at desc
  limit greatest(1,least(coalesce(p_limit,200),1000));
end
$function$;

CREATE OR REPLACE FUNCTION public.aggregate_yard_stock_v628(p_tenant_id uuid, p_location_id uuid DEFAULT NULL::uuid, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 300)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  if p_location_id is not null
     and exists(
       select 1
       from public.aggregate_direct_transit_locations_v621 m
       where m.tenant_id=p_tenant_id
         and m.transit_location_id=p_location_id
     ) then
    raise exception 'Direct Supply transit is not a physical yard location';
  end if;

  return query
  with material as (
    select
      b.variant_id,
      p.name product_name,
      pv.name variant_name,
      pv.sku,
      coalesce(u.code,'') base_unit_code,
      pv.cost_price master_cost_price,
      case
        when p_location_id is null then pv.selling_price
        else coalesce(max(lps.selling_price),pv.selling_price)
      end effective_selling_price,
      round(sum(b.quantity),3) on_hand,
      round(sum(coalesce(b.reserved_quantity,0)),3) reserved,
      round(sum(coalesce(b.damaged_quantity,0)),3) damaged,
      round(sum(coalesce(b.quarantine_quantity,0)),3) quarantine,
      round(sum(greatest(
        b.quantity
        -coalesce(b.reserved_quantity,0)
        -coalesce(b.damaged_quantity,0)
        -coalesce(b.quarantine_quantity,0),
        0
      )),3) available,
      round(
        coalesce(
          sum(b.quantity*coalesce(b.average_cost,pv.cost_price))
            /nullif(sum(b.quantity),0),
          pv.cost_price
        ),
        4
      ) average_cost
    from public.location_stock_balances b
    join public.product_variants pv
      on pv.id=b.variant_id
     and pv.tenant_id=b.tenant_id
     and pv.status='active'
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
     and p.status='active'
     and p.item_type='stock'
    left join public.product_units_v481 pbu
      on pbu.tenant_id=pv.tenant_id
     and pbu.variant_id=pv.id
     and pbu.is_base
     and pbu.active
    left join public.inventory_units_v481 u
      on u.id=pbu.unit_id
     and u.tenant_id=pbu.tenant_id
     and u.active
    left join public.location_product_settings lps
      on lps.tenant_id=b.tenant_id
     and lps.location_id=b.location_id
     and lps.variant_id=b.variant_id
     and lps.active
    where b.tenant_id=p_tenant_id
      and (p_location_id is null or b.location_id=p_location_id)
      and not exists(
        select 1
        from public.aggregate_direct_transit_locations_v621 m
        where m.tenant_id=b.tenant_id
          and m.transit_location_id=b.location_id
      )
      and private.erp_document_scope_allowed(
        p_tenant_id,b.location_id,p_location_id,'view'
      )
      and (
        p_query is null
        or trim(p_query)=''
        or p.name ilike '%'||trim(p_query)||'%'
        or pv.name ilike '%'||trim(p_query)||'%'
        or pv.sku ilike '%'||trim(p_query)||'%'
      )
    group by
      b.variant_id,p.name,pv.name,pv.sku,u.code,
      pv.cost_price,pv.selling_price
    having
      sum(b.quantity)<>0
      or sum(coalesce(b.reserved_quantity,0))<>0
      or sum(coalesce(b.damaged_quantity,0))<>0
      or sum(coalesce(b.quarantine_quantity,0))<>0
  )
  select jsonb_build_object(
    'variant_id',m.variant_id,
    'product_name',m.product_name,
    'variant_name',m.variant_name,
    'sku',m.sku,
    'base_unit_code',m.base_unit_code,
    'tracking_mode',private.v483_tracking_mode(p_tenant_id,m.variant_id),
    'on_hand',m.on_hand,
    'available',m.available,
    'reserved',m.reserved,
    'damaged',m.damaged,
    'quarantine',m.quarantine,
    'average_cost',m.average_cost,
    'master_cost_price',m.master_cost_price,
    'selling_price',m.effective_selling_price,
    'locations',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'location_id',x.location_id,
          'location_name',x.location_name,
          'on_hand',x.on_hand,
          'available',x.available,
          'reserved',x.reserved,
          'damaged',x.damaged,
          'quarantine',x.quarantine
        )
        order by x.location_name
      )
      from (
        select
          sb.location_id,
          bl.name location_name,
          round(sb.quantity,3) on_hand,
          round(greatest(
            sb.quantity
            -coalesce(sb.reserved_quantity,0)
            -coalesce(sb.damaged_quantity,0)
            -coalesce(sb.quarantine_quantity,0),
            0
          ),3) available,
          round(coalesce(sb.reserved_quantity,0),3) reserved,
          round(coalesce(sb.damaged_quantity,0),3) damaged,
          round(coalesce(sb.quarantine_quantity,0),3) quarantine
        from public.location_stock_balances sb
        join public.business_locations bl on bl.id=sb.location_id
        where sb.tenant_id=p_tenant_id
          and sb.variant_id=m.variant_id
          and (p_location_id is null or sb.location_id=p_location_id)
          and not exists(
            select 1
            from public.aggregate_direct_transit_locations_v621 tm
            where tm.tenant_id=sb.tenant_id
              and tm.transit_location_id=sb.location_id
          )
          and private.erp_document_scope_allowed(
            p_tenant_id,sb.location_id,p_location_id,'view'
          )
      ) x
    ),'[]'::jsonb),
    'batches',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'batch_id',x.batch_id,
          'batch_number',x.batch_number,
          'quality_label',x.quality_label,
          'purchase_cost_base',x.purchase_cost_base,
          'selling_price_base',x.selling_price_base,
          'supplier_name',x.supplier_name,
          'manufactured_on',x.manufactured_on,
          'expiry_on',x.expiry_on,
          'status',x.status,
          'on_hand',x.on_hand,
          'available',x.available,
          'reserved',x.reserved,
          'damaged',x.damaged
        )
        order by x.batch_number
      )
      from (
        select
          ib.id batch_id,
          ib.batch_number,
          ib.quality_label,
          ib.purchase_cost_base,
          ib.selling_price_base,
          sup.name supplier_name,
          ib.manufactured_on,
          ib.expiry_on,
          ib.status,
          round(sum(ibb.quantity),3) on_hand,
          round(sum(greatest(
            ibb.quantity
            -coalesce(ibb.reserved_quantity,0)
            -coalesce(ibb.damaged_quantity,0),
            0
          )),3) available,
          round(sum(coalesce(ibb.reserved_quantity,0)),3) reserved,
          round(sum(coalesce(ibb.damaged_quantity,0)),3) damaged
        from public.inventory_batches_v483 ib
        join public.inventory_batch_balances_v483 ibb
          on ibb.tenant_id=ib.tenant_id
         and ibb.batch_id=ib.id
        left join public.suppliers sup on sup.id=ib.supplier_id
        where ib.tenant_id=p_tenant_id
          and ib.variant_id=m.variant_id
          and (p_location_id is null or ibb.location_id=p_location_id)
          and not exists(
            select 1
            from public.aggregate_direct_transit_locations_v621 tm
            where tm.tenant_id=ibb.tenant_id
              and tm.transit_location_id=ibb.location_id
          )
          and private.erp_document_scope_allowed(
            p_tenant_id,ibb.location_id,p_location_id,'view'
          )
        group by
          ib.id,ib.batch_number,ib.quality_label,
          ib.purchase_cost_base,ib.selling_price_base,
          sup.name,ib.manufactured_on,ib.expiry_on,ib.status
        having
          sum(ibb.quantity)<>0
          or sum(coalesce(ibb.reserved_quantity,0))<>0
          or sum(coalesce(ibb.damaged_quantity,0))<>0
      ) x
    ),'[]'::jsonb)
  )
  from material m
  order by m.product_name,m.variant_name,m.sku
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$function$;

revoke all on function public.inventory_update_product_v628(
  uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric
) from public,anon;
grant execute on function public.inventory_update_product_v628(
  uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric
) to authenticated,service_role;

revoke all on function public.aggregate_vehicle_driver_save_v628(uuid,uuid,text,text)
from public,anon;
grant execute on function public.aggregate_vehicle_driver_save_v628(uuid,uuid,text,text)
to authenticated,service_role;

revoke all on function public.aggregate_yard_batch_profile_save_v628(uuid,uuid,text,numeric)
from public,anon;
grant execute on function public.aggregate_yard_batch_profile_save_v628(uuid,uuid,text,numeric)
to authenticated,service_role;

revoke all on function private.v628_batch_price_override(uuid,uuid,jsonb,uuid,numeric)
from public,anon,authenticated;

revoke all on function private.v482_price_sale_items(uuid,uuid,jsonb,uuid)
from public,anon,authenticated;

revoke all on function private.v483_apply_purchase_trace(uuid,uuid,uuid,uuid,jsonb)
from public,anon,authenticated;

revoke all on function public.inventory_batch_search_v483(uuid,text,uuid,integer)
from public,anon;
grant execute on function public.inventory_batch_search_v483(uuid,text,uuid,integer)
to authenticated,service_role;

revoke all on function public.aggregate_yard_stock_v628(uuid,uuid,text,integer)
from public,anon;
grant execute on function public.aggregate_yard_stock_v628(uuid,uuid,text,integer)
to authenticated,service_role;


update public.location_product_settings lps
set selling_price=pv.selling_price,
    updated_at=now()
from public.product_variants pv
where lps.tenant_id='0df82260-f683-4873-a999-865f39282723'::uuid
  and lps.location_id='93baf862-abc4-4931-a494-a8fc3b11d9e0'::uuid
  and lps.variant_id='a4321658-bcee-4a81-80b4-6ae975e67d24'::uuid
  and pv.id=lps.variant_id
  and pv.tenant_id=lps.tenant_id
  and lps.selling_price=0
  and pv.selling_price=25;


insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  329,
  '6.2.8-product-batch-yard-readiness',
  'Product Pricing Batch and Yard Readiness',
  'Keeps future location prices aligned with product master edits unless explicitly overridden; adds editable batch quality and selling rate metadata, authoritative batch-aware Sale pricing, simple truck driver maintenance, and a physical-yard stock register with batch detail. Existing posted invoices and GST snapshots are not rewritten.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
