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

---

## 7. Phase 5: Mobile POS Smart Inventory Integration Architecture

Phase 5 brings the shared Smart Scanning and Identification engines directly to mobile retail devices in `apps/mobile_pos` (`MobilePosHomeScreen` and `BarcodeScannerScreen`).

```
+-----------------------------------------------------------------------------------+
|                     Mobile POS Home Screen (MobilePosHomeScreen)                  |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |             ThqBarcodeWedgeListener (Root Window HID Event Interceptor)      |  |
|  |   - Captures Bluetooth handheld scanner guns / HID barcode devices          |  |
|  |   - Fast hardware keystroke discrimination (< 50ms)                         |  |
|  |   - Dispatches parsed scan stream to _handleScanCode                        |  |
|  +-----------------------------------------------------------------------------+  |
|                                         |                                         |
|         +-------------------------------+-------------------------------+         |
|         |                               |                               |         |
|         v                               v                               v         |
|   [Bluetooth Gun]             [Search onSubmitted]            [BarcodeScannerScreen]
|         |                               |                   (Continuous Camera /  |
|         |                               |                    Flash / Flip / Manual)|
|         +-------------------------------+-------------------------------+         |
|                                         |                                         |
|                                         v                                         |
|  +-----------------------------------------------------------------------------+  |
|  |            MobilePosSmartInventoryService (Dual-Engine Orchestrator)        |  |
|  |   - Tier 1: Supabase RPC (inventory_product_lookup_v482)                    |  |
|  |   - Tier 2: Offline SQLite catalog (MobilePosLocalStore / products table)   |  |
|  |   - Preserves leading zeros (e.g. 0089012345678)                            |  |
|  +-----------------------------------------------------------------------------+  |
|                                         |                                         |
|                  +----------------------+-----------------------+                 |
|                  |                                              |                 |
|            [Exact Match]                                   [Ambiguous]            |
|                  v                                              v                 |
|        _addProduct(MobileProduct)                    MobilePosMultipleMatchDialog  |
|   - Auto-checks serial tracking                     - Compact mobile sheet        |
|   - Calls _add(MobileProduct)                       - Displays SKU, price, stock  |
|   - Consolidates quantity on repeat scan            - Explicit cashier selection  |
|   - Recalculates discounts, taxes, totals           - Dispatches to _addProduct   |
|   - ThqNotify success banner                        - Zero database stock mutation|
+-----------------------------------------------------------------------------------+
```

### 7.1 Key Architectural Components

1. **`MobilePosSmartInventoryService` (`apps/mobile_pos/lib/services/mobile_pos_smart_inventory_service.dart`):**
   - Singleton service bridging `ProductIdentificationEngine` with the Mobile POS execution environment.
   - Dual-repository architecture:
     - Online: `RpcProductIdentificationRepository` calling Supabase RPC `inventory_product_lookup_v482`.
     - Offline: `LocalProductIdentificationRepository` backed by `MobilePosLocalStore.instance.db` querying table `products`.
   - `resolveProduct(match, {products})`: Resolves `ProductIdentificationMatch` to `MobileProduct` by matching in-memory cached products, querying the local SQLite database, or parsing the raw RPC payload map.

2. **Upgraded Full-Screen Scanner (`BarcodeScannerScreen`):**
   - Replaced legacy single-scan raw `MobileScanner` with full `ThqSmartScannerView` + `SmartScannerController`.
   - Supports:
     - **Continuous Scanning Mode:** Keeps camera active while items are scanned in rapid succession, showing item count and real-time feedback toast.
     - **Torch Toggle:** Hardware flashlight toggle for dark stockrooms and warehouses.
     - **Camera Switch:** Seamless flip between back and front cameras.
     - **Manual Code Entry Modal:** `_ManualCodeEntryDialog` with autofocus for keyboard/num-pad input of barcode, SKU, or serial number.
     - **Live Toast Overlay:** Instant color-coded visual indicator displaying scanned code and status.
     - Backward-compatible fallback for callers requesting single-code return.

3. **Root Bluetooth / USB Scanner Wedge Interception:**
   - Wraps the root layout of `MobilePosHomeScreen` in `ThqBarcodeWedgeListener`.
   - Captures wireless Bluetooth barcode scanners paired to the mobile device in HID keyboard mode without requiring the search input to be focused.

4. **Search Bar `onSubmitted` Integration:**
   - Search field `onSubmitted` triggers `_handleScanCode(value, source: ScannerSource.manual)`.
   - Clears the search text and automatically runs multi-tier identification.

5. **Cart Integration (`_addProduct` / `_add`):**
   - Serial tracked products prompt for serial number validation against `MobilePosLocalStore.findSerial`.
   - Non-serial items route directly to `_add(MobileProduct)`.
   - Repeated scans of the same product consolidate quantity without creating redundant cart lines (`line.quantity += step`).
   - Re-evaluates unit price, customer wholesale/retail price tiering, taxes, round-off, and totals.
   - Stock check verifies offline available stock for inventory-tracked products.
   - **Zero database mutation upon scan:** Inventory quantities in SQLite and Supabase decrement strictly when the bill is completed and synchronized.

6. **Ambiguity Resolution (`MobilePosMultipleMatchDialog`):**
   - When a barcode or identifier returns multiple candidate variants, displays a mobile-optimized modal dialog.
   - Displays variant name, SKU, price, and available stock with individual `Select` actions.
   - Requires explicit cashier choice before adding to cart.

---

## 8. THQ Client Mobile Smart Inventory Integration Architecture (Phase 6)

### 8.1 Philosophy and Operational Context
`apps/client_mobile` serves as the primary mobile back-office, warehouse, yard, and operational management tool for THQ ERP. Unlike POS applications that directly populate sales billing carts, Client Mobile Smart Inventory functions as an **operational verification, product discovery, and staging engine**.

```
+-----------------------------------------------------------------------------------+
|               THQ Client Mobile — Smart Inventory Architecture                    |
|                                                                                   |
|  [Hardware HID Scanner]        [Integrated Camera]        [Manual Code Entry]     |
|   (ThqBarcodeWedgeListener)   (ThqSmartScannerView)    (MobileManualCodeEntry)    |
|                \                       |                       /                  |
|                 +----------------------+----------------------+                   |
|                                        |                                          |
|                                        v                                          |
|                       MobileSmartInventoryService                                 |
|               (ProductIdentificationEngine + Supabase RPC)                        |
|                                        |                                          |
|                     +------------------+------------------+                       |
|                     |                                     |                       |
|             [Exact Match]                            [Ambiguous]                  |
|                     v                                     v                       |
|         _handleResolvedMatch               MobileSmartInventoryMultipleMatch      |
|     - Updates Last Scan Card               - Multi-variant disambiguation sheet   |
|     - Adds to Bulk Session (if active)     - Explicit operator selection          |
|     - Logs to Activity Stream              - Dispatches to _handleResolvedMatch   |
|     - Zero Stock Mutation                  - Zero Stock Mutation                  |
+-----------------------------------------------------------------------------------+
```

