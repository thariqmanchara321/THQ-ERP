-- 363_v716_authoritative_gst_and_nongst_mode_separation.sql
-- ============================================================================
-- THQ ERP v7.1.6 — Final GST / Non-GST Separation & Authorization Hardening
--
-- 1. Authoritative server-side tax-mode resolution supporting:
--    - Business temporal tax mode (gst_tenant_tax_modes_v520)
--    - Location-specific GST registration mapping (gst_location_registrations_v520)
--    - Transaction-effective dates
--    - Safe Non-GST fallback for unregistered operations
-- 2. Clean permission separation:
--    - Non-GST operations require only module permissions (sales, purchases, returns,
--      restaurant, transport/service) without demanding GST compliance roles.
--    - GST operations strictly enforce legal compliance, profiles, and snapshots.
-- 3. Purchases, Sales Returns, Purchase Returns, Restaurant & Transport:
--    - Allow Non-GST execution with 0 tax lines and clean double-entry accounting.
-- 4. Offline POS Sync:
--    - Eliminates false TAX_CHANGED conflicts in Non-GST mode.
-- 5. Additional charges:
--    - Supports commercial freight/transport in Non-GST mode while preserving strict
--      tax-classification rules in GST Registered mode.
-- ============================================================================

-- 1. Upgraded Tax Mode Resolution with location and date scoping
create or replace function private.gst_tax_mode_resolve_v520(
  p_tenant_id uuid,
  p_location_id uuid,
  p_date date default current_date
)
returns text
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  d date := coalesce(p_date, current_date);
  v_mode text;
  v_loc_reg text;
