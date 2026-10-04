begin;

-- Future price edits share the same transaction as their inherited location rates.
-- Existing transaction rows, GST snapshots and stock valuation are never rewritten.
CREATE OR REPLACE FUNCTION public.inventory_update_product_v628(p_tenant_id uuid, p_variant_id uuid, p_name text, p_description text, p_category_name text, p_brand_name text, p_sku text, p_barcode text, p_part_number text, p_cost_price numeric, p_selling_price numeric, p_list_price numeric, p_tax_rate numeric, p_reorder_level numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_old_selling numeric;
  v_old_cost numeric;
  v_result jsonb;
  v_synced integer:=0;
begin
  if not private.has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select selling_price,cost_price
  into v_old_selling,v_old_cost
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

  update public.product_units_v481
  set sale_price=case when sale_price is not null
        and abs(sale_price-coalesce(v_old_selling,0)*conversion_to_base)<=0.000001
        then p_selling_price*conversion_to_base else sale_price end,
      purchase_cost=case when purchase_cost is not null
        and abs(purchase_cost-coalesce(v_old_cost,0)*conversion_to_base)<=0.000001
        then p_cost_price*conversion_to_base else purchase_cost end,
      updated_at=now()
  where tenant_id=p_tenant_id and variant_id=p_variant_id
    and ((sale_price is not null and abs(sale_price-coalesce(v_old_selling,0)*conversion_to_base)<=0.000001)
      or (purchase_cost is not null and abs(purchase_cost-coalesce(v_old_cost,0)*conversion_to_base)<=0.000001));


  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'master_cost_price',p_cost_price,
    'master_selling_price',p_selling_price,
    'location_prices_synced',v_synced
  );
end
$function$;

create or replace function public.inventory_sale_batches_v628(
  p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_sale_date date
) returns setof jsonb language plpgsql stable security definer
set search_path=public,private,pg_temp as $function$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id)
    or not (private.erp_user_is_owner(p_tenant_id,auth.uid())
      or private.erp_has_permission(p_tenant_id,'sales.manage')
      or private.v483_trace_view_allowed(p_tenant_id)) then
    raise exception 'Sales or traceability permission required' using errcode='42501';
  end if;
  if p_location_id is null or not private.erp_document_scope_allowed(
      p_tenant_id,p_location_id,p_location_id,'view') then
    raise exception 'Yard location access required' using errcode='42501';
  end if;
  return query select jsonb_build_object(
    'batch_id',b.id,'batch_number',b.batch_number,'variant_id',b.variant_id,
    'quality_label',b.quality_label,'purchase_cost_base',b.purchase_cost_base,
    'selling_price_base',b.selling_price_base,'expiry_on',b.expiry_on,
    'available_quantity',greatest(bb.quantity-coalesce(bb.reserved_quantity,0)
      -coalesce(bb.damaged_quantity,0),0))
  from inventory_batches_v483 b
  join inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
  left join product_tracking_policies_v483 tp on tp.tenant_id=b.tenant_id and tp.variant_id=b.variant_id
  where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active'
    and bb.location_id=p_location_id
    and bb.quantity-coalesce(bb.reserved_quantity,0)-coalesce(bb.damaged_quantity,0)>0
    and (coalesce(tp.allow_expired_sale,false) or b.expiry_on is null
      or b.expiry_on>=coalesce(p_sale_date,current_date))
  order by b.expiry_on nulls last,b.created_at,b.batch_number;
end
$function$;