### 8.2 Architectural Principles & Invariants

1. **Strict Online Network Model (No Duplicate SQLite):**
   - Unlike `pos_app` and `mobile_pos`, `apps/client_mobile` does not maintain an offline SQLite database.
   - Identification relies on `RpcProductIdentificationRepository` calling Supabase RPC `inventory_product_lookup_v482`.
   - When offline or unreachable (`SocketException`, `TimeoutException`), the service returns a clean `ProductIdentificationResult.error` with user-friendly messaging stating that Client Mobile requires an active network connection.

2. **Session Models Promoted to Shared Foundation:**
   - Promoted `SmartScanSession`, `SmartScanSessionItem`, and `UnresolvedScanItem` from `apps/client_app` to `packages/erp_core/lib/src/inventory/smart_inventory_session_models.dart`.
   - Exported through `package:erp_core/erp_core.dart` to establish a shared cross-platform staging standard.
   - Backward-compatibility re-exports maintained in `apps/client_app/lib/models/smart_inventory_session_models.dart`.

3. **Strict Non-Mutating Operational Staging:**
   - In accordance with THQ accounting rules, scanning in Client Mobile is strictly observational and staging.
   - Bulk scan sessions consolidate items, track scan counts, and collect unresolved codes in memory. Finishing a session archives it into historical memory without altering `public.location_stock_balances` or writing ledger entries. Actual physical counts and reconciliation are reserved for Phase 9.

4. **Multi-Tenant & Multi-Location Isolation:**
   - Lookups and catalog searches pass authenticated `tenantId` and active `locationId` from `MobileSession`.
   - Location switcher allows seamless location context switching for multi-warehouse managers.

5. **Cost Price Security & Permission Guarding:**
   - Product detail modals enforce role and permission checks:
     ```dart
     final canViewCost = session.isOwner || session.hasPermission('inventory.manage');
     ```
   - Unauthorized personnel see a secure restricted notice with no financial data leakage.

### 8.3 Core Components

1. **`MobileSmartInventoryService` (`apps/client_mobile/lib/services/mobile_smart_inventory_service.dart`):**
   - Manages the singleton `ProductIdentificationEngine` instance with online RPC caller.
   - Maintains active and completed bulk scanning sessions.
   - Emits real-time scan activity via a broadcast `activityStream` and maintains a 100-entry rolling memory feed.
   - Provides `searchCatalog` fallback calling `inventory_list_products_v483` with debounced multi-field fuzzy matching.

2. **`MobileSmartInventoryWorkspaceScreen` (`apps/client_mobile/lib/screens/smart_inventory/mobile_smart_inventory_workspace_screen.dart`):**
   - 5-tab responsive mobile workspace:
     - **Overview:** Active location header, quick actions, active session status, and recent scan activity feed.
     - **Scan:** Full camera viewfinder (`ThqSmartScannerView`), mode toggle (Continuous/Single), flash/camera switches, manual code entry button, and real-time feedback card.
     - **Lookup:** Debounced multi-field product search by name, SKU, barcode, brand, or part number with quick-tap details.
     - **Bulk:** Live staging list displaying staged products, consolidated scan counts, unresolved flags, and session finish action.
     - **History:** Completed session archive displaying item counts, unit totals, timestamps, and detail breakdowns.
   - Root `ThqBarcodeWedgeListener` capturing external Bluetooth barcode scanners across all tabs.

3. **Dialogs & Modals (`apps/client_mobile/lib/widgets/mobile_smart_inventory_dialogs.dart`):**
   - `MobileSmartInventoryMultipleMatchDialog`: Disambiguation dialog for ambiguous codes.
   - `MobileManualCodeEntryDialog`: Quick code typing modal with validation.
   - `MobileProductDetailModal`: Full product sheet with stock levels, selling price, and permission-guarded cost price.

4. **Navigation Integration:**
   - Primary Tabs: Tab bar and action card in `MobileInventoryWorkspace`.
   - Modules Catalog: Listed under Operations in `MobileModulesCatalogPage`.
   - More Drawer: Quick shortcut in `_MoreTab`.

---

## 9. Phase 7: Smart Excel / CSV Product Import Engine Architecture

### 9.1 Objectives & Scope

Phase 7 provides a resilient, professional, and reusable product import capability allowing businesses to bulk import product catalogues into THQ ERP from vendor-provided spreadsheets.

### 9.2 Key Invariants & Safeguards

1. **Zero Live Stock Ledger Mutations:**
   - Product catalogue import strictly creates and catalogues products and variants.
   - It does **NOT** write to `public.location_stock_balances` or generate inventory movement records.
   - Any opening stock column in the source spreadsheet is staged with an explicit informational warning that stock ledger adjustments must be performed through verified stock intake or reconciliation workflows (Phase 9).

2. **Leading Zero & Identifier Integrity:**
   - Numeric codes like `0012345678905` or `04523` are treated strictly as string tokens throughout the pipeline.
   - Both CSV and XLSX parsers prevent truncation of leading zeros and eliminate accidental scientific notation conversion.

3. **Non-destructive Dry-Run Validation:**
   - Full validation pass analyzes data types, required fields (Product Name, SKU), price bounds, and duplicate collisions in-memory prior to any database operation.

4. **Cost Price Protection:**
   - Cost price columns are hidden and zeroed out for users lacking `inventory.manage` or `owner` privileges.

5. **Idempotent Batch Processing:**
   - Chunks of 50 rows are batched against backend RPC `inventory_bulk_create_products` with per-row exception capture.

### 9.3 Engine Architecture (`packages/erp_core/lib/src/import/`)

- **`SmartCsvParser` (`csv_parser.dart`):**
  - Pure Dart RFC 4180 compliant parser.
  - Auto-detects delimiters (`,`, `;`, `\t`).
  - Handles UTF-8 BOM, multiline fields, and escaped quotes (`""`).

- **`SmartXlsxParser` (`xlsx_parser.dart`):**
  - Pure Dart parser utilizing `excel: 4.0.6`.
  - Multi-sheet discovery and sheet-specific parsing.
  - Type-safe cell extraction preserving integers and text codes without trailing `.0`.

- **`SmartColumnMapper` (`smart_column_mapper.dart`):**
  - Multi-synonym matching engine for 17 standard THQ fields.
  - Assigns confidence scores (`high`, `medium`, `low`, `unmapped`).
  - Flags missing mandatory fields (`Product Name`, `SKU`).

