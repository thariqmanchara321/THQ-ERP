-- THQ ERP v4.8.9 — restaurant stabilization, unit-aware menu lines and authoritative pricing.
-- Restaurant order prices are resolved on the server using the v4.8.2 pricing engine.
begin;

alter table public.restaurant_order_items
  add column if not exists unit_id uuid references public.inventory_units_v481(id) on delete set null,
  add column if not exists conversion_to_base numeric not null default 1,
  add column if not exists pricing_source text,
  add column if not exists price_list_id uuid references public.price_lists_v482(id) on delete set null,
  add column if not exists pricing_metadata jsonb not null default '{}'::jsonb;

-- Backfill the historical lines with the product base/default sale unit where possible.
update public.restaurant_order_items i
set unit_id = coalesce(
      i.unit_id,
      (select pu.unit_id from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id and pu.active and pu.is_default_sale limit 1),
      (select pu.unit_id from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id and pu.active and pu.is_base limit 1)
    ),
    conversion_to_base = coalesce(
      (select pu.conversion_to_base from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id
         and pu.unit_id=coalesce(
           i.unit_id,
           (select pu2.unit_id from public.product_units_v481 pu2 where pu2.tenant_id=i.tenant_id and pu2.variant_id=i.variant_id and pu2.active and pu2.is_default_sale limit 1),
           (select pu3.unit_id from public.product_units_v481 pu3 where pu3.tenant_id=i.tenant_id and pu3.variant_id=i.variant_id and pu3.active and pu3.is_base limit 1)
         ) and pu.active limit 1),
      1
    ),
    pricing_source=coalesce(i.pricing_source,'legacy_snapshot')
where i.unit_id is null or i.pricing_source is null;

create index if not exists idx_restaurant_order_items_unit_v489
  on public.restaurant_order_items(tenant_id,variant_id,unit_id);

-- Authoritative, location-scoped restaurant order creation. Client-provided price/tax
-- values are deliberately ignored; only product/unit/quantity/discount/note are accepted.
create or replace function public.restaurant_order_create_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_order_type text,p_table_id uuid,p_customer_id uuid,
  p_preparation_minutes integer,p_chef_note text,p_delivery_address text,p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
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

  -- Resolve all prices first. The pricing helper also resolves a missing unit_id to the
  -- configured default sale/base unit.
  v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);

  insert into public.restaurant_orders(
    id,tenant_id,location_id,device_id,order_number,order_type,table_id,customer_id,
    preparation_minutes,chef_note,delivery_address,created_by
  ) values(
    v_id,p_tenant_id,p_location_id,p_device_id,'',p_order_type,p_table_id,p_customer_id,
    greatest(coalesce(p_preparation_minutes,15),0),nullif(trim(p_chef_note),''),nullif(trim(p_delivery_address),''),auth.uid()
  ) returning order_number,tracking_code into v_order,v_track;

  for x in select value from jsonb_array_elements(v_priced) loop
    -- Normalization validates unit enablement, quantity step/fraction rules and conversion.
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

    select coalesce(pv.tax_rate,0) into v_tax
    from public.product_variants pv
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
  perform private.thq_sync_bump_v480(p_tenant_id,'restaurant','restaurant_order',v_id::text,'create');
  return jsonb_build_object('order_id',v_id,'order_number',v_order,'tracking_code',v_track,'pricing_engine','v4.8.2','restaurant_engine','v4.8.9');
end $$;
grant execute on function public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb) to authenticated;

