# THQ ERP — Smart Inventory Architecture

**Document Version:** 1.0.0  
**Phase:** Phase 0 Architecture Definition  
**Date:** 2026-11-10  

---

## 1. Architectural Philosophy

THQ Smart Inventory is designed as a **shared enterprise capability** embedded deeply into the existing THQ ERP Flutter/Dart monorepo. It adheres to these architectural invariants:

1. **Single Source of Truth:** No second product database or disjoint stock table. All products exist in `public.products` / `public.product_variants`, all identifiers in `public.product_identifiers_v482`, and all physical stock balances in `public.location_stock_balances`.
2. **Universal Hardware Interoperability:** Barcode input is treated polymorphically whether originating from:
   - Built-in cameras on iOS and Android devices (`mobile_scanner`).
   - USB hardware barcode guns acting as keyboard HID wedges.
   - Bluetooth handheld ring or pocket scanners.
   - Remote smartphone camera streaming scans to a desktop terminal (Phone-to-PC).
3. **Defensive Multi-Tiered Identification:**
   - Tier 1: In-memory exact lookup index (< 1ms).
   - Tier 2: Local SQLite cache (`thq_pos_offline_v486.sqlite` / `thq_mobile_pos_v488.sqlite`) (< 5ms).
   - Tier 3: Supabase RPC `inventory_product_lookup_v482` (< 150ms).
   - Tier 4: Swappable external open catalog lookup (Open Food Facts / GS1) for unknown items.
4. **Authoritative Stock Ledgers:**
   - Physical stock counts and adjustments execute through security-definer RPCs (`inventory_stock_count_post_v485` and `inventory_adjust_stock_v483`) ensuring immutable stock movement ledger records.

---

## 2. Component Layout & Packages

```
packages/erp_core/
  └── lib/src/smart_inventory/
      ├── smart_inventory_models.dart         # Universal scan results, session models, import models
      ├── smart_scanner_controller.dart       # State machine for continuous/single scanning
      ├── product_identification_engine.dart  # Multi-tiered resolution logic
      └── external_product_lookup_service.dart# External catalog interface & providers

packages/thq_ui/
  └── lib/src/scanner/
      ├── thq_barcode_wedge_listener.dart     # Hardware USB/Bluetooth HID listener
      ├── thq_smart_scanner_view.dart         # Camera viewfinder with controls
      ├── thq_product_lookup_dialog.dart      # Quick lookup modal
      └── thq_multiple_match_dialog.dart      # Conflict resolution picker

apps/client_app/
  └── lib/screens/smart_inventory/
      ├── smart_inventory_workspace_screen.dart # 9-tab ERP back-office hub
      └── tabs/                               # Dashboard, Scan Center, Lookup, Bulk, Import,
                                              # Counting, Receiving, Studio, History

apps/pos_app/
  ├── lib/screens/pos_screen.dart             # POS checkout with wedge listener & rapid increment
  └── lib/services/phone_to_pc_scanner_service.dart # Realtime receiver for mobile scans

apps/mobile_pos/
  ├── lib/screens/barcode_scanner_screen.dart # Modernized viewfinder (continuous, torch, zoom)
  └── lib/services/mobile_scanner_bridge.dart # Phone-to-PC remote transmitter
```

---

## 3. Security & Isolation Model

- **Tenant Boundaries:** Every query and RPC mandates `tenant_id` validation via `private.erp_user_has_tenant_access(p_tenant_id)`.
- **Location Permissions:** Stock adjustments and counts verify location access permissions (`private.v4_location_access`).
- **No Secret Leakage:** No Supabase service-role keys are compiled into client binaries. All transactions authenticate via standard bearer JWTs and hardware device secrets.
- **Fail-Closed Default Deny:** RLS protects all new and existing tables.

---

## 4. Product Identification Architecture (Phase 2)

### 4.1 Orchestration Flow

