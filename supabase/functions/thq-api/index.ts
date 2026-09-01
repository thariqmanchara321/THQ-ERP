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

const errorText = (error: unknown) => {
  if (error instanceof Error) return error.message
  if (error && typeof error === 'object') {
    const e = error as Record<string, unknown>
    const parts = [e.message, e.details, e.hint, e.code]
      .map((value) => text(value))
      .filter((value) => value.length > 0 && value !== '[object Object]')
    if (parts.length > 0) return parts.join(' • ')
    try { return JSON.stringify(error) } catch (_) { /* ignore */ }
  }
  return String(error)
}

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
      case 'runtime-health':
        rpc = 'erp_runtime_health_v489'
        break
      case 'restaurant-operations':
        rpc = 'restaurant_operations_summary_v489'
        params = { ...params, p_location_id: payload.location_id ?? null, p_device_id: payload.device_id ?? null }
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
      case 'tracking-policy':
        if (action === 'get') {
          rpc = 'inventory_tracking_policy_v483'
          params = { ...params, p_variant_id: payload.variant_id }
        } else if (action === 'save') {
          rpc = 'inventory_tracking_policy_save_v483'
          params = { ...params, p_variant_id: payload.variant_id, p_tracking_mode: payload.tracking_mode ?? 'none', p_warranty_enabled: payload.warranty_enabled ?? false, p_warranty_months: payload.warranty_months ?? 0, p_warranty_days: payload.warranty_days ?? 0, p_require_batch_expiry: payload.require_batch_expiry ?? false, p_allow_expired_sale: payload.allow_expired_sale ?? false }
        } else if (action === 'reconciliation') {
          rpc = 'inventory_tracking_reconciliation_v483'
          params = { ...params, p_variant_id: payload.variant_id, p_location_id: payload.location_id }
        } else if (action === 'register-opening') {
          rpc = 'inventory_tracking_register_opening_v483'
          params = { ...params, p_variant_id: payload.variant_id, p_location_id: payload.location_id, p_serial_numbers: payload.serial_numbers ?? [], p_batches: payload.batches ?? [], p_note: payload.note ?? null }
        } else {
          return json({ success: false, error: 'Unsupported tracking-policy action.' }, 400)
        }
        break
      case 'serials':
        if (action === 'search' || action === 'list') {
          rpc = 'inventory_serial_search_v483'
          params = { ...params, p_query: payload.query ?? '', p_location_id: payload.location_id ?? null, p_limit: payload.limit ?? 200 }
        } else if (action === 'history') {
          rpc = 'inventory_serial_history_v483'
          params = { ...params, p_serial_id: payload.serial_id }
        } else if (action === 'resolve') {
          rpc = 'inventory_serial_resolve_v483'
          params = { ...params, p_serial_number: payload.serial_number, p_location_id: payload.location_id ?? null }
        } else {
          return json({ success: false, error: 'Unsupported serials action.' }, 400)
        }
        break
      case 'batches':
        if (action === 'search' || action === 'list') {
          rpc = 'inventory_batch_search_v483'
          params = { ...params, p_query: payload.query ?? '', p_location_id: payload.location_id ?? null, p_limit: payload.limit ?? 200 }
        } else if (action === 'history') {
          rpc = 'inventory_batch_history_v483'
          params = { ...params, p_batch_id: payload.batch_id }
        } else {
          return json({ success: false, error: 'Unsupported batches action.' }, 400)
        }
        break
      case 'batch-history':
        rpc = 'inventory_batch_history_v483'
        params = { ...params, p_batch_id: payload.batch_id }
        break
      case 'warranties':
        rpc = 'warranty_register_v483'
        params = { ...params, p_query: payload.query ?? '', p_status: payload.status ?? null, p_expiring_days: payload.expiring_days ?? null, p_limit: payload.limit ?? 300, p_location_id: payload.location_id ?? null }
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
      case 'warehouses':
        rpc = 'warehouse_locations_v485'
        break
      case 'warehouse-inventory':
        rpc = 'warehouse_inventory_v485'
        params = { ...params, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'stock-transfers':
        if (action === 'list') {
          rpc = 'inventory_transfers_list_v485'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'inventory_transfer_detail_v485'
          params = { ...params, p_transfer_id: payload.transfer_id }
        } else if (action === 'create' || action === 'request') {
          rpc = 'inventory_transfer_request_v485'
          params = { ...params, p_from_location_id: payload.from_location_id, p_to_location_id: payload.to_location_id, p_items: payload.items ?? [], p_notes: payload.notes ?? '', p_expected_arrival_date: payload.expected_arrival_date ?? null, p_transport_reference: payload.transport_reference ?? '', p_request_id: payload.request_id ?? null }
        } else if (action === 'approve' || action === 'reject') {
          rpc = 'inventory_transfer_decide_v485'
          params = { ...params, p_transfer_id: payload.transfer_id, p_approve: action === 'approve', p_note: payload.note ?? '' }
        } else if (action === 'cancel') {
          rpc = 'inventory_transfer_cancel_v485'
          params = { ...params, p_transfer_id: payload.transfer_id, p_reason: payload.reason ?? '' }
        } else if (action === 'dispatch') {
          rpc = 'inventory_transfer_dispatch_v485'
          params = { ...params, p_transfer_id: payload.transfer_id, p_device_id: payload.device_id ?? null, p_dispatch_note: payload.note ?? '', p_transport_reference: payload.transport_reference ?? '' }
        } else if (action === 'receive') {
          rpc = 'inventory_transfer_receive_v485'
          params = { ...params, p_transfer_id: payload.transfer_id, p_device_id: payload.device_id ?? null, p_receive_note: payload.note ?? '' }
        } else if (action === 'history') {
          rpc = 'inventory_transfer_history_v485'
          params = { ...params, p_transfer_id: payload.transfer_id }
        } else if (action === 'tracking-options') {
          rpc = 'inventory_transfer_tracking_options_v485'
          params = { ...params, p_location_id: payload.location_id, p_variant_id: payload.variant_id }
        } else {
          return json({ success: false, error: 'Unsupported stock-transfers action.' }, 400)
        }
        break
      case 'stock-counts':
        if (action === 'snapshot') {
          rpc = 'inventory_stock_count_snapshot_v485'
          params = { ...params, p_location_id: payload.location_id, p_query: payload.query ?? '' }
        } else if (action === 'post') {
          rpc = 'inventory_stock_count_post_v485'
          params = { ...params, p_location_id: payload.location_id, p_items: payload.items ?? [], p_notes: payload.notes ?? '', p_device_id: payload.device_id ?? null, p_request_id: payload.request_id ?? null }
        } else if (action === 'list') {
          rpc = 'stock_counts_list_v485'
          params = { ...params, p_location_id: payload.location_id ?? null, p_from: payload.from ?? null, p_to: payload.to ?? null, p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'stock_count_detail_v485'
          params = { ...params, p_count_id: payload.count_id }
        } else {
          return json({ success: false, error: 'Unsupported stock-counts action.' }, 400)
        }
        break
      case 'stock-reconciliation':
        rpc = 'inventory_stock_reconciliation_v485'
        params = { ...params, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_only_variance: payload.only_variance ?? false, p_limit: payload.limit ?? 2000 }
        break
      case 'business-summary':
        rpc = 'mobile_business_summary_v480'
        params = { ...params, p_day: payload.day ?? null }
        break
      case 'store-summary':
        rpc = 'mobile_store_status_v480'
        params = { ...params, p_day: payload.day ?? null }
        break
      case 'purchase-requests':
        if (action === 'list') {
          rpc = 'purchase_request_list_v484'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'purchase_request_detail_v484'
          params = { ...params, p_request_id: payload.request_id }
        } else if (action === 'create') {
          rpc = 'purchase_request_create_v484'
          params = { ...params, p_location_id: payload.location_id, p_items: payload.items ?? [], p_required_date: payload.required_date ?? null, p_priority: payload.priority ?? 'normal', p_preferred_supplier_id: payload.preferred_supplier_id ?? null, p_purpose: payload.purpose ?? '', p_notes: payload.notes ?? '' }
        } else if (action === 'status') {
          rpc = 'purchase_request_status_v484'
          params = { ...params, p_request_id: payload.request_id, p_status: payload.status, p_note: payload.note ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported purchase-requests action.' }, 400)
        }
        break
      case 'purchase-orders':
        if (action === 'list') {
          rpc = 'purchase_order_list_v484'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'purchase_order_detail_v484'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id }
        } else if (action === 'create') {
          rpc = 'purchase_order_create_v484'
          params = { ...params, p_location_id: payload.location_id, p_supplier_id: payload.supplier_id, p_items: payload.items ?? [], p_expected_date: payload.expected_date ?? null, p_notes: payload.notes ?? '', p_request_id: payload.request_id ?? null }
        } else if (action === 'status') {
          rpc = 'purchase_order_status_v480'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id, p_status: payload.status, p_reason: payload.reason ?? '' }
        } else if (action === 'decide') {
          rpc = 'purchase_order_decide_v484'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id, p_approve: payload.approve ?? false, p_note: payload.note ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported purchase-orders action.' }, 400)
        }
        break
      case 'goods-receipts':
        if (action === 'list') {
          rpc = 'goods_receipt_list_v484'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'goods_receipt_detail_v484'
          params = { ...params, p_goods_receipt_id: payload.goods_receipt_id }
        } else if (action === 'create') {
          rpc = 'goods_receipt_create_v484'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id, p_receipt_date: payload.receipt_date ?? null, p_items: payload.items ?? [], p_supplier_delivery_note: payload.supplier_delivery_note ?? '', p_notes: payload.notes ?? '' }
        } else if (action === 'post') {
          rpc = 'goods_receipt_post_v484'
          params = { ...params, p_goods_receipt_id: payload.goods_receipt_id, p_device_id: payload.device_id ?? null }
        } else if (action === 'cancel') {
          rpc = 'goods_receipt_cancel_v490'
          params = { ...params, p_goods_receipt_id: payload.goods_receipt_id, p_reason: payload.reason ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported goods-receipts action.' }, 400)
        }
        break
      case 'purchase-invoices':
        if (action === 'list') {
          rpc = 'purchase_invoice_list_v484'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'purchase_invoice_detail_v484'
          params = { ...params, p_purchase_invoice_id: payload.purchase_invoice_id }
        } else if (action === 'create') {
          rpc = 'purchase_invoice_create_v489'
          params = { ...params, p_purchase_order_id: payload.purchase_order_id, p_supplier_invoice_number: payload.supplier_invoice_number, p_invoice_date: payload.invoice_date ?? null, p_due_date: payload.due_date ?? null, p_items: payload.items ?? [], p_additional_charges: payload.additional_charges ?? 0, p_round_off: payload.round_off ?? 0, p_notes: payload.notes ?? '' }
        } else if (action === 'post') {
          rpc = 'purchase_invoice_post_v484'
          params = { ...params, p_purchase_invoice_id: payload.purchase_invoice_id }
        } else if (action === 'void') {
          rpc = 'purchase_invoice_void_v490'
          params = { ...params, p_purchase_invoice_id: payload.purchase_invoice_id, p_reason: payload.reason ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported purchase-invoices action.' }, 400)
        }
        break
      case 'supplier-payments-v2':
        if (action === 'list') {
          rpc = 'supplier_payment_list_v484'
          params = { ...params, p_location_id: payload.location_id ?? null, p_supplier_id: payload.supplier_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'create') {
          rpc = 'supplier_payment_create_v490'
          params = { ...params, p_location_id: payload.location_id, p_supplier_id: payload.supplier_id, p_payment_date: payload.payment_date ?? null, p_amount: payload.amount, p_payment_method: payload.payment_method, p_allocations: payload.allocations ?? [], p_reference_number: payload.reference_number ?? '', p_notes: payload.notes ?? '', p_device_id: payload.device_id ?? null }
        } else if (action === 'void') {
          rpc = 'supplier_payment_void_v490'
          params = { ...params, p_supplier_payment_id: payload.supplier_payment_id, p_reason: payload.reason ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported supplier-payments-v2 action.' }, 400)
        }
        break
      case 'supplier-ledger-v2':
        rpc = 'suppliers_get_statement_v484'
        params = { ...params, p_supplier_id: payload.supplier_id, p_from: payload.from ?? null, p_to: payload.to ?? null, p_location_id: payload.location_id ?? null }
        break
      case 'purchase-price-history':
        rpc = 'purchase_price_history_v484'
        params = { ...params, p_variant_id: payload.variant_id ?? null, p_supplier_id: payload.supplier_id ?? null, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        break
      case 'purchasing-dashboard':
        rpc = 'purchasing_dashboard_v484'
        params = { ...params, p_location_id: payload.location_id ?? null }
        break
      case 'purchase-cycle':
        rpc = 'purchase_cycle_summary_v490'
        params = { ...params, p_purchase_order_id: payload.purchase_order_id }
        break
      case 'finance-operations-health':
        rpc = 'finance_operations_health_v490'
        break
      case 'transaction-bulk-import':
        rpc = 'transaction_bulk_import_v490'
        params = { ...params, p_import_type: payload.import_type, p_location_id: payload.location_id, p_device_id: payload.device_id ?? null, p_source_name: payload.source_name ?? '', p_source_key: payload.source_key, p_documents: payload.documents ?? [] }
        break
      case 'loans':
        if (action === 'list') {
          rpc = 'loan_list_v491'
          params = { ...params, p_location_id: payload.location_id ?? null, p_status: payload.status ?? null, p_direction: payload.direction ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'loan_detail_v491'
          params = { ...params, p_loan_id: payload.loan_id }
        } else if (action === 'create') {
          rpc = 'loan_create_v491'
          params = { ...params, p_location_id: payload.location_id, p_payload: payload.loan ?? {} }
        } else if (action === 'update') {
          rpc = 'loan_update_v491'
          params = { ...params, p_loan_id: payload.loan_id, p_payload: payload.loan ?? {} }
        } else if (action === 'submit') {
          rpc = 'loan_submit_v490'
          params = { ...params, p_loan_id: payload.loan_id }
        } else if (action === 'decide') {
          rpc = 'loan_decide_v490'
          params = { ...params, p_loan_id: payload.loan_id, p_approve: payload.approve ?? false, p_note: payload.note ?? '' }
        } else if (action === 'disburse') {
          rpc = 'loan_activate_v491'
          params = { ...params, p_loan_id: payload.loan_id, p_disbursement_date: payload.disbursement_date ?? null, p_payment_method: payload.payment_method ?? 'bank', p_reference_number: payload.reference_number ?? '', p_device_id: payload.device_id ?? null }
        } else if (action === 'payment') {
          rpc = 'loan_payment_create_v491'
          params = { ...params, p_loan_id: payload.loan_id, p_amount: payload.amount, p_payment_date: payload.payment_date ?? null, p_payment_method: payload.payment_method ?? 'cash', p_reference_number: payload.reference_number ?? '', p_notes: payload.notes ?? '', p_device_id: payload.device_id ?? null }
        } else if (action === 'payment-reverse') {
          rpc = 'loan_payment_reverse_v491'
          params = { ...params, p_payment_id: payload.payment_id, p_reason: payload.reason ?? '' }
        } else if (action === 'rate-change') {
          rpc = 'loan_rate_change_v490'
          params = { ...params, p_loan_id: payload.loan_id, p_new_rate: payload.new_rate, p_effective_date: payload.effective_date ?? null, p_rate_index: payload.rate_index ?? null, p_rate_margin: payload.rate_margin ?? null, p_reason: payload.reason ?? '' }
        } else if (action === 'status') {
          rpc = 'loan_status_v490'
          params = { ...params, p_loan_id: payload.loan_id, p_status: payload.status, p_reason: payload.reason ?? '' }
        } else if (action === 'collateral-save') {
          rpc = 'loan_collateral_save_v490'
          params = { ...params, p_loan_id: payload.loan_id, p_collateral_id: payload.collateral_id ?? null, p_type: payload.type, p_description: payload.description, p_reference_number: payload.reference_number ?? '', p_estimated_value: payload.estimated_value ?? 0, p_status: payload.status ?? 'active', p_notes: payload.notes ?? '' }
        } else if (action === 'guarantor-save') {
          rpc = 'loan_guarantor_save_v490'
          params = { ...params, p_loan_id: payload.loan_id, p_guarantor_id: payload.guarantor_id ?? null, p_customer_id: payload.customer_id ?? null, p_name: payload.name, p_phone: payload.phone ?? '', p_email: payload.email ?? '', p_guarantee_amount: payload.guarantee_amount ?? null, p_notes: payload.notes ?? '' }
        } else if (action === 'settings-get') {
          rpc = 'loan_settings_v491_get'
        } else if (action === 'settings-set') {
          rpc = 'loan_settings_v491_set'
          params = { ...params, p_reflect: payload.reflect_in_accounting ?? true }
        } else {
          return json({ success: false, error: 'Unsupported loans action.' }, 400)
        }
        break
      case 'loan-dashboard':
        rpc = 'loan_dashboard_v491'
        params = { ...params, p_location_id: payload.location_id ?? null }
        break
      case 'loan-warnings':
        rpc = 'loan_warnings_v491'
        params = { ...params, p_location_id: payload.location_id ?? null, p_limit: payload.limit ?? 250 }
        break
      case 'customer-loans':
        rpc = 'customer_loan_summary_v490'
        params = { ...params, p_customer_id: payload.customer_id }
        break
      case 'payment-center':
        if (action === 'summary') {
          rpc = 'payments_party_summary_v491'
          params = { ...params, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 500 }
        } else if (action === 'detail') {
          rpc = 'payments_party_detail_v491'
          params = { ...params, p_party_type: payload.party_type, p_party_id: payload.party_id, p_location_id: payload.location_id ?? null }
        } else {
          return json({ success: false, error: 'Unsupported payment-center action.' }, 400)
        }
        break
      case 'v5-finance':
        if (action === 'summary') {
          rpc = 'finance_controls_summary_v500'
        } else if (action === 'financial-years') {
          rpc = 'financial_years_list_v500'
        } else if (action === 'financial-year-save') {
          rpc = 'financial_year_save_v500'
          params = { ...params, p_year_id: payload.year_id ?? null, p_name: payload.name, p_start_date: payload.start_date, p_end_date: payload.end_date, p_locked_through: payload.locked_through ?? null }
        } else if (action === 'financial-year-close') {
          rpc = 'financial_year_close_v500'
          params = { ...params, p_year_id: payload.year_id }
        } else if (action === 'bank-accounts') {
          rpc = 'bank_accounts_list_v500'
        } else if (action === 'bank-account-save') {
          rpc = 'bank_account_save_v500'
          params = { ...params, p_bank_account_id: payload.bank_account_id ?? null, p_account_name: payload.name, p_bank_name: payload.bank_name ?? '', p_account_number_masked: payload.account_number ?? '', p_ifsc_code: payload.ifsc ?? '', p_accounting_account_id: payload.accounting_account_id, p_opening_balance: payload.opening_balance ?? 0, p_active: payload.active ?? true }
        } else if (action === 'voucher-list') {
          rpc = 'finance_vouchers_list_v500'
          params = { ...params, p_from: payload.from ?? null, p_to: payload.to ?? null, p_type: payload.voucher_type ?? null, p_query: payload.query ?? '' }
        } else if (action === 'voucher-post') {
          rpc = 'finance_voucher_post_v500'
          params = { ...params, p_location_id: payload.location_id ?? null, p_voucher_type: payload.voucher_type, p_voucher_date: payload.voucher_date ?? null, p_amount: payload.amount, p_debit_account_id: payload.debit_account_id, p_credit_account_id: payload.credit_account_id, p_party_type: payload.party_type ?? null, p_party_id: payload.party_id ?? null, p_payment_method: payload.payment_method ?? null, p_reference_number: payload.reference ?? '', p_narration: payload.narration ?? '' }
        } else if (action === 'journal-list') {
          rpc = 'journal_center_list_v500'
          params = { ...params, p_from: payload.from ?? null, p_to: payload.to ?? null, p_query: payload.query ?? '', p_status: payload.status ?? null, p_limit: payload.limit ?? 500 }
        } else if (action === 'journal-detail') {
          rpc = 'journal_center_detail_v500'
          params = { ...params, p_journal_id: payload.journal_id }
        } else if (action === 'journal-reverse') {
          rpc = 'journal_reverse_v500'
          params = { ...params, p_journal_id: payload.journal_id, p_reason: payload.reason ?? '' }
        } else if (action === 'bank-statement-list') {
          rpc = 'bank_statement_list_v500'
          params = { ...params, p_bank_account_id: payload.bank_account_id, p_from: payload.from ?? null, p_to: payload.to ?? null, p_status: payload.unmatched_only === true ? 'unmatched' : (payload.status ?? null) }
        } else if (action === 'bank-statement-save') {
          rpc = 'bank_statement_line_save_v500'
          params = { ...params, p_bank_account_id: payload.bank_account_id, p_line_id: payload.line_id ?? null, p_transaction_date: payload.statement_date, p_direction: payload.direction ?? ((Number(payload.credit ?? 0) > 0) ? 'credit' : 'debit'), p_amount: payload.amount ?? Math.max(Number(payload.debit ?? 0), Number(payload.credit ?? 0)), p_reference: payload.reference ?? '', p_description: payload.description ?? '' }
        } else if (action === 'bank-statement-match') {
          rpc = 'bank_statement_match_v500'
          params = { ...params, p_line_id: payload.statement_line_id, p_journal_id: payload.journal_id }
        } else if (action === 'recurring-list') {
          rpc = 'recurring_expenses_list_v500'
        } else if (action === 'recurring-save') {
          rpc = 'recurring_expense_save_v500'
          params = { ...params, p_id: payload.recurring_id ?? null, p_location_id: payload.location_id, p_category_id: payload.category_id, p_title: payload.name, p_payee: payload.payee ?? '', p_description: payload.description ?? '', p_amount: payload.amount, p_tax_amount: payload.tax_amount ?? 0, p_payment_method: payload.payment_method ?? 'cash', p_frequency: payload.frequency ?? 'monthly', p_next_run_date: payload.next_due_date, p_auto_post: payload.auto_post ?? false, p_active: payload.active ?? true }
        } else if (action === 'recurring-process') {
          rpc = 'recurring_expenses_process_v500'
          params = { ...params, p_through_date: payload.as_of ?? null }
        } else if (action === 'reconciliation') {
          rpc = 'finance_reconciliation_v500'
        } else {
          return json({ success: false, error: 'Unsupported v5-finance action.' }, 400)
        }
        break
      case 'v5-crm':
        if (action === 'profile') {
          rpc = 'customer_crm_profile_v500'
          params = { ...params, p_customer_id: payload.customer_id }
        } else if (action === 'save') {
          rpc = 'customer_crm_save_v500'
          params = { ...params, p_customer_id: payload.customer_id, p_group_id: payload.group_id ?? null, p_salesperson_user_id: payload.salesperson_user_id ?? null, p_birthday: payload.birthday ?? null, p_anniversary: payload.anniversary ?? null, p_notes: payload.notes ?? '' }
        } else if (action === 'groups') {
          rpc = 'customer_groups_list_v500'
        } else if (action === 'group-save') {
          rpc = 'customer_group_save_v500'
          params = { ...params, p_group_id: payload.group_id ?? null, p_name: payload.name, p_description: payload.description ?? '', p_discount_percent: payload.discount_percent ?? 0, p_active: payload.active ?? true }
        } else if (action === 'loyalty-adjust') {
          rpc = 'customer_loyalty_adjust_v500'
          params = { ...params, p_customer_id: payload.customer_id, p_points: payload.points, p_source_type: payload.source_type ?? 'manual', p_source_id: payload.source_id ?? null, p_note: payload.note ?? '' }
        } else {
          return json({ success: false, error: 'Unsupported v5-crm action.' }, 400)
        }
        break
      case 'v5-purchasing-intelligence':
        if (action === 'quotations') {
          rpc = 'purchase_quotations_list_v500'
          params = { ...params, p_request_id: payload.request_id ?? null, p_status: payload.status ?? null, p_query: payload.query ?? '' }
        } else if (action === 'quotation-detail') {
          rpc = 'purchase_quotation_detail_v500'
          params = { ...params, p_quotation_id: payload.quotation_id }
        } else if (action === 'quotation-save') {
          rpc = 'purchase_quotation_save_v500'
          params = { ...params, p_quotation_id: payload.quotation_id ?? null, p_request_id: payload.request_id ?? null, p_location_id: payload.location_id, p_supplier_id: payload.supplier_id, p_supplier_quote_reference: payload.supplier_quote_reference ?? '', p_quote_date: payload.quote_date ?? null, p_valid_until: payload.valid_until ?? null, p_expected_delivery_date: payload.expected_delivery_date ?? null, p_payment_terms: payload.payment_terms ?? '', p_items: payload.items ?? [], p_notes: payload.notes ?? '' }
        } else if (action === 'quotation-convert') {
          rpc = 'purchase_quotation_convert_v500'
          params = { ...params, p_quotation_id: payload.quotation_id, p_notes: payload.notes ?? '' }
        } else if (action === 'supplier-performance') {
          rpc = 'supplier_performance_v500'
          params = { ...params, p_from: payload.from ?? null, p_to: payload.to ?? null, p_limit: payload.limit ?? 500 }
        } else if (action === 'reorder') {
          rpc = 'reorder_suggestions_v500'
          params = { ...params, p_location_id: payload.location_id ?? null, p_days: payload.days ?? 30, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        } else {
          return json({ success: false, error: 'Unsupported v5-purchasing-intelligence action.' }, 400)
        }
        break
      case 'v5-reports':
        if (action === 'catalog') {
          rpc = 'reports_catalog_v500'
          params = {}
        } else if (action === 'returns') {
          rpc = 'returns_report_v500'
          params = { ...params, p_kind: payload.kind ?? 'all', p_from: payload.from ?? null, p_to: payload.to ?? null, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 5000 }
        } else {
          rpc = 'reports_center_data_v500'
          params = { ...params, p_report_key: payload.report_key, p_from: payload.from, p_to: payload.to, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 1000 }
        }
        break
      case 'v5-dashboard':
        rpc = 'dashboard_business_intelligence_v500'
        params = { ...params, p_location_id: payload.location_id ?? null, p_day: payload.day ?? null }
        break
      case 'v5-capabilities':
        rpc = 'thq_v500_capabilities'
        params = {}
        break
      case 'client-mobile':
        if (action === 'context') {
          rpc = 'mobile_client_context_v487'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'dashboard') {
          rpc = 'mobile_client_dashboard_v487'
          params = { ...params, p_device_id: payload.device_id, p_day: payload.day ?? null, p_location_id: payload.location_id ?? null }
        } else if (action === 'sales') {
          rpc = 'mobile_sales_status_v487'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id ?? null, p_limit: payload.limit ?? 100 }
        } else if (action === 'purchases') {
          rpc = 'mobile_purchases_status_v487'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id ?? null, p_limit: payload.limit ?? 100 }
        } else if (action === 'inventory') {
          rpc = 'mobile_inventory_status_v487'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 250 }
        } else if (action === 'customer-outstanding') {
          rpc = 'mobile_customer_outstanding_v487'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 250 }
        } else if (action === 'supplier-outstanding') {
          rpc = 'mobile_supplier_outstanding_v487'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id ?? null, p_query: payload.query ?? '', p_limit: payload.limit ?? 250 }
        } else if (action === 'approvals') {
          rpc = 'mobile_approvals_v487'
          params = { ...params, p_device_id: payload.device_id, p_status: payload.status ?? 'pending', p_limit: payload.limit ?? 200 }
        } else if (action === 'approval-decision') {
          rpc = 'mobile_approval_decide_v487'
          params = { ...params, p_device_id: payload.device_id, p_approval_type: payload.approval_type, p_id: payload.id, p_approve: payload.approve ?? false, p_note: payload.note ?? '' }
        } else if (action === 'customer-payment') {
          rpc = 'mobile_customer_payment_v487'
          params = { ...params, p_device_id: payload.device_id, p_customer_id: payload.customer_id, p_amount: payload.amount, p_payment_method: payload.payment_method, p_reference_number: payload.reference_number ?? '', p_notes: payload.notes ?? '', p_sale_id: payload.sale_id ?? null, p_request_id: payload.request_id ?? null }
        } else if (action === 'contract') {
          rpc = 'mobile_client_api_contract_v487'
          params = { ...params, p_device_id: payload.device_id }
        } else {
          return json({ success: false, error: 'Unsupported client-mobile action.' }, 400)
        }
        break
      case 'mobile-pos':
        if (action === 'context') {
          rpc = 'mobile_pos_terminal_context_v488'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'sync') {
          rpc = 'mobile_pos_sale_sync_v488'
          params = { ...params, p_device_id: payload.device_id, p_request_id: payload.request_id, p_payload: payload.invoice ?? payload.payload ?? {} }
        } else if (action === 'products') {
          rpc = 'pos_offline_product_cache_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'customers') {
          rpc = 'pos_offline_customer_cache_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'serials') {
          rpc = 'pos_offline_available_serials_v486'
          params = { ...params, p_device_id: payload.device_id, p_after: payload.after ?? '', p_limit: payload.limit ?? 1000 }
        } else if (action === 'manifest') {
          rpc = 'mobile_pos_cache_manifest_v488'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'status') {
          rpc = 'mobile_pos_sync_status_v488'
          params = { ...params, p_device_id: payload.device_id, p_limit: payload.limit ?? 100 }
        } else if (action === 'receipt-event') {
          rpc = 'mobile_pos_receipt_event_v488'
          params = { ...params, p_device_id: payload.device_id, p_request_id: payload.request_id, p_event_type: payload.event_type, p_local_invoice_number: payload.local_invoice_number ?? null }
        } else if (action === 'kot') {
          rpc = 'mobile_pos_kot_create_v488'
          params = { ...params, p_device_id: payload.device_id, p_request_id: payload.request_id, p_order_type: payload.order_type ?? 'takeaway', p_table_id: payload.table_id ?? null, p_customer_id: payload.customer_id ?? null, p_items: payload.items ?? [], p_note: payload.note ?? '', p_send_now: payload.send_now ?? true }
        } else if (action === 'settings') {
          rpc = 'mobile_pos_terminal_settings_get_v488'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'contract') {
          rpc = 'mobile_pos_api_contract_v488'
          params = { ...params, p_device_id: payload.device_id }
        } else {
          return json({ success: false, error: 'Unsupported mobile-pos action.' }, 400)
        }
        break
      case 'offline-pos':
        if (action === 'sync') {
          rpc = 'pos_offline_sale_sync_v486'
          params = { ...params, p_device_id: payload.device_id, p_location_id: payload.location_id, p_request_id: payload.request_id, p_payload: payload.invoice ?? payload.payload ?? {} }
        } else if (action === 'request') {
          rpc = 'pos_offline_request_lookup_v486'
          params = { ...params, p_request_id: payload.request_id }
        } else if (action === 'list') {
          rpc = 'pos_offline_sync_list_v486'
          params = { ...params, p_device_id: payload.device_id, p_status: payload.status ?? null, p_limit: payload.limit ?? 500 }
        } else if (action === 'summary') {
          rpc = 'pos_offline_sync_summary_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'products') {
          rpc = 'pos_offline_product_cache_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'customers') {
          rpc = 'pos_offline_customer_cache_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'serials') {
          rpc = 'pos_offline_available_serials_v486'
          params = { ...params, p_device_id: payload.device_id, p_after: payload.after ?? '', p_limit: payload.limit ?? 1000 }
        } else if (action === 'manifest') {
          rpc = 'pos_offline_cache_manifest_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else if (action === 'contract') {
          rpc = 'pos_offline_api_contract_v486'
          params = { ...params, p_device_id: payload.device_id }
        } else {
          return json({ success: false, error: 'Unsupported offline-pos action.' }, 400)
        }
        break
      default:
        return json({ success: false, error: `Unknown THQ API resource: ${resource}` }, 404)
    }

    const { data, error } = await caller.rpc(rpc, params)
    if (error) throw error
    return json({ success: true, api_version: 'v1', resource, action, data })
  } catch (error) {
    return json({ success: false, error: errorText(error) }, 400)
  }
})