begin
  -- A. Check if the location is specifically mapped to an active GST registration on this date
  if p_location_id is not null then
    select r.registration_type into v_loc_reg
    from public.gst_location_registrations_v520 lr
    join public.gst_registrations_v520 r on r.id = lr.registration_id and r.tenant_id = lr.tenant_id
    where lr.tenant_id = p_tenant_id
      and lr.location_id = p_location_id
      and r.active = true
      and d between lr.effective_from and coalesce(lr.effective_to, 'infinity'::date)
      and d between r.effective_from and coalesce(r.effective_to, 'infinity'::date)
    limit 1;

    if v_loc_reg is not null then
      return 'gst_registered';
    end if;
  end if;

  -- B. Check authoritative temporal tenant tax modes
  select m.tax_mode into v_mode
  from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id = p_tenant_id
    and d between m.effective_from and coalesce(m.effective_to, 'infinity'::date)
  order by m.effective_from desc, m.created_at desc
  limit 1;

  if v_mode is not null then
    return v_mode;
  end if;

  -- C. Fallback: If GST registration/settings exist but no mode is configured, signal unconfigured
  if exists(select 1 from public.gst_tenant_tax_modes_v520 m where m.tenant_id = p_tenant_id and m.tax_mode = 'gst_registered')
     or exists(select 1 from public.gst_registrations_v520 r where r.tenant_id = p_tenant_id and r.active = true)
     or exists(select 1 from public.business_locations l where l.tenant_id = p_tenant_id and nullif(trim(l.gstin), '') is not null)
     or exists(select 1 from public.tenant_settings s where s.tenant_id = p_tenant_id and
               coalesce(nullif(trim(s.config->>'business.gstin'), ''), nullif(trim(s.config#>>'{business,gstin}'), '')) is not null)
  then
    return 'unconfigured';
  else
    return 'non_gst';
  end if;
end;
$function$;

-- Overload maintaining 2-parameter backward compatibility
create or replace function private.gst_tax_mode_resolve_v520(
  p_tenant_id uuid,
  p_date date default current_date
)
returns text
language sql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
  select private.gst_tax_mode_resolve_v520(p_tenant_id, null::uuid, p_date);
$function$;

-- 2. Upgraded Calculation Permission Check
create or replace function private.invoice_calculate_allowed_v632(
  p_tenant_id uuid,
  p_date date,
  p_kind text
)
returns boolean
language sql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
 select private.erp_user_has_tenant_access(p_tenant_id) and (
   -- 1. Business owner is always authorized
   private.erp_user_is_owner(p_tenant_id, auth.uid())
   -- 2. Dedicated GST compliance role
   or private.gst_v520_has_access(p_tenant_id, 'gst_compliance.calculate')
   or private.gst_v520_has_access(p_tenant_id, 'gst_compliance.view')
   -- 3. Non-GST mode allows module-specific operational permissions without GST roles
   or (
     private.gst_tax_mode_resolve_v520(p_tenant_id, p_date) = 'non_gst' and (
       case 
         when lower(trim(coalesce(p_kind,''))) in ('sale','pos','counter') then
           (private.erp_has_permission(p_tenant_id, 'sales.manage') or private.erp_has_permission(p_tenant_id, 'sales.create'))
         when lower(trim(coalesce(p_kind,''))) in ('purchase','purchase_order','purchase_invoice','purchase_invoice_v484') then
           (private.erp_has_permission(p_tenant_id, 'purchases.manage') or private.erp_has_permission(p_tenant_id, 'purchases.create'))
         when lower(trim(coalesce(p_kind,''))) in ('sales_return','sale_return') then
           (private.erp_has_permission(p_tenant_id, 'sales.manage') or private.erp_has_permission(p_tenant_id, 'sales.return'))
         when lower(trim(coalesce(p_kind,''))) in ('purchase_return') then
           (private.erp_has_permission(p_tenant_id, 'purchases.manage') or private.erp_has_permission(p_tenant_id, 'purchases.return'))
         when lower(trim(coalesce(p_kind,''))) in ('restaurant') then
           (private.erp_has_permission(p_tenant_id, 'restaurant.manage') or private.erp_has_permission(p_tenant_id, 'restaurant.order') or private.erp_has_permission(p_tenant_id, 'sales.manage'))
         when lower(trim(coalesce(p_kind,''))) in ('service','transport') then
           (private.erp_has_permission(p_tenant_id, 'transport_service.manage') or private.erp_has_permission(p_tenant_id, 'transport_service.create') or private.erp_has_permission(p_tenant_id, 'sales.manage'))
         else false
       end
     )
   )
 );
$fn$;

-- 3. Upgraded Items Stripping for Non-GST mode
create or replace function private.sale_items_for_tax_mode_v632(
  p_tenant_id uuid,
  p_date date,
  p_items jsonb
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
begin
 if private.gst_tax_mode_resolve_v520(p_tenant_id, p_date) <> 'non_gst' then
   return coalesce(p_items, '[]'::jsonb);
 end if;
 if jsonb_typeof(p_items) <> 'array' or p_items is null then
   return '[]'::jsonb;
 end if;
 return (
   select coalesce(
     jsonb_agg(
       (x.value - 'thq_tax_override_v630') || jsonb_build_object('tax_rate', 0)
       order by x.ordinality
     ),
     '[]'::jsonb
   )
   from jsonb_array_elements(p_items) with ordinality x(value, ordinality)
 );
end $fn$;

-- 4. Authoritative Non-GST Document Quote Engine
create or replace function private.gst_document_quote_non_gst_v520(
  p_tenant_id uuid,
  p_document_kind text,
  p_location_id uuid,
  p_party_id uuid,
  p_document_date date,
  p_supply_type text,
  p_place_of_supply_code text,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  d date := coalesce(p_document_date, current_date);
  kind text := lower(trim(coalesce(p_document_kind, '')));
  x jsonb;
  v_variant uuid;
  prod record;
  qty numeric;
  price numeric;
  discount numeric;
  base numeric;
  line_total numeric;
  v_hsn text;
  v_supply_kind text;
  lines jsonb := '[]'::jsonb;
  subtotal numeric := 0;
  discount_total numeric := 0;
  base_total numeric := 0;
  line_total_sum numeric := 0;
  grand numeric;
begin
  if not private.invoice_calculate_allowed_v632(p_tenant_id, d, kind) then
    raise exception 'Permission required for % calculation', kind;
  end if;
  if private.gst_tax_mode_resolve_v520(p_tenant_id, p_location_id, d) <> 'non_gst' then
    raise exception 'Non-GST quote requested for a business that is not in Non-GST mode';
  end if;
  if kind not in ('sale', 'purchase', 'pos', 'counter') then
    raise exception 'Document kind must be sale or purchase';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Tax quote requires at least one item';
  end if;
  if coalesce(p_additional_charges, 0) < 0 then
    raise exception 'Additional charges cannot be negative';
  end if;
  if abs(coalesce(p_round_off, 0)) > 1.000001 then
    raise exception 'Round-off cannot exceed 1.00 in either direction';
  end if;
  if not exists(select 1 from public.business_locations l where l.id = p_location_id and l.tenant_id = p_tenant_id and l.active) then
    raise exception 'Active location not found';
  end if;
  if kind in ('sale', 'pos', 'counter') and (p_party_id is null or not exists(select 1 from public.customers c where c.id = p_party_id and c.tenant_id = p_tenant_id and c.status = 'active')) then
    raise exception 'Active customer not found';
  end if;
  if kind = 'purchase' and (p_party_id is null or not exists(select 1 from public.suppliers s where s.id = p_party_id and s.tenant_id = p_tenant_id and s.status = 'active')) then
    raise exception 'Active supplier not found';
  end if;

  for x in select value from jsonb_array_elements(p_items) loop
    begin
      x := x - 'thq_tax_override_v630';
      v_variant := (x->>'variant_id')::uuid;
      qty := coalesce(nullif(x->>'quantity', '')::numeric, 0);
      price := coalesce(nullif(x->>'unit_price', '')::numeric, nullif(x->>'unit_cost', '')::numeric, 0);
      discount := coalesce(nullif(x->>'discount_amount', '')::numeric, 0);
    exception when others then
      raise exception 'Invalid Non-GST quote item';
    end;
    if v_variant is null or qty <= 0 or price < 0 or discount < 0 then
      raise exception 'Non-GST quote item has invalid product/quantity/price/discount';
    end if;

    select p.id product_id, p.name, p.item_type, pv.name variant_name, pv.sku, a.hsn_sac legacy_hsn
      into prod
    from public.product_variants pv
    join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    left join public.product_invoice_attributes_v45 a on a.tenant_id = pv.tenant_id and a.variant_id = pv.id
    where pv.id = v_variant and pv.tenant_id = p_tenant_id and pv.status = 'active' and p.status = 'active';
    if not found then raise exception 'Product is invalid or inactive'; end if;

    v_hsn := prod.legacy_hsn;
    v_supply_kind := case when prod.item_type = 'service' then 'service' else 'goods' end;
    base := round(qty * price, 4);
    if discount > base then raise exception 'Discount exceeds line value'; end if;
    base := base - discount;
    line_total := round(base, 2);

    subtotal := subtotal + round(qty * price, 4);
    discount_total := discount_total + discount;
    base_total := base_total + base;
    line_total_sum := line_total_sum + line_total;

    lines := lines || jsonb_build_array(jsonb_build_object(
      'variant_id', v_variant,
      'product_id', prod.product_id,
      'product_name', coalesce(nullif(trim(x->>'invoice_description'), ''), prod.name),
      'variant_name', prod.variant_name,
      'sku', prod.sku,
      'supply_kind', v_supply_kind,
      'hsn_sac', v_hsn,
      'quantity', qty,
      'unit_price', price,
      'discount', discount,
      'taxability', 'non_gst',
      'tax_inclusive', false,
      'reverse_charge', false,
      'gst_rate', 0,
      'applied_gst_rate', 0,
      'cess_rate', 0,
      'applied_cess_rate', 0,
      'cess_per_unit', 0,
      'applied_cess_per_unit', 0,
      'taxable_value', round(base, 2),
      'cgst', 0, 'sgst', 0, 'utgst', 0, 'igst', 0, 'cess', 0, 'tax_amount', 0,
      'rcm_cgst', 0, 'rcm_sgst', 0, 'rcm_utgst', 0, 'rcm_igst', 0, 'rcm_cess', 0, 'rcm_tax_amount', 0,
      'rcm_liability_party', null,
      'line_total', line_total,
      'calculation_rounding', 0,
      'profile_source', 'tenant_non_gst',
      'profile_status', 'not_applicable'
    ));
  end loop;

  grand := round(line_total_sum + coalesce(p_additional_charges, 0) + coalesce(p_round_off, 0), 2);

  return jsonb_build_object(
    'engine', 'gst_v520_document_non_gst_1',
    'tax_mode', 'non_gst',
    'gst_applicable', false,
    'compliance_status', 'not_applicable',
    'document_kind', kind,
    'document_class', 'commercial_invoice',
    'document_date', d,
    'supply_type', 'NON_GST',
    'supplier_registration_id', null,
    'recipient_registration_id', null,
    'supplier_gstin', null,
    'supplier_state_code', null,
    'recipient_gstin', null,
    'recipient_state_code', null,
    'party_profile_id', null,
    'place_of_supply_code', null,
    'interstate', false,
    'local_tax_name', null,
    'zero_rated', false,
    'without_payment', false,
    'deemed_export', false,
    'composition_supplier', false,
    'lines', lines,
    'totals', jsonb_build_object(
      'subtotal', round(subtotal, 2),
      'discount', round(discount_total, 2),
      'taxable_value', round(base_total, 2),
      'cgst', 0, 'sgst', 0, 'utgst', 0, 'igst', 0, 'cess', 0,
      'tax_collected_total', 0,
      'rcm_cgst', 0, 'rcm_sgst', 0, 'rcm_utgst', 0, 'rcm_igst', 0, 'rcm_cess', 0,
      'rcm_tax_payable_total', 0,
      'thq_rcm_tax_payable_total', 0,
      'recipient_rcm_tax_payable_total', 0,
      'government_tax_total', 0,
      'additional_charges', coalesce(p_additional_charges, 0),
      'calculation_rounding', 0,
      'round_off', coalesce(p_round_off, 0),
      'grand_total', grand
    ),
    'errors', '[]'::jsonb,
    'warnings', '[]'::jsonb,
    'ready_for_compliance', true
  );
end;
$function$;

-- 5. Hardened Authoritative Purchases Creator
create or replace function public.gst_purchase_create_v520(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_supplier_invoice_number text,
  p_purchase_date date,
  p_due_date date,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0,
  p_initial_payment numeric default 0,
  p_payment_method text default 'cash'::text,
  p_payment_reference text default null::text,
  p_notes text default null::text,
  p_location_id uuid default null::uuid,
  p_device_id uuid default null::uuid,
  p_request_id text default null::text,
  p_supply_type text default null::text,
  p_place_of_supply_code text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_req_payload jsonb;
  v_req_state jsonb;
  v_old_req jsonb;
  v_supply text;
  v_pos text;
  v_normalized jsonb;
  v_quote jsonb;
  v_bridge jsonb;
  v_basis jsonb;
  v_recon jsonb;
  v_source jsonb;
  v_purchase_id uuid;
  v_purchase_number text;
  v_snapshot uuid;
  v_journal uuid;
  v_document_number text;
  v_response jsonb;
  v_totals jsonb;
  v_supplier_invoice text := nullif(trim(coalesce(p_supplier_invoice_number, '')), '');
  v_tax_mode text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_user_is_owner(p_tenant_id, auth.uid()) or private.erp_has_permission(p_tenant_id, 'purchases.manage')) then
    raise exception 'Purchases permission required';
  end if;
  if not private.invoice_calculate_allowed_v632(p_tenant_id, p_purchase_date, 'purchase') then
    raise exception 'Purchase calculation permission required';
  end if;
  if p_location_id is null then raise exception 'Business location is required'; end if;
  if p_purchase_date is null then raise exception 'Purchase date is required'; end if;
  if p_due_date is not null and p_due_date < p_purchase_date then raise exception 'Due date cannot be before purchase date'; end if;
  if coalesce(p_initial_payment, 0) < 0 then raise exception 'Initial payment cannot be negative'; end if;

  v_tax_mode := private.gst_tax_mode_resolve_v520(p_tenant_id, p_location_id, p_purchase_date);

  -- In GST Registered mode, unclassified charges require service product classification.
  -- In Non-GST mode, commercial transport/additional charges are permitted.
  if coalesce(p_additional_charges, 0) <> 0 and v_tax_mode = 'gst_registered' then
    raise exception 'Additional charges are not enabled for authoritative GST Purchases until charge-level GST classification is configured. Enter transport or freight as a service item.';
  end if;

  -- Ensure items reflect tax mode (clean 0 tax_rate in Non-GST mode)
  p_items := private.sale_items_for_tax_mode_v632(p_tenant_id, p_purchase_date, p_items);

  if v_supplier_invoice is null then
    v_supplier_invoice := coalesce(
      nullif(trim(p_request_id), ''),
      'PUR-' || to_char(coalesce(p_purchase_date, current_date), 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 6)
    );
  end if;

  v_req_payload := jsonb_build_object(
    'supplier_id', p_supplier_id, 'supplier_invoice_number', v_supplier_invoice,
    'purchase_date', p_purchase_date, 'due_date', p_due_date, 'items', coalesce(p_items, '[]'::jsonb),
    'additional_charges', coalesce(p_additional_charges, 0), 'round_off', coalesce(p_round_off, 0),
    'initial_payment', coalesce(p_initial_payment, 0), 'payment_method', lower(trim(coalesce(p_payment_method, ''))),
    'payment_reference', nullif(trim(coalesce(p_payment_reference, '')), ''), 'notes', nullif(trim(coalesce(p_notes, '')), ''),
    'location_id', p_location_id, 'device_id', p_device_id, 'supply_type', nullif(upper(trim(coalesce(p_supply_type, ''))), ''),
    'place_of_supply_code', nullif(trim(coalesce(p_place_of_supply_code, '')), '')
  );

  v_req_state := private.gst_request_begin_v520(p_tenant_id, p_request_id, 'gst.purchase.create.v520', v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean, false) then return v_req_state->'response'; end if;

  v_old_req := private.v47_request_existing(p_tenant_id, p_request_id, 'purchase.create');
  if v_old_req is not null then raise exception 'Request ID is already used by the legacy Purchase path'; end if;

  v_normalized := private.v481_normalize_items(p_tenant_id, p_items, 'purchase');
  v_basis := private.gst_purchase_inventory_basis_capture_v520(p_tenant_id, v_normalized);
  v_supply := private.gst_purchase_supply_type_resolve_v520(p_tenant_id, p_supplier_id, p_purchase_date, p_supply_type);
  v_pos := coalesce(nullif(trim(coalesce(p_place_of_supply_code, '')), ''), nullif(trim(coalesce(p_supply_type, '')), ''));

  v_quote := public.gst_document_quote_v520(
    p_tenant_id, 'purchase', p_location_id, p_supplier_id, p_purchase_date,
    v_supply, v_pos, v_normalized, coalesce(p_additional_charges, 0), coalesce(p_round_off, 0)
  );

  if coalesce((v_quote->>'ready_for_compliance')::boolean, false) is not true then
    raise exception 'Purchase is not ready to post: %', coalesce(v_quote->'errors', '[]'::jsonb)::text;
  end if;

  v_totals := v_quote->'totals';
  if coalesce(p_initial_payment, 0) > coalesce((v_totals->>'grand_total')::numeric, 0) + 0.005 then
    raise exception 'Payment cannot exceed Purchase total';
  end if;

  v_bridge := private.gst_purchase_bridge_v520(p_items, v_normalized, (v_totals->>'grand_total')::numeric);

  perform private.gst_authoritative_context_enter_v520(p_tenant_id, 'purchase');

  v_source := public.purchases_create_v483(
    p_tenant_id, p_supplier_id, v_supplier_invoice, p_purchase_date, p_due_date,
    v_bridge->'items', (v_bridge->>'additional_charges')::numeric, p_initial_payment,
    p_payment_method, p_notes, p_location_id, p_device_id, p_request_id
  );

  v_purchase_id := nullif(v_source->>'purchase_id', '')::uuid;
  if v_purchase_id is null then raise exception 'GST Purchase source could not be resolved'; end if;
  perform private.gst_authoritative_context_bind_v520(v_purchase_id);

  select p.purchase_number into v_purchase_number
  from public.purchases p
  where p.tenant_id = p_tenant_id and p.id = v_purchase_id and p.status = 'posted' and lower(trim(coalesce(p.supplier_invoice_number, ''))) = lower(v_supplier_invoice)
  for update;

  if v_purchase_number is null then
    raise exception 'GST Purchase source is not posted or supplier invoice identity changed';
  end if;

  if exists(select 1 from public.journal_entries j where j.tenant_id = p_tenant_id and j.source_type = 'purchase' and j.source_id = v_purchase_id and j.status = 'posted') then
    raise exception 'Legacy Purchase journal was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id = p_tenant_id and m.source_type = 'purchase' and m.source_id = v_purchase_id) then
    raise exception 'Legacy GST evidence was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.journal_entries j join public.purchase_payments pp on pp.id = j.source_id and pp.purchase_id = v_purchase_id where j.tenant_id = p_tenant_id and j.source_type = 'purchase_payment' and j.status = 'posted') then
    raise exception 'Standalone initial Purchase payment journal was created inside authoritative GST context';
  end if;

  v_recon := private.gst_purchase_reconcile_source_v520(p_tenant_id, v_purchase_id, p_location_id, v_quote, v_basis, p_payment_reference);
  v_snapshot := private.gst_snapshot_create_v520(p_tenant_id, 'purchase', v_purchase_id, v_purchase_number, p_location_id, p_purchase_date, v_quote, v_recon->'line_ids');
  v_journal := private.gst_authoritative_journal_post_v520(p_tenant_id, v_snapshot);

  select s.document_number into v_document_number
  from public.gst_document_snapshots_v520 s
  where s.id = v_snapshot and s.tenant_id = p_tenant_id;

  if v_document_number is null or lower(trim(v_document_number)) <> lower(v_supplier_invoice) then
    raise exception 'GST Purchase legal supplier invoice number was not captured';
  end if;

  v_response := coalesce(v_source, '{}'::jsonb) || jsonb_build_object(
    'success', true, 'gst_engine', v_quote->>'engine',
    'gst_status', case when v_quote->>'tax_mode' = 'non_gst' then 'NOT_APPLICABLE' else 'POSTED' end,
    'tax_mode', v_quote->>'tax_mode', 'gst_applicable', v_quote->>'tax_mode' = 'gst_registered',
    'gst_supply_type', v_supply, 'place_of_supply_code', v_quote->>'place_of_supply_code',
    'purchase_id', v_purchase_id, 'purchase_number', v_purchase_number,
    'supplier_invoice_number', v_document_number,
    'grand_total', (v_totals->>'grand_total')::numeric,
    'taxable_total', (v_totals->>'taxable_value')::numeric,
    'tax_total', (v_totals->>'tax_collected_total')::numeric,
    'cgst', (v_totals->>'cgst')::numeric, 'sgst', (v_totals->>'sgst')::numeric,
    'utgst', (v_totals->>'utgst')::numeric, 'igst', (v_totals->>'igst')::numeric,
    'cess', (v_totals->>'cess')::numeric,
    'thq_rcm_tax_payable_total', coalesce((v_totals->>'thq_rcm_tax_payable_total')::numeric, 0),
    'gst_snapshot_id', v_snapshot, 'journal_id', v_journal,
    'inventory_costs', v_recon->'inventory_costs', 'gst_ready_for_compliance', true
  );

  v_response := private.gst_request_complete_v520(p_tenant_id, p_request_id, 'gst.purchase.create.v520', 'purchase', v_purchase_id, v_snapshot, v_journal, v_response);
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end;
$function$;

-- 6. Hardened Sales Returns Creator
create or replace function public.gst_sales_return_create_v520(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_return_date date,
  p_items jsonb,
  p_reason text,
  p_location_id uuid default null::uuid,
  p_device_id uuid default null::uuid,
  p_request_id text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_req_payload jsonb; v_req_state jsonb; v_quote jsonb; v_totals jsonb; v_sale public.sales%rowtype; v_origin public.document_origins%rowtype;
  v_id uuid := gen_random_uuid(); v_no text; x jsonb; ql jsonb; si public.sale_items%rowtype; v_ri uuid; v_line_ids jsonb := '[]'::jsonb;
  v_snapshot uuid; v_journal uuid; v_response jsonb; v_stock_type text; v_cost numeric := 0; v_paid numeric := 0; v_prev_returns numeric := 0; v_ar_reduce numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_user_is_owner(p_tenant_id, auth.uid()) or private.erp_has_permission(p_tenant_id, 'sales.return') or private.erp_has_permission(p_tenant_id, 'sales.manage')) then
    raise exception 'Sales return permission required';
  end if;
  if not private.invoice_calculate_allowed_v632(p_tenant_id, p_return_date, 'sales_return') then
    raise exception 'Sales return calculation permission required';
  end if;
  if trim(coalesce(p_reason, '')) = '' then raise exception 'Return reason is required'; end if;
  if p_return_date is null then raise exception 'Return date is required'; end if;

  select * into v_sale from public.sales where tenant_id = p_tenant_id and id = p_sale_id and status = 'posted' for update;
  if not found then raise exception 'Posted Sale not found'; end if;
  select * into v_origin from public.document_origins where tenant_id = p_tenant_id and entity_type = 'sale' and entity_id = p_sale_id order by created_at limit 1;
  if v_origin.location_id is null then raise exception 'Original Sale does not have a business location'; end if;
  if p_location_id is not null and p_location_id <> v_origin.location_id then raise exception 'Sales Return location must match the original Sale location'; end if;
  perform private.v4_location_access(p_tenant_id, v_origin.location_id, 'operate');
  if p_device_id is not null then perform private.erp_validate_transaction_origin(p_tenant_id, v_origin.location_id, p_device_id, 'sales'); end if;

  v_req_payload := jsonb_build_object('sale_id', p_sale_id, 'return_date', p_return_date, 'items', coalesce(p_items, '[]'::jsonb), 'reason', trim(p_reason), 'location_id', v_origin.location_id, 'device_id', p_device_id);
  v_req_state := private.gst_request_begin_v520(p_tenant_id, p_request_id, 'gst.sales_return.create.v520', v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean, false) then return v_req_state->'response'; end if;

  v_quote := private.gst_sales_return_quote_v520(p_tenant_id, p_sale_id, p_return_date, p_items);
  v_totals := v_quote->'totals';
  if coalesce((v_quote->>'ready_for_compliance')::boolean, false) is not true then raise exception 'Sales Return is not compliance-ready'; end if;

  perform private.gst_authoritative_context_enter_v520(p_tenant_id, 'sales_return');
  v_no := 'SRN-' || lpad(nextval('public.sales_return_number_seq')::text, 6, '0');
  insert into public.sales_returns(id, tenant_id, sale_id, return_number, location_id, device_id, return_date, reason, created_by)
  values(v_id, p_tenant_id, p_sale_id, v_no, v_origin.location_id, p_device_id, p_return_date, trim(p_reason), auth.uid());
  perform private.gst_authoritative_context_bind_v520(v_id);

  for ql in select value from jsonb_array_elements(v_quote->'lines') loop
    select * into si from public.sale_items where tenant_id = p_tenant_id and sale_id = p_sale_id and id = (ql->>'sale_item_id')::uuid;
    insert into public.sales_return_items(sales_return_id, sale_item_id, variant_id, quantity, unit_price, discount_amount, tax_rate, line_total, entered_unit_id, entered_unit_code, entered_quantity, conversion_to_base)
    values(
      v_id, si.id, si.variant_id, (ql->>'quantity')::numeric, (ql->>'unit_price')::numeric, (ql->>'discount')::numeric,
      coalesce((ql->>'applied_gst_rate')::numeric, 0), (ql->>'line_total')::numeric,
      si.entered_unit_id, si.entered_unit_code,
      case when coalesce(si.conversion_to_base, 1) > 0 then (ql->>'quantity')::numeric / coalesce(si.conversion_to_base, 1) else (ql->>'quantity')::numeric end,
      coalesce(si.conversion_to_base, 1)
    )
    returning id into v_ri;
    v_line_ids := v_line_ids || jsonb_build_array(v_ri);

    select p.item_type into v_stock_type from public.product_variants pv join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id where pv.id = si.variant_id and pv.tenant_id = p_tenant_id;
    if v_stock_type = 'stock' then
      perform public.inventory_adjust_stock(p_tenant_id, si.variant_id, (ql->>'quantity')::numeric, 'Sale return • ' || v_no);
      perform private.v4_location_stock_apply(p_tenant_id, v_origin.location_id, si.variant_id, (ql->>'quantity')::numeric, 'sale_return', 'sales_return', v_id, v_no, trim(p_reason), p_device_id, false);
      select coalesce(si.cost_total, 0) * ((ql->>'quantity')::numeric / nullif(si.quantity, 0)) into v_cost;
    end if;
    select value into x from jsonb_array_elements(p_items) where (value->>'sale_item_id')::uuid = si.id limit 1;
    perform private.gst_sales_return_tracking_apply_v520(p_tenant_id, v_id, v_ri, coalesce(x, '{}'::jsonb));
  end loop;

  update public.sales_returns
  set subtotal = (v_totals->>'taxable_value')::numeric,
      tax_total = (v_totals->>'tax_collected_total')::numeric,
      grand_total = (v_totals->>'grand_total')::numeric
  where id = v_id and tenant_id = p_tenant_id;

  if exists(select 1 from public.journal_entries where tenant_id = p_tenant_id and source_type = 'sales_return' and source_id = v_id and status = 'posted') then
    raise exception 'Legacy Sales Return journal was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 where tenant_id = p_tenant_id and source_type = 'sales_return' and source_id = v_id) then
    raise exception 'Legacy GST evidence was created inside authoritative GST context';
  end if;

  insert into public.transaction_corrections(tenant_id, entity_type, entity_id, correction_type, reason, created_by, metadata)
  values(p_tenant_id, 'sale', p_sale_id, 'return', trim(p_reason), auth.uid(), jsonb_build_object('return_id', v_id, 'return_number', v_no, 'amount', (v_totals->>'grand_total')::numeric, 'gst_engine', 'v5.2'));

  v_snapshot := private.gst_snapshot_create_v520(p_tenant_id, 'sales_return', v_id, v_no, v_origin.location_id, p_return_date, v_quote, v_line_ids);
  v_journal := private.gst_authoritative_journal_post_v520(p_tenant_id, v_snapshot);

  select coalesce(sum(amount), 0) into v_paid from public.sale_payments where tenant_id = p_tenant_id and sale_id = p_sale_id;
  select coalesce(sum(grand_total), 0) into v_prev_returns from public.sales_returns where tenant_id = p_tenant_id and sale_id = p_sale_id and id <> v_id and refund_status <> 'waived' and created_at <= (select created_at from public.sales_returns where id = v_id);
  v_ar_reduce := least((v_totals->>'grand_total')::numeric, greatest(v_sale.grand_total - v_paid - v_prev_returns, 0));
  v_credit := greatest((v_totals->>'grand_total')::numeric - v_ar_reduce, 0);

  v_response := jsonb_build_object(
    'success', true, 'gst_engine', v_quote->>'engine',
    'gst_status', case when v_quote->>'tax_mode' = 'non_gst' then 'NOT_APPLICABLE' else 'POSTED' end,
    'tax_mode', v_quote->>'tax_mode',
    'return_id', v_id, 'return_number', v_no, 'sale_id', p_sale_id,
    'document_class', case when v_quote->>'tax_mode' = 'non_gst' then 'commercial_credit_note' else 'credit_note' end,
    'grand_total', (v_totals->>'grand_total')::numeric,
    'taxable_total', (v_totals->>'taxable_value')::numeric,
    'tax_total', (v_totals->>'tax_collected_total')::numeric,
    'cgst', (v_totals->>'cgst')::numeric, 'sgst', (v_totals->>'sgst')::numeric,
    'utgst', (v_totals->>'utgst')::numeric, 'igst', (v_totals->>'igst')::numeric,
    'cess', (v_totals->>'cess')::numeric,
    'recipient_rcm_tax_reversal_total', (v_totals->>'recipient_rcm_tax_payable_total')::numeric,
    'receivable_reduction', round(v_ar_reduce, 2), 'customer_credit_due', round(v_credit, 2),
    'refund_status', 'credit_due',
    'gst_snapshot_id', v_snapshot, 'journal_id', v_journal,
    'original_sale_snapshot_id', v_quote->>'original_sale_snapshot_id'
  );

  v_response := private.gst_request_complete_v520(p_tenant_id, p_request_id, 'gst.sales_return.create.v520', 'sales_return', v_id, v_snapshot, v_journal, v_response);
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end $$;

-- 7. Hardened Purchase Returns Creator
create or replace function public.gst_purchase_return_create_v520(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_return_date date,
  p_items jsonb,
  p_reason text,
  p_location_id uuid default null::uuid,
  p_device_id uuid default null::uuid,
  p_request_id text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_req_payload jsonb; v_req_state jsonb; v_quote jsonb; v_totals jsonb;
  v_purchase public.purchases%rowtype; v_origin public.document_origins%rowtype;
  v_id uuid := gen_random_uuid(); v_no text; x jsonb; ql jsonb; pi public.purchase_items%rowtype; v_ri uuid;
  v_line_ids jsonb := '[]'::jsonb; v_snapshot uuid; v_journal uuid; v_response jsonb;
  v_stock_type text; v_available numeric; v_paid numeric := 0; v_prev_returns numeric := 0; v_ap_reduce numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_user_is_owner(p_tenant_id, auth.uid()) or private.erp_has_permission(p_tenant_id, 'purchases.return') or private.erp_has_permission(p_tenant_id, 'purchases.manage')) then
    raise exception 'Purchase return permission required';
  end if;
  if not private.invoice_calculate_allowed_v632(p_tenant_id, p_return_date, 'purchase_return') then
    raise exception 'Purchase return calculation permission required';
  end if;
  if trim(coalesce(p_reason, '')) = '' then raise exception 'Return reason is required'; end if;
  if p_return_date is null then raise exception 'Return date is required'; end if;

  select * into v_purchase from public.purchases
  where tenant_id = p_tenant_id and id = p_purchase_id and status = 'posted'
  for update;
  if not found then raise exception 'Posted Purchase not found'; end if;

  select * into v_origin from public.document_origins
  where tenant_id = p_tenant_id and entity_type = 'purchase' and entity_id = p_purchase_id
  order by created_at limit 1;
  if v_origin.location_id is null then raise exception 'Original Purchase does not have a business location'; end if;
  if p_location_id is not null and p_location_id <> v_origin.location_id then
    raise exception 'Purchase Return location must match the original Purchase location';
  end if;
  perform private.v4_location_access(p_tenant_id, v_origin.location_id, 'operate');
  if p_device_id is not null then
    perform private.erp_validate_transaction_origin(p_tenant_id, v_origin.location_id, p_device_id, 'purchases');
  end if;

  v_req_payload := jsonb_build_object(
    'purchase_id', p_purchase_id, 'return_date', p_return_date, 'items', coalesce(p_items, '[]'::jsonb),
    'reason', trim(p_reason), 'location_id', v_origin.location_id, 'device_id', p_device_id
  );
  v_req_state := private.gst_request_begin_v520(p_tenant_id, p_request_id, 'gst.purchase_return.create.v520', v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean, false) then return v_req_state->'response'; end if;

  v_quote := private.gst_purchase_return_quote_v520(p_tenant_id, p_purchase_id, p_return_date, p_items);
  v_totals := v_quote->'totals';
  if coalesce((v_quote->>'ready_for_compliance')::boolean, false) is not true then
    raise exception 'Purchase Return is not compliance-ready';
  end if;

  perform private.gst_authoritative_context_enter_v520(p_tenant_id, 'purchase_return');
  v_no := 'PRN-' || lpad(nextval('public.purchase_return_number_seq')::text, 6, '0');
  insert into public.purchase_returns(
    id, tenant_id, purchase_id, return_number, location_id, device_id, return_date, reason, credit_status, created_by
  ) values(
    v_id, p_tenant_id, p_purchase_id, v_no, v_origin.location_id, p_device_id, p_return_date, trim(p_reason), 'supplier_credit', auth.uid()
  );
  perform private.gst_authoritative_context_bind_v520(v_id);

  for ql in select value from jsonb_array_elements(v_quote->'lines') loop
    select * into pi from public.purchase_items
    where tenant_id = p_tenant_id and purchase_id = p_purchase_id and id = (ql->>'purchase_item_id')::uuid;

    insert into public.purchase_return_items(
      purchase_return_id, purchase_item_id, variant_id, quantity, unit_cost, discount_amount, tax_rate, line_total,
      entered_unit_id, entered_unit_code, entered_quantity, conversion_to_base
    ) values(
      v_id, pi.id, pi.variant_id, (ql->>'quantity')::numeric, (ql->>'unit_price')::numeric, (ql->>'discount')::numeric,
      coalesce((ql->>'applied_gst_rate')::numeric, 0), (ql->>'line_total')::numeric,
      pi.entered_unit_id, pi.entered_unit_code,
      case when coalesce(pi.conversion_to_base, 1) > 0 then (ql->>'quantity')::numeric / coalesce(pi.conversion_to_base, 1) else (ql->>'quantity')::numeric end,
      coalesce(pi.conversion_to_base, 1)
    ) returning id into v_ri;
    v_line_ids := v_line_ids || jsonb_build_array(v_ri);

    select p.item_type into v_stock_type
    from public.product_variants pv
    join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    where pv.id = pi.variant_id and pv.tenant_id = p_tenant_id;

    if v_stock_type = 'stock' then
      select quantity into v_available
      from public.location_stock_balances
      where tenant_id = p_tenant_id and location_id = v_origin.location_id and variant_id = pi.variant_id
      for update;
      if coalesce(v_available, 0) < (ql->>'quantity')::numeric - 0.000001 then
        raise exception 'Insufficient location stock to return item %', pi.variant_id;
      end if;
      perform public.inventory_adjust_stock(p_tenant_id, pi.variant_id, -((ql->>'quantity')::numeric), 'Purchase return • ' || v_no);
      perform private.v4_location_stock_apply(p_tenant_id, v_origin.location_id, pi.variant_id, -((ql->>'quantity')::numeric), 'purchase_return', 'purchase_return', v_id, v_no, trim(p_reason), p_device_id, false);
    end if;

    select value into x from jsonb_array_elements(p_items) where (value->>'purchase_item_id')::uuid = pi.id limit 1;
    perform private.gst_purchase_return_tracking_apply_v520(p_tenant_id, v_id, v_ri, coalesce(x, '{}'::jsonb));
  end loop;

  update public.purchase_returns
  set subtotal = (v_totals->>'taxable_value')::numeric,
      tax_total = (v_totals->>'tax_collected_total')::numeric,
      grand_total = (v_totals->>'grand_total')::numeric
  where id = v_id and tenant_id = p_tenant_id;

  if exists(select 1 from public.journal_entries where tenant_id = p_tenant_id and source_type = 'purchase_return' and source_id = v_id and status = 'posted') then
    raise exception 'Legacy Purchase Return journal was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 where tenant_id = p_tenant_id and source_type = 'purchase_return' and source_id = v_id) then
    raise exception 'Legacy GST evidence was created inside authoritative GST context';
  end if;

  insert into public.transaction_corrections(tenant_id, entity_type, entity_id, correction_type, reason, created_by, metadata)
  values(p_tenant_id, 'purchase', p_purchase_id, 'return', trim(p_reason), auth.uid(), jsonb_build_object('return_id', v_id, 'return_number', v_no, 'amount', (v_totals->>'grand_total')::numeric, 'gst_engine', 'v5.2'));

  v_snapshot := private.gst_snapshot_create_v520(p_tenant_id, 'purchase_return', v_id, v_no, v_origin.location_id, p_return_date, v_quote, v_line_ids);
  v_journal := private.gst_authoritative_journal_post_v520(p_tenant_id, v_snapshot);

  select coalesce(sum(amount), 0) into v_paid from public.purchase_payments where tenant_id = p_tenant_id and purchase_id = p_purchase_id;
  select coalesce(sum(grand_total), 0) into v_prev_returns from public.purchase_returns where tenant_id = p_tenant_id and purchase_id = p_purchase_id and id <> v_id and credit_status <> 'waived' and created_at <= (select created_at from public.purchase_returns where id = v_id);
  v_ap_reduce := least((v_totals->>'grand_total')::numeric, greatest(v_purchase.grand_total - v_paid - v_prev_returns, 0));
  v_credit := greatest((v_totals->>'grand_total')::numeric - v_ap_reduce, 0);

  v_response := jsonb_build_object(
    'success', true, 'gst_engine', v_quote->>'engine',
    'gst_status', case when v_quote->>'tax_mode' = 'non_gst' then 'NOT_APPLICABLE' else 'POSTED' end,
    'tax_mode', v_quote->>'tax_mode',
    'return_id', v_id, 'return_number', v_no, 'purchase_id', p_purchase_id,
    'document_class', case when v_quote->>'tax_mode' = 'non_gst' then 'commercial_debit_note' else 'debit_note' end,
    'grand_total', (v_totals->>'grand_total')::numeric,
    'taxable_total', (v_totals->>'taxable_value')::numeric,
    'tax_total', (v_totals->>'tax_collected_total')::numeric,
    'cgst', (v_totals->>'cgst')::numeric, 'sgst', (v_totals->>'sgst')::numeric,
    'utgst', (v_totals->>'utgst')::numeric, 'igst', (v_totals->>'igst')::numeric,
    'cess', (v_totals->>'cess')::numeric,
    'thq_rcm_tax_reversal_total', (v_totals->>'thq_rcm_tax_payable_total')::numeric,
    'payable_reduction', round(v_ap_reduce, 2), 'supplier_credit_due', round(v_credit, 2),
    'credit_status', 'supplier_credit',
    'gst_snapshot_id', v_snapshot, 'journal_id', v_journal,
    'original_purchase_snapshot_id', v_quote->>'original_purchase_snapshot_id'
  );

  v_response := private.gst_request_complete_v520(p_tenant_id, p_request_id, 'gst.purchase_return.create.v520', 'purchase_return', v_id, v_snapshot, v_journal, v_response);
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end $$;

-- 8. Hardened Restaurant Billing Creator
create or replace function public.gst_restaurant_order_bill_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_customer_id uuid,
  p_due_date date,
  p_payment_allocations jsonb,
  p_tracking_assignments jsonb default '[]'::jsonb,
  p_discount_type text default 'none',
  p_discount_value numeric default 0,
  p_charge_selections jsonb default '[]'::jsonb,
  p_notes text default null,
  p_supply_type text default null,
  p_place_of_supply_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  v_customer uuid;
  v_base_items jsonb;
  v_commercial jsonb;
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
  v_summary jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant billing permission denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id, 'sales.manage')
    or private.erp_has_permission(p_tenant_id, 'sales.create')
  ) then
    raise exception 'Sales permission required for Restaurant invoice posting';
  end if;

  select * into o from public.restaurant_orders where id = p_order_id and tenant_id = p_tenant_id for update;
  if not found then raise exception 'Restaurant order not found'; end if;

  if not private.invoice_calculate_allowed_v632(p_tenant_id, coalesce(o.order_date, current_date), 'restaurant') then
    raise exception 'Restaurant calculation permission required';
  end if;

  if jsonb_typeof(coalesce(p_payment_allocations, '[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant payment allocations must be an array';
  end if;
  if jsonb_typeof(coalesce(p_tracking_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant tracking assignments must be an array';
  end if;
  if jsonb_typeof(coalesce(p_charge_selections, '[]'::jsonb)) <> 'array' then
    raise exception 'Restaurant charge selections must be an array';
  end if;

  v_wrapper_request := 'gst-restaurant-order-v610:' || p_order_id::text;
  v_sale_request := 'gst-restaurant-sale-v610:' || p_order_id::text;

  v_req_payload := jsonb_build_object(
    'order_id', p_order_id, 'device_id', p_device_id, 'customer_id', p_customer_id,
    'due_date', p_due_date, 'payment_allocations', coalesce(p_payment_allocations, '[]'::jsonb),
    'tracking_assignments', coalesce(p_tracking_assignments, '[]'::jsonb),
    'discount_type', p_discount_type, 'discount_value', p_discount_value,
    'charge_selections', coalesce(p_charge_selections, '[]'::jsonb),
    'notes', p_notes, 'supply_type', p_supply_type, 'place_of_supply_code', p_place_of_supply_code
  );

  v_req_state := private.gst_request_begin_v520(p_tenant_id, v_wrapper_request, 'gst.restaurant.order.bill.v610', v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean, false) then return v_req_state->'response'; end if;

  if o.status = 'billed' and o.sale_id is not null then
    return private.restaurant_order_bill_v610_existing_response(p_tenant_id, o.id);
  end if;
  if o.status in ('voided', 'cancelled') then raise exception 'Cannot bill a % order', o.status; end if;

  v_customer := coalesce(p_customer_id, o.customer_id, private.restaurant_default_walkin_customer_v610(p_tenant_id));
  if v_customer is null then raise exception 'Active customer is required to bill a restaurant order'; end if;

  v_base_items := private.restaurant_order_billable_items_v610(p_tenant_id, p_order_id);
  if jsonb_array_length(v_base_items) = 0 then raise exception 'Restaurant order has no active unbilled items'; end if;

  v_commercial := private.sales_commercial_expand_v610(p_tenant_id, coalesce(o.order_type, 'sale'), v_base_items, p_discount_type, p_discount_value, p_charge_selections);
  v_items := private.restaurant_assign_tracking_to_sale_items_v610(v_commercial->'items', coalesce(p_tracking_assignments, '[]'::jsonb));

  v_sale := public.gst_sale_create_v522(
    p_tenant_id=>p_tenant_id, p_customer_id=>v_customer,
    p_sale_date=>coalesce(o.order_date, current_date),
    p_due_date=>p_due_date, p_items=>v_items,
    p_payment_allocations=>coalesce(p_payment_allocations, '[]'::jsonb),
    p_notes=>concat_ws(' • ', nullif(trim(coalesce(p_notes, '')), ''), 'Restaurant ' || coalesce(o.order_type, 'order') || ' #' || coalesce(o.order_number, '')),
    p_location_id=>o.location_id, p_device_id=>p_device_id,
    p_request_id=>v_sale_request, p_supply_type=>p_supply_type,
    p_place_of_supply_code=>p_place_of_supply_code
  );

  v_sale_id := nullif(v_sale->>'sale_id', '')::uuid;
  v_snapshot := nullif(v_sale->>'gst_snapshot_id', '')::uuid;
  v_journal := nullif(v_sale->>'journal_id', '')::uuid;

  if v_sale_id is null or v_snapshot is null or v_journal is null then
    raise exception 'Authoritative Sale did not return complete evidence for Restaurant billing';
  end if;

  perform private.restaurant_order_bind_sale_v610(
    p_tenant_id=>p_tenant_id, p_order_id=>p_order_id, p_sale_id=>v_sale_id,
    p_commercial_summary=>jsonb_build_object(
      'discount_type', p_discount_type, 'discount_value', p_discount_value,
      'document_discount_applied', v_commercial->'document_discount_applied',
      'charge_total', v_commercial->'charge_total',
      'charge_breakdown', v_commercial->'charge_breakdown',
      'subtotal', v_commercial->'subtotal', 'discount_total', v_commercial->'discount_total',
      'taxable_amount', v_commercial->'taxable_amount', 'tax_total', v_commercial->'tax_total',
      'grand_total', v_commercial->'grand_total'
    ),
    p_final_customer_id=>v_customer
  );

  v_summary := jsonb_build_object(
    'order_id', p_order_id, 'order_number', o.order_number, 'table_id', o.table_id,
    'customer_id', v_customer, 'commercial', v_commercial, 'billed_at', now()
  );

  v_response := coalesce(v_sale, '{}'::jsonb) || jsonb_build_object(
    'success', true, 'restaurant_order_billed', true, 'order_id', p_order_id,
    'order_number', o.order_number, 'sale_id', v_sale_id, 'sale_number', v_sale->>'sale_number',
    'invoice_number', v_sale->>'invoice_number', 'restaurant_summary', v_summary
  );

  v_response := private.gst_request_complete_v520(p_tenant_id, v_wrapper_request, 'gst.restaurant.order.bill.v610', 'restaurant_order', p_order_id, v_snapshot, v_journal, v_response);
  return v_response;
end;
$$;

-- 9. Hardened Transport / Service Job Billing
create or replace function public.gst_service_job_bill_v520(
  p_tenant_id uuid,
  p_job_id uuid,
  p_billing_variant_id uuid,
  p_due_date date,
  p_initial_payment numeric,
  p_payment_method text,
  p_payment_reference text,
  p_device_id uuid,
  p_request_id text,
  p_supply_type text default null::text,
  p_place_of_supply_code text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  j public.service_jobs%rowtype;
  v_item_type text;
  v_req_payload jsonb;
  v_req_state jsonb;
  v_old_req jsonb;
  v_contract_items jsonb;
  v_normalized jsonb;
  v_supply text;
  v_pos text;
  v_quote jsonb;
  v_bridge jsonb;
  v_source jsonb;
  v_sale_id uuid;
  v_sale_number text;
  v_line_ids jsonb;
  v_snapshot uuid;
  v_journal uuid;
  v_document_number text;
  v_response jsonb;
  v_totals jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id, 'transport_service.create')
    or private.erp_has_permission(p_tenant_id, 'transport_service.manage')
  ) then
    raise exception 'Transport service permission required';
  end if;

  select * into j from public.service_jobs where tenant_id = p_tenant_id and id = p_job_id for update;
  if not found then raise exception 'Service job not found'; end if;

  if not private.invoice_calculate_allowed_v632(p_tenant_id, coalesce(j.scheduled_date, current_date), 'service') then
    raise exception 'Service calculation permission required';
  end if;

  if p_job_id is null then raise exception 'Service job is required'; end if;
  if p_billing_variant_id is null then raise exception 'Billing service item is required'; end if;
  if coalesce(p_initial_payment, 0) < 0 then raise exception 'Initial payment cannot be negative'; end if;

  v_req_payload := jsonb_build_object(
    'job_id', p_job_id, 'billing_variant_id', p_billing_variant_id, 'due_date', p_due_date,
    'initial_payment', coalesce(p_initial_payment, 0), 'payment_method', lower(trim(coalesce(p_payment_method, ''))),
    'payment_reference', nullif(trim(coalesce(p_payment_reference, '')), ''), 'device_id', p_device_id,
    'supply_type', nullif(upper(trim(coalesce(p_supply_type, ''))), ''),
    'place_of_supply_code', nullif(trim(coalesce(p_place_of_supply_code, '')), '')
  );

  v_req_state := private.gst_request_begin_v520(p_tenant_id, p_request_id, 'gst.service_job.bill.v520', v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean, false) then return v_req_state->'response'; end if;

  v_old_req := private.v47_request_existing(p_tenant_id, p_request_id, 'service_job.bill');
  if v_old_req is not null then raise exception 'Request ID is already used by the legacy service billing path'; end if;

  v_contract_items := private.gst_service_job_contract_items_v520(p_tenant_id, p_job_id, p_billing_variant_id);
  v_normalized := private.v481_normalize_items(p_tenant_id, v_contract_items, 'sale');
  v_supply := private.gst_sale_supply_type_resolve_v520(p_tenant_id, j.customer_id, coalesce(j.scheduled_date, current_date), p_supply_type);
  v_pos := private.gst_sale_pos_resolve_v520(p_tenant_id, j.customer_id, j.location_id, coalesce(j.scheduled_date, current_date), v_supply, v_normalized, p_place_of_supply_code);

  v_quote := public.gst_document_quote_v520(p_tenant_id, 'sale', j.location_id, j.customer_id, coalesce(j.scheduled_date, current_date), v_supply, v_pos, v_normalized, 0, 0);
  if coalesce((v_quote->>'ready_for_compliance')::boolean, false) is not true then
    raise exception 'Service invoice is not ready to post: %', coalesce(v_quote->'errors', '[]'::jsonb)::text;
  end if;

  v_totals := v_quote->'totals';
  if coalesce(p_initial_payment, 0) > coalesce((v_totals->>'grand_total')::numeric, 0) + 0.005 then
    raise exception 'Initial payment cannot exceed service invoice total';
  end if;

  v_bridge := private.gst_service_job_bridge_v520(v_contract_items, v_normalized, (v_totals->>'grand_total')::numeric);

  perform private.gst_authoritative_context_enter_v520(p_tenant_id, 'service_job_bill');

  v_source := public.service_job_bill_v51(
    p_tenant_id, p_job_id, p_billing_variant_id, p_due_date,
    coalesce(p_initial_payment, 0), p_payment_method, p_payment_reference,
    p_device_id, p_request_id
  );

  v_sale_id := nullif(v_source->>'sale_id', '')::uuid;
  if v_sale_id is null then raise exception 'Service billing sale could not be resolved'; end if;
  perform private.gst_authoritative_context_bind_v520(v_sale_id);

  select s.sale_number into v_sale_number from public.sales s where s.tenant_id = p_tenant_id and s.id = v_sale_id and s.status = 'posted' for update;
  if v_sale_number is null then raise exception 'Service billing sale is not posted'; end if;

  if exists(select 1 from public.journal_entries jn where jn.tenant_id = p_tenant_id and jn.source_type = 'sale' and jn.source_id = v_sale_id and jn.status = 'posted') then
    raise exception 'Legacy Service sale journal was created inside authoritative context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id = p_tenant_id and m.source_type = 'sale' and m.source_id = v_sale_id) then
    raise exception 'Legacy GST evidence was created inside authoritative context';
  end if;

  v_line_ids := private.gst_sale_reconcile_source_v520(p_tenant_id, v_sale_id, v_quote);
  v_snapshot := private.gst_snapshot_create_v520(p_tenant_id, 'sale', v_sale_id, v_sale_number, j.location_id, coalesce(j.scheduled_date, current_date), v_quote, v_line_ids);
  v_journal := private.gst_authoritative_journal_post_v520(p_tenant_id, v_snapshot);

  select s.document_number into v_document_number from public.gst_document_snapshots_v520 s where s.id = v_snapshot and s.tenant_id = p_tenant_id;
  if v_document_number is null then raise exception 'Service invoice legal document number was not captured'; end if;

  v_response := coalesce(v_source, '{}'::jsonb) || jsonb_build_object(
    'success', true, 'gst_engine', v_quote->>'engine',
    'gst_status', case when v_quote->>'tax_mode' = 'non_gst' then 'NOT_APPLICABLE' else 'POSTED' end,
    'tax_mode', v_quote->>'tax_mode', 'gst_applicable', v_quote->>'tax_mode' = 'gst_registered',
    'sale_id', v_sale_id, 'sale_number', v_sale_number, 'invoice_number', v_document_number,
    'grand_total', (v_totals->>'grand_total')::numeric,
    'taxable_total', (v_totals->>'taxable_value')::numeric,
    'tax_total', (v_totals->>'tax_collected_total')::numeric,
    'cgst', (v_totals->>'cgst')::numeric, 'sgst', (v_totals->>'sgst')::numeric,
    'utgst', (v_totals->>'utgst')::numeric, 'igst', (v_totals->>'igst')::numeric,
    'cess', (v_totals->>'cess')::numeric,
    'gst_snapshot_id', v_snapshot, 'journal_id', v_journal,
    'gst_ready_for_compliance', true
  );

  v_response := private.gst_request_complete_v520(p_tenant_id, p_request_id, 'gst.service_job.bill.v520', 'sale', v_sale_id, v_snapshot, v_journal, v_response);
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end $$;

-- 10. Hardened Offline POS & Mobile POS Sync
create or replace function public.gst_pos_offline_sale_sync_v522(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid,
  p_request_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_request text := nullif(trim(coalesce(p_request_id, '')), '');
  v_location uuid; v_identity jsonb; v_hash text; q public.pos_offline_sync_v486%rowtype;
  v_items jsonb; v_priced jsonb; v_post_priced jsonb; v_client jsonb; v_server jsonb;
  v_i integer; v_client_price numeric; v_server_price numeric; v_client_tax numeric; v_server_tax numeric;
  v_variant uuid; v_customer uuid; v_sale_date date; v_due_date date; v_local text; v_message text;
  v_profile public.gst_product_tax_profiles_v520%rowtype; v_product_tax numeric;
  v_result jsonb; v_sale_id uuid; v_snapshot uuid; v_journal uuid; v_sale_request text;
  v_allocations jsonb;
  v_tax_mode text;
begin
  if v_request is null then raise exception 'Request ID is required'; end if;
  if length(v_request) > 160 then raise exception 'Offline v5.2.2 request ID is too long'; end if;
  v_location := private.v486_pos_device_location(p_tenant_id, p_device_id, p_location_id);
  perform private.erp_validate_transaction_origin(p_tenant_id, v_location, p_device_id, 'sales');

  v_sale_date := coalesce(nullif(p_payload->>'sale_date', '')::date, current_date);
  v_tax_mode := private.gst_tax_mode_resolve_v520(p_tenant_id, v_location, v_sale_date);

  -- Only in GST Registered mode are unclassified additional charges blocked.
  if coalesce(nullif(p_payload->>'additional_charges', '')::numeric, 0) <> 0 and v_tax_mode = 'gst_registered' then
    return private.v520_offline_conflict(
      p_tenant_id, p_device_id, v_location, v_request,
      private.gst_request_hash_v520(jsonb_build_object('device_id', p_device_id, 'location_id', v_location, 'payload', coalesce(p_payload, '{}'::jsonb))),
      nullif(trim(coalesce(p_payload->>'local_invoice_number', '')), ''),
      'UNCLASSIFIED_CHARGE', 'Additional Charges are not supported in GST mode. Add a GST-classified Service product instead.', p_payload
    );
  end if;

  v_identity := jsonb_build_object('device_id', p_device_id, 'location_id', v_location, 'payload', coalesce(p_payload, '{}'::jsonb));
  v_hash := private.gst_request_hash_v520(v_identity);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':offline-v522:' || v_request, 0));

  select * into q from public.pos_offline_sync_v486
  where tenant_id = p_tenant_id and request_id = v_request for update;
  if found then
    if coalesce(q.sync_contract_version, 'v4.8.6') not in ('v5.2.2', 'v5.2') then
      raise exception 'Request ID already belongs to a legacy Offline POS sync contract';
    end if;
    if q.request_hash is distinct from v_hash or q.device_id is distinct from p_device_id or
       q.location_id is distinct from v_location or q.payload_snapshot is distinct from coalesce(p_payload, '{}'::jsonb) then
      raise exception 'Request ID was already used with a different Offline POS device, location, or payload';
    end if;
    if q.status = 'synced' then
      if q.server_response is null or q.sale_id is null or q.gst_snapshot_id is null or q.gst_journal_id is null then
        raise exception 'Synced v5.2.2 Offline POS request is missing authoritative recovery evidence';
      end if;
      return q.server_response || jsonb_build_object('idempotent_replay', true);
    end if;
    if q.status = 'cancelled' then raise exception 'Cancelled Offline POS request cannot be reused'; end if;
  end if;

  v_items := coalesce(p_payload->'items', '[]'::jsonb);
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then raise exception 'Offline invoice has no items'; end if;
  v_customer := nullif(p_payload->>'customer_id', '')::uuid;
  v_local := nullif(trim(coalesce(p_payload->>'local_invoice_number', '')), '');
  if v_customer is null or not exists(select 1 from public.customers c where c.id = v_customer and c.tenant_id = p_tenant_id and c.status = 'active') then
    return private.v520_offline_conflict(p_tenant_id, p_device_id, v_location, v_request, v_hash, v_local, 'CUSTOMER_UNAVAILABLE', 'Customer is no longer available.', p_payload);
  end if;

  v_due_date := nullif(p_payload->>'due_date', '')::date;
  v_allocations := coalesce(p_payload->'payment_allocations', '[]'::jsonb);
  if jsonb_typeof(v_allocations) <> 'array' or jsonb_array_length(v_allocations) = 0 then
    return private.v520_offline_conflict(p_tenant_id, p_device_id, v_location, v_request, v_hash, v_local, 'PAYMENT_ALLOCATION_REQUIRED', 'Build 30 offline invoices require payment_allocations.', p_payload);
  end if;

  v_priced := private.v482_price_sale_items(p_tenant_id, v_customer, v_items, v_location);
  for v_i in 0..jsonb_array_length(v_items)-1 loop
    v_client := v_items->v_i; v_server := v_priced->v_i; v_variant := nullif(v_client->>'variant_id', '')::uuid;
    v_client_price := coalesce(nullif(v_client->>'unit_price', '')::numeric, 0); v_server_price := coalesce(nullif(v_server->>'unit_price', '')::numeric, 0);
    if abs(v_client_price - v_server_price) > 0.005 then
      v_message := format('Price changed for product %s. Offline %s, current %s.', v_variant, round(v_client_price, 2), round(v_server_price, 2));
      return private.v520_offline_conflict(p_tenant_id, p_device_id, v_location, v_request, v_hash, v_local, 'PRICE_CHANGED', v_message, p_payload);
    end if;

    select p.tax_rate into v_product_tax from public.product_variants pv join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    where pv.id = v_variant and pv.tenant_id = p_tenant_id;
    if not found then return private.v520_offline_conflict(p_tenant_id, p_device_id, v_location, v_request, v_hash, v_local, 'PRODUCT_UNAVAILABLE', 'A product on the offline invoice is no longer available.', p_payload); end if;

    if v_tax_mode = 'non_gst' then
      v_server_tax := 0;
    else
      select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id, v_variant, v_sale_date);
      v_server_tax := case when v_profile.id is null then coalesce(v_product_tax, 0) when v_profile.taxability = 'taxable' then coalesce(v_profile.gst_rate, 0) else 0 end;
    end if;

    v_client_tax := coalesce(nullif(v_client->>'tax_rate', '')::numeric, 0);
    if v_tax_mode = 'gst_registered' and abs(v_client_tax - v_server_tax) > 0.0001 then
      v_message := format('Tax changed for product %s. Offline %s, current %s.', v_variant, round(v_client_tax, 4), round(v_server_tax, 4));
      return private.v520_offline_conflict(p_tenant_id, p_device_id, v_location, v_request, v_hash, v_local, 'TAX_CHANGED', v_message, p_payload);
    end if;
  end loop;

  insert into public.pos_offline_sync_v486(tenant_id, request_id, device_id, location_id, local_invoice_number, status, payload_snapshot, attempts, last_attempt_at, created_by, updated_at, sync_contract_version, request_hash)
  values(p_tenant_id, v_request, p_device_id, v_location, v_local, 'syncing', p_payload, 1, now(), auth.uid(), now(), 'v5.2.2', v_hash)
  on conflict(tenant_id, request_id) do update set status = 'syncing', attempts = public.pos_offline_sync_v486.attempts + 1, last_attempt_at = now(), updated_at = now(), conflict_code = null, conflict_message = null;

  begin
    v_sale_request := 'offline-v522:' || v_request;
    v_result := public.gst_sale_create_v522(
      p_tenant_id, v_customer, v_sale_date, v_due_date, v_items, v_allocations,
      trim(concat_ws(' • ', nullif(p_payload->>'notes', ''), 'Offline POS ' || coalesce(v_local, ''))), v_location, p_device_id, v_sale_request,
      nullif(p_payload->>'supply_type', ''), nullif(p_payload->>'place_of_supply_code', '')
    );
    v_sale_id := nullif(v_result->>'sale_id', '')::uuid;
    v_snapshot := nullif(v_result->>'gst_snapshot_id', '')::uuid;
    v_journal := nullif(v_result->>'journal_id', '')::uuid;
    if v_sale_id is null or v_snapshot is null or v_journal is null then raise exception 'Authoritative Sale did not return complete evidence'; end if;

    v_post_priced := private.v482_price_sale_items(p_tenant_id, v_customer, v_items, v_location);
    for v_i in 0..jsonb_array_length(v_items)-1 loop
      v_client := v_items->v_i; v_server := v_post_priced->v_i; v_variant := nullif(v_client->>'variant_id', '')::uuid;
      v_client_price := coalesce(nullif(v_client->>'unit_price', '')::numeric, 0); v_server_price := coalesce(nullif(v_server->>'unit_price', '')::numeric, 0);
      if abs(v_client_price - v_server_price) > 0.005 then raise exception 'OFFLINE_PRICE_CHANGED: product % changed during sync', v_variant; end if;

      if v_tax_mode = 'non_gst' then
        v_server_tax := 0;
      else
        select p.tax_rate into v_product_tax from public.product_variants pv join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id where pv.id = v_variant and pv.tenant_id = p_tenant_id;
        select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id, v_variant, v_sale_date);
        v_server_tax := case when v_profile.id is null then coalesce(v_product_tax, 0) when v_profile.taxability = 'taxable' then coalesce(v_profile.gst_rate, 0) else 0 end;
      end if;

      v_client_tax := coalesce(nullif(v_client->>'tax_rate', '')::numeric, 0);
      if v_tax_mode = 'gst_registered' and abs(v_client_tax - v_server_tax) > 0.0001 then
        raise exception 'OFFLINE_TAX_CHANGED: product % changed during sync', v_variant;
      end if;
    end loop;
  exception when others then
    update public.pos_offline_sync_v486
    set status = 'failed', conflict_code = 'SERVER_ERROR', conflict_message = sqlerrm, updated_at = now()
    where tenant_id = p_tenant_id and request_id = v_request;
    raise;
  end;

  update public.pos_offline_sync_v486
  set status = 'synced', sale_id = v_sale_id, gst_snapshot_id = v_snapshot, gst_journal_id = v_journal,
      server_response = v_result, synced_at = now(), updated_at = now(), conflict_code = null, conflict_message = null
  where tenant_id = p_tenant_id and request_id = v_request;

  return v_result;
end;
$$;

-- 11. Authoritative Document Journal Composer Hardening
create or replace function private.gst_snapshot_document_journal_lines_v520(
  p_tenant_id uuid,
  p_snapshot_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  s public.gst_document_snapshots_v520%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_tax_lines jsonb;
  v_delta numeric;
  v_total numeric;
  v_paid numeric := 0;
  v_balance numeric;
  v_cost numeric := 0;
  v_base_stock numeric := 0;
  v_base_expense numeric := 0;
  v_party uuid;
  v_origin_time timestamptz;
  v_method record;
  v_payment_acc text;
  v_original_total numeric;
  v_previous_returns numeric;
  v_outstanding numeric;
  v_reduce numeric;
  v_credit numeric;
begin
  select * into s from public.gst_document_snapshots_v520 where id = p_snapshot_id and tenant_id = p_tenant_id;
  if not found then raise exception 'Authoritative GST snapshot not found'; end if;

  if abs(coalesce(s.additional_charges, 0)) > 0.0001 and s.tax_mode = 'gst_registered' then
    raise exception 'GST journal composer does not accept unclassified additional charges';
  end if;

  v_total := round(s.grand_total, 2);
  v_delta := round(coalesce(s.calculation_rounding, 0) + coalesce(s.round_off, 0), 2);
  v_tax_lines := private.gst_snapshot_tax_journal_lines_v520(p_tenant_id, p_snapshot_id);

  if s.source_type = 'sale' then
    select x.customer_id into v_party from public.sales x where x.id = s.source_id and x.tenant_id = p_tenant_id and x.status = 'posted';
    if v_party is null then raise exception 'Posted Sale source not found'; end if;
    select created_at into v_origin_time from public.document_origins where tenant_id = p_tenant_id and entity_type = 'sale' and entity_id = s.source_id order by created_at limit 1;
    for v_method in
      select lower(coalesce(payment_method, 'cash')) method, round(sum(amount), 2) amount
      from public.sale_payments
      where tenant_id = p_tenant_id and sale_id = s.source_id and (v_origin_time is null or created_at <= v_origin_time)
      group by lower(coalesce(payment_method, 'cash'))
    loop
      v_paid := v_paid + v_method.amount;
      v_payment_acc := 'payment.' || case when v_method.method = 'cash' then 'cash' when v_method.method = 'upi' then 'upi' when v_method.method in ('card', 'credit_card', 'debit_card') then 'card' else 'bank' end;
      v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, v_payment_acc, v_method.amount, 'debit', 'Sale receipt', 'customer', v_party));
    end loop;
    v_paid := least(round(v_paid, 2), v_total);
    v_balance := round(v_total - v_paid, 2);
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_receivable', v_balance, 'debit', 'Customer receivable', 'customer', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'sales_revenue', round(s.taxable_total, 2), 'credit', 'Sales revenue', 'customer', v_party));
    if coalesce(s.additional_charges, 0) > 0 and s.tax_mode <> 'gst_registered' then
      v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'sales_revenue', round(s.additional_charges, 2), 'credit', 'Additional delivery / service charges', 'customer', v_party));
    end if;
    v_lines := v_lines || v_tax_lines;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'sale', 'GST sale calculation/document round off'));

    -- COGS and Inventory Asset belong only to physical stock lines.
    select round(coalesce(sum(coalesce(si.cost_total, 0)) filter(where p.item_type = 'stock'), 0), 2)
      into v_cost
    from public.sale_items si
    join public.product_variants pv on pv.id = si.variant_id and pv.tenant_id = si.tenant_id
    join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    where si.tenant_id = p_tenant_id and si.sale_id = s.source_id;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'cogs', v_cost, 'debit', 'Cost of goods sold'));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_cost, 'credit', 'Inventory issued'));

  elsif s.source_type = 'purchase' then
    select x.supplier_id into v_party from public.purchases x where x.id = s.source_id and x.tenant_id = p_tenant_id and x.status = 'posted';
    if v_party is null then raise exception 'Posted Purchase source not found'; end if;
    select created_at into v_origin_time from public.document_origins where tenant_id = p_tenant_id and entity_type = 'purchase' and entity_id = s.source_id order by created_at limit 1;
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type = 'stock'), 0), 2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type <> 'stock'), 0), 2)
      into v_base_stock, v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_items pi on pi.id = ls.source_line_id and pi.purchase_id = s.source_id
    join public.product_variants pv on pv.id = pi.variant_id
    join public.products p on p.id = pv.product_id
    where ls.snapshot_id = s.id;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_base_stock, 'debit', 'Purchased stock at GST taxable value', 'supplier', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'purchase_expense', v_base_expense, 'debit', 'Purchased service/non-stock at GST taxable value', 'supplier', v_party));
    if coalesce(s.additional_charges, 0) > 0 and s.tax_mode <> 'gst_registered' then
      v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'purchase_expense', round(s.additional_charges, 2), 'debit', 'Additional purchase charges / freight', 'supplier', v_party));
    end if;
    v_lines := v_lines || v_tax_lines;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'purchase', 'GST purchase calculation/document round off'));
    for v_method in
      select lower(coalesce(payment_method, 'cash')) method, round(sum(amount), 2) amount
      from public.purchase_payments
      where tenant_id = p_tenant_id and purchase_id = s.source_id and (v_origin_time is null or created_at <= v_origin_time)
      group by lower(coalesce(payment_method, 'cash'))
    loop
      v_paid := v_paid + v_method.amount;
      v_payment_acc := 'payment.' || case when v_method.method = 'cash' then 'cash' when v_method.method = 'upi' then 'upi' when v_method.method in ('card', 'credit_card', 'debit_card') then 'card' else 'bank' end;
      v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, v_payment_acc, v_method.amount, 'credit', 'Supplier payment', 'supplier', v_party));
    end loop;
    v_paid := least(round(v_paid, 2), v_total);
    v_balance := round(v_total - v_paid, 2);
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_payable', v_balance, 'credit', 'Supplier payable', 'supplier', v_party));

  elsif s.source_type = 'purchase_invoice_v484' then
    select x.supplier_id into v_party from public.purchase_invoices_v484 x where x.id = s.source_id and x.tenant_id = p_tenant_id and x.status in ('draft', 'posted', 'part_paid', 'paid');
    if v_party is null then raise exception 'Purchase Invoice source not found'; end if;
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type = 'stock'), 0), 2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type <> 'stock'), 0), 2)
      into v_base_stock, v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_invoice_items_v484 ii on ii.id = ls.source_line_id and ii.purchase_invoice_id = s.source_id
    join public.product_variants pv on pv.id = ii.variant_id
    join public.products p on p.id = pv.product_id
    where ls.snapshot_id = s.id;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_base_stock, 'debit', 'Purchase invoice stock value', 'supplier', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'purchase_expense', v_base_expense, 'debit', 'Purchase invoice service/non-stock value', 'supplier', v_party));
    if coalesce(s.additional_charges, 0) > 0 and s.tax_mode <> 'gst_registered' then
      v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'purchase_expense', round(s.additional_charges, 2), 'debit', 'Purchase invoice additional charges', 'supplier', v_party));
    end if;
    v_lines := v_lines || v_tax_lines;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'purchase', 'GST purchase invoice calculation/document round off'));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_payable', v_total, 'credit', 'Supplier payable', 'supplier', v_party));

  elsif s.source_type = 'sales_return' then
    select sa.customer_id, sa.grand_total into v_party, v_original_total
    from public.sales_returns sr join public.sales sa on sa.id = sr.sale_id and sa.tenant_id = sr.tenant_id
    where sr.id = s.source_id and sr.tenant_id = p_tenant_id;
    if v_party is null then raise exception 'Sales Return source not found'; end if;
    select round(coalesce(sum(amount), 0), 2) into v_paid
    from public.sale_payments p join public.sales_returns sr on sr.sale_id = p.sale_id where sr.id = s.source_id;
    select round(coalesce(sum(r2.grand_total), 0), 2) into v_previous_returns
    from public.sales_returns r1 join public.sales_returns r2 on r2.sale_id = r1.sale_id and r2.id <> r1.id and r2.created_at <= r1.created_at and r2.refund_status <> 'waived'
    where r1.id = s.source_id;
    v_outstanding := greatest(round(v_original_total - v_paid - v_previous_returns, 2), 0);
    v_reduce := least(v_total, v_outstanding);
    v_credit := greatest(round(v_total - v_reduce, 2), 0);
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'sales_revenue', round(s.taxable_total, 2), 'debit', 'Sales return revenue reversal', 'customer', v_party));
    v_lines := v_lines || v_tax_lines;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'sales_return', 'GST sales return calculation/document round off'));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_receivable', v_reduce, 'credit', 'Reduce customer receivable', 'customer', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'customer_credits', v_credit, 'credit', 'Customer return credit / refund due', 'customer', v_party));

    select round(coalesce(sum(coalesce(si.cost_total, 0) * (ri.quantity / nullif(si.quantity, 0))) filter(where p.item_type = 'stock'), 0), 2)
      into v_cost
    from public.sales_return_items ri
    join public.sale_items si on si.id = ri.sale_item_id
    join public.product_variants pv on pv.id = si.variant_id and pv.tenant_id = si.tenant_id
    join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    where ri.sales_return_id = s.source_id;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_cost, 'debit', 'Returned inventory restored'));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'cogs', v_cost, 'credit', 'COGS reversed for returned goods'));

  elsif s.source_type = 'purchase_return' then
    select pu.supplier_id, pu.grand_total into v_party, v_original_total
    from public.purchase_returns pr join public.purchases pu on pu.id = pr.purchase_id and pu.tenant_id = pr.tenant_id
    where pr.id = s.source_id and pr.tenant_id = p_tenant_id;
    if v_party is null then raise exception 'Purchase Return source not found'; end if;
    select round(coalesce(sum(amount), 0), 2) into v_paid
    from public.purchase_payments p join public.purchase_returns pr on pr.purchase_id = p.purchase_id where pr.id = s.source_id;
    select round(coalesce(sum(r2.grand_total), 0), 2) into v_previous_returns
    from public.purchase_returns r1 join public.purchase_returns r2 on r2.purchase_id = r1.purchase_id and r2.id <> r1.id and r2.created_at <= r1.created_at and r2.credit_status <> 'waived'
    where r1.id = s.source_id;
    v_outstanding := greatest(round(v_original_total - v_paid - v_previous_returns, 2), 0);
    v_reduce := least(v_total, v_outstanding);
    v_credit := greatest(round(v_total - v_reduce, 2), 0);
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_payable', v_reduce, 'debit', 'Reduce supplier payable', 'supplier', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'supplier_credits', v_credit, 'debit', 'Supplier return credit / refund due', 'supplier', v_party));
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type = 'stock'), 0), 2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type <> 'stock'), 0), 2)
      into v_base_stock, v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_return_items ri on ri.id = ls.source_line_id and ri.purchase_return_id = s.source_id
    join public.product_variants pv on pv.id = ri.variant_id
    join public.products p on p.id = pv.product_id
    where ls.snapshot_id = s.id;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_base_stock, 'credit', 'Purchase return stock value reversal', 'supplier', v_party));
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'purchase_expense', v_base_expense, 'credit', 'Purchase return service/non-stock reversal', 'supplier', v_party));
    v_lines := v_lines || v_tax_lines;
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'purchase_return', 'GST purchase return calculation/document round off'));
  else
    raise exception 'GST document journal composer does not support source type %', s.source_type;
  end if;
  return v_lines;