```
                      SmartScanResult (from Phase 1: Camera / USB / Manual)
                                      │
                                      ▼
                      ProductIdentificationRequest
                       (rawIdentifier, tenantId, locationId, source)
                                      │
                                      ▼
                      ProductIdentificationEngine
                                      │
                 ┌────────────────────┴────────────────────┐
                 │                                         │
                 ▼                                         ▼
   Online Path (via RpcCaller)              Offline Path (SQLite / Memory)
RpcProductIdentificationRepository        LocalProductIdentificationRepository
                 │                                         │
       PostgreSQL RPC Execution                 Indexed Local Search
     inventory_product_lookup_v482              (barcode, SKU, part, id, searchCodes)
                 │                                         │
                 └────────────────────┬────────────────────┘
                                      │
                                      ▼
                       Match Prioritization & Ambiguity Check
                                      │
             ┌────────────────────────┼────────────────────────┐
             ▼                        ▼                        ▼
       [exactMatch]          [multipleMatches]            [noMatch / offlineMiss]
  Single candidate picked   Ambiguity preserved;        No candidates identified;
    by priority hierarchy    requires user selection      diagnostic info attached
```

### 4.2 Matching Priority Hierarchy

When resolving scanned codes, `ProductIdentificationEngine` enforces a strict 9-tier priority ranking:
1. `MatchMethod.exactBarcode` (EAN-13, UPC, Code 128)
2. `MatchMethod.exactQr` (THQ encoded QR matrix: `THQ:PRODUCT:...`)
3. `MatchMethod.exactInternal` (Internal warehouse/bin tags)
4. `MatchMethod.exactSku` (Canonical product variant SKU)
5. `MatchMethod.exactManufacturer` (Part numbers / OEM codes)
6. `MatchMethod.exactSupplier` (Vendor SKU mapping)
7. `MatchMethod.exactAlternateSku` (Legacy migration cross-references)
8. `MatchMethod.legacyBarcodeFallback` (Historical pre-v482 product barcodes)
9. `MatchMethod.searchIndexMatch` (Tokenized multi-code index)

### 4.3 Safe Data Integrity Guarantees

1. **Leading Zeros Invariant:** Barcodes such as `0012345678905` are strictly preserved as immutable strings. No numeric parsing (`int.parse`, `double.parse`) is ever performed on identifier codes.
2. **Deterministic Ambiguity Handling:** If multiple variants match at the highest priority level, the engine returns `ProductIdentificationStatus.multipleMatches` with `isAmbiguous = true`. It **never** silently auto-selects the first candidate.
3. **Fail-Closed Error Propagation:** Network disconnects or database exceptions are classified as `ProductIdentificationStatus.error` with error details, preventing technical faults from appearing as normal "not found" results.
4. **Tenant Isolation:** Lookups require explicit `tenantId`. A scanned barcode can never bypass tenant boundaries or expose records belonging to other businesses.

---

## 5. Phase 3 — Client Smart Inventory Workspace Architecture

### 5.1 Overview and Navigation Integration

The Client Smart Inventory Workspace is implemented natively within `apps/client_app` as `SmartInventoryWorkspaceScreen`. It is registered into the primary client navigation system:
- **Module Routing:** Added `smart_inventory` to `_isRoutableClientModule`, `_moduleIcon` (`Icons.qr_code_scanner`), and `_moduleCache` in `client_home_screen.dart`.
- **Direct Entrypoint:** Added a "Smart Inventory" action button in `inventory_products_screen.dart` header toolbar for instant one-click access from the main products catalog.

### 5.2 Workspace Component Structure

```
┌────────────────────────────────────────────────────────────────────────┐
│                       SmartInventoryWorkspaceScreen                    │
│  [Icon] Smart Inventory | Multi-identifier scanning   [Store Status]   │
├───────────┬───────────────┬────────────────┬───────────────┬───────────┤
│ Overview  │  Scan Center  │ Product Lookup │ Bulk Scanning │ History   │
└───────────┴───────────────┴────────────────┴───────────────┴───────────┘
      │             │               │                │             │
  Overview      Single /         Text & Code       Continuous     Local
   Metrics &   Continuous        Search Across     Crate/Truck    Session
  Quick Links  Viewfinder &     All Identifiers    Staging List   Auditing
               Wedge Stream                       (Zero Stock
                                                   Mutation)
```

