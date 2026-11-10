# THQ ERP — Smart Inventory Implementation Map

**Document Version:** 1.0.0  
**Phase:** Phase 0 — Complete Existing Project Inspection & Architecture Blueprint  
**Date:** 2026-11-10  
**Project:** THQ ERP (`thariqmanchara321/THQ-ERP`)  
**Target Architecture:** Windows Desktop (Client & POS), Web (Admin), Android/iOS (Mobile POS & Client Mobile), PostgreSQL 17 (Supabase `yguzrxcdvyimjrfvtcvp`)  
**Active Development Branch:** `main` (synchronized with `feat/gst-nongst-final-architecture` at v8.2.2 Build 19)

---

## 1. Executive Summary & Existing Architecture

THQ ERP is an enterprise multi-tenant ERP and POS ecosystem developed in Flutter and Dart, backed by Supabase (PostgreSQL 17) and local SQLite storage engines for resilient offline-first operations. The system currently powers multi-store businesses with strict tenant isolation, hardware device activation, double-entry accounting, and authoritative GST/Non-GST compliance.

The goal of this project is to integrate a unified **Smart Inventory** system into the existing codebase without creating a secondary application or a duplicate product catalog. Smart Inventory operates as a shared capability accessible across all 5 applications in the THQ suite:
1. **THQ Business Client (`apps/client_app`):** Windows desktop / Web enterprise back-office management.
2. **THQ POS Terminal (`apps/pos_app`):** Windows desktop high-throughput retail & quick-serve billing.
3. **THQ Mobile POS (`apps/mobile_pos`):** Android/iOS handheld floor terminal with offline sale queue.
4. **THQ Client Mobile (`apps/client_mobile`):** Android/iOS executive and warehouse mobile companion.
5. **THQ Admin Panel (`apps/admin_panel`):** Platform superadmin and multi-tenant administration.

---

## 2. Existing Components & Reusability Audit

### 2.1 Reusable Client Services & Screens

| Component | Path | Status | Reuse Strategy |
| :--- | :--- | :--- | :--- |
| **`BarcodeService`** | `apps/client_app/lib/services/barcode_service.dart` | Working (v4.8.2) | Retain for backward compatibility; expand via `ProductIdentificationEngine`. |
| **`ProductIdentificationService`** | `apps/client_app/lib/services/product_identification_service.dart`<br>`apps/pos_app/lib/services/product_identification_service.dart` | Working (v4.8.2) | Contains complete identifier CRUD (`list`, `save`, `generate`, `archive`, `lookup`, `labelTemplates`). Refactor into shared `packages/erp_core`. |
| **`BarcodeWorkbenchScreen`** | `apps/client_app/lib/screens/barcode_workbench_screen.dart` | Working (v4.8.2) | Legacy desktop workbench. Integrate as a tab within the new Client Smart Inventory Workspace. |
| **`ProductIdentifiersScreen`** | `apps/client_app/lib/screens/product_identifiers_screen.dart` | Working (v4.8.2) | 542-line screen for managing multiple barcodes, QR codes, supplier codes, and printing labels. Direct reuse inside Barcode Studio. |
| **`LabelPrintingService`** | `apps/client_app/lib/services/label_printing_service.dart` | Working (v4.8.2) | Generates A4 and thermal PDF labels with `pw.BarcodeWidget` (Code 128 & QR). Direct reuse in Barcode Studio. |
| **`InventoryService`** | `apps/client_app/lib/services/inventory_service.dart`<br>`apps/pos_app/lib/services/inventory_service.dart` | Working (v4.8.3, v6.3.5) | Manages product catalog, stock adjustments (`inventory_adjust_stock_v483`), stock counts (`inventory_stock_count_post_v483`), and movement ledgers. |
| **`BulkImportService`** | `apps/client_app/lib/services/bulk_import_service.dart`<br>`apps/pos_app/lib/services/bulk_import_service.dart` | Working (v4.5, v4.9) | Handles bulk product imports via `inventory_bulk_create_products_v45`. Refactor to support Excel/CSV preview and deduplication. |
| **`StockTransferService`** | `apps/client_app/lib/services/stock_transfer_service.dart` | Working (v4.8.5) | Inter-store stock transfer workflows and warehouse inventory tracking. |
| **`BarcodeScannerScreen`** | `apps/mobile_pos/lib/screens/barcode_scanner_screen.dart` | Working (v4.8.8) | Single-scan camera screen using `mobile_scanner: 7.4.0`. Enhance into a multi-mode scanner (continuous, torch, zoom, preview). |
| **`ProductIdentifier` Model** | `packages/erp_core/lib/src/pricing.dart` | Working (v4.8.2) | Core entity model representing secondary barcodes, QR, and manufacturer codes. |
| **`OfflinePosService`** | `apps/pos_app/lib/services/offline_pos_service.dart` | Working (v4.8.6) | Direct `sqlite3` SQLite database caching products (`offline_products`), customers, serials, and invoice queues. |
| **`MobilePosLocalStore`** | `apps/mobile_pos/lib/services/mobile_pos_local_store.dart` | Working (v4.8.8) | `sqflite` SQLite storage caching offline catalog, serials, and holding carts. |