create or replace function public.pricing_resolve_batches_v628(
  p_tenant_id uuid,p_variant_id uuid,p_customer_id uuid,p_unit_id uuid,
  p_quantity numeric,p_location_id uuid,p_batches jsonb
) returns jsonb language plpgsql stable security definer
set search_path=public,private,pg_temp as $function$
declare v_price jsonb; v_batch jsonb; v_factor numeric; v_total numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if p_location_id is null or not private.erp_document_scope_allowed(
      p_tenant_id,p_location_id,p_location_id,'view') then
    raise exception 'Yard location access required' using errcode='42501';
  end if;
  v_price:=private.pricing_resolve_v482_internal(p_tenant_id,p_variant_id,
    p_customer_id,p_unit_id,p_quantity,p_location_id);
  select conversion_to_base into v_factor from product_units_v481
    where tenant_id=p_tenant_id and variant_id=p_variant_id
      and unit_id=(v_price->>'unit_id')::uuid and active and allow_sale;
  select sum((value->>'quantity')::numeric) into v_total from jsonb_array_elements(p_batches);
  if v_total is null or abs(v_total-p_quantity*v_factor)>0.000001 then
    raise exception 'Batch allocation must equal the sale base quantity';
  end if;
  if exists(select 1 from jsonb_array_elements(p_batches)
    group by value->>'batch_id' having count(*)>1) then
    raise exception 'Choose each batch only once';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_batches) x
    left join inventory_batches_v483 b on b.id=(x->>'batch_id')::uuid
      and b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active'
    left join inventory_batch_balances_v483 bb on bb.batch_id=b.id
      and bb.tenant_id=b.tenant_id and bb.location_id=p_location_id
    where b.id is null or bb.batch_id is null or (x->>'quantity')::numeric<=0
      or (x->>'quantity')::numeric>bb.quantity-coalesce(bb.reserved_quantity,0)-coalesce(bb.damaged_quantity,0)
  ) then raise exception 'Selected batch quantity is unavailable in this yard';end if;
  if not exists(select 1 from location_stock_balances sb
      where tenant_id=p_tenant_id and variant_id=p_variant_id and location_id=p_location_id
        and sb.quantity-coalesce(sb.reserved_quantity,0)-coalesce(sb.damaged_quantity,0)
          -coalesce(sb.quarantine_quantity,0)>=v_total) then
    raise exception 'Insufficient available physical stock in this yard';
  end if;
  v_batch:=private.v628_batch_price_override(p_tenant_id,p_variant_id,
    p_batches,(v_price->>'unit_id')::uuid,(v_price->>'unit_price')::numeric);
  if coalesce((v_batch->>'batch_specific')::boolean,false) then
    v_price:=v_price||jsonb_build_object('unit_price',v_batch->'unit_price','source','batch_price');
  end if;
  return v_price;