### 5.3 Tab Specifications

1. **Screen A: Overview Tab (`SmartInventoryOverviewTab`):**
   - Summary metric stat cards: Session Scans, Identified Products, Unresolved Scans, and Active Bulk Session.
   - Quick action launchers to jump directly to Scan Center, Catalog Lookup, or Bulk Scan.
   - Real-time recent activity stream showing the last 8 scans with success badges, matched SKU/code, and timestamps.

2. **Screen B: Scan Center Tab (`SmartInventoryScanCenterTab`):**
   - Embedded `ThqBarcodeWedgeListener` wrapping the view to capture rapid USB/Bluetooth scanner keystrokes without requiring focus.
   - ChoiceChips for Single Scan vs Continuous Scan modes.
   - On-demand camera viewfinder (`ThqSmartScannerView`) toggle for laptops/tablets with built-in cameras.
   - Manual entry input with auto-focus for damaged barcodes.
   - Comprehensive product card rendering: SKU, barcode, unit, stock quantity, selling price, and authorized cost price (strictly gated by `inventory.manage` / `owner`).
   - Ambiguity resolution picker when multiple variants match.
   - Clear visual diagnostic cards for Product Not Found, Offline Cache Miss, or Network Errors.

3. **Screen C: Product Lookup Tab (`SmartInventoryProductLookupTab`):**
   - Multi-identifier live text search with 350ms debounce.
   - Filter chips to filter by All Identifiers, Has Barcode, Has SKU, or Has Manufacturer Code.
   - Detailed inspection modal displaying registered identifiers, category, brand, and stock status.

4. **Screen D: Bulk Scanning Tab (`SmartInventoryBulkScanTab`):**
   - Continuous scanning mode into an active staging session (`SmartScanSession`).
   - Rapid barcode wedge ingestion accumulating quantities for repeated scans.
   - Dedicated tabs for Identified Products vs Unresolved Scans.
   - Item increment/decrement/delete controls without touching the database.
   - Unresolved scan preservation with retry capability.
   - Explicit "Finish Session" and "Cancel" controls.

5. **Screen E: Scan History Tab (`SmartInventoryScanHistoryTab`):**
   - Inspection of completed bulk scan sessions during the client runtime.
   - Detailed session dialog displaying operator, timestamp, items, and unit totals.
   - Explicit disclaimers clarifying that sessions are temporary audit records ahead of Phase 8 database hardening.

### 5.4 Non-Negotiable Business & Accounting Protections

1. **Zero Stock Mutation Invariant:** Scanning in Phase 3 is strictly for verification, inspection, and temporary bulk staging. No database inventory balance, cost basis, or stock movement table is modified.
2. **Cost Price Protection:** Product cost price is strictly guarded behind `session.hasPermission('inventory.manage') || session.hasRole('owner')`. Non-admin staff can only see selling prices and available quantities.
3. **Multi-Store Isolation:** All lookup requests explicitly pass the currently selected store location (`LocationScopeService.selectedLocationId`) or fallback to the session's primary location. Store inventory balances remain strictly partitioned.
4. **POS Decoupling:** `apps/client_app` maintains complete architectural independence from POS offline SQLite tables (`OfflinePosService`), ensuring the client workspace operates seamlessly in both online and standard client environments.

---

## 6. Phase 4: POS Desktop Smart Inventory Integration Architecture

### 6.1 Architectural Overview

Phase 4 embeds the shared Smart Scanning Engine (`SmartScannerController`, `ThqBarcodeWedgeListener`, `ThqSmartScannerView`) and the Smart Product Identification Engine (`ProductIdentificationEngine`) directly into the production POS Desktop billing screen (`apps/pos_app/lib/screens/pos_screen.dart`).