- **`SmartImportValidator` (`smart_import_validator.dart`):**
  - In-memory validation verifying mandatory fields, non-negative prices, valid tax rates, and numeric bounds.

- **`SmartDuplicateDetector` (`smart_duplicate_detector.dart`):**
  - Intra-file duplicate detector (flags repeated SKUs or barcodes within the uploaded file).
  - Catalog duplicate detector (checks existing live records via `ProductIdentificationRepository`).

- **`SampleTemplateGenerator` (`sample_template_generator.dart`):**
  - Generates downloadable CSV template with UTF-8 BOM and stylized Excel (.xlsx) templates with sample rows.

- **`SmartImportEngine` (`smart_import_engine.dart`):**
  - Orchestrates the full import pipeline from file loading to batch execution and error CSV generation.

### 9.4 Desktop User Interface (`apps/client_app`)

- **`SmartInventoryImportTab` (`tabs/smart_inventory_import_tab.dart`):**
  - Embedded as Tab 5 in `SmartInventoryWorkspaceScreen`.
  - Guided 7-step desktop import workflow:
    1. File Upload (drag-and-drop / browse).
    2. Worksheet Selection (for multi-sheet workbooks).
    3. Column Mapping (interactive mapping table with confidence indicators & dropdown overrides).
    4. Validation Dry-Run (non-mutating background check).
    5. Visual Pre-Import Preview (dense data table with error tooltips and status filters).
    6. Duplicate Resolution Strategy (`Skip Duplicates`, `Import New Only`, `Update Existing`).
    7. Batch Import Execution & Failure CSV Export.
- **Catalog Integration:**
  - "Import Products" entry point added to `InventoryProductsScreen` toolbar with automatic refresh upon return.
  - Quick Action launcher added to `SmartInventoryOverviewTab`.

---

## 10. Phase 8: Smart Barcode Studio & Label Printing Engine Architecture

### 10.1 Objectives & Scope

The Smart Barcode Studio provides an integrated design, generation, and batch-printing environment for product labels across desktop and retail environments.
It enables business operators to:
1. Search and select products across the active store catalogue.
2. Filter for products missing barcodes or needing re-labelling.
3. Validate barcode symbologies (Code 128, EAN-13, UPC-A, QR Code) with strict check-digit algorithms.
4. Auto-generate conflict-free in-store EAN-13 barcodes (GS1 prefix `28`), UPC-A (prefix `2`), Code 128, or structured QR payloads.
5. Configure thermal rolls (e.g. 50x30mm, 50x25mm, 58x40mm) and A4 multi-label sheets (e.g. 24, 14, 40 labels per page).
6. Toggle element visibility (Store name, Product title, Brand/Variant, SKU, Selling Price, Barcode number).
7. Preview labels live on an interactive scaled canvas matching physical label dimensions.
8. Print batch jobs directly to thermal or laser printers or export as high-fidelity PDF documents.

### 10.2 Key Invariants & Safeguards

- **Catalogue & Printing Only:** Label generation and printing operations NEVER mutate inventory stock balances (`location_stock_balances`), create movement ledger entries (`inventory_movement_history_v481`), or post accounting vouchers.
- **Zero Schema Migrations:** Reuses existing production Supabase database objects:
  - `label_templates_v482` & `label_template_save_v482`
  - `product_identifiers_v482` & `product_identifier_save_v482`
  - `product_identifier_generate_v482`
  - `private.v482_ean13_check_digit`
- **GS1 In-Store Namespace Guarantee:** Internal EAN-13 generation strictly uses prefix `28` (reserved by GS1 for restricted circulation), guaranteeing zero collisions with external manufacturer barcodes.
- **Leading Zero Preservation:** All barcodes and SKUs are stored and processed strictly as text strings (e.g. `'0012345678905'`).

### 10.3 Core Barcode Subsystem (`packages/erp_core/lib/src/barcode/`)

- **`barcode_format.dart` (`LabelBarcodeFormat`, `BarcodeValidator`):**
  - Defines `LabelBarcodeFormat` enum: `code128`, `ean13`, `upcA`, `qrCode`.
  - Implements EAN-13 modulo-10 check digit calculation with 1/3 alternating weighting.
  - Implements UPC-A modulo-10 check digit calculation with 3/1 alternating weighting.
  - Validates Code 128 ASCII range (32 to 126) and length limits.
  - Validates QR Code alphanumeric content and length.
- **`barcode_generator.dart` (`BarcodeGenerator`):**
  - `generateInternalEan13(sequence)`: produces `'28' + pad10(seq) + checkDigit`.
  - `generateInternalUpcA(sequence)`: produces `'2' + pad10(seq) + checkDigit`.
  - `generateCode128({required sku, sequence})`: produces sanitized alphanumeric code.
  - `generateThqQrPayload({required variantId, required codeOrSequence})`: produces structured payload `THQ:PRODUCT:<variant_short_id>:<code_or_seq>`.
- **`label_models.dart` (`LabelTemplate`, `LabelDimensions`, `LabelPrintItem`, `PaperMode`):**
  - `PaperMode`: `thermal` (continuous roll, 1 label per page), `a4` (multi-label grid layout).
  - Built-in presets:
    - Standard Thermal: 50 × 30 mm
    - Compact Jewelry / Tag: 50 × 25 mm
    - Shipping / Box: 58 × 40 mm
    - A4 Sheet: 24 labels (70 × 37 mm, 3 columns × 8 rows)
    - A4 Sheet: 14 labels (105 × 42 mm, 2 columns × 7 rows)
    - A4 Sheet: 40 micro-tags (52.5 × 29.7 mm, 4 columns × 10 rows)
  - `LabelPrintItem`: item model tracking product identifiers, copies count, and price formatting.

### 10.4 Enhanced Printing Engine (`apps/client_app/lib/services/label_printing_service.dart`)

- Reusable vector PDF compilation using `package:pdf` and `package:printing`.
- Vector barcode rendering via `pw.BarcodeWidget` for crisp thermal printing at 203 DPI and 300 DPI without pixelation.
- Supports batch roll rendering (one PDF page per printed label copy) and A4 sheet rendering (items flow into grid cells with row/column boundaries and auto page breaks).
- 100% backward compatible with legacy single-label `printLabels(...)` invocations.

### 10.5 Interactive Studio UI (`apps/client_app/lib/screens/smart_inventory/tabs/smart_barcode_studio_tab.dart`)