end
$function$;
CREATE OR REPLACE FUNCTION private.v483_apply_batch_sale(p_tenant_id uuid, p_variant_id uuid, p_sale_id uuid, p_sale_item_id uuid, p_customer_id uuid, p_location_id uuid, p_sale_date date, p_quantity numeric, p_requested jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_remaining numeric:=p_quantity;v_out jsonb:='[]'::jsonb;v_allow_expired boolean:=false;r record;x jsonb;v_batch_id uuid;v_take numeric;v_requested_qty numeric;v_batch_number text;v_seen uuid[]:='{}'::uuid[];v_ref text;v_available numeric;
begin
 select allow_expired_sale into v_allow_expired from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 if jsonb_array_length(coalesce(p_requested,'[]'::jsonb))>0 then
  for x in select value from jsonb_array_elements(p_requested) loop
   v_requested_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);if v_requested_qty<=0 then raise exception 'Requested batch quantity must be positive';end if;
   v_batch_id:=null;
   if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid;else
    v_batch_number:=trim(coalesce(x->>'batch_number',''));select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(v_batch_number);end if;
   if v_batch_id is null then raise exception 'Batch not found for tracked product';end if;
   if v_batch_id=any(v_seen) then raise exception 'The same batch cannot appear twice on one sale line';end if;v_seen:=array_append(v_seen,v_batch_id);
   select b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0)-coalesce(bb.damaged_quantity,0) available_quantity into r
     from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
     where b.tenant_id=p_tenant_id and b.id=v_batch_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and b.status='active' for update of bb;
   v_available:=coalesce(r.available_quantity,0);
   if not found or v_available+0.000001<v_requested_qty then raise exception 'Insufficient unreserved quantity in selected batch %',coalesce(r.batch_number,v_batch_number);end if;
   if not coalesce(v_allow_expired,false) and r.expiry_on is not null and r.expiry_on<p_sale_date then raise exception 'Batch % expired on %',r.batch_number,r.expiry_on;end if;
   update public.inventory_batch_balances_v483 set quantity=quantity-v_requested_qty,updated_at=now() where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
     values(p_tenant_id,p_variant_id,v_batch_id,'sale',v_requested_qty,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||v_batch_id::text,
      (select jsonb_build_object('quality_label',b.quality_label,'selling_price_base',b.selling_price_base,
        'purchase_cost_base',b.purchase_cost_base,'allocation','selected') from inventory_batches_v483 b where b.id=v_batch_id),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,v_batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_requested_qty,p_sale_date);
   v_remaining:=v_remaining-v_requested_qty;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',v_batch_id,'batch_number',r.batch_number,'quantity',v_requested_qty,'expiry_on',r.expiry_on));
  end loop;
  if abs(v_remaining)>0.000001 then raise exception 'Selected batch quantities must equal required base quantity %',p_quantity;end if;
 else
  for r in
    select b.id batch_id,b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0)-coalesce(bb.damaged_quantity,0) available_quantity
    from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
    where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id
      and bb.quantity-coalesce(bb.reserved_quantity,0)-coalesce(bb.damaged_quantity,0)>0 and b.status='active'
      and (coalesce(v_allow_expired,false) or b.expiry_on is null or b.expiry_on>=p_sale_date)
    order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number for update of bb
  loop
   exit when v_remaining<=0.000001;v_take:=least(v_remaining,r.available_quantity);
   update public.inventory_batch_balances_v483 set quantity=quantity-v_take,updated_at=now() where tenant_id=p_tenant_id and batch_id=r.batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
     values(p_tenant_id,p_variant_id,r.batch_id,'sale',v_take,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||r.batch_id::text,(select jsonb_build_object('allocation','FEFO','quality_label',b.quality_label,
    'selling_price_base',b.selling_price_base,'purchase_cost_base',b.purchase_cost_base) from inventory_batches_v483 b where b.id=r.batch_id),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,r.batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_take,p_sale_date);
   v_remaining:=v_remaining-v_take;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',r.batch_id,'batch_number',r.batch_number,'quantity',v_take,'expiry_on',r.expiry_on));
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient eligible unreserved batch stock. Required %, unavailable %',p_quantity,v_remaining;end if;
 end if;
 update public.inventory_batches_v483 b set status='exhausted',updated_at=now()
 where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active'
   and not exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=b.tenant_id and bb.batch_id=b.id and bb.quantity>0);
 return v_out;
end$function$

