# THQ ERP — Smart Inventory Database Schema & Contracts

**Document Version:** 1.0.0  
**Phase:** Phase 0 Database Architecture  
**Date:** 2026-11-10  

---

## 1. Existing Reused Database Objects

### 1.1 `public.product_identifiers_v482`
Stores multiple barcodes, QR codes, and supplier reference numbers per variant.
- `id` (uuid, PK)
- `tenant_id` (uuid, FK -> `public.tenants`)
- `variant_id` (uuid, FK -> `public.product_variants`)
- `identifier_type` (text: `'barcode' | 'qr' | 'manufacturer' | 'supplier' | 'internal' | 'alternate_sku'`)
- `code` (text, not null)
- `supplier_id` (uuid, nullable -> `public.suppliers`)
- `label` (text)
- `is_primary` (boolean, default false)
- `generated` (boolean, default false)
- `active` (boolean, default true)
- Unique indexes:
  - `(tenant_id, lower(trim(code))) WHERE active` (guarantees no barcode collision across different products in the same tenant).
  - `(tenant_id, variant_id, identifier_type) WHERE active AND is_primary AND identifier_type IN ('barcode','qr','internal')` (one primary barcode/QR per variant).

### 1.2 `public.product_identifier_sequences_v482`
- `tenant_id` (uuid, PK)
- `next_barcode` (bigint, default 1) -> Generates internal EAN-13 codes starting with prefix `28`.
- `next_qr` (bigint, default 1) -> Generates internal QR strings format `THQ:PRODUCT:<variant_short>:<seq>`.

### 1.3 `public.inventory_product_lookup_v482(p_tenant_id uuid, p_code text, p_location_id uuid default null)`
Primary read-only RPC powering online product identification:
- Resolves `p_code` against `product_variants.sku`, `product_identifiers_v482.code`, and legacy `product_variants.barcode` / `product_variants.part_number`.
- Returns enriched product JSONB with prices, location-specific stock quantities, and associated identifier records.
- Security definer enforcing `private.erp_user_has_tenant_access(p_tenant_id)` and `private.v4_location_access`.

### 1.4 `public.stock_counts` & `public.stock_count_items`
- Physical inventory reconciliation headers and lines.
- Lines record `system_quantity`, `counted_quantity`, and derived `variance`.

---

## 2. Proposed Additive Database Objects (Phase 8 Migration)

All tables strictly enforce multi-tenant isolation, immutable timestamps, and Row Level Security.

### 2.1 `public.inventory_scan_sessions`
Audit log and work session container for bulk scanning, physical counts, and phone-to-pc pairings.
```sql
CREATE TABLE IF NOT EXISTS public.inventory_scan_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    location_id UUID REFERENCES public.business_locations(id) ON DELETE SET NULL,
    device_id UUID REFERENCES public.registered_devices(id) ON DELETE SET NULL,
    session_type TEXT NOT NULL CHECK (session_type IN ('bulk_scan', 'stock_count', 'purchase_receive', 'pairing')),
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    item_count INTEGER NOT NULL DEFAULT 0,
    total_quantity NUMERIC NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 2.2 `public.inventory_import_batches`
Tracks batches of Excel and CSV product imports with error telemetry.
```sql
CREATE TABLE IF NOT EXISTS public.inventory_import_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    location_id UUID REFERENCES public.business_locations(id) ON DELETE SET NULL,
    file_name TEXT NOT NULL,
    file_format TEXT NOT NULL CHECK (file_format IN ('xlsx', 'csv')),
    total_rows INTEGER NOT NULL DEFAULT 0,
    valid_rows INTEGER NOT NULL DEFAULT 0,
    imported_rows INTEGER NOT NULL DEFAULT 0,
    failed_rows INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'preview' CHECK (status IN ('preview', 'processing', 'completed', 'failed')),
    error_summary JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## 3. Row Level Security Policies

```sql
ALTER TABLE public.inventory_scan_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_import_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY inventory_scan_sessions_tenant ON public.inventory_scan_sessions
    FOR ALL TO authenticated
    USING (private.erp_user_has_tenant_access(tenant_id))
    WITH CHECK (private.erp_user_has_tenant_access(tenant_id));

CREATE POLICY inventory_import_batches_tenant ON public.inventory_import_batches
    FOR ALL TO authenticated
    USING (private.erp_user_has_tenant_access(tenant_id))
    WITH CHECK (private.erp_user_has_tenant_access(tenant_id));
```

