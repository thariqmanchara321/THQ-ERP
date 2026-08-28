import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders })

const text = (value: unknown) => String(value ?? '').trim()
const map = (value: unknown) =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'POST required.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  try {
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })
    const { data: { user } } = await caller.auth.getUser()
    if (!user) return json({ success: false, error: 'Authentication required.' }, 401)

    const body = map(await req.json())
    const tenantId = text(body.tenant_id)
    const resource = text(body.resource).toLowerCase()
    const action = (text(body.action) || 'get').toLowerCase()
    const payload = map(body.payload)

    if (resource === 'contract') {
      const { data, error } = await caller.rpc('thq_api_contract_v480')
      if (error) throw error
      return json({ success: true, data })
    }
    if (!tenantId) return json({ success: false, error: 'tenant_id is required.' }, 400)

    let rpc = ''
    let params: Record<string, unknown> = { p_tenant_id: tenantId }

    switch (resource) {
      case 'sync':
        rpc = 'thq_sync_versions_v480'
        break
      case 'attention':
        rpc = 'business_attention_summary_v480'
        params = { ...params, p_location_id: payload.location_id ?? null, p_days: payload.days ?? 30 }
        break
      case 'inventory-intelligence':
        rpc = 'inventory_intelligence_v480'
        params = { ...params, p_location_id: payload.location_id ?? null, p_days: payload.days ?? 30, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'units':
        rpc = 'inventory_units_list_v481'
        params = { ...params, p_active_only: payload.active_only ?? true }
        break
      case 'product-units':
        if (action === 'list') {
          rpc = 'inventory_product_units_v481'
          params = { ...params, p_variant_id: payload.variant_id }
        } else if (action === 'save') {
          rpc = 'inventory_product_units_save_v481'
          params = { ...params, p_variant_id: payload.variant_id, p_base_unit_code: payload.base_unit_code, p_units: payload.units ?? [] }
        } else {
          return json({ success: false, error: 'Unsupported product-units action.' }, 400)
        }
        break
      case 'inventory-movements':
        rpc = 'inventory_movement_history_v481'
        params = { ...params, p_variant_id: payload.variant_id ?? null, p_location_id: payload.location_id ?? null, p_movement_type: payload.movement_type ?? null, p_from: payload.from ?? null, p_to: payload.to ?? null, p_limit: payload.limit ?? 500 }
        break
      case 'pricing':
        if (action === 'lists') {
          rpc = 'pricing_lists_v482'
        } else if (action === 'rules') {
          rpc = 'pricing_rules_v482'
          params = { ...params, p_price_list_id: payload.price_list_id, p_variant_id: payload.variant_id ?? null }
        } else if (action === 'resolve') {
          rpc = 'pricing_resolve_v482'
          params = { ...params, p_variant_id: payload.variant_id, p_customer_id: payload.customer_id ?? null, p_unit_id: payload.unit_id ?? null, p_quantity: payload.quantity ?? 1, p_location_id: payload.location_id ?? null }
        } else if (action === 'save-list') {
          rpc = 'pricing_list_save_v482'
          params = { ...params, p_price_list_id: payload.price_list_id ?? null, p_code: payload.code, p_name: payload.name, p_description: payload.description ?? '', p_is_default: payload.is_default ?? false, p_active: payload.active ?? true }
        } else if (action === 'save-rule') {
          rpc = 'pricing_rule_save_v482'
          params = { ...params, p_rule_id: payload.rule_id ?? null, p_price_list_id: payload.price_list_id, p_variant_id: payload.variant_id, p_unit_id: payload.unit_id, p_min_quantity: payload.min_quantity ?? 1, p_unit_price: payload.unit_price, p_active: payload.active ?? true }
        } else if (action === 'set-customer-list') {
          rpc = 'customer_pricing_profile_set_v482'
          params = { ...params, p_customer_id: payload.customer_id, p_price_list_id: payload.price_list_id ?? null }
        } else if (action === 'customer-prices') {
          rpc = 'customer_prices_v482'
          params = { ...params, p_customer_id: payload.customer_id, p_variant_id: payload.variant_id ?? null }
        } else if (action === 'save-customer-price') {
          rpc = 'customer_price_save_v482'
          params = { ...params, p_rule_id: payload.rule_id ?? null, p_customer_id: payload.customer_id, p_variant_id: payload.variant_id, p_unit_id: payload.unit_id, p_min_quantity: payload.min_quantity ?? 1, p_unit_price: payload.unit_price, p_active: payload.active ?? true }
        } else {
          return json({ success: false, error: 'Unsupported pricing action.' }, 400)
        }
        break
      case 'product-identifiers':
        if (action === 'list') {
          rpc = 'product_identifiers_v482_list'
          params = { ...params, p_variant_id: payload.variant_id }
        } else if (action === 'save') {
          rpc = 'product_identifier_save_v482'
          params = { ...params, p_identifier_id: payload.identifier_id ?? null, p_variant_id: payload.variant_id, p_identifier_type: payload.identifier_type, p_code: payload.code, p_supplier_id: payload.supplier_id ?? null, p_label: payload.label ?? '', p_is_primary: payload.is_primary ?? false, p_active: payload.active ?? true }
        } else if (action === 'generate') {
          rpc = 'product_identifier_generate_v482'
          params = { ...params, p_variant_id: payload.variant_id, p_identifier_type: payload.identifier_type }
        } else if (action === 'archive') {
          rpc = 'product_identifier_archive_v482'
          params = { ...params, p_identifier_id: payload.identifier_id }
        } else if (action === 'lookup') {
          rpc = 'inventory_product_lookup_v482'
          params = { ...params, p_code: payload.code, p_location_id: payload.location_id ?? null }
        } else {
          return json({ success: false, error: 'Unsupported product-identifiers action.' }, 400)
        }
        break
      case 'label-templates':
        if (action === 'list') {
          rpc = 'label_templates_v482'
        } else if (action === 'save') {
          rpc = 'label_template_save_v482'
          params = { ...params, p_template_id: payload.template_id ?? null, p_code: payload.code, p_name: payload.name, p_paper_mode: payload.paper_mode ?? 'thermal', p_width_mm: payload.width_mm ?? 50, p_height_mm: payload.height_mm ?? 30, p_columns: payload.columns ?? 1, p_show_business: payload.show_business ?? true, p_show_product: payload.show_product ?? true, p_show_price: payload.show_price ?? true, p_show_sku: payload.show_sku ?? true, p_show_code_text: payload.show_code_text ?? true, p_code_mode: payload.code_mode ?? 'barcode', p_is_default: payload.is_default ?? false, p_active: payload.active ?? true }
        } else {
          return json({ success: false, error: 'Unsupported label-templates action.' }, 400)
        }
        break
      case 'customer-credit':
        rpc = 'customer_credit_intelligence_v480'
        params = { ...params, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'supplier-payables':
        rpc = 'supplier_payables_intelligence_v480'
        params = { ...params, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'reorder-suggestions':
        rpc = 'purchase_reorder_suggestions_v480'
        params = { ...params, p_location_id: payload.location_id ?? null, p_days: payload.days ?? 30, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'business-summary':
        rpc = 'mobile_business_summary_v480'
        params = { ...params, p_day: payload.day ?? null }
        break
      case 'store-summary':
        rpc = 'mobile_store_status_v480'
        params = { ...params, p_day: payload.day ?? null }
        break
      case 'purchase-orders':
        if (action === 'list') {
          rpc = 'purchase_order_list_v480'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'purchase_order_detail_v480'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id }
        } else if (action === 'create') {
          rpc = 'purchase_order_create_v480'
          params = { ...params, p_location_id: payload.location_id, p_supplier_id: payload.supplier_id, p_items: payload.items ?? [], p_expected_date: payload.expected_date ?? null, p_notes: payload.notes ?? '' }
        } else if (action === 'status') {
          rpc = 'purchase_order_status_v480'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id, p_status: payload.status, p_reason: payload.reason ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported purchase-orders action.' }, 400)
        }
        break
      default:
        return json({ success: false, error: `Unknown THQ API resource: ${resource}` }, 404)
    }

    const { data, error } = await caller.rpc(rpc, params)
    if (error) throw error
    return json({ success: true, api_version: 'v1', resource, action, data })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return json({ success: false, error: message }, 400)
  }
})