- Embedded as Tab 6 in `SmartInventoryWorkspaceScreen`.
- Left Pane (Product Catalogue & Selection):
  - Fast search with debouncing.
  - Filter chips: `All`, `Missing Barcode`, `Selected`.
  - Checkbox multi-select, per-item copies stepper, barcode format validation status badge, and individual "Generate" button.
  - Batch action dropdown: "Set all copies = 1", "Set all copies = 5", "Match stock quantity", "Generate EAN-13 for missing".
- Right Pane (Studio Designer & Live Preview):
  - Preset template selector (Standard presets + Custom dimensions).
  - Barcode symbology selector.
  - Element toggles (Store, Product, Brand/Variant, SKU, Price, Barcode Number).
  - Real-time scaled live preview canvas reflecting label aspect ratio and toggles.
  - Preview pagination through selected products (`Label X of Y`).
  - Total labels count and paper/sheet estimation.
  - Direct "Print Labels" action via native printer dialog and "Export PDF" file save.
- Navigation integration:
  - Quick action launcher added to `SmartInventoryOverviewTab` linking to Tab 6.
  - "Barcode Studio" toolbar button added to `InventoryProductsScreen`.

---

## 11. Phase 9: Physical Stock Counting & Reconciliation Engine Architecture

### 11.1 Objectives & Scope

Phase 9 delivers a physical cycle counting and inventory reconciliation subsystem integrated into the THQ Smart Inventory Workspace.
It allows warehouse managers and store operators to:
1. Capture an instantaneous snapshot of system stock balances across all product lines or filtered categories.
2. Rapidly count inventory using USB/Bluetooth barcode guns, camera viewfinders, or manual SKU search.
3. Automatically resolve scanned codes into catalogue variants and track scan occurrences in real-time.
4. Calculate stock variances on the fly:
   - **Matched:** Counted quantity matches expected system stock (`Variance == 0`).
   - **Shortage:** Physical count is lower than expected system stock (`Variance < 0`).
   - **Excess:** Physical count exceeds expected system stock (`Variance > 0`).
   - **Uncounted:** Products in snapshot that have not yet been physically counted.
   - **Unstocked:** Scanned items found in the physical store that were not present in the system snapshot.
5. Filter items by discrepancy type to investigate missing or excess stock.
6. Detect and warn on concurrent stock movements (sales/receipts) that occurred between snapshot capture and count completion.
7. Review discrepancy breakdowns and post approved reconciliation adjustments atomically into the double-entry inventory ledger with guaranteed request idempotency.
8. Maintain a persistent audit trail of past counts and variances.

### 11.2 Key Invariants & Accounting Safeguards

1. **Non-Destructive Accounting & Zero Direct Balance Mutations:**
   - UI code NEVER directly mutates `public.location_stock_balances` or bypasses ledger integrity.
   - All approved counts post strictly through the verified PostgreSQL stored procedure `public.inventory_stock_count_post_v485`.
   - The stored procedure automatically calculates `v_delta := v_counted - v_system` per item, acquires row locks (`FOR UPDATE`), invokes `public.inventory_adjust_stock`, records movement lines in the movement history ledger via `private.v4_location_stock_apply`, and updates store sync versions.
2. **Zero Schema Migrations:**
   - Reuses existing production Supabase database objects:
     - `public.inventory_stock_count_snapshot_v485(p_tenant_id, p_location_id, p_query)`
     - `public.inventory_stock_count_post_v485(p_tenant_id, p_location_id, p_items, p_notes, p_device_id, p_request_id)`
     - `public.stock_counts_list_v485(p_tenant_id, p_location_id, p_from, p_to, p_limit)`
     - `public.stock_count_detail_v485(p_tenant_id, p_count_id)`
     - Tables: `public.stock_counts`, `public.stock_count_items`.
3. **Idempotent Posting Guarantee:**
   - Every session generates a cryptographically secure RFC 4122 v4 UUID `p_request_id`.
   - Repeated submissions replay the cached response without creating duplicate adjustment vouchers.
4. **Separation of Permissions:**
   - Counting and scanning can be performed by store staff (`inventory.view`).
   - Posting adjustments and approving discrepancies requires `inventory.stock_count`, `inventory.manage`, or `owner` privileges.
5. **Handling Live Stock Movements:**
   - Pre-flight concurrent change detection checks fresh stock balances against the snapshot, warning the user if sales or receipts occurred during the counting process.

### 11.3 Core Domain Models (`packages/erp_core/lib/src/inventory/stock_count_models.dart`)

- **`StockCountStatus`:** `draft`, `inProgress`, `review`, `posted`, `cancelled`.
- **`StockCountVarianceType`:** `matched`, `shortage`, `excess`, `notCounted`.
- **`StockCountItem`:** Tracks variantId, productId, names, SKU, barcode, unitName, systemQuantity (from snapshot), countedQuantity, trackingMode, trackingPayload, reservedQuantity, damagedQuantity, quarantineQuantity, isCounted, scanCount, and lastScannedAt.
- **`StockCountSummary`:** Aggregates metrics (totalItems, countedItems, uncountedItems, matchedItems, shortageItems, excessItems, unresolvedCount, totalSystemQuantity, totalCountedQuantity, netVarianceQuantity, completionPercentage).
- **`StockCountSession`:** Active count session container managing items list, session metadata, unresolved scans, match recording (`recordScanMatch`), and post payload conversion (`toPostPayload`).
- **`StockCountAuditRecord`:** Immutable model representing historical stock count runs parsed from `stock_counts_list_v485`.

### 11.4 Stock Counting Service (`apps/client_app/lib/services/stock_counting_service.dart`)

- `fetchSnapshot({tenantId, locationId, query})`: Invokes `inventory_stock_count_snapshot_v485` and maps to `StockCountItem` list.
- `postStockCount({tenantId, locationId, items, notes, deviceId, requestId})`: Invokes `inventory_stock_count_post_v485` with validation and error wrapping.
- `checkConcurrentStockChanges({tenantId, locationId, originalItems})`: Compares original snapshot with fresh balances to detect concurrent sales or receipts.
- `listPastCounts({tenantId, locationId, from, to, limit})`: Lists past counts from `stock_counts_list_v485`.
- `getCountDetail({tenantId, countId})`: Retrieves line-level audit details from `stock_count_detail_v485`.
- `setCustomRpc(...)`: Dependency injection hook for deterministic testing.

### 11.5 Desktop User Interface (`apps/client_app/lib/screens/smart_inventory/tabs/smart_stock_count_tab.dart`)