end
$$;

-- 12. Authoritative Sale Journal Composer (POS/Client v5.2.2) Hardening
create or replace function private.gst_snapshot_sale_journal_lines_v522(
  p_tenant_id uuid,
  p_snapshot_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  s public.gst_document_snapshots_v520%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_tax jsonb;
  v_party uuid;
  v_paid numeric := 0;
  v_balance numeric;
  v_cost numeric := 0;
  v_delta numeric;
  r record;
  x jsonb;
begin
  select * into s from public.gst_document_snapshots_v520 where id = p_snapshot_id and tenant_id = p_tenant_id;
  if not found or s.source_type <> 'sale' then raise exception 'v5.2.2 Sale snapshot not found'; end if;

  if abs(coalesce(s.additional_charges, 0)) > 0.0001 and s.tax_mode = 'gst_registered' then
    raise exception 'Unclassified Additional Charges are not permitted';
  end if;

  select customer_id into v_party from public.sales where id = s.source_id and tenant_id = p_tenant_id and status = 'posted';
  if v_party is null then raise exception 'Posted Sale source not found'; end if;

  for r in
    select a.method_code, sum(a.settlement_amount)::numeric amount
    from public.sale_payment_allocations_v522 a
    where a.tenant_id = p_tenant_id and a.sale_id = s.source_id and a.settlement_amount > 0
    group by a.method_code
  loop
    x := private.gst_payment_gl_line_v522(p_tenant_id, r.method_code, r.amount, 'Sale receipt - ' || r.method_code, v_party);
    if x is not null then v_lines := v_lines || jsonb_build_array(x); end if;
    v_paid := v_paid + r.amount;
  end loop;

  v_paid := least(round(v_paid, 2), round(s.grand_total, 2));
  v_balance := round(s.grand_total - v_paid, 2);

  v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'accounts_receivable', v_balance, 'debit', 'Customer receivable', 'customer', v_party));
  v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'sales_revenue', round(s.taxable_total, 2), 'credit', 'Sales revenue', 'customer', v_party));
  if coalesce(s.additional_charges, 0) > 0 and s.tax_mode <> 'gst_registered' then
    v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'sales_revenue', round(s.additional_charges, 2), 'credit', 'Additional delivery / service charges', 'customer', v_party));
  end if;
  v_tax := private.gst_snapshot_tax_journal_lines_v520(p_tenant_id, p_snapshot_id);
  v_lines := v_lines || v_tax;
  v_delta := round(coalesce(s.calculation_rounding, 0) + coalesce(s.round_off, 0), 2);
  v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_rounding_line_v520(p_tenant_id, v_delta, 'sale', 'GST sale calculation/document round off'));

  select round(coalesce(sum(coalesce(si.cost_total, 0)) filter(where p.item_type = 'stock'), 0), 2) into v_cost
  from public.sale_items si join public.product_variants pv on pv.id = si.variant_id and pv.tenant_id = si.tenant_id
  join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
  where si.tenant_id = p_tenant_id and si.sale_id = s.source_id;

  v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'cogs', v_cost, 'debit', 'Cost of goods sold'));
  v_lines := private.gst_append_nonnull_line_v520(v_lines, private.gst_gl_line_v520(p_tenant_id, 'inventory_asset', v_cost, 'credit', 'Inventory issued'));
  return v_lines;