;
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
      pv.id variant_id,
      p.name product_name,
      pv.name variant_name,
      pv.sku,
      coalesce(u.code,'') base_unit_code,
      pv.cost_price master_cost_price,
      case
        when p_location_id is null then pv.selling_price
        else coalesce(max(lps.selling_price),pv.selling_price)
      end effective_selling_price,
      round(sum(coalesce(b.quantity,0)),3) on_hand,
      round(sum(coalesce(b.reserved_quantity,0)),3) reserved,
      round(sum(coalesce(b.damaged_quantity,0)),3) damaged,
      round(sum(coalesce(b.quarantine_quantity,0)),3) quarantine,
      round(sum(greatest(
        coalesce(b.quantity,0)
        -coalesce(b.reserved_quantity,0)
        -coalesce(b.damaged_quantity,0)
        -coalesce(b.quarantine_quantity,0),
        0
      )),3) available,
      round(
        coalesce(
          sum(b.quantity*coalesce(b.average_cost,pv.cost_price))
            /nullif(sum(coalesce(b.quantity,0)),0),
          pv.cost_price
        ),
        4
      ) average_cost
    from public.product_variants pv
    join public.business_locations scope on scope.tenant_id=pv.tenant_id and scope.active
      and (p_location_id is null or scope.id=p_location_id)
      and not exists(select 1 from aggregate_direct_transit_locations_v621 tm
        where tm.tenant_id=scope.tenant_id and tm.transit_location_id=scope.id)
      and private.erp_document_scope_allowed(p_tenant_id,scope.id,p_location_id,'view')
    left join public.location_stock_balances b on b.tenant_id=pv.tenant_id
      and b.variant_id=pv.id and b.location_id=scope.id
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
    where pv.tenant_id=p_tenant_id and pv.status='active'

      and (
        p_query is null
        or trim(p_query)=''
        or p.name ilike '%'||trim(p_query)||'%'
        or pv.name ilike '%'||trim(p_query)||'%'
        or pv.sku ilike '%'||trim(p_query)||'%'
      )
    group by
      pv.id,p.name,pv.name,pv.sku,u.code,
      pv.cost_price,pv.selling_price

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
    'received',coalesce((select sum(greatest(sm.quantity_delta,0)) from location_stock_movements sm
      where sm.tenant_id=p_tenant_id and sm.variant_id=m.variant_id and sm.movement_type='purchase'
        and (p_location_id is null or sm.location_id=p_location_id)
        and not exists(select 1 from aggregate_direct_transit_locations_v621 tm
          where tm.tenant_id=sm.tenant_id and tm.transit_location_id=sm.location_id)
        and private.erp_document_scope_allowed(p_tenant_id,sm.location_id,p_location_id,'view')),0),
    'dispatched',coalesce((select sum(greatest(-sm.quantity_delta,0)) from location_stock_movements sm
      where sm.tenant_id=p_tenant_id and sm.variant_id=m.variant_id and sm.movement_type='sale'
        and (p_location_id is null or sm.location_id=p_location_id)
        and not exists(select 1 from aggregate_direct_transit_locations_v621 tm
          where tm.tenant_id=sm.tenant_id and tm.transit_location_id=sm.location_id)
        and private.erp_document_scope_allowed(p_tenant_id,sm.location_id,p_location_id,'view')),0),
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

  if not exists(select 1 from inventory_batch_balances_v483 bb
    where bb.tenant_id=p_tenant_id and bb.batch_id=p_batch_id
      and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,null,'view')) then
    raise exception 'Batch location access required' using errcode='42501';
  end if;
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

  if v_before.location_id is not null and not private.erp_document_scope_allowed(
      p_tenant_id,v_before.location_id,null,'view') then
    raise exception 'Truck location access required' using errcode='42501';
  end if;
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

revoke all on function public.inventory_sale_batches_v628(uuid,uuid,uuid,date) from public,anon;
grant execute on function public.inventory_sale_batches_v628(uuid,uuid,uuid,date) to authenticated,service_role;
revoke all on function public.pricing_resolve_batches_v628(uuid,uuid,uuid,uuid,numeric,uuid,jsonb) from public,anon;
grant execute on function public.pricing_resolve_batches_v628(uuid,uuid,uuid,uuid,numeric,uuid,jsonb) to authenticated,service_role;
revoke all on function private.v483_apply_batch_sale(uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,jsonb) from public,anon,authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(330,'6.2.8-material-yard-workflow-integrity','Material Yard Workflow Integrity',
  'Scoped batch selection and rate preview; excludes reserved and damaged batch stock; captures new trace quality/rate metadata; includes zero-stock materials and posted movements in Yard Stock; keeps inherited future unit rates aligned. Posted invoices stay unchanged.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,
  release_name=excluded.release_name,notes=excluded.notes;
commit;
