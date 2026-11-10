-- THQ ERP Material Yard Negotiated Pricing Clarification (v713)
-- 1. Update public.aggregate_load_list_v629 to expose actual invoice_rate, invoice_amount, and invoice_number
-- 2. Update public.aggregate_load_detail_v629 to include invoice_rate and invoice_amount in JSONB detail
-- 3. Update private.load_evidence_v630 to attach full purchase evidence with line items (pi.unit_cost)
--    and direct invoice resolution metrics for Crusher Register and load reports

-- 1. Drop and recreate aggregate_load_list_v629 with invoice resolution fields
drop function if exists public.aggregate_load_list_v629(uuid, uuid, text, text, integer);

create or replace function public.aggregate_load_list_v629(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_status text default null::text,
  p_query text default null::text,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  variant_id uuid,
  supplier_id uuid,
  customer_id uuid,
  product_name text,
  quantity numeric,
  unit_code text,
  measurement_method text,
  vehicle_id uuid,
  vehicle_registration text,
  driver_name text,
  supplier_name text,
  customer_name text,
  source_name text,
  destination_name text,
  source_reference text,
  freight_mode text,
  freight_amount numeric,
  purchase_id uuid,
  sale_id uuid,
  order_id uuid,
  order_line_id uuid,
  order_number text,
  created_at timestamp with time zone,
  invoice_rate numeric,
  invoice_amount numeric,
  invoice_number text
)
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,
    l.load_number,
    l.load_date,
    l.direction,
    l.status,
    l.location_id,
    l.variant_id,
    l.supplier_id,
    l.customer_id,
    l.product_name_snapshot,
    l.quantity,
    l.unit_code,
    l.measurement_method,
    l.vehicle_id,
    l.vehicle_registration_snapshot,
    l.driver_name_snapshot,
    s.name,
    c.name,
    l.source_name,
    l.destination_name,
    l.source_reference,
    l.freight_mode,
    l.freight_amount,
    l.purchase_id,
    l.sale_id,
    l.order_id,
    l.order_line_id,
    o.order_number,
    l.created_at,
    -- Actual negotiated transaction rate
    case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select pi.unit_cost
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select si.unit_price
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_price', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id
          and d.load_id = l.id
        limit 1
      )
    end as invoice_rate,
    -- Actual allocated invoice amount
    case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select round(l.quantity * pi.unit_cost, 2)
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select round(l.quantity * si.unit_price, 2)
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_total', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id
          and d.load_id = l.id
        limit 1
      )
    end as invoice_amount,
    -- Linked invoice number
    case
      when l.direction = 'inbound' and l.purchase_id is not null then pd.purchase_number
      when l.direction = 'outbound' and l.sale_id is not null then sd.sale_number
      else null
    end as invoice_number
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id = l.supplier_id and s.tenant_id = l.tenant_id
  left join public.customers c
    on c.id = l.customer_id and c.tenant_id = l.tenant_id
  left join public.purchases pd
    on pd.id = l.purchase_id and pd.tenant_id = l.tenant_id
  left join public.sales sd
    on sd.id = l.sale_id and sd.tenant_id = l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id = l.order_id and o.tenant_id = l.tenant_id
  where l.tenant_id = p_tenant_id
    and l.direction <> 'direct_delivery'
    and private.erp_document_scope_allowed(p_tenant_id, l.location_id, p_location_id, 'view')
    and (p_status is null or trim(p_status) = '' or l.status = lower(trim(p_status)))
    and (
      p_query is null or trim(p_query) = ''
      or l.load_number ilike '%' || trim(p_query) || '%'
      or l.product_name_snapshot ilike '%' || trim(p_query) || '%'
      or coalesce(l.vehicle_registration_snapshot, '') ilike '%' || trim(p_query) || '%'
      or coalesce(l.driver_name_snapshot, '') ilike '%' || trim(p_query) || '%'
      or coalesce(s.name, '') ilike '%' || trim(p_query) || '%'
      or coalesce(c.name, '') ilike '%' || trim(p_query) || '%'
      or coalesce(o.order_number, '') ilike '%' || trim(p_query) || '%'
      or coalesce(pd.purchase_number, '') ilike '%' || trim(p_query) || '%'
      or coalesce(sd.sale_number, '') ilike '%' || trim(p_query) || '%'
    )
  order by l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 300), 1000));
end
$function$;