---

## 4. Phase 7: Bulk Import RPCs and Invariant Guarantees

### 4.1 Backend Functions

1. **`public.inventory_bulk_create_products(p_tenant_id uuid, p_rows jsonb) RETURNS jsonb`**
   - **Access control:** Verified via `private.erp_user_has_tenant_access(p_tenant_id)`.
   - **Permission check:** Verified via `private.erp_has_permission(p_tenant_id, 'bulk_import.use')` or `'inventory.manage'`.
   - **Processing:** Iterates through `p_rows` and calls `public.inventory_create_product` with per-row exception safety.
   - **Audit logging:** Writes audit trail entry to `private.business_audit_write`.
   - **Output:** Returns JSON object `{ "success_count": ok, "failed_count": failed, "errors": errs }`.

2. **`public.inventory_update_product_v628(...) RETURNS jsonb`**
   - Invoked when user selects `DuplicateHandlingMode.updateExisting` to update existing product catalog details by `variant_id`.

### 4.2 Non-Mutating Live Stock Invariant

- In according with THQ ERP double-entry inventory integrity:
  - Product catalogue creation strictly creates catalog rows in `public.inventory_products` and `public.inventory_product_variants`.
  - It does **NOT** write opening balances or ledger adjustments into `public.location_stock_balances` or stock movement tables.
  - Opening stock numbers in supplier spreadsheets are informational only; live stock adjustments require approved stock count posts (Phase 9).

---

## 5. Phase 8: Barcode Generation & Label Template Database Contracts

### 5.1 Reused Existing RPCs & Functions

1. **`public.label_templates_v482(p_tenant_id uuid) RETURNS SETOF public.label_templates_v482`**
   - Retrieves active and default label templates configured for the business tenant.
   - Output includes: `id`, `code`, `name`, `paper_mode`, `width_mm`, `height_mm`, `columns`, `rows`, `show_business`, `show_product`, `show_price`, `show_sku`, `show_code_text`, `code_mode`, `is_default`, `active`.

2. **`public.label_template_save_v482(p_tenant_id uuid, p_template_id uuid, p_code text, p_name text, p_paper_mode text, p_width_mm numeric, p_height_mm numeric, p_columns integer, p_show_business boolean, p_show_product boolean, p_show_price boolean, p_show_sku boolean, p_show_code_text boolean, p_code_mode text, p_is_default boolean, p_active boolean) RETURNS uuid`**
   - Saves or updates a custom label layout for the tenant.
   - Enforces `inventory.manage` permission check or `owner` role.
   - Atomically resets other default templates if `p_is_default` is set to true.

3. **`public.product_identifier_generate_v482(p_tenant_id uuid, p_variant_id uuid, p_identifier_type text) RETURNS jsonb`**
   - Generates an in-store barcode using sequence table `public.product_identifier_sequences_v482`.
   - For `p_identifier_type = 'barcode'`:
     - Uses prefix `'28'` (GS1 reserved for restricted/in-store circulation).
     - Pads the 10-digit sequential counter: `'28' || lpad(v_seq::text, 10, '0')`.
     - Appends the standard modulo-10 check digit via `private.v482_ean13_check_digit(v_seed)`.
   - Guaranteed zero collision with external manufacturer EAN-13 barcodes.

4. **`public.product_identifier_save_v482(p_tenant_id uuid, p_identifier_id uuid, p_variant_id uuid, p_identifier_type text, p_code text, p_supplier_id uuid, p_label text, p_is_primary boolean, p_active boolean) RETURNS uuid`**
   - Saves new or generated identifiers for a product variant.
   - Preserves exact string representation including leading zeroes.

### 5.2 Strict Invariants for Label Operations

- Barcode generation and label printing are strictly catalogue, identification, and presentation operations.
- They NEVER alter stock counts in `public.location_stock_balances` or create entries in financial accounts.

---

## 6. Phase 9: Physical Stock Counting & Reconciliation Database Contracts