- Embedded as Tab 7 in `SmartInventoryWorkspaceScreen`.
- Key UI Capabilities:
  - **Session Setup & Historical Review:** Displays location badge, past count audits table with variance summaries, and "Start New Stock Count" action dialog.
  - **Active Counting Workspace:**
    - Live barcode scanner integration via `ThqBarcodeWedgeListener` (hardware guns) and optional `ThqSmartScannerView` (camera).
    - Manual search and SKU input with auto-increment.
    - Progress metric chips (Expected, Counted %, Matched, Shortages, Excess, Unresolved).
    - Discrepancy filter chips: `All`, `Pending`, `Shortages`, `Excess`, `Matched`.
    - Interactive product table with +/- steppers, real-time variance badges, and one-click "Match" button.
  - **Review & Approval Dialog:**
    - Discrepancy breakdown cards and net variance calculation.
    - Concurrent movement warning banner if stock changed during the count.
    - Reconciliation notes input.
    - Explicit verification confirmation checkbox.
    - Permission-checked "Post Adjustments" action.
- Navigation integration:
  - Quick action launcher added to `SmartInventoryOverviewTab` linking to Tab 7.
  - "Stock Count" toolbar button added to `InventoryProductsScreen`.

---

## 12. Phase 10: Smart Purchase Receiving & Inventory Inward Engine Architecture

### 12.1 Purpose & Scope
The Smart Purchase Receiving & Inventory Inward Engine delivers an industrial receiving workflow within THQ Smart Inventory. It bridges procurement with physical warehouse and store operations by enabling warehouse operators and store staff to receive inward shipments against approved Purchase Orders or direct deliveries, verify delivered quantities through hardware barcode scanning or camera recognition, record damaged or rejected goods, handle delivery discrepancies, and post approved receipts atomically into the inventory ledger without corrupting financial records or mutating live stock balances out-of-band.

### 12.2 Architectural Invariants & Guarantees
1. **Zero Direct Stock Balance Mutations:** UI screens and services NEVER directly update `public.location_stock_balances`. All stock movements and balance adjustments are posted exclusively through approved, audited database RPCs:
   - For PO-based receiving: `public.goods_receipt_create_v484` followed by `public.goods_receipt_post_v484`.
   - For direct supplier receipts: `PurchaseService.createPurchase` (`public.gst_purchase_create_v520`).
2. **Atomic Inventory & Ledger Posting:** Inward postings create immutable entries in `location_stock_movements`, update line receipts on `purchase_order_items_v480`, transition `purchase_orders_v480.status` (`partially_received` or `received`), and advance the store sync version for offline clients.
3. **Multi-Identifier Product Resolution:** Inwarded items are identified via the unified `ClientSmartInventoryService` and `ProductIdentificationEngine` across barcodes (EAN-13, UPC-A, Code 128), internal product codes, SKUs, manufacturer part numbers, supplier reference numbers, and custom QR codes.
4. **Leading-Zero & String Fidelity:** Barcodes and numeric SKUs (e.g., `0012345678905`) are handled strictly as strings, preventing truncation or numeric parsing corruption.
5. **Multi-Store Location Isolation:** Goods receipts are scoped to the active store/warehouse location (`location_id`), strictly respecting RLS policies and store memberships.
6. **Role & Permission Encasement:** Posting goods receipts requires `purchases.manage`, `inventory.manage`, or the `owner` role. Staff with read-only permissions can inspect open orders and audit trails but cannot commit ledger adjustments.

### 12.3 Domain Models (`packages/erp_core/lib/src/inventory/purchase_receiving_models.dart`)
- `ReceivingMode`: Enum distinguishing `purchaseOrder` (against an existing PO) from `directInward` (ad-hoc supplier delivery).
- `ReceivingItemStatus`: Detailed line state (`pending`, `partial`, `complete`, `excess`, `unexpected`).
- `PurchaseReceivingItem`: Tracks ordered quantity, previously received balance, current session received count, accepted quantity, damaged quantity, rejected quantity, unit cost, tracking modes (serials/batches), inspection notes, and discrepancy indicators (`isFullyReceived`, `isPartiallyReceived`, `isMissing`, `isUnexpected`, `hasDiscrepancy`).
- `PurchaseReceivingSummary`: Aggregates session metrics including total ordered, total received, total accepted, total damaged, total rejected, line breakdown (complete, partial, missing, excess, unexpected), unresolved scan count, and completion percentage.
- `PurchaseReceivingSession`: In-memory session container managing items, scan matching (`recordScanMatch`), unresolvable scan accumulation (`recordUnresolvedScan`), and formatting JSON payloads for `goods_receipt_create_v484` (`toGrnPayload`).
- `PurchaseOrderSummaryRecord` & `GoodsReceiptSummaryRecord`: Lightweight records deserialized from RPC outputs for responsive listing and auditing.

### 12.4 Service Layer (`apps/client_app/lib/services/purchase_receiving_service.dart`)
- Singleton `PurchaseReceivingService.instance` coordinating procurement and inventory RPCs:
  - `listReceivablePurchaseOrders`: Queries `purchase_order_list_v484` for approved, ordered, confirmed, or partially received POs with remaining items.
  - `fetchReceivingItemsForPo`: Queries `purchase_order_detail_v484` and maps line items to `PurchaseReceivingItem` with remaining expected quantities.
  - `createGoodsReceipt`: Invokes `goods_receipt_create_v484` to create a draft GRN (`GRN-YYMMDD-XXXXXX`).
  - `postGoodsReceipt`: Invokes `goods_receipt_post_v484` with device telemetry to atomically update stock balances, movements, and PO status.
  - `createAndPostGoodsReceipt`: Atomically creates and posts the GRN, returning complete GRN number and ledger status.
  - `listPastGoodsReceipts`: Queries `goods_receipt_list_v484` for historical GRN audit trails.
  - `postDirectInwardReceipt`: Integrates with `PurchaseService.createPurchase` for non-PO inward receipts.

### 12.5 UI & Workspace Layer (`SmartPurchaseReceivingTab`)
- Segmented Setup View:
  - **Open Purchase Orders:** Displays open orders, supplier names, location, order dates, remaining units vs ordered, and one-click "Receive Goods" launcher.
  - **Direct Inward:** Ad-hoc receiving form with supplier selection, supplier invoice number, and delivery note fields.
  - **GRN History:** Historical audit table of posted goods receipts with drill-down and receipt dates.
- Active Receiving Workspace:
  - Live hardware wedge listener (`ThqBarcodeWedgeListener`) for high-speed USB/Bluetooth barcode guns.
  - On-demand camera viewfinder (`ThqSmartScannerView`) for mobile or webcam receiving.
  - Manual search toolbar with instant auto-increment on enter.
  - Progress metric chips (Ordered, Received %, Accepted, Complete Lines, Missing Lines, Damaged, Rejected, Excess, Unresolved Scans).
  - Status filter chips (`All`, `Pending`, `Received`, `Missing`, `Damaged / Rejected`, `Excess / Extra`).
  - Item rows with `[-] [qty] [+]` steppers, status badges, remaining expected labels, and one-click "Match" button.