revoke all on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer) from public, anon;
grant execute on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer) to authenticated, service_role;


-- 2. Update aggregate_load_detail_v629 to include actual invoice rate and allocated amount
create or replace function public.aggregate_load_detail_v629(p_tenant_id uuid, p_load_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'load_id', l.id,
    'load_number', l.load_number,
    'load_date', l.load_date,
    'direction', l.direction,
    'status', l.status,
    'location_id', l.location_id,
    'variant_id', l.variant_id,
    'product_name', l.product_name_snapshot,
    'unit_code', l.unit_code,
    'quantity', l.quantity,
    'measurement_method', l.measurement_method,
    'body_length_ft', l.body_length_ft,
    'body_width_ft', l.body_width_ft,
    'body_height_ft', l.body_height_ft,
    'gross_weight_kg', l.gross_weight_kg,
    'tare_weight_kg', l.tare_weight_kg,
    'net_weight_kg', l.net_weight_kg,
    'vehicle_id', l.vehicle_id,
    'driver_id', l.driver_id,
    'vehicle_registration', l.vehicle_registration_snapshot,
    'driver_name', l.driver_name_snapshot,
    'supplier_name', s.name,
    'customer_name', c.name,
    'sale_number', sd.sale_number,
    'purchase_number', pd.purchase_number,
    'supplier_id', l.supplier_id,
    'customer_id', l.customer_id,
    'source_name', l.source_name,
    'destination_name', l.destination_name,
    'source_reference', l.source_reference,
    'freight_mode', l.freight_mode,
    'freight_amount', l.freight_amount,
    'capacity_override', l.capacity_override,
    'capacity_override_reason', l.capacity_override_reason,
    'notes', l.notes,
    'purchase_id', l.purchase_id,
    'sale_id', l.sale_id,
    'order_id', l.order_id,
    'order_line_id', l.order_line_id,
    'invoice_rate', case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select pi.unit_cost
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select si.unit_price
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_price', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id
          and d.load_id = l.id
        limit 1
      )
    end,
    'invoice_amount', case
      when l.direction = 'inbound' and l.purchase_id is not null then (
        select round(l.quantity * pi.unit_cost, 2)
        from public.purchase_items pi
        where pi.tenant_id = l.tenant_id
          and pi.purchase_id = l.purchase_id
          and pi.variant_id = l.variant_id
        order by pi.created_at, pi.id
        limit 1
      )
      when l.direction = 'outbound' and l.sale_id is not null then (
        select round(l.quantity * si.unit_price, 2)
        from public.sale_items si
        where si.tenant_id = l.tenant_id
          and si.sale_id = l.sale_id
          and si.variant_id = l.variant_id
        order by si.created_at, si.id
        limit 1
      )
      else (
        select nullif(d.details->>'purchasing_total', '')::numeric
        from public.material_load_delivery_v630 d
        where d.tenant_id = l.tenant_id
          and d.load_id = l.id
        limit 1
      )
    end,
    'invoice_number', case
      when l.direction = 'inbound' and l.purchase_id is not null then pd.purchase_number
      when l.direction = 'outbound' and l.sale_id is not null then sd.sale_number
      else null
    end
  )
  into v_result
  from public.aggregate_loads_v617 l
  left join public.suppliers s on s.id = l.supplier_id and s.tenant_id = l.tenant_id
  left join public.customers c on c.id = l.customer_id and c.tenant_id = l.tenant_id
  left join public.sales sd on sd.id = l.sale_id and sd.tenant_id = l.tenant_id
  left join public.purchases pd on pd.id = l.purchase_id and pd.tenant_id = l.tenant_id
  where l.id = p_load_id
    and l.tenant_id = p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id, l.location_id, null, 'view');

  if v_result is null then
    raise exception 'Load not found';
  end if;

  return v_result;
end
$function$;

revoke all on function public.aggregate_load_detail_v629(uuid, uuid) from public, anon;
grant execute on function public.aggregate_load_detail_v629(uuid, uuid) to authenticated, service_role;