-- Bill a restaurant order atomically. A deterministic request ID makes retries safe if
-- the client loses connectivity after the sale is created but before it receives the response.
create or replace function public.restaurant_order_bill_v489(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid,p_customer_id uuid,p_due_date date,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_round_off numeric default 0
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;v_customer uuid;v_items jsonb;v_sale jsonb;v_sale_id uuid;v_existing jsonb;
  v_total numeric;v_method text;
begin
  select * into o from public.restaurant_orders
  where id=p_order_id and tenant_id=p_tenant_id for update;
  if o.id is null then raise exception 'Restaurant order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,o.location_id,p_device_id,'restaurant','operate');
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'restaurant.order')
     and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then
    raise exception 'Restaurant billing permission denied';
  end if;
  if o.status='cancelled' then raise exception 'Cancelled restaurant order cannot be billed';end if;
  if o.status='billed' and o.sale_id is not null then
    select jsonb_build_object('success',true,'idempotent',true,'order_id',o.id,'sale_id',s.id,
      'sale_number',s.sale_number,'grand_total',s.grand_total,'round_off',coalesce(s.round_off,0))
      into v_existing from public.sales s where s.id=o.sale_id and s.tenant_id=p_tenant_id;
    if v_existing is not null then return v_existing;end if;
  end if;
  v_customer:=coalesce(o.customer_id,p_customer_id);
  if v_customer is null or not exists(
    select 1 from public.customers c where c.id=v_customer and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
  ) then raise exception 'Choose an active customer before billing';end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'variant_id',i.variant_id,'quantity',i.quantity,'unit_id',i.unit_id,
      'unit_price',i.unit_price,'discount_amount',i.discount_amount,'tax_rate',i.tax_rate
    )) order by i.created_at,i.id),'[]'::jsonb)
    into v_items from public.restaurant_order_items i where i.order_id=o.id and i.tenant_id=p_tenant_id;
  if jsonb_array_length(v_items)=0 then raise exception 'Restaurant order has no items';end if;
  v_method:=coalesce(nullif(lower(trim(p_payment_method)),''),'cash');
  -- Create the sale without a payment first. This lets the authoritative pricing engine
  -- determine the exact current total; non-credit restaurant bills are then settled for
  -- that server total in the same transaction, so a changed price cannot strand billing.
  v_sale:=public.sales_create_v489(
    p_tenant_id,v_customer,current_date,p_due_date,v_items,0,coalesce(p_round_off,0),
    0,v_method,coalesce(p_payment_reference,''),'Restaurant '||o.order_number,o.location_id,p_device_id,
    'restaurant-bill:'||o.id::text
  );
  v_sale_id:=nullif(v_sale->>'sale_id','')::uuid;
  if v_sale_id is null then raise exception 'Restaurant sale was not created';end if;
  v_total:=coalesce(nullif(v_sale->>'grand_total','')::numeric,0);
  if v_method<>'credit' and v_total>0.005 then
    perform public.sales_add_payment_v47(
      p_tenant_id,v_sale_id,v_total,v_method,coalesce(p_payment_reference,''),
      'Restaurant settlement '||o.order_number,'restaurant-payment:'||o.id::text
    );
    v_sale:=v_sale||jsonb_build_object('paid_total',v_total,'balance_due',0);
  end if;
  update public.restaurant_orders set status='billed',sale_id=v_sale_id,billed_at=coalesce(billed_at,now()),updated_at=now()
   where id=o.id and tenant_id=p_tenant_id;
  update public.restaurant_kots set status='served',served_at=coalesce(served_at,now())
   where tenant_id=p_tenant_id and order_id=o.id and status not in('served','cancelled');
  perform private.thq_sync_bump_v480(p_tenant_id,'restaurant','restaurant_order',o.id::text,'bill');
  return coalesce(v_sale,'{}'::jsonb)||jsonb_build_object('success',true,'order_id',o.id,'restaurant_billing','v4.8.9');
end $$;
grant execute on function public.restaurant_order_bill_v489(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric) to authenticated;

-- Add concise restaurant operational metrics for the redesigned Floor / Orders / Kitchen workspace.
create or replace function public.restaurant_operations_summary_v489(
  p_tenant_id uuid,p_location_id uuid default null,p_device_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_tables bigint:=0;v_occupied bigint:=0;v_open bigint:=0;v_queue bigint:=0;v_preparing bigint:=0;v_ready bigint:=0;v_sales numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_device_id is not null and p_location_id is not null then
    perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','view');
  end if;
  select count(*) into v_tables from public.restaurant_tables t
   where t.tenant_id=p_tenant_id and t.active
     and (p_location_id is null or t.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,t.location_id,p_location_id,'view');
  select count(distinct r.table_id),count(*)
    into v_occupied,v_open
    from public.restaurant_orders r
   where r.tenant_id=p_tenant_id and r.status not in('billed','cancelled')
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select count(*) filter(where k.status='queued'),count(*) filter(where k.status='preparing'),count(*) filter(where k.status='ready')
    into v_queue,v_preparing,v_ready
    from public.restaurant_kots k
   where k.tenant_id=p_tenant_id and k.status not in('served','cancelled')
     and (p_location_id is null or k.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,k.location_id,p_location_id,'view');
  select coalesce(sum(s.grand_total),0) into v_sales
    from public.restaurant_orders r join public.sales s on s.id=r.sale_id and s.tenant_id=r.tenant_id
   where r.tenant_id=p_tenant_id and r.status='billed' and s.sale_date=current_date
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  return jsonb_build_object(
    'tables',v_tables,'occupied_tables',v_occupied,'available_tables',greatest(v_tables-v_occupied,0),
    'open_orders',v_open,'kot_queued',v_queue,'kot_preparing',v_preparing,'kot_ready',v_ready,
    'restaurant_sales_today',round(v_sales,2)
  );
end $$;
grant execute on function public.restaurant_operations_summary_v489(uuid,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(177,'4.8.9','Stabilization & Operations','Restaurant V2 stabilization: authoritative pricing/tax, unit-aware order lines and operations summary for Floor/Orders/Kitchen.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 177 restaurant pricing and operations applied' as status;