- Review & Approval Dialog:
  - Full discrepancy breakdown (under-delivery missing lines, excess deliveries, damaged items, rejected items).
  - Supplier delivery note / challan number and receiving remarks capture.
  - Accounting guarantee explanation.
  - Explicit physical inspection confirmation checkbox.
  - Permission-gated "Confirm & Post Receipt" action.
- Workspace Navigation:
  - Embedded as Tab 8 into `SmartInventoryWorkspaceScreen` (length 9).
  - Quick action card added to `SmartInventoryOverviewTab`.
  - "Receive Goods" shortcut added to `InventoryProductsScreen`.
  - "Receive Goods" button added to `PurchasesScreen`.

---

## 13. Phase 11: Phone-to-PC Wireless Smart Scanner Architecture

### 13.1 Purpose & Scope
The Phone-to-PC Wireless Smart Scanner enables any Android or iOS device running THQ Mobile (`apps/client_mobile` or `apps/mobile_pos`) to pair wirelessly with a desktop THQ workstation (`apps/pos_app` or `apps/client_app`) and function as a high-performance, real-time wireless barcode scanner. It eliminates the need for expensive dedicated wireless scanning guns while providing live bi-directional feedback, strict cryptographic isolation, check-digit frame verification, and zero permanent credential exposure.

### 13.2 Security, Pairing, & Cryptographic Guarantees
1. **Zero Permanent Secrets in QR Codes:** Pairing QR codes contain no API keys, Supabase service-role secrets, master passwords, or permanent auth tokens.
2. **Ephemeral Handshake Secrets with 256-Bit Cryptographic Entropy:** Pairing payload generates 256 bits of true cryptographic entropy via `Random.secure()` (32 bytes encoded in URL-safe base64, producing 44 characters) valid for 10 minutes.
3. **Single-Use Consumption & Revocation:** Pairing credentials are strictly single-use. Once an authorized mobile scanner joins, the host marks the payload consumed (`isConsumed = true`), preventing any replay or secondary hijacking.
4. **Private Channel Authorization:** Supabase Realtime channels are initialized with `opts: const RealtimeChannelConfig(private: true)` ensuring WebSocket subscriptions require active Supabase user authentication. Both host and scanner verify an active authenticated user before opening channels.
5. **Bi-Directional HMAC-SHA256 Signatures:**
   - Scan packets transmitted from mobile to desktop are signed: `sessionId:messageId:rawCode`.
   - Acknowledgement packets (`WirelessScanAck`) transmitted back from desktop to mobile are also signed: `sessionId:messageId:success:receivedCode`.
   - Both ends verify HMAC signatures with `handshakeSecret`; any forged or tampered packet is discarded immediately.
6. **Message Freshness (< 30s):** Scan messages enforce strict wall-clock freshness (`timestamp.difference(DateTime.now()).abs() < 30s`), preventing delayed or replayed packets from entering sessions.
7. **Zero Secrets in Logs:** String representations (`toString()`) mask cryptographic tokens (`sec: [PROTECTED]`, `sig: [PROTECTED]`). No credentials or handshake secrets are written to logs or persistent storage.
8. **Sliding-Window Deduplication & Explicit Duplicate ACK:** Workstations maintain a sliding-window message registry (`_seenMessageIds` and 900ms deduplication). When a rapid duplicate scan is suppressed from re-entering billing/inventory carts, an explicit duplicate ACK (`isDuplicate: true`) is transmitted to mobile, providing immediate user feedback.

### 13.3 Camera Accuracy & Symbology Verification Engine (`BarcodeAccuracyVerifier`)
Resolves historical issues with mobile camera recognition (glitched frames, dropped bits, or truncated reads):
- **EAN-13 Check Digit Verification:** Validates Modulo 10 check digit; drops corrupt camera frames before transmission and notifies user with a visual warning.
- **UPC-A Check Digit Verification:** Validates Modulo 10 check digit; drops corrupt frames with visible alert.
- **Code 128 Verification & Checksum Clarification:** Mobile camera decoding engines (e.g. Google ML Kit and ZXing) automatically validate and strip the mandatory Modulo 103 checksum character internally before exposing `rawValue`. Therefore, `BarcodeAccuracyVerifier` checks that all decoded characters reside within standard printable ASCII bounds (32–126), validating data encoding integrity rather than low-level symbology parity.
- **String Preservation & End-to-End Traceability:** Barcodes with leading zeros (e.g. `0012345678905`) are preserved strictly as strings throughout transmission (`rawCode` -> `transmittedCode` -> `receivedCode`), decoding, and catalog lookup without numeric conversion. Mobile verifies `ack.receivedCode == item.rawCode`.
- **Immediate Visible Feedback on Invalid Scans:** Viewfinders in `ThqMobileWirelessScannerScreen` and `ThqSmartScannerView` display transient warning frames and alert banners on rejected frames rather than silently discarding them.

### 13.4 Pluggable Transport Layer
- `WirelessScannerTransport`: Abstract transport interface defining incoming scans, incoming ACKs, paired device stream, connection state, and hosting/joining lifecycle.
- `SupabaseRealtimeScannerTransport`: Production cloud relay using authenticated Supabase Realtime Private Broadcast Channels (`thq_scan_<tenant>_<session>`). Sub-millisecond latency, zero database writes, requires no firewall holes or open local ports, and works across separate Wi-Fi networks and cellular (4G/5G).
- `MockWirelessScannerTransport`: In-memory transport for lightning-fast, hermetic unit and widget testing with simulated latency, signed auto-ACKs, and network disruption testing.

### 13.5 Desktop Host Integrations
- **THQ POS Desktop (`apps/pos_app`):**
  - Header icon with live status indicator (Grey = Unpaired, Green = Phone Connected).
  - Tapping opens `ThqWirelessScannerDialog` displaying vector QR, countdown timer, and paired device metadata.
  - Incoming wireless scans automatically trigger `_handleScanCode(code, source: ScannerSource.remotePhone)`.
  - Resolved items are added to the active cart (or quantity incremented) and a bi-directional HMAC-signed ACK with the resolved product name and echoed `receivedCode` is transmitted back to the phone.
- **THQ Client Desktop (`apps/client_app`):**
  - Integrated into `SmartInventoryWorkspaceScreen` header bar with connection badge.
  - Incoming scans feed directly into active inventory workflows (Scan Center, Product Lookup, Bulk Staging, Stock Count, Purchase Receiving).