### 2.2 Database Entities & Functions (PostgreSQL 17 / Supabase)

| Object Name | Type | Migration Source | Purpose & Status |
| :--- | :--- | :--- | :--- |
| **`product_identifiers_v482`** | Table | `131_v482_product_identification.sql` | Master registry of variant identifiers (barcode, QR, manufacturer, supplier, internal, alternate SKU). Has RLS enabled. |
| **`product_identifier_sequences_v482`** | Table | `131_v482_product_identification.sql` | Tenant-level sequences for generating valid EAN-13 barcodes and formatted QR codes. |
| **`inventory_product_lookup_v482`** | RPC Function | `131_v482_product_identification.sql` | Core lookup routine. Matches SKU, active identifiers, or legacy barcodes; returns enriched product JSON. |
| **`product_identifiers_v482_list`** | RPC Function | `131_v482_product_identification.sql` | Returns all active/inactive identifiers for a variant. |
| **`product_identifier_save_v482`** | RPC Function | `131_v482_product_identification.sql` | Upserts identifier with cross-product SKU and identifier collision guards. |
| **`product_identifier_generate_v482`** | RPC Function | `131_v482_product_identification.sql` | Generates unique internal EAN-13 (prefix `28` + checksum) or QR (`THQ:PRODUCT:...`). |
| **`product_identifier_archive_v482`** | RPC Function | `131_v482_product_identification.sql` | Safely archives an identifier without breaking audit history. |
| **`stock_counts` & `stock_count_items`** | Tables | `032_v4_stock_transfers_counts.sql` | Session header and item lines for physical inventory counting and audit reconciliations. |
| **`inventory_stock_count_snapshot_v485`** | RPC Function | `151_v485_stock_count_trace_reconciliation.sql` | Fetches store physical stock snapshot for counting sessions with tracking details. |
| **`inventory_stock_count_post_v485`** | RPC Function | `151_v485_stock_count_trace_reconciliation.sql` | Atomically reconciles counted stock against system balances, posting stock movements. |
| **`stock_counts_list_v485`** | RPC Function | `152_v485_reconciliation_api_contract.sql` | Paged history of stock counts with variance totals. |
| **`stock_count_detail_v485`** | RPC Function | `152_v485_reconciliation_api_contract.sql` | Returns full details of a count session including item lines and variance. |
| **`inventory_stock_reconciliation_v485`**| RPC Function | `152_v485_reconciliation_api_contract.sql` | Compares company-wide vs location stock balances and flags tracking discrepancies. |
| **`inventory_bulk_create_products_v45`**| RPC Function | `085_v45_invoice_bulk_import.sql` | Batch creates products and assigns opening balances. |
| **`thq_sync_events_v480`** | Table | `116_v480_sync_contract.sql` | Monotonically incrementing sync event log for client synchronization. |

---

## 3. Gap Analysis & Missing Capabilities

