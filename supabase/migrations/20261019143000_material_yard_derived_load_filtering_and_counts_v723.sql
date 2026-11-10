-- ============================================================================
-- Migration: 20261019143000_material_yard_derived_load_filtering_and_counts_v723.sql
-- Description: Material Yard Derived Load Workflow Filtering, Authoritative Grand Totals, and Summary Counts
-- ============================================================================

-- 1. Drop existing aggregate_load_list_v629 to support enhanced return columns & workflow filtering
drop function if exists public.aggregate_load_list_v629(uuid, uuid, text, text, integer);
drop function if exists public.aggregate_load_list_v629(uuid, uuid, text, text, integer, text);

-- 2. Enhanced aggregate_load_list_v629 with workflow status, authoritative invoice totals & direction filtering
create or replace function public.aggregate_load_list_v629(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_status text default null::text,
  p_query text default null::text,
  p_limit integer default 500,
  p_direction text default null::text
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
  invoice_number text,
  invoice_status text,
  invoice_grand_total numeric,
  is_rate_pending boolean,
  workflow_status text
)
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  with load_base as (
    select
      l.id as b_load_id,
      l.load_number as b_load_number,
      l.load_date as b_load_date,
      l.direction as b_direction,
      l.status as b_status,
      l.location_id as b_location_id,
      l.variant_id as b_variant_id,
      l.supplier_id as b_supplier_id,
      l.customer_id as b_customer_id,
      l.product_name_snapshot as b_product_name,
      l.quantity as b_quantity,
      l.unit_code as b_unit_code,
      l.measurement_method as b_measurement_method,
      l.vehicle_id as b_vehicle_id,
      l.vehicle_registration_snapshot as b_vehicle_registration,
      l.driver_name_snapshot as b_driver_name,
      s.name as b_supplier_name,
      c.name as b_customer_name,
      l.source_name as b_source_name,
      l.destination_name as b_destination_name,
      l.source_reference as b_source_reference,
      l.freight_mode as b_freight_mode,
      l.freight_amount as b_freight_amount,
      l.purchase_id as b_purchase_id,
      l.sale_id as b_sale_id,
      l.order_id as b_order_id,
      l.order_line_id as b_order_line_id,
      o.order_number as b_order_number,
      l.created_at as b_created_at,
      pd.purchase_number as b_pd_number,
      pd.status as b_pd_status,
      pd.grand_total as b_pd_grand_total,
      sd.sale_number as b_sd_number,
      sd.status as b_sd_status,
      sd.grand_total as b_sd_grand_total,
      -- Pricing resolution
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
        when l.direction = 'outbound' then (
          select nullif(d.details->>'selling_price', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
        else (
          select nullif(d.details->>'purchasing_price', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
      end as b_invoice_rate,
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
        when l.direction = 'outbound' then (
          select nullif(d.details->>'selling_total', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
        else (
          select nullif(d.details->>'purchasing_total', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
      end as b_invoice_amount
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
      and (p_location_id is null or l.location_id = p_location_id)
      and (p_direction is null or p_direction = 'all' or l.direction = p_direction)
      and (
        p_query is null or trim(p_query) = ''
        or l.load_number ilike '%' || trim(p_query) || '%'
        or l.product_name_snapshot ilike '%' || trim(p_query) || '%'
        or coalesce(l.vehicle_registration_snapshot, '') ilike '%' || trim(p_query) || '%'
        or coalesce(l.driver_name_snapshot, '') ilike '%' || trim(p_query) || '%'
        or coalesce(s.name, '') ilike '%' || trim(p_query) || '%'
        or coalesce(c.name, '') ilike '%' || trim(p_query) || '%'
        or coalesce(l.source_reference, '') ilike '%' || trim(p_query) || '%'
        or coalesce(pd.purchase_number, '') ilike '%' || trim(p_query) || '%'
        or coalesce(sd.sale_number, '') ilike '%' || trim(p_query) || '%'
        or coalesce(l.source_name, '') ilike '%' || trim(p_query) || '%'
        or coalesce(l.destination_name, '') ilike '%' || trim(p_query) || '%'
      )
  ),
  classified as (
    select
      b.*,
      case
        when b.b_direction = 'inbound' and b.b_purchase_id is not null then b.b_pd_number
        when b.b_direction = 'outbound' and b.b_sale_id is not null then b.b_sd_number
        else null
      end as c_invoice_number,
      case
        when b.b_direction = 'inbound' and b.b_purchase_id is not null then b.b_pd_status
        when b.b_direction = 'outbound' and b.b_sale_id is not null then b.b_sd_status
        else null
      end as c_invoice_status,
      case
        when b.b_direction = 'inbound' and b.b_purchase_id is not null then b.b_pd_grand_total
        when b.b_direction = 'outbound' and b.b_sale_id is not null then b.b_sd_grand_total
        else null
      end as c_invoice_grand_total,
      (b.b_invoice_rate is null or b.b_invoice_rate <= 0) as c_is_rate_pending,
      -- Authoritative Billed flag
      case
        when b.b_direction = 'inbound' and b.b_purchase_id is not null and b.b_pd_status = 'posted' then true
        when b.b_direction = 'outbound' and b.b_sale_id is not null and b.b_sd_status = 'posted' then true
        else false
      end as c_is_billed
    from load_base b
  ),
  with_workflow as (
    select
      c.*,
      case
        when c.b_status = 'cancelled' then 'cancelled'
        when c.b_status = 'draft' then 'draft'
        when c.c_is_billed then 'billed'
        when c.b_status = 'completed' and c.c_is_rate_pending then 'rate_pending'
        when c.b_status = 'completed' then 'unbilled'
        else c.b_status
      end as c_workflow_status
    from classified c
  )
  select
    w.b_load_id,
    w.b_load_number,
    w.b_load_date,
    w.b_direction,
    w.b_status,
    w.b_location_id,
    w.b_variant_id,
    w.b_supplier_id,
    w.b_customer_id,
    w.b_product_name,
    w.b_quantity,
    w.b_unit_code,
    w.b_measurement_method,
    w.b_vehicle_id,
    w.b_vehicle_registration,
    w.b_driver_name,
    w.b_supplier_name,
    w.b_customer_name,
    w.b_source_name,
    w.b_destination_name,
    w.b_source_reference,
    w.b_freight_mode,
    w.b_freight_amount,
    w.b_purchase_id,
    w.b_sale_id,
    w.b_order_id,
    w.b_order_line_id,
    w.b_order_number,
    w.b_created_at,
    w.b_invoice_rate,
    w.b_invoice_amount,
    w.c_invoice_number,
    w.c_invoice_status,
    w.c_invoice_grand_total,
    w.c_is_rate_pending,
    w.c_workflow_status
  from with_workflow w
  where
    p_status is null
    or p_status = 'all'
    or (p_status = 'needs_action' and w.b_status <> 'cancelled' and not w.c_is_billed)
    or (p_status = 'unbilled' and w.b_status = 'completed' and not w.c_is_billed)
    or (p_status = 'rate_pending' and w.b_status <> 'cancelled' and not w.c_is_billed and w.c_is_rate_pending)
    or (p_status = 'billed' and w.c_is_billed)
    or (p_status = 'draft' and w.b_status = 'draft')
    or (p_status = 'cancelled' and w.b_status = 'cancelled')
    or (p_status = 'completed' and w.b_status = 'completed')
  order by
    -- Prioritize pending actionable work, then by date descending
    case when p_status = 'needs_action' or p_status is null then
      case when w.b_status <> 'cancelled' and not w.c_is_billed then 0 else 1 end
    else 0 end,
    w.b_load_date desc,
    w.b_created_at desc
  limit greatest(1, least(coalesce(p_limit, 500), 1000));
end;
$function$;

revoke all on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer, text) from public, anon;
grant execute on function public.aggregate_load_list_v629(uuid, uuid, text, text, integer, text) to authenticated, service_role;

-- 3. Authoritative Complete Load Workflow Counts (Independent of Page Limits)
create or replace function public.aggregate_load_counts_v723(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_direction text default null::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_needs_action int := 0;
  v_unbilled int := 0;
  v_billed int := 0;
  v_rate_pending int := 0;
  v_draft int := 0;
  v_cancelled int := 0;
  v_total int := 0;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  with load_pricing as (
    select
      l.id,
      l.direction,
      l.status,
      l.purchase_id,
      l.sale_id,
      pd.status as purchase_status,
      sd.status as sale_status,
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
        when l.direction = 'outbound' then (
          select nullif(d.details->>'selling_price', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
        else (
          select nullif(d.details->>'purchasing_price', '')::numeric
          from public.material_load_delivery_v630 d
          where d.tenant_id = l.tenant_id and d.load_id = l.id
          limit 1
        )
      end as resolved_rate,
      case
        when l.direction = 'inbound' and l.purchase_id is not null and pd.status = 'posted' then true
        when l.direction = 'outbound' and l.sale_id is not null and sd.status = 'posted' then true
        else false
      end as is_billed
    from public.aggregate_loads_v617 l
    left join public.purchases pd
      on pd.id = l.purchase_id and pd.tenant_id = l.tenant_id
    left join public.sales sd
      on sd.id = l.sale_id and sd.tenant_id = l.tenant_id
    where l.tenant_id = p_tenant_id
      and (p_location_id is null or l.location_id = p_location_id)
      and (p_direction is null or p_direction = 'all' or l.direction = p_direction)
  )
  select
    count(*),
    count(*) filter (where status <> 'cancelled' and not is_billed),
    count(*) filter (where status = 'completed' and not is_billed),
    count(*) filter (where is_billed),
    count(*) filter (where status <> 'cancelled' and not is_billed and (resolved_rate is null or resolved_rate <= 0)),
    count(*) filter (where status = 'draft'),
    count(*) filter (where status = 'cancelled')
  into
    v_total,
    v_needs_action,
    v_unbilled,
    v_billed,
    v_rate_pending,
    v_draft,
    v_cancelled
  from load_pricing;

  return jsonb_build_object(
    'needs_action_count', v_needs_action,
    'unbilled_count', v_unbilled,
    'billed_count', v_billed,
    'rate_pending_count', v_rate_pending,
    'draft_count', v_draft,
    'cancelled_count', v_cancelled,
    'total_count', v_total
  );
end;
$function$;

revoke all on function public.aggregate_load_counts_v723(uuid, uuid, text) from public, anon;
grant execute on function public.aggregate_load_counts_v723(uuid, uuid, text) to authenticated, service_role;