### 13.6 Mobile Scanning Interface (`ThqMobileWirelessScannerScreen`)
- Embedded in `packages/thq_ui` and accessible across `client_mobile` and `mobile_pos`.
- Dual operational modes:
  - **Pairing Mode:** Viewfinder scans desktop QR code, decodes `thq_wireless_pair` payload, verifies tenant match, single-use validity, and joins session.
  - **Active Scan Mode:** Continuous camera scanning with `BarcodeAccuracyVerifier`, torch toggle, zoom scale controls, camera flip, single vs. continuous toggle, and manual barcode entry fallback.
- Live transmission status banner (Pending / Delivered / Failed).
- 5-second ACK timeout: scans that do not receive a cryptographically signed desktop acknowledgement within 5 seconds transition to failed.
- Floating Desktop Product ACK Banner displaying the product name confirmed by the desktop workstation or duplicate suppression notice.
- Expandable session scan history drawer.

---

## 14. Phase 12: External Product Intelligence & GS1 Barcode Lookup Architecture

### 14.1 Purpose & Scope
The External Product Intelligence system empowers operators to rapidly identify unknown products, discover matching candidates from external catalogues, and enrich existing THQ product records with accurate titles, brands, categories, descriptions, images, and technical specifications.

### 14.2 Core Principles & Architectural Guarantees
1. **Zero Automatic Overwriting:**
   External suggestions are **NEVER** applied automatically to existing catalogue records. Operators are presented with an interactive side-by-side comparison highlighting discrepancies and must explicitly approve changes on a field-by-field basis.
2. **Strict Protection of Ledger & Inventory Invariants:**
   External intelligence cannot alter operational accounting and inventory fields:
   - Selling Price (protected)
   - Purchase / Cost Price (protected)
   - List Price (protected)
   - Tax Rate (protected)
   - Stock Quantity / Inventory Balances (protected)
   - Reorder Levels (protected)
   These fields are permanently locked with visual protected badges in `ThqCatalogueComparisonView`.
3. **Format Validation vs. Official GS1 Verification:**
   - *Mathematical Check Digit Validation:* `BarcodeAccuracyVerifier` checks Modulo 10 check digits locally for EAN-13, UPC-A, and GTIN-14, ensuring camera reads are mathematically valid.
   - *GS1 Registry Platform (GRP) Licencing:* Format validity does not imply brand ownership. Live validation against GS1 GRP endpoints requires active GS1 Member Organization subscription credentials. When unconfigured, `Gs1RegistryProvider` accurately documents this requirement and returns an informative `unauthorized` status rather than claiming unverified access.
4. **Resilience & Non-Blocking POS Guarantee:**
   External lookups enforce a strict 8-second timeout, run asynchronously, and never block POS sales, offline billing, or core ERP workflows. If external services fail or are rate limited (HTTP 429), THQ operations continue uninterrupted.
5. **Audit Provenance Logging:**
   Approved enrichments are permanently recorded in `product_variants.custom_fields['external_provenance']`, capturing provider ID, source name, external barcode, approved field list, confidence score, user ID, and timestamp with zero database schema migrations.

### 14.3 Shared Architecture & Components

#### Shared Engine Models (`packages/erp_core/lib/src/intelligence/external_product_models.dart`)
- `ExternalLookupStatus`: `success`, `noMatch`, `rateLimited`, `providerError`, `offline`, `unauthorized`.
- `ExternalProductCandidate`: Discovered candidate with exact barcode preservation (leading zero fidelity), symbology, title, brand, manufacturer, category, description, public image URL, key-value specifications, match confidence (0.0–1.0), GS1 verification flag, and raw JSON payload.
- `ExternalLookupRequest`: Structured query parameters supporting exact barcode lookup or multi-attribute text search.
- `CatalogueComparisonField`: Represents compared field with current THQ value, external suggestion, conflict flag (`isConflict`), user acceptance toggle (`isAccepted`), and protected invariant flag (`isProtected`).
- `CatalogueComparison`: Encapsulates side-by-side comparison, conflict detection, field approval states, payload extraction (`buildEnrichmentPayload()`), and audit provenance generation (`buildAuditProvenance(...)`).

#### HTTP Client Abstraction (`packages/erp_core/lib/src/intelligence/product_intelligence_http_client.dart`)
- `ProductIntelligenceHttpClient`: Clean interface abstracting HTTP operations.
- `DefaultProductIntelligenceHttpClient`: Production HTTP client with standard `User-Agent: THQ-ERP/1.0`, 8-second timeout enforcement, and HTTP status code translation (404 -> noMatch, 429 -> rateLimited, 401/403 -> unauthorized).
- `MockProductIntelligenceHttpClient`: Hermetic mock client for deterministic unit testing without outbound network calls.

#### Provider Implementations
- **`OpenProductFactsProvider` (`open_product_facts_provider.dart`):** Queries Open Food Facts (`https://world.openfoodfacts.org/api/v2/product/{barcode}.json`) under Open Database License (ODbL) terms. Parses product names, brands, categories, manufacturers, packaging, and net quantities.
- **`Gs1RegistryProvider` (`gs1_registry_provider.dart`):** Validates GTIN format and check digit locally. When configured with GS1 Member API credentials, queries GS1 GRP endpoints (`https://api.gs1.org/grp/v3/products/{gtin14}`). If unconfigured, cleanly returns `unauthorized` with an educational message regarding GS1 subscription requirements.
- **`MockExternalProductProvider` (`mock_external_product_provider.dart`):** In-memory catalogue pre-seeded with real-world building materials (UltraTech Cement), groceries (Bru Instant Coffee), electrical components (Havells Socket), and stationery (Classmate Notebook). Supports keyword search and simulated network delays.

#### Central Orchestrator Engine (`ExternalProductIntelligenceEngine`)
- Multi-provider parallel dispatch.
- In-flight request deduplication (coalesces rapid concurrent queries for the same barcode into a single shared Future).
- 15-minute in-memory cache to respect provider rate limits and ensure snappy local UX.
- Direct cache eviction (`clearCache()`).

#### Reusable UI (`packages/thq_ui/lib/src/intelligence/thq_catalogue_comparison_view.dart`)
- `ThqCatalogueComparisonView`:
  - Discovered product header card with thumbnail image, source badge, and match confidence pill.
  - Conflict warning banner and protected accounting invariant alert.
  - Field selection toolbar ("Accept Non-Conflicting", "Select All", "Clear All").
  - Side-by-side comparison table (Field, Current Value, External Suggestion, Conflict Badge, Accept Toggle / Lock).
  - Additional specifications chip container.
  - Responsive action footer with "Enrich Product", "Create As New Draft", and "Discard" actions.

