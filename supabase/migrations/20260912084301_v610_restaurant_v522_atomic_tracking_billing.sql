create or replace function public.gst_restaurant_order_bill_v522(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_customer_id uuid,
  p_due_date date,
  p_payment_allocations jsonb,
  p_tracking_assignments jsonb default '[]'::jsonb,
  p_notes text default null,
  p_supply_type text default null,
  p_place_of_supply_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  v_customer uuid;
  v_items jsonb;
  v_wrapper_request text;
  v_sale_request text;
  v_req_payload jsonb;
  v_req_state jsonb;
  v_sale jsonb;
  v_sale_id uuid;
  v_snapshot uuid;
  v_journal uuid;
  v_response jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant billing permission denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.manage')
  ) then
    raise exception 'Sales permission required for Restaurant invoice posting';
  end if;

  if not (
    private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
    or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
  ) then
    raise exception 'GST calculation permission required';
  end if;

  if p_order_id is null then
    raise exception 'Restaurant order is required';
  end if;

  if jsonb_typeof(coalesce(p_payment_allocations,'[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant payment allocations must be an array';
  end if;

  if jsonb_typeof(coalesce(p_tracking_assignments,'[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant tracking assignments must be an array';
  end if;

  v_wrapper_request := 'gst-restaurant-order-v522:' || p_order_id::text;
  v_sale_request := 'gst-restaurant-sale-v522:' || p_order_id::text;

  v_req_payload := jsonb_build_object(
    'order_id', p_order_id,
    'device_id', p_device_id,
    'customer_id', p_customer_id,
    'due_date', p_due_date,
    'payment_allocations', coalesce(p_payment_allocations,'[]'::jsonb),
    'tracking_assignments', coalesce(p_tracking_assignments,'[]'::jsonb),
    'notes', nullif(trim(coalesce(p_notes,'')),''),
    'supply_type', nullif(upper(trim(coalesce(p_supply_type,''))),''),
    'place_of_supply_code', nullif(trim(coalesce(p_place_of_supply_code,'')),'')
  );

  v_req_state := private.gst_request_begin_v520(
    p_tenant_id,
    v_wrapper_request,
    'gst.restaurant.order.bill.v522',
    v_req_payload
  );

  if coalesce((v_req_state->>'existing')::boolean,false) then
    return v_req_state->'response';
  end if;

  select *
  into o
  from public.restaurant_orders
  where id = p_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Restaurant order not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    o.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if o.status = 'cancelled' then
    raise exception 'Cancelled restaurant order cannot be billed';
  end if;

  if o.status = 'billed' or o.sale_id is not null then
    raise exception 'Restaurant order is already billed; reconcile the existing invoice instead of converting it silently';
  end if;

  v_customer := coalesce(o.customer_id,p_customer_id);
  if v_customer is null or not exists (
    select 1
    from public.customers c
    where c.id = v_customer
      and c.tenant_id = p_tenant_id
      and coalesce(c.status,'active') = 'active'
  ) then
    raise exception 'Choose an active customer before billing';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'variant_id', i.variant_id,
          'quantity', greatest(i.quantity - coalesce(i.cancelled_quantity,0),0),
          'unit_id', i.unit_id,
          'unit_price', i.unit_price,
          'discount_amount',
            case
              when i.quantity > 0 then round(
                i.discount_amount *
                (greatest(i.quantity - coalesce(i.cancelled_quantity,0),0) / i.quantity),
                6
              )
              else 0
            end,
          'serial_numbers', coalesce(a.serial_numbers,'[]'::jsonb),
          'batches', coalesce(a.batches,'[]'::jsonb)
        )
      )
      order by i.created_at, i.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.restaurant_order_items i
  left join lateral (
    select
      coalesce(x.value->'serial_numbers','[]'::jsonb) as serial_numbers,
      coalesce(x.value->'batches','[]'::jsonb) as batches
    from jsonb_array_elements(coalesce(p_tracking_assignments,'[]'::jsonb)) x(value)
    where x.value->>'order_item_id' = i.id::text
    limit 1
  ) a on true
  where i.order_id = o.id
    and i.tenant_id = p_tenant_id
    and greatest(i.quantity - coalesce(i.cancelled_quantity,0),0) > 0;

  if jsonb_array_length(v_items) = 0 then
    raise exception 'Restaurant order has no billable items';
  end if;

  v_sale := public.gst_sale_create_v522(
    p_tenant_id => p_tenant_id,
    p_customer_id => v_customer,
    p_sale_date => current_date,
    p_due_date => p_due_date,
    p_items => v_items,
    p_payment_allocations => coalesce(p_payment_allocations,'[]'::jsonb),
    p_notes => concat_ws(' | ', 'Restaurant ' || o.order_number, nullif(trim(coalesce(p_notes,'')),'')),
    p_location_id => o.location_id,
    p_device_id => p_device_id,
    p_request_id => v_sale_request,
    p_supply_type => p_supply_type,
    p_place_of_supply_code => p_place_of_supply_code
  );

  v_sale_id := nullif(v_sale->>'sale_id','')::uuid;
  v_snapshot := nullif(v_sale->>'gst_snapshot_id','')::uuid;
  v_journal := nullif(v_sale->>'journal_id','')::uuid;

  if v_sale_id is null or v_snapshot is null or v_journal is null then
    raise exception 'Restaurant GST v5.2.2 Sale did not create complete authoritative evidence';
  end if;

  update public.restaurant_orders
  set status = 'billed',
      sale_id = v_sale_id,
      billed_at = coalesce(billed_at,now()),
      updated_at = now()
  where id = o.id
    and tenant_id = p_tenant_id
    and status <> 'cancelled'
    and sale_id is null;

  if not found then
    raise exception 'Restaurant order billing state changed concurrently';
  end if;

  update public.restaurant_kots
  set status = 'served',
      served_at = coalesce(served_at,now())
  where tenant_id = p_tenant_id
    and order_id = o.id
    and status not in ('served','cancelled');

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    o.id::text,
    'bill_v522'
  );

  v_response := coalesce(v_sale,'{}'::jsonb) || jsonb_build_object(
    'success', true,
    'order_id', o.id,
    'order_number', o.order_number,
    'restaurant_billing', 'v5.2.2-gst',
    'tracking_assignments_applied', jsonb_array_length(coalesce(p_tracking_assignments,'[]'::jsonb)),
    'legacy_fallback_used', false
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'restaurant.order.bill.gst_v522',
    'restaurant_order',
    o.id,
    o.order_number,
    to_jsonb(o),
    jsonb_build_object(
      'sale_id', v_sale_id,
      'sale_number', v_sale->>'sale_number',
      'grand_total', v_sale->>'grand_total',
      'payments', v_sale->'payments',
      'gst_snapshot_id', v_snapshot,
      'journal_id', v_journal,
      'tracking_assignments', coalesce(p_tracking_assignments,'[]'::jsonb),
      'void_aware', true,
      'multi_payment', true
    )
  );

  v_response := private.gst_request_complete_v520(
    p_tenant_id,
    v_wrapper_request,
    'gst.restaurant.order.bill.v522',
    'restaurant_order',
    o.id,
    v_snapshot,
    v_journal,
    v_response
  );

  return v_response;
end;
$$;

revoke all on function public.gst_restaurant_order_bill_v522(uuid,uuid,uuid,uuid,date,jsonb,jsonb,text,text,text) from public;
grant execute on function public.gst_restaurant_order_bill_v522(uuid,uuid,uuid,uuid,date,jsonb,jsonb,text,text,text) to authenticated, service_role;

create or replace function public.gst_transaction_cutover_contract_v522(
  p_tenant_id uuid,
  p_channel text default 'client',
  p_device_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v jsonb;
  v_channel text := lower(trim(coalesce(p_channel,'client')));
begin
  v := public.gst_transaction_cutover_contract_v520(
    p_tenant_id,
    p_channel,
    p_device_id
  );

  if v_channel='client' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object(
          'sale','gst_sale_create_v522',
          'restaurant_bill_v522','gst_restaurant_order_bill_v522'
        ),
      true
    );
  elsif v_channel='pos' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object(
          'sale','gst_pos_sale_create_v522',
          'restaurant_bill_v522','gst_restaurant_order_bill_v522'
        ),
      true
    );
  elsif v_channel in ('pos_offline','offline_pos') then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object('sale_sync','gst_pos_offline_sale_sync_v522'),
      true
    );
  elsif v_channel='mobile_pos' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object(
          'sale_sync','gst_mobile_pos_sale_sync_v522',
          'purchase','gst_mobile_pos_purchase_create_v522',
          'restaurant_bill_v522','gst_restaurant_order_bill_v522'
        ),
      true
    );
  end if;

  v := v || jsonb_build_object(
    'version','5.2.2',
    'build',30,
    'multi_payment',true,
    'automatic_round_off',true,
    'legacy_fallback_after_v522_failure',false,
    'additional_charges','service_products_only',
    'restaurant_v522_atomic_billing',true,
    'restaurant_tracking_assignments',true,
    'payment_methods',jsonb_build_array(
      'cash','upi','card','bank','cheque','wallet','credit','other'
    )
  );
  return v;
end;
$$;