1. **Shared Scanning Engine**:
   - `apps/mobile_pos` has a basic 84-line scanner that dismisses immediately upon scanning a single barcode.
   - `apps/client_app` and `apps/pos_app` rely purely on focus on a specific `TextField` for keyboard-wedge (USB/Bluetooth) scanners. If the user clicks elsewhere, scanner keystrokes are lost or trigger unintentional UI shortcuts.
   - `apps/client_mobile` has zero scanning integration.
   - No cross-platform abstraction exists to coordinate camera, USB HID, and Bluetooth scanner inputs uniformly.

2. **Unified Product Identification Engine**:
   - Product lookup logic is duplicated between client applications.
   - When a barcode matches multiple products (e.g. multi-pack vs single, or supplier code collision), the current POS simply fails or takes the first match without giving the user a choice.
   - No fallback to external product data (Open Food Facts, UPC, GS1) when a scanned product is unknown.

3. **Client Smart Inventory Workspace**:
   - There is no central Smart Inventory Workspace in `apps/client_app`.
   - The 9 required business operational sections (Dashboard, Scan Center, Product Lookup, Bulk Scanner, Smart Import, Stock Counting, Purchase Receiving, Barcode Studio, Scan History) are fragmented or missing.

4. **Desktop POS Scanning Experience**:
   - USB/Bluetooth scanning works only when the search field is explicitly focused.
   - Repeated scanning increments quantity only if already in the cart, but does not provide immediate audible/visual feedback for successful vs failed scans.
   - No Phone-to-PC scan input capability.

5. **Mobile POS & Client Mobile Scanning**:
   - Mobile POS cannot scan continuously without repeatedly opening the scanner dialog.
   - No torch/zoom controls, no product preview card prior to adding to cart, and no Phone-to-PC terminal transmission mode.
   - Client Mobile has an inventory tab that only displays a read-only list.

6. **Purchase Receiving by Barcode**:
   - Purchase orders cannot be verified by scanning delivery shipments item-by-item against purchase order lines.

7. **External Product Information**:
   - No external catalog integration exists. Businesses creating products for recognized barcodes must type in details manually.

---

## 4. Architectural Design & Implementation Strategy

```
                                  +-----------------------------------------------+
                                  |              THQ SMART INVENTORY              |
                                  |            (Shared Core Capability)           |
                                  +-----------------------------------------------+
                                                          |
                       +----------------------------------+----------------------------------+
                       |                                                                     |
         +----------------------------+                                        +----------------------------+
         |    Shared Core Engine      |                                        |    Shared UI Components    |
         |  (packages/erp_core)       |                                        |     (packages/thq_ui)      |
         +----------------------------+                                        +----------------------------+
         | • SmartScannerController   |                                        | • ThqSmartScannerView      |
         | • ProductIdentificationEng |                                        | • ThqBarcodeWedgeListener  |
         | • ExternalProductService   |                                        | • ThqProductLookupDialog   |
         | • SmartImportEngine        |                                        | • ThqMultipleMatchDialog   |
         | • ScanSession & Item Model |                                        | • ThqBarcodeLabelWidget    |
         +----------------------------+                                        +----------------------------+
                       |                                                                     |
        +--------------+---------------+-----------------------+-----------------------------+
        |                              |                       |                             |
+----------------+             +----------------+      +----------------+            +----------------+
| THQ Business   |             | THQ POS        |      | THQ Mobile POS |            | THQ Client     |
| (apps/client)  |             | (apps/pos_app) |      | (mobile_pos)   |            | Mobile         |
+----------------+             +----------------+      +----------------+            +----------------+
| • 9-Tab Smart  |             | • Wedge Hook   |      | • Continuous   |            | • Inventory    |
|   Workspace    |             | • Live Cart    |      |   Mobile Scan  |            |   Scanner      |
| • Bulk Import  |             |   Increment    |      | • Phone-to-PC  |            | • Quick Stock  |
| • Count/Receive|             | • Phone-to-PC  |      |   Remote Mode  |            |   Count        |
| • Label Studio |             |   Receiver     |      | • Offline Sync |            | • Identifier   |
+----------------+             +----------------+      +----------------+            |   Assignment   |
                                                                                     +----------------+
```