#### Workspace Integration (`apps/client_app`)
- **`SmartProductIntelligenceTab` (`apps/client_app/lib/screens/smart_inventory/tabs/smart_product_intelligence_tab.dart`):**
  - Search bar with hardware wedge barcode scanner (`ThqBarcodeWedgeListener`) and wireless phone scanner (`WirelessScannerCoordinator`) integration.
  - Provider filter dropdown ("All Providers", "Open Food Facts", "Verified by GS1", "Mock Catalogue").
  - Quick action chips for sample products.
  - Multi-candidate selector list and embedded `ThqCatalogueComparisonView`.
  - Confirmation and execution using `InventoryService.updateProduct` (preserving protected fields) and `InventoryService.createProduct`.
  - Provenance audit recording in `product_variants.custom_fields`.
- **`SmartInventoryWorkspaceScreen`:**
  - Expanded to 10 tabs (TabController length 10).
  - Tab 10: "Product Intelligence" (`Icons.auto_awesome`).
  - Added "Product Intelligence" quick workspace card to `SmartInventoryOverviewTab`.

---

## Phase 13: Permissions, Security, Offline & Synchronization Hardening

### 1. Supabase Realtime Authorization
- **Virtual Table Authorization:** Enabled Row Level Security (RLS) on `realtime.messages` with SELECT and INSERT policies for `authenticated` role.
- **Topic Gatekeeper (`private.erp_realtime_topic_authorized`):** Inspects incoming broadcast and presence topics:
  - Wireless scanner topics: `thq_scan_<tenantIdHex>_<sessionId>` and `thq_scan_<uuid>_<sessionId>`.
  - Tenant broadcast topics: `thq_tenant_<uuid>`.
  - POS terminal topics: `thq_pos_<uuid>`.
- Converts 32-character hex tenant representations to UUID and validates active membership via `private.erp_user_has_tenant_access(v_tenant_id)`. Unauthenticated users or users not belonging to the tenant are rejected immediately at the Supabase Realtime layer.

### 2. Role & Permission Enforcement
- **Cost Price Protection:**
  - Server-side masking in `public.inventory_get_product_detail` and `public.pos_offline_product_cache_v486` (and by extension `public.mobile_pos_product_cache_v520`). If requesting user is not owner and lacks `inventory.view_cost` and `inventory.manage`, `cost_price` and `purchase_cost` are stripped or set to `null`.
  - Client-side masking across Client Desktop (`ProductDetailScreen`, `InventoryProductsScreen`), POS Desktop (`ProductDetailScreen`), and comparison views (`CatalogueComparison`). Unauthorized users see `• • • • (Restricted)`.
- **Catalogue & Action Guardrails:**
  - `SmartProductIntelligenceTab`: Gated `_applyEnrichment` with `inventory.manage` permission check. Disabled button with tooltip for unauthorized users.
  - `SmartStockCountTab`: Gated `_executePostStockCount` with `_canApproveAndPost` (`inventory.stock_count` or `inventory.manage`).
  - `SmartPurchaseReceivingTab`: Gated `_executePostReceipt` with `_canReceiveAndPost` (`purchases.receive`, `purchases.manage`, or `inventory.manage`).

### 3. Tenant & Location Isolation
- **Scanner Session Hardening:** Added explicit `currentTenantId` and `currentLocationId` checks in `WirelessScannerTransport` and `WirelessScannerCoordinator`. Rejects pairing attempts when QR payload does not match active session tenant and assigned location.
- **Mobile Scanner Screen:** Added `locationId` property to `ThqMobileWirelessScannerScreen` with upfront location validation before initiating WebSocket handshake.

### 4. Offline & Synchronization Hardening
- **Crash Recovery & Orphan Prevention:** Added `'syncing'` status to offline sync queue queries in `OfflinePosSyncService` (Desktop POS) and `MobilePosSyncService` (Mobile POS). Prevents transactions interrupted by an unexpected application kill or network failure from being permanently orphaned in SQLite/drift.
- **Idempotency Guarantee:** Permanent UUID `p_request_id` generated on client side is preserved through all retry attempts, guaranteeing that repeated uploads never generate duplicate sales, vouchers, or inventory adjustments on the server.

---

## Phase 14: Complete UI/UX Refinement & Smart Inventory Control Centre

### 1. Smart Inventory Control Centre Architecture
- **Control Centre Overview (`SmartInventoryOverviewTab`):**
  - Transformed from a basic session scanning metric list into an Executive Inventory Control Centre.
  - Live Catalogue & Stock Health KPIs:
    - Real-time Product & Variant counts (Active vs Inactive).
    - Low-stock SKU warning count with direct jump link to Catalogue Lookup.
    - Out-of-stock SKU alert with critical indicator.
    - Total on-hand stock units across the active store/warehouse.
    - Inventory Valuation calculation (`costPrice * stockQuantity`), strictly masked with `• • • • (Restricted)` when the user lacks `inventory.view_cost`, `inventory.manage`, or owner role.
  - Operations Pipeline:
    - Active monitoring of open Purchase Orders awaiting inward goods receipt.
    - Historical stock count audits count with quick navigation.
    - Missing primary barcode counter alerting operators to un-barcoded SKUs requiring label printing.
  - Scanning & Session Metrics:
    - Retains live session counts (Session Scans, Identified Products, Unresolved Scans, Bulk Session state) in a dedicated Hardware & Scan Activity row.
  - Action Launchers:
    - 8 quick workspace cards linking directly to Scan Center, Product Lookup, Bulk Scanning, Product Import, Barcode Studio, Stock Count, Purchase Receiving, and Product Intelligence.
  - On-Demand Refresh:
    - Integrated refresh button in the Control Centre header allowing operators to reload live metrics on demand.

### 2. Workspace Navigation & Information Architecture
- **Information Architecture Groupings (`SmartInventoryWorkspaceScreen`):**
  - Updated header subtitle: "Complete inventory control centre: catalogue, audits, goods receiving, barcode printing & scanning".
  - Maintained complete backward compatibility with all 10 tab indices (0: Overview, 1: Scan Center, 2: Product Lookup, 3: Bulk Scanning, 4: Scan History, 5: Product Import, 6: Barcode Studio, 7: Stock Count, 8: Purchase Receiving, 9: Product Intelligence).
  - Responsive header controls adapting gracefully between full desktop and compact displays.

### 3. Product Catalogue & Lookup Improvements (`SmartInventoryProductLookupTab`)
- Multi-identifier search with debounced typing across Name, SKU, Barcode, QR, and Part Number.
- Responsive filter chips (`All Identifiers`, `Has Barcode`, `Has SKU`, `Has Mfg Code`, `All Stock`, `In Stock`, `Low / Out of Stock`) using `Wrap` layout to eliminate overflow on compact screens.
- Enhanced modal breakdown with registered identifiers and direct "View Full Product" action opening `ProductDetailScreen` for authorized users.
- Role-based cost price masking preserved in both table and detail modal.