### 6.1 Reused Existing RPCs & Functions

1. **`public.inventory_stock_count_snapshot_v485(p_tenant_id uuid, p_location_id uuid, p_query text DEFAULT NULL) RETURNS jsonb`**
   - Captures an atomic snapshot of system stock balances for the given business location.
   - Output per row:
     - `product_id`, `variant_id`, `product_name`, `variant_name`, `sku`, `barcode`, `unit_name`.
     - `tracking_mode` (`none`, `serial`, `batch`).
     - `system_quantity`: Total current stock from `public.location_stock_balances`.
     - `reserved_quantity`, `damaged_quantity`, `quarantine_quantity`, `available_quantity`.
     - `tracking`: Tracking details JSON (batches/serials if applicable).
   - Read-only; acquires no locks and causes zero mutations.

2. **`public.inventory_stock_count_post_v485(p_tenant_id uuid, p_location_id uuid, p_items jsonb, p_notes text DEFAULT NULL, p_device_id text DEFAULT NULL, p_request_id text DEFAULT NULL) RETURNS jsonb`**
   - Posts and reconciles an approved physical stock count.
   - Enforces location access permissions (`private.v4_location_access`) and role check (`inventory.stock_count`, `inventory.manage`, or `owner`).
   - Guarantees idempotency via `p_request_id` (UUID v4): returns cached response if re-posted.
   - Generates sequential count number: `CNT-YYMMDD-XXXXXX`.
   - Inserts master record into `public.stock_counts` with status `'posted'`.
   - Per item in `p_items`:
     - Locks balance row with `FOR UPDATE`.
     - Calculates delta: `v_delta := v_counted - v_system`.
     - If `v_delta != 0`:
       - Invokes `public.inventory_adjust_stock` with reason `'Physical stock count reconciliation'`.
       - Applies adjustment atomically to `public.location_stock_balances` and appends movement to `public.inventory_movement_history_v481` via `private.v4_location_stock_apply`.
     - Inserts line record into `public.stock_count_items`.
   - Updates `public.stock_counts` with line totals and variance metrics.
   - Bumps location sync version to ensure POS and mobile terminals synchronize updated balances.

3. **`public.stock_counts_list_v485(p_tenant_id uuid, p_location_id uuid DEFAULT NULL, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_limit integer DEFAULT 100) RETURNS jsonb`**
   - Returns paginated list of historical stock count sessions for audit and compliance.
   - Fields: `id`, `count_number`, `tenant_id`, `location_id`, `location_name`, `status`, `reconciliation_status`, `notes`, `line_count`, `total_system_quantity`, `total_counted_quantity`, `total_variance`, `created_at`, `posted_at`, `created_by`, `posted_by`.

4. **`public.stock_count_detail_v485(p_tenant_id uuid, p_count_id uuid) RETURNS jsonb`**
   - Returns full line-item details of a specific historical stock count run.

### 6.2 Strict Invariants for Stock Count Operations

- UI code must NEVER directly update `public.location_stock_balances`.
- All stock balance updates MUST originate from `public.inventory_stock_count_post_v485`, guaranteeing that ledger adjustments, row locks, sync version increments, and audit records are posted in a single atomic database transaction.
- Client requests MUST provide an RFC 4122 v4 UUID `p_request_id` to guarantee idempotent execution.

---

## 7. Phase 10: Smart Purchase Receiving Database Contracts

### 7.1 Existing Reused Procedures (ZERO Migrations Required)
Phase 10 requires **ZERO database migrations or schema alterations**. It uses existing, proven, production database procedures:

1. **`public.goods_receipt_create_v484(p_tenant_id uuid, p_purchase_order_id uuid, p_receipt_date date, p_items jsonb, p_supplier_delivery_note text, p_notes text) RETURNS jsonb`**
   - Validates that the purchase order exists and belongs to `p_tenant_id`.
   - Generates sequential Goods Receipt Note number: `GRN-YYMMDD-XXXXXX`.
   - Verifies each item in `p_items`:
     - Requires `abs(received_quantity - (accepted_quantity + damaged_quantity + rejected_quantity)) <= 0.000001`.
     - Validates that `received_quantity <= remaining_quantity` on the PO line.
     - Captures `damage_note`, `rejection_reason`, and `tracking` payloads (batches/serials).
   - Inserts draft record into `public.goods_receipts_v484` and `public.goods_receipt_items_v484`.
   - Returns `{ goods_receipt_id: uuid, grn_number: text, status: 'draft' }`.