-- 3. Update private.load_evidence_v630 to return full purchase with line items
create or replace function private.load_evidence_v630(t uuid, load uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  l public.aggregate_loads_v617%rowtype;
  result jsonb;
begin
  select * into l from public.aggregate_loads_v617 where tenant_id = t and id = load;
  if not found then raise exception 'Load not found'; end if;
  perform private.yard_cost_assert_v630(t, l.location_id, false);
  result := public.aggregate_load_detail_v629(t, load);
  return result || jsonb_build_object(
    'load_record', to_jsonb(l),
    'trip', coalesce((select to_jsonb(h) from public.transport_trip_hub_v611 h where h.tenant_id = t and h.material_load_id = load), '{}'::jsonb),
    'driver_current', coalesce((select to_jsonb(d) from public.logistics_drivers_v61 d where d.tenant_id = t and d.id = l.driver_id), '{}'::jsonb),
    'vehicle_current', coalesce((select to_jsonb(v) || jsonb_build_object('yard_profile', (select to_jsonb(p) from public.aggregate_vehicle_profiles_v617 p where p.tenant_id = t and p.vehicle_id = v.id)) from public.service_vehicles v where v.tenant_id = t and v.id = l.vehicle_id), '{}'::jsonb),
    'load_events', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at, e.id) from public.aggregate_load_events_v617 e where e.tenant_id = t and e.load_id = load), '[]'::jsonb),
    'location_name', (select name from public.business_locations where tenant_id = t and id = l.location_id),
    'legacy_freight_payments', coalesce((select jsonb_agg(to_jsonb(f) order by f.settled_at) from public.aggregate_freight_settlements_v620 f where f.tenant_id = t and f.load_id = load), '[]'::jsonb),
    'sale', coalesce((
      select to_jsonb(s) || jsonb_build_object(
        'items', coalesce((
          select jsonb_agg(to_jsonb(si) order by si.created_at, si.id)
          from public.sale_items si
          where si.tenant_id = t and si.sale_id = s.id
        ), '[]'::jsonb)
      )
      from public.sales s
      where s.tenant_id = t and s.id = l.sale_id
    ), '{}'::jsonb),
    'purchase', coalesce((
      select to_jsonb(p) || jsonb_build_object(
        'items', coalesce((
          select jsonb_agg(to_jsonb(pi) order by pi.created_at, pi.id)
          from public.purchase_items pi
          where pi.tenant_id = t and pi.purchase_id = p.id
        ), '[]'::jsonb)
      )
      from public.purchases p
      where p.tenant_id = t and p.id = l.purchase_id
    ), '{}'::jsonb),
    'customer_payments', coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.tenant_id = t and p.sale_id = l.sale_id), '[]'::jsonb),
    'delivery', coalesce((select details from public.material_load_delivery_v630 where tenant_id = t and load_id = load), '{}'::jsonb),
    'costs', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('paid_amount', coalesce(private.load_cost_paid_v630(c.id), 0), 'outstanding', case when c.staff_mode = 'salary_allocation' or c.status <> 'posted' then 0 else c.amount - coalesce(private.load_cost_paid_v630(c.id), 0) end, 'billing_service', (select p.name from public.product_variants v join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id where v.id = c.billing_variant_id and v.tenant_id = t)) order by c.created_at, c.id) from public.material_load_costs_v630 c where c.tenant_id = t and c.load_id = load), '[]'::jsonb),
    'cost_payments', coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('cost_description', c.description, 'payee', c.payee) order by p.payment_date, p.created_at) from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id = p.cost_id and c.tenant_id = p.tenant_id where c.tenant_id = t and c.load_id = load), '[]'::jsonb),
    'staff_payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'payment_date', p.payment_date, 'amount', a.amount, 'payment_method', p.payment_method, 'reference', p.reference, 'payee', p.payee_snapshot, 'cost_id', c.id, 'cost_description', c.description, 'from_advance', a.from_advance, 'journal_id', a.journal_id, 'notes', p.notes) order by p.payment_date, p.created_at) from public.material_load_costs_v630 c join public.staff_payment_allocations_v630 a on a.earning_id = c.staff_earning_id join public.staff_payments_v630 p on p.id = a.payment_id and p.tenant_id = c.tenant_id where c.tenant_id = t and c.load_id = load), '[]'::jsonb),
    'cost_total', coalesce((select sum(amount) from public.material_load_costs_v630 where tenant_id = t and load_id = load and status <> 'void'), 0),
    'customer_charge_total', coalesce((select sum(bill_amount) from public.material_load_costs_v630 where tenant_id = t and load_id = load and status <> 'void'), 0),
    'history', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.workforce_audit_v630 a where a.tenant_id = t and a.load_id = load), '[]'::jsonb)
  );
end $$;
