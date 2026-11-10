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