end;
$function$;

-- 13. Tax Mode Set: Allow Business Owner as well as GST configure role
create or replace function public.gst_tax_mode_set_v520(
  p_tenant_id uuid,
  p_tax_mode text,
  p_effective_from date default current_date,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_mode text := lower(trim(coalesce(p_tax_mode, '')));
  v_date date := coalesce(p_effective_from, current_date);
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  cur public.gst_tenant_tax_modes_v520%rowtype;
  v_id uuid;
  v_before jsonb;
begin
  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.gst_v520_has_access(p_tenant_id, 'gst_compliance.configure')
  ) then
    raise exception 'GST/tax configuration permission required';
  end if;
  if v_mode not in ('gst_registered', 'non_gst') then
    raise exception 'Tax mode must be gst_registered or non_gst';
  end if;
  if not exists(select 1 from public.tenants t where t.id = p_tenant_id and t.status = 'active') then
    raise exception 'Active business not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':tax-mode-v520', 0));

  if exists(
    select 1 from public.gst_document_snapshots_v520 s
    where s.tenant_id = p_tenant_id
      and s.document_date >= v_date
      and s.tax_mode <> v_mode
  ) then
    raise exception 'Tax mode cannot be changed across already-posted authoritative documents. Choose a later effective date.';
  end if;

  select * into cur
  from public.gst_tenant_tax_modes_v520 m
  where m.tenant_id = p_tenant_id and m.effective_to is null
  order by m.effective_from desc
  limit 1
  for update;

  if cur.id is null then
    insert into public.gst_tenant_tax_modes_v520(tenant_id, tax_mode, effective_from, reason, created_by)
    values(p_tenant_id, v_mode, v_date, v_reason, auth.uid())
    returning id into v_id;
  elsif v_date < cur.effective_from then
    raise exception 'Effective date cannot precede the current tax-mode period (%)', cur.effective_from;
  elsif v_date = cur.effective_from then
    v_before := to_jsonb(cur);
    update public.gst_tenant_tax_modes_v520
    set tax_mode = v_mode, reason = v_reason
    where id = cur.id
    returning id into v_id;
  elsif cur.tax_mode = v_mode then
    v_id := cur.id;
  else
    v_before := to_jsonb(cur);
    update public.gst_tenant_tax_modes_v520
      set effective_to = v_date - 1
      where id = cur.id;
    insert into public.gst_tenant_tax_modes_v520(tenant_id, tax_mode, effective_from, reason, created_by)
    values(p_tenant_id, v_mode, v_date, v_reason, auth.uid())
    returning id into v_id;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id, 'gst.tax_mode.set', 'tenant', p_tenant_id, v_mode,
    v_before,
    (select to_jsonb(m) from public.gst_tenant_tax_modes_v520 m where m.id = v_id)
  );

  return public.gst_tax_mode_get_v520(p_tenant_id, v_date);