---

## 5. Phase-by-Phase Execution Plan

### Phase 1: Shared Scanning Engine
- **Location:** `packages/erp_core/lib/src/smart_inventory/` and `packages/thq_ui/lib/src/scanner/`
- **Features:**
  - `SmartScannerController`: Universal scanning controller managing state, pause/resume, single vs continuous mode, torch, zoom, debounce, and scan history.
  - `ThqBarcodeWedgeListener`: Global keyboard event interceptor for USB and Bluetooth wedge scanners on desktop and tablet environments. Detects rapid keystroke intervals (< 40ms) followed by Enter/Tab, preventing scan input loss when input fields are unfocused.
  - `ThqSmartScannerView`: Mobile camera scanner widget wrapping `mobile_scanner` with overlay frame, flashlight toggle, zoom slider, continuous scan throttle, and haptic/auditory feedback.
  - Support formats: EAN-8, EAN-13, UPC-A, UPC-E, Code 128, Code 39, QR.

### Phase 2: Product Identification Engine
- **Location:** `packages/erp_core/lib/src/smart_inventory/product_identification_engine.dart`
- **Resolution Pipeline:**
  1. Input validation & sanitization (trim, character check).
  2. Barcode type detection (EAN-13 check digit validation, QR structure).
  3. Tenant & Store context enforcement.
  4. Local cache & local SQLite lookup (`offline_products`, `products`).
  5. Online Supabase lookup (`inventory_product_lookup_v482`).
  6. Multi-match resolution (returns `IdentificationOutcome.multipleMatches` with candidate list).
  7. External catalog fallback (if online and enabled).
- **Outcomes:** `exactMatch`, `multipleMatches`, `notFound`, `offlineCachedMatch`.

### Phase 3: Client Smart Inventory Workspace
- **Location:** `apps/client_app/lib/screens/smart_inventory/`
- **Sections:**
  1. **Dashboard:** Key metrics (total tagged products, missing barcode count, active scan sessions, recent imports).
  2. **Scan Center:** Camera / USB / BT scanning with instant product detail card and identifier assignment.
  3. **Product Lookup:** Omnichannel search (Barcode, QR, SKU, Name, Manufacturer, Supplier code) with store stock breakdown.
  4. **Bulk Scanner:** Multi-item scanning session table with real-time tally, quantity adjust, and batch stock adjustment/transfer commit.
  5. **Smart Import:** Excel (.xlsx) and CSV reader with column auto-mapping, deduplication, conflict preview, and atomic batch import.
  6. **Stock Counting:** Live physical count session against store inventory snapshot, displaying variance and posting reconciliation movements.
  7. **Purchase Receiving:** Barcode-based goods receiving matched against open Purchase Orders.
  8. **Barcode Studio:** Barcode and QR generator, custom template selection (thermal/A4), and batch PDF label printing.
  9. **Scan History:** Audit trail of all scanning operations and device events.

### Phase 4: Desktop POS Integration
- **Location:** `apps/pos_app/lib/screens/pos_screen.dart`
- **Enhancements:**
  - Integrate `ThqBarcodeWedgeListener` at the screen root so USB/BT scanners immediately route to `_handleScannedCode` even when search is not focused.
  - Repeated scans of the same barcode increment the existing line item quantity smoothly.
  - Multi-match dialog when a barcode matches more than one variant/product.
  - Phone-to-PC scan receiver (listen to real-time paired mobile scanner events).

### Phase 5: Mobile POS Integration
- **Location:** `apps/mobile_pos/lib/screens/`
- **Enhancements:**
  - Modernize `BarcodeScannerScreen` with continuous scan mode, torch toggle, zoom, and live item counter.
  - Add Phone-to-PC pairing mode: Mobile terminal connects to an active desktop POS terminal via Supabase Realtime channel authenticated by device activation tokens, broadcasting scanned barcodes directly to the desktop cart.
  - Preserve all existing offline sale queueing and FEFO logic.