```
+-----------------------------------------------------------------------------------+
|                        POS Desktop Billing Screen (PosScreen)                     |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |             ThqBarcodeWedgeListener (Root Window HID Event Interceptor)      |  |
|  |   - Captures USB/Bluetooth barcode guns without requiring field focus       |  |
|  |   - Inter-keystroke timing discrimination (< 50ms per key)                  |  |
|  |   - Dispatches parsed barcode stream to PosSmartInventoryService             |  |
|  +-----------------------------------------------------------------------------+  |
|                                         |                                         |
|                                         v                                         |
|  +-----------------------------------------------------------------------------+  |
|  |              PosSmartInventoryService (Dual-Engine Orchestrator)             |  |
|  |   - Tier 1: Supabase RPC (inventory_product_lookup_v482)                    |  |
|  |   - Tier 2: Offline SQLite catalog (OfflinePosService / offline_products)    |  |
|  |   - Preserves leading zeros and exact raw text integrity                    |  |
|  +-----------------------------------------------------------------------------+  |
|                                         |                                         |
|                  +----------------------+-----------------------+                 |
|                  |                                              |                 |
|            [Exact Match]                                   [Ambiguous]            |
|                  v                                              v                 |
|        _add(InventoryProduct)                       PosMultipleMatchDialog        |
|   - Existing cart line lookup                       - Cashier picks exact         |
|   - Consolidated quantity step                        candidate variant           |
|   - Scheduled pricing & tax sync                    - Dispatches to _add(p)       |
|   - Visual feedback banner                                                        |
+-----------------------------------------------------------------------------------+
```

### 6.2 Key Architectural Components

1. **`PosSmartInventoryService` (`apps/pos_app/lib/services/pos_smart_inventory_service.dart`):**
   - Singleton service that bridges `ProductIdentificationEngine` with POS environment.
   - Configures a `DualProductIdentificationRepository`:
     - Online: `RpcProductIdentificationRepository` using Supabase RPC `inventory_product_lookup_v482`.
     - Offline: `LocalProductIdentificationRepository` backed by SQLite `OfflinePosService.instance.getDb()`.
   - Maps `ProductIdentificationMatch` to `InventoryProduct` using existing fast-path `_productByVariantId` cache, falling back to raw payload dictionary reconstruction.

2. **Root Keyboard Wedge Interception:**
   - Wraps the entire POS billing scaffold with `ThqBarcodeWedgeListener`.
   - Cashiers can scan items at any time without manually clicking or focusing the barcode text field.
   - Text fields with active focus ignore wedge intercept unless rapid keystrokes match barcode gun cadence.

3. **Cart Integration (`_add(InventoryProduct)`):**
   - Strictly routes identified products through the existing `_add(product)` method in `PosScreen`.
   - Completely preserves existing business logic:
     - Out of stock warnings for inventory-tracked products.
     - Automatic quantity step incrementation for repeated scans of the same variant (`line.quantity += line.quantityStep`).
     - Line pricing, customer price lists, tax rules, and order discounts are recomputed through standard POS commercial pipelines.
   - Zero database mutation occurs upon scanning: physical stock decreases only when the cashier completes and posts the sale transaction.

4. **Ambiguity Resolution (`PosMultipleMatchDialog`):**
   - When a master barcode maps to multiple variant candidates (e.g. 10mm vs 12mm steel rods sharing a manufacturer barcode), a compact modal displays candidates with SKU, prices, and available stock.
   - The cashier makes an explicit disambiguation choice, preventing silent cart misattribution.

5. **Camera Viewfinder Integration:**
   - Cashiers can toggle an on-demand camera viewfinder (`ThqSmartScannerView`) via the header action button.
   - Displays live camera preview on tablet/laptop form factors and seamlessly collapses when toggled off.

6. **Scan Feedback Banner:**
   - Compact, non-disruptive feedback banner rendered below the header.
   - Displays positive confirmation on item add and informative warnings on unknown codes or offline cache misses.
   - Automatically dismisses after 4 seconds or on manual close.



