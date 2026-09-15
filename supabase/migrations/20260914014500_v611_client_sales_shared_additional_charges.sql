-- THQ ERP v6.1.1
-- Shared Additional Charges setting + authoritative Client Sale wrapper.

create or replace function public.sales_additional_charges_enabled_v611(
  p_tenant_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_settings jsonb;
  v_raw text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  v_settings := public.tenant_settings_v2_get(p_tenant_id);
  v_raw := lower(
    trim(
      coalesce(
        v_settings->>'sales.additional_charges_enabled',
        'true'
      )
    )
  );

  return v_raw in ('true','1','yes','on');
end;
$$;

revoke all on function public.sales_additional_charges_enabled_v611(uuid)
from public;
grant execute on function public.sales_additional_charges_enabled_v611(uuid)
to authenticated,service_role;

create or replace function public.sales_commercial_quote_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
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
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  perform private.erp_validate_transaction_origin(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'sales'
  );

  if jsonb_typeof(coalesce(p_charge_selections,'[]'::jsonb)) <> 'array' then
    raise exception 'Additional charge selections must be an array';
  end if;

  if not public.sales_additional_charges_enabled_v611(p_tenant_id)
     and jsonb_array_length(coalesce(p_charge_selections,'[]'::jsonb)) > 0 then
    raise exception 'Additional charges are disabled in Business Settings';
  end if;

  return private.sales_commercial_expand_v610(
    p_tenant_id,
    p_order_type,
    p_items,
    p_discount_type,
    p_discount_value,
    p_charge_selections
  );
end;
$$;

create or replace function public.gst_client_sale_create_v611(
  p_tenant_id uuid,
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
  p_charge_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_enabled boolean;
  v_commercial jsonb;
  v_sale jsonb;
  v_sale_id uuid;
  v_summary jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  perform private.erp_validate_transaction_origin(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'sales'
  );

  if jsonb_typeof(coalesce(p_charge_selections,'[]'::jsonb)) <> 'array' then
    raise exception 'Additional charge selections must be an array';
  end if;

  v_enabled := public.sales_additional_charges_enabled_v611(p_tenant_id);

  if not v_enabled
     and jsonb_array_length(coalesce(p_charge_selections,'[]'::jsonb)) > 0 then
    raise exception 'Additional charges are disabled in Business Settings';
  end if;

  v_commercial := private.sales_commercial_expand_v610(
    p_tenant_id,
    'sale',
    p_items,
    'none',
    0,
    case
      when v_enabled then coalesce(p_charge_selections,'[]'::jsonb)
      else '[]'::jsonb
    end
  );

  v_sale := public.gst_sale_create_v522(
    p_tenant_id=>p_tenant_id,
    p_customer_id=>p_customer_id,
    p_sale_date=>p_sale_date,
    p_due_date=>p_due_date,
    p_items=>v_commercial->'items',
    p_payment_allocations=>coalesce(p_payment_allocations,'[]'::jsonb),
    p_notes=>p_notes,
    p_location_id=>p_location_id,
    p_device_id=>p_device_id,
    p_request_id=>p_request_id,
    p_supply_type=>p_supply_type,
    p_place_of_supply_code=>p_place_of_supply_code
  );

  v_sale_id := nullif(v_sale->>'sale_id','')::uuid;
  if v_sale_id is null then
    raise exception 'Client GST sale did not return a sale ID';
  end if;

  insert into public.sale_commercial_summary_v610(
    tenant_id,
    sale_id,
    source_type,
    source_id,
    order_type,
    discount_type,
    discount_value,
    document_discount_total,
    classified_charge_total,
    charge_breakdown
  )
  values(
    p_tenant_id,
    v_sale_id,
    'sale',
    null,
    'sale',
    'none',
    0,
    coalesce(
      nullif(v_commercial->>'document_discount_total','')::numeric,
      0
    ),
    coalesce(
      nullif(v_commercial->>'classified_charge_total','')::numeric,
      0
    ),
    coalesce(v_commercial->'charge_breakdown','[]'::jsonb)
  )
  on conflict(tenant_id,sale_id) do update set
    source_type=excluded.source_type,
    source_id=excluded.source_id,
    order_type=excluded.order_type,
    discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,
    document_discount_total=excluded.document_discount_total,
    classified_charge_total=excluded.classified_charge_total,
    charge_breakdown=excluded.charge_breakdown;

  v_summary := v_commercial - 'items';

  return coalesce(v_sale,'{}'::jsonb) || jsonb_build_object(
    'commercial_summary',v_summary,
    'additional_charges_enabled',v_enabled,
    'client_billing','v6.1.1-commercial-gst-v5.2.2',
    'legacy_fallback_used',false
  );
end;
$$;

revoke all on function public.gst_client_sale_create_v611(
  uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text,jsonb
) from public;

grant execute on function public.gst_client_sale_create_v611(
  uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text,jsonb
) to authenticated,service_role;
