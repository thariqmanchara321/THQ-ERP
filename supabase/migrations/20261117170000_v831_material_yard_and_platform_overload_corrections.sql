-- Migration 20261117170000_v831_material_yard_and_platform_overload_corrections.sql
-- Description:
-- 1. Drops obsolete narrower function signatures from v628-v709 that caused ambiguous overload errors (42725).
-- 2. Eliminates variable name collision (v_sale_id vs table column id) in public.aggregate_load_sale_create_v630.
-- 3. Aligns customer validation message with v632 contract ('Select the customer recorded on the confirmed Load Ticket').

-- ============================================================================
-- 1. Drop Obsolete Narrower Overloads
-- ============================================================================
DROP FUNCTION IF EXISTS public.aggregate_load_sale_create_v630(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb
);

DROP FUNCTION IF EXISTS public.aggregate_load_purchase_create_v629(
  uuid, uuid, uuid, text, date, date, jsonb, numeric, numeric, numeric, text, text, text, uuid, uuid, text, text, text
);

DROP FUNCTION IF EXISTS public.aggregate_load_edit_v628(
  uuid, uuid, text, uuid, uuid, numeric, text, text, numeric, numeric, numeric, numeric, numeric, numeric, uuid, uuid, uuid, uuid, text, text, text, text, numeric, boolean, text, text
);

DROP FUNCTION IF EXISTS public.platform_device_issue_activation_v709(
  uuid, uuid, text, text, text
);

-- ============================================================================
-- 2. Update private.aggregate_load_sale_core_v630 (Aligned Customer Message)
-- ============================================================================
CREATE OR REPLACE FUNCTION private.aggregate_load_sale_core_v630(
  p_tenant_id uuid,
  p_load_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_due_date date,
  p_items jsonb,
  p_payment_allocations jsonb,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_supply_type text,
  p_place_of_supply_code text,
  p_charge_selections jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_load public.aggregate_loads_v617%rowtype;
  v_result jsonb;
  v_id uuid;
begin
  v_load := private.aggregate_load_document_lock_v629(p_tenant_id, p_load_id, 'outbound', p_location_id);
  if v_load.customer_id is not null and v_load.customer_id is distinct from p_customer_id then
    raise exception 'Select the customer recorded on the confirmed Load Ticket';
  end if;

  v_result := public.gst_client_sale_create_v611(
    p_tenant_id, p_customer_id, p_sale_date, p_due_date, p_items, p_payment_allocations,
    p_notes, p_location_id, p_device_id, p_request_id, p_supply_type, p_place_of_supply_code, p_charge_selections
  );

  v_id := nullif(v_result->>'sale_id', '')::uuid;
  if v_id is null then
    raise exception 'Authoritative Sale did not return a sale ID';
  end if;

  perform public.aggregate_load_link_document_v617(p_tenant_id, p_load_id, 'sale', v_id);

  update public.aggregate_loads_v617
  set customer_id = coalesce(customer_id, p_customer_id)
  where id = p_load_id and tenant_id = p_tenant_id and customer_id is null;

  return v_result || jsonb_build_object('material_load_id', p_load_id, 'load_linked', true);
end;
$function$;

revoke all on function private.aggregate_load_sale_core_v630(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb
) from public, anon, authenticated;

-- ============================================================================
-- 3. Update public.aggregate_load_sale_create_v630 (Fix Ambiguous Variable Name & Align Message)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.aggregate_load_sale_create_v630(
  p_tenant_id uuid,
  p_load_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_due_date date,
  p_items jsonb,
  p_payment_allocations jsonb,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_supply_type text,
  p_place_of_supply_code text,
  p_charge_selections jsonb DEFAULT '[]'::jsonb,
  p_load_updated_at timestamptz DEFAULT null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  l public.aggregate_loads_v617%rowtype;
  result jsonb;
  items jsonb;
  v_sale_id uuid;
begin
  l := private.aggregate_load_document_lock_v629(p_tenant_id, p_load_id, 'outbound', p_location_id);

  -- Concurrency check: load modified after billing draft opened
  if p_load_updated_at is not null and l.updated_at > p_load_updated_at then
    raise exception 'The load was modified in Material Yard after this sale draft was opened. Please refresh to inspect the latest load details before posting.';
  end if;

  -- Validate customer matches load ticket
  if l.customer_id is not null and l.customer_id is distinct from p_customer_id then
    raise exception 'Select the customer recorded on the confirmed Load Ticket';
  end if;

  perform private.load_costs_post_v630(p_tenant_id, p_load_id);
  items := private.load_sale_items_v630(p_tenant_id, p_load_id, p_items, p_sale_date);

  result := private.aggregate_load_sale_core_v630(
    p_tenant_id, p_load_id, p_customer_id, p_sale_date, p_due_date, items,
    p_payment_allocations, p_notes, p_location_id, p_device_id, p_request_id,
    p_supply_type, p_place_of_supply_code, p_charge_selections
  );

  v_sale_id := (result->>'sale_id')::uuid;

  insert into public.material_load_sale_snapshots_v630(sale_id, tenant_id, load_id, evidence)
  values (
    v_sale_id, p_tenant_id, p_load_id,
    private.load_evidence_v630(p_tenant_id, p_load_id) || jsonb_build_object(
      'invoice_items_entered', p_items,
      'invoice_terms_entered', jsonb_build_object(
        'customer_id', p_customer_id,
        'sale_date', p_sale_date,
        'due_date', p_due_date,
        'notes', p_notes,
        'supply_type', p_supply_type,
        'place_of_supply_code', p_place_of_supply_code,
        'payment_allocations', p_payment_allocations,
        'charge_selections', p_charge_selections
      ),
      'snapshot_at', now()
    )
  )
  on conflict(sale_id) do nothing;

  update public.aggregate_loads_v617
  set customer_id = coalesce(customer_id, p_customer_id),
      status = 'completed',
      updated_at = now()
  where id = p_load_id and tenant_id = p_tenant_id;

  return result || jsonb_build_object('load_costs_recorded', true);
end $function$;

revoke all on function public.aggregate_load_sale_create_v630(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb, timestamptz
) from public, anon;

grant execute on function public.aggregate_load_sale_create_v630(
  uuid, uuid, uuid, date, date, jsonb, jsonb, text, uuid, uuid, text, text, text, jsonb, timestamptz
) to authenticated, service_role;