### Phase 6: Client Mobile Integration
- **Location:** `apps/client_mobile/lib/screens/workspace/`
- **Enhancements:**
  - Add `mobile_scanner: 7.4.0` to `apps/client_mobile/pubspec.yaml`.
  - Add camera barcode scanner action to `MobileInventoryWorkspace`.
  - Enable quick stock count scan sheet and identifier assignment on the go.

### Phase 7: Stock Counting & Purchase Receiving
- **Location:** `apps/client_app/lib/screens/smart_inventory/tabs/`
- **Implementation:**
  - Complete integration with existing backend functions `inventory_stock_count_snapshot_v485` and `inventory_stock_count_post_v485`.
  - Real-time comparison between recorded system quantity and physical count.
  - PO Receiving: Load open purchase order lines, scan incoming packages, verify quantities against expected order lines, highlight discrepancies, and complete purchase receipts.

### Phase 8: Supabase Database Additions
- **Location:** `supabase/migrations/20261110140000_smart_inventory_foundation_v830.sql`
- **Additive Tables:**
  - `inventory_scan_sessions`: Tracks bulk scanning sessions, stock counts, and receiving sessions across devices.
  - `inventory_import_batches`: Records Excel/CSV import history, file metadata, error logs, and imported record counts.
  - `inventory_import_rows`: Staging and audit rows for import batches.
  - All tables enforce strict multi-tenant isolation via `tenant_id` foreign keys and PostgreSQL Row Level Security (RLS).

### Phase 9: External Product Information
- **Location:** `packages/erp_core/lib/src/smart_inventory/external_product_lookup_service.dart`
- **Implementation:**
  - Clean abstraction `ExternalProductLookupService` with swappable providers.
  - Primary provider: Open Food Facts / Open Product Data REST API (no proprietary keys required, completely safe).
  - Caches results locally to avoid redundant external network requests.
  - Never overwrites business selling prices or stock balances.

---

## 6. Dependency & Package Changes

| App / Package | Dependency | Current Version | Planned Change | Justification |
| :--- | :--- | :--- | :--- | :--- |
| **`packages/erp_core`** | None | - | None | Pure Dart business logic and models. |
| **`packages/thq_ui`** | `mobile_scanner` | None | `mobile_scanner: 7.4.0` | Shared camera scanner widget used by mobile applications. |
| **`apps/client_mobile`** | `mobile_scanner` | None | `mobile_scanner: 7.4.0` | Mobile camera scanning parity with `mobile_pos`. |
| **`apps/client_app`** | `excel`, `printing`, `pdf` | Installed | None | Already has `excel: 4.0.6`, `printing: 5.14.3`, `pdf: 3.12.0`. |
| **`apps/pos_app`** | `excel`, `printing`, `pdf` | Installed | None | Already has all required file/print libraries. |
| **`apps/mobile_pos`** | `mobile_scanner`, `sqflite` | 7.4.0, 2.4.3 | None | Already has required scanner and database libraries. |

---

## 7. Risks & Verification Strategy

1. **Risk: Keystroke Interception in Desktop POS**
   - *Mitigation:* The keyboard wedge listener will only treat input as a barcode scan if keystrokes arrive with inter-key intervals under 40 milliseconds and end with Enter/Tab, ensuring standard user keyboard typing in text fields is not hijacked.
2. **Risk: Inventory Balance Discrepancy**
   - *Mitigation:* All inventory stock changes MUST route through `inventory_adjust_stock_v483` or `inventory_stock_count_post_v485`. Direct table mutations are strictly prohibited and prevented by PostgreSQL RLS.
3. **Risk: Offline Data Loss or Duplicate Sales**
   - *Mitigation:* Retain the proven `requestId` UUID lease pattern and local SQLite reservation tables (`thq_pos_offline_v486.sqlite` and `thq_mobile_pos_v488.sqlite`).
4. **Risk: External Data Pollution**
   - *Mitigation:* External catalog lookups only pre-fill product metadata (title, brand, category, description, image URL) during product creation. Existing internal prices and stock are never overridden.