2. **`public.goods_receipt_post_v484(p_tenant_id uuid, p_goods_receipt_id uuid, p_device_id text) RETURNS jsonb`**
   - Atomically locks the GRN with `FOR UPDATE`.
   - Idempotent: if already `'posted'`, returns existing record without re-posting.
   - For accepted items:
     - Invokes `public.inventory_adjust_stock` and `private.v4_location_stock_apply`.
     - Inserts entries into `public.location_stock_movements`.
     - Updates `public.location_stock_balances` with row-level locks.
     - Logs damaged items to quarantine/damaged tracking when applicable.
   - Updates `purchase_order_items_v480.received_quantity` and checks overall completion.
   - Updates `purchase_orders_v480.status`:
     - If all lines fully received: `'received'`.
     - If partially received: `'partially_received'`.
   - Bumps location sync version for POS and mobile clients.
   - Returns `{ goods_receipt_id: uuid, status: 'posted', purchase_order_status: text }`.

3. **`public.goods_receipt_list_v484(p_tenant_id uuid, p_location_id uuid DEFAULT NULL, p_status text DEFAULT NULL, p_query text DEFAULT '', p_limit integer DEFAULT 500)`**
   - Returns historical GRNs for audit review and discrepancy inspection.
   - Columns: `id`, `grn_number`, `receipt_date`, `status`, `purchase_order_id`, `order_number`, `supplier_id`, `supplier_name`, `location_id`, `location_name`, `line_count`, `received_quantity`, `accepted_quantity`, `damaged_quantity`, `rejected_quantity`, `created_at`.

4. **`public.purchase_order_list_v484(p_tenant_id uuid, p_location_id uuid, p_status text, p_query text, p_limit integer)`**
   - Retrieves open purchase orders eligible for receiving (status `'approved'`, `'ordered'`, `'confirmed'`, `'partially_received'`).

5. **`public.purchase_order_detail_v484(p_tenant_id uuid, p_purchase_order_id uuid)`**
   - Retrieves line items with `ordered_quantity`, `received_quantity`, and `remaining_receive_quantity`.

6. **`public.gst_purchase_create_v520(...)` via `PurchaseService.createPurchase`**
   - Used for Direct Inward receiving when goods arrive without a prior Purchase Order.
   - Atomically records supplier invoice, tax breakdowns, stock balance additions, and journal entries.

### 7.2 Strict Invariants for Goods Receiving Operations
- UI code must NEVER directly modify `public.location_stock_balances`.
- Receiving against Purchase Orders MUST post through `public.goods_receipt_create_v484` and `public.goods_receipt_post_v484`.
- Under-deliveries properly record partial status; over-deliveries and unexpected items are flagged in the UI for managerial review.
- All numbers, barcodes, and SKU strings preserve exact leading zeros.

---

## 8. Phase 11: Phone-to-PC Wireless Smart Scanner Architecture & Ephemeral Relays

### 8.1 Database Impact & Migration Guarantee
- **Zero Database Migrations Required:** Phase 11 introduces **no new tables, columns, indexes, or stored procedures**.
- **Ephemeral Broadcast Channels:** Communication between mobile scanners and desktop workstations operates exclusively through in-memory, zero-disk **Supabase Realtime Broadcast Channels** (`thq_scan_<tenant>_<session>`).
- **No Database Polling:** Real-time push notifications occur over authenticated WebSockets. No database records are written or polled during scanning.
- **Cryptographic Packet Invariants:** Scan packets are authenticated using ephemeral HMAC-SHA256 signatures generated with short-lived session secrets. Secrets are discarded in memory after 10 minutes or on unpairing.
- **Inventory & Financial Immutability:** Wireless scans entering POS Desktop or Client Desktop invoke existing, audited business and inventory services (`_handleScanCode`, `PosSmartInventoryService`). No raw database mutations occur outside established double-entry and RLS guardrails.