end;
$function$;

-- 14. Sales Invoice Context: Allow Owner and sales.create
create or replace function public.sales_invoice_context_v632(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_sale_date date,
  p_load_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $fn$
declare
  m text;
  l public.aggregate_loads_v617%rowtype;
begin
  if auth.uid() is null
     or not private.erp_user_has_tenant_access(p_tenant_id)
     or not (
       private.erp_user_is_owner(p_tenant_id, auth.uid())
       or private.erp_has_permission(p_tenant_id, 'sales.manage')
       or private.erp_has_permission(p_tenant_id, 'sales.create')
     ) then
    raise exception 'Sales permission required' using errcode = '42501';
  end if;

  perform private.erp_validate_transaction_origin(p_tenant_id, p_location_id, p_device_id, 'sales');
  if p_sale_date is null then raise exception 'Invoice date is required'; end if;

  m := private.gst_tax_mode_resolve_v520(p_tenant_id, p_location_id, p_sale_date);
  if m = 'unconfigured' then
    raise exception 'GST registration was detected. Complete the business GST setup for this invoice date before billing';
  end if;

  if p_load_id is not null then
    l := private.aggregate_load_document_lock_v629(p_tenant_id, p_load_id, 'outbound', p_location_id);
  end if;

  return jsonb_build_object(
    'tax_mode', m,
    'gst_applicable', m = 'gst_registered',
    'locked_customer_id', l.customer_id,
    'sale_date', p_sale_date,
    'load_id', p_load_id
  );
end $fn$;

-- Permissions & Privileges Lockdown
revoke all on function private.gst_tax_mode_resolve_v520(uuid, uuid, date) from public, anon, authenticated;
revoke all on function private.gst_tax_mode_resolve_v520(uuid, date) from public, anon, authenticated;
revoke all on function private.invoice_calculate_allowed_v632(uuid, date, text) from public, anon, authenticated;
revoke all on function private.sale_items_for_tax_mode_v632(uuid, date, jsonb) from public, anon, authenticated;
revoke all on function private.gst_document_quote_non_gst_v520(uuid, text, uuid, uuid, date, text, text, jsonb, numeric, numeric) from public, anon, authenticated;
revoke all on function private.gst_snapshot_document_journal_lines_v520(uuid, uuid) from public, anon, authenticated;
revoke all on function private.gst_snapshot_sale_journal_lines_v522(uuid, uuid) from public, anon, authenticated;

revoke all on function public.sales_invoice_context_v632(uuid, uuid, uuid, date, uuid) from public, anon;
grant execute on function public.sales_invoice_context_v632(uuid, uuid, uuid, date, uuid) to authenticated, service_role;

revoke all on function public.gst_purchase_create_v520(uuid, uuid, text, date, date, jsonb, numeric, numeric, numeric, text, text, text, uuid, uuid, text, text, text) from public, anon;
grant execute on function public.gst_purchase_create_v520(uuid, uuid, text, date, date, jsonb, numeric, numeric, numeric, text, text, text, uuid, uuid, text, text, text) to authenticated, service_role;

revoke all on function public.gst_sales_return_create_v520(uuid, uuid, date, jsonb, text, uuid, uuid, text) from public, anon;
grant execute on function public.gst_sales_return_create_v520(uuid, uuid, date, jsonb, text, uuid, uuid, text) to authenticated, service_role;

revoke all on function public.gst_purchase_return_create_v520(uuid, uuid, date, jsonb, text, uuid, uuid, text) from public, anon;
grant execute on function public.gst_purchase_return_create_v520(uuid, uuid, date, jsonb, text, uuid, uuid, text) to authenticated, service_role;

revoke all on function public.gst_restaurant_order_bill_v610(uuid, uuid, uuid, uuid, date, jsonb, jsonb, text, numeric, jsonb, text, text, text) from public, anon;
grant execute on function public.gst_restaurant_order_bill_v610(uuid, uuid, uuid, uuid, date, jsonb, jsonb, text, numeric, jsonb, text, text, text) to authenticated, service_role;

revoke all on function public.gst_service_job_bill_v520(uuid, uuid, uuid, date, numeric, text, text, uuid, text, text, text) from public, anon;
grant execute on function public.gst_service_job_bill_v520(uuid, uuid, uuid, date, numeric, text, text, uuid, text, text, text) to authenticated, service_role;

revoke all on function public.gst_pos_offline_sale_sync_v522(uuid, uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.gst_pos_offline_sale_sync_v522(uuid, uuid, uuid, text, jsonb) to authenticated, service_role;

revoke all on function public.gst_tax_mode_set_v520(uuid, text, date, text) from public, anon;
grant execute on function public.gst_tax_mode_set_v520(uuid, text, date, text) to authenticated, service_role;
