# THQ ERP — Smart Inventory Test Plan

**Document Version:** 1.0.0  
**Phase:** Phase 0 Quality Assurance & Test Strategy  
**Date:** 2026-11-10  

---

## 1. Test Architecture & Scope

This test plan specifies the verification requirements for all Smart Inventory capabilities across unit, widget, service, and regression boundaries.

### Test Matrix

| Layer | Component | Test Target | Pass Criteria |
| :--- | :--- | :--- | :--- |
| **Unit** | `SmartScannerController` | `packages/erp_core/test/` | Single scan vs continuous mode, debounce, pause/resume, scan history accumulation. |
| **Unit** | `ProductIdentificationEngine` | `packages/erp_core/test/` | Exact SKU match, active identifier match, multiple matches resolution, unknown code fallback. |
| **Unit** | `ExternalProductLookupService` | `packages/erp_core/test/` | Mock response parsing, schema validation, non-destructive pricing guard, timeout fallback. |
| **Unit** | `SmartImportEngine` | `packages/erp_core/test/` | CSV & XLSX parsing, column auto-mapping, header normalization, duplicate barcode detection, invalid row quarantine. |
| **Widget** | `ThqBarcodeWedgeListener` | `packages/thq_ui/test/` | Rapid keystroke (<40ms) detection vs human typing, Enter key dispatch, unfocused window event capture. |
| **Widget** | `SmartInventoryWorkspaceScreen` | `apps/client_app/test/` | 9-tab switching, dense data rendering, search input, loading/error states, desktop responsiveness. |
| **Integration** | POS Scanning Checkout | `apps/pos_app/test/` | Scanned item cart insertion, repeated scan quantity increment, stock limits check, discount retention. |
| **Integration** | Mobile POS Offline Scanning | `apps/mobile_pos/test/` | Continuous scan queueing, offline product lookup, SQLite reservation integrity, sync event creation. |
| **Integration** | Stock Counting Reconciliation | `apps/client_app/test/` | Physical count entry, variance calculation against system snapshot, atomic ledger posting. |
| **Database** | Supabase Migrations & RLS | `backend/tests/` | RLS isolation across tenants, rejection of unauthorized cross-tenant scans, idempotent migration execution. |

---

## 2. Regression Safety Rules

1. Existing sales and purchase workflows MUST NOT experience altered calculations, missing tax columns, or broken invoice printing.
2. Existing POS keyboard shortcuts (F1-F12, Enter, Escape) MUST remain fully operational and not collide with the barcode wedge listener.
3. Database migrations MUST be additive, safe, and backwards-compatible with active client versions (v8.1.0 through v8.2.2).

---

## 3. Phase 1 Verification Results (2026-11-10)

| Suite | Location | Tests Total | Tests Passed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `packages/erp_core` (All Tests) | `packages/erp_core/test/` | 63 | 63 | **PASSED** (Baseline 49 + 14 New) |
| `SmartScannerController` Unit Suite | `packages/erp_core/test/smart_scanner_controller_test.dart` | 14 | 14 | **PASSED** |
| `packages/thq_ui` (All Tests) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** (Baseline 65 + 8 New) |
| `ThqBarcodeWedgeListener` Widget Suite | `packages/thq_ui/test/thq_barcode_wedge_listener_test.dart` | 6 | 6 | **PASSED** |
| `ThqSmartScannerView` Widget Suite | `packages/thq_ui/test/thq_smart_scanner_view_test.dart` | 2 | 2 | **PASSED** |
| POS App Regression Check | `apps/pos_app/test/widget_test.dart` | 1 | 1 | **PASSED** |

### Verified Coverage Highlights:
- **`SmartScannerController`**:
  1. Default initialization (Idle -> Ready on `startScanning()`).
  2. Single scan mode accepts initial scan then transitions cleanly to Paused.
  3. Continuous scan mode accepts distinct sequential barcodes.
  4. Duplicate suppression enforces millisecond debounce threshold (burst frame drop).
  5. `allowDuplicates: true` bypasses debounce when intentional rapid increments occur.
  6. Leading zero preservation (`0012345678905` retained exactly).
  7. Whitespace trimming and empty string validation rejection.
  8. Min/Max barcode length enforcement according to `ScannerConfiguration`.
  9. Rolling history buffer bounds truncation to `maxHistorySize`.
  10. Real-time Stream broadcast for results and status changes.
  11. Clean disposal preventing memory leaks and rejecting subsequent calls.
  12. Universal symbology parsing across Code 128, EAN, UPC, QR, Data Matrix.
  13. `SmartScanResult` serialization roundtrip (`toMap()` / `fromMap()`).
- **`ThqBarcodeWedgeListener`**:
  1. Rapid hardware keystrokes (<45ms) terminated by Enter/Tab detected and dispatched.
  2. Slow human typing (>100ms) ignored, avoiding spurious wedge triggers.
  3. Active `EditableText` input focus protection (human form entry uninterrupted).
  4. Shortcut key suppression (Control/Alt/Meta combinations ignored).
  5. Direct bidirectional binding to `SmartScannerController`.
- **`ThqSmartScannerView`**:
  1. Cross-platform camera rendering on Android, iOS, macOS, Web.
  2. Graceful desktop card fallback on Windows/Linux pointing user to USB/Bluetooth wedge or Phone-to-PC sync.

---

## 4. Phase 2 Verification Results (2026-11-10)

| Suite | Location | Tests Total | Tests Passed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `packages/erp_core` (All Tests) | `packages/erp_core/test/` | 83 | 83 | **PASSED** (Baseline 49 + Phase 1 (14) + Phase 2 (20)) |
| `ProductIdentificationEngine` Unit Suite | `packages/erp_core/test/product_identification_engine_test.dart` | 20 | 20 | **PASSED** |
| `packages/thq_ui` (Regression Suite) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/pos_app` (POS Baseline Suite) | `apps/pos_app/test/widget_test.dart` | 1 | 1 | **PASSED** |

### Verified Coverage Highlights:
- **`ProductIdentificationEngine`**:
  1. Exact barcode resolution (`MatchMethod.exactBarcode`) with variant and price mapping.
  2. Exact QR matrix resolution (`MatchMethod.exactQr`) with `SmartBarcodeFormat.qrCode`.
  3. Exact canonical SKU lookup (`MatchMethod.exactSku`).
  4. Exact Manufacturer / Part number lookup (`MatchMethod.exactManufacturer`).
  5. Exact Internal warehouse tag lookup (`MatchMethod.exactInternal`).
  6. Exact Supplier vendor code lookup (`MatchMethod.exactSupplier`).
  7. Exact Alternate legacy SKU resolution (`MatchMethod.exactAlternateSku`).
  8. Leading zero preservation (`0012345678905` retained exactly; never parsed as integer).
  9. Case-insensitive lookup with immutable preservation of raw input casing.
  10. Whitespace trimming and empty/whitespace-only input rejection (`invalidIdentifier`).
  11. Unknown product resolution returning clean `noMatch` status.
  12. Multiple matching product handling: returns `multipleMatches` without silent auto-selection.
  13. Priority ranking enforcement: exact barcode takes precedence over collateral search tokens.
  14. Offline cache miss identification (`offlineMiss`).
  15. Empty/unpopulated offline store detection with diagnostic reasoning.
  16. Direct integration with Phase 1 `SmartScanResult` (`identifyScan`).
  17. Scanner source and device ID propagation through to request metadata.
  18. `RpcProductIdentificationRepository` argument mapping (`p_tenant_id`, `p_code`, `p_location_id`).
  19. `RepositoryException` handling: preserves network errors as `status: error` (never masked as not-found).
  20. `CompositeProductIdentificationRepository` automatic fallback to offline cache on network failure.

---

## Phase 3 Test Matrix & Execution (Client Smart Inventory Workspace)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| Client Smart Inventory Service & Workspace Suite | `apps/client_app/test/smart_inventory_workspace_test.dart` | 6 | 6 | **PASSED** |
| Client App Full Suite (Regression) | `apps/client_app/test/` | 248 | 248 | **PASSED** |
| `packages/erp_core` Full Suite | `packages/erp_core/test/` | 83 | 83 | **PASSED** |
| `packages/thq_ui` Full Suite | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |

### Verified Phase 3 Capabilities:
1. `ClientSmartInventoryService.identifyScan`: Resolves incoming scanner hardware wedge / camera scan results to a `ProductIdentificationMatch` via RPC caller and appends entry to recent activity feed.
2. `ClientSmartInventoryService.identifyCode`: Handles non-existent barcode / code gracefully, returning `noMatch` status and logging unresolved attempt.
3. `ClientSmartInventoryService.searchCatalog`: Multi-field substring search across product name, SKU, barcode, and search codes.
4. `Bulk Scanning Session Lifecycle`: Starts session, accumulates repeated scans, increments quantities, records unresolved scans, finishes session, and preserves session in completed history without mutating stock.
5. `SmartInventoryWorkspaceScreen` Structure: Renders responsive workspace header, 5-tab segmented bar, and Overview action launchers.
6. `SmartInventoryScanCenterTab` Rendering: Displays USB/Bluetooth hardware wedge listener status, single/continuous mode chips, camera toggle, manual entry field, and awaiting scan input state.
7. `Static Analysis`: Zero issues (`flutter analyze apps/client_app` passed clean).

---

## 6. Phase 4 Test Matrix & Execution (POS Desktop Smart Inventory Integration)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `PosSmartInventoryService` Unit Suite | `apps/pos_app/test/pos_smart_inventory_test.dart` | 5 | 5 | **PASSED** |
| `PosMultipleMatchDialog` Widget Suite | `apps/pos_app/test/pos_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| `PosScreen` Smart Inventory Integration Suite | `apps/pos_app/test/pos_smart_inventory_test.dart` | 5 | 5 | **PASSED** |
| POS App Full Test Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 83 | 83 | **PASSED** |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 248 | 248 | **PASSED** |

### Verified Phase 4 Capabilities:
1. **Preservation of Leading Zeros:** Barcodes with leading zeros (`0089012345678`) are preserved exactly throughout identification and cart mapping.
2. **Exact SKU Manual Entry:** Manual entry of SKU (`SKU-CEM-PPC`) resolves cleanly without error.
3. **Clean No-Match Handling:** Unrecognized barcodes return `ProductIdentificationStatus.noMatch` without corrupting active cart.
4. **Offline Fallback on RPC Failure:** Network failure triggers automatic fallback to local SQLite catalog (`OfflinePosService`), seamlessly resolving cached products.
5. **Product Resolution to `InventoryProduct`:** `resolveProduct` constructs valid POS `InventoryProduct` instances with selling price, unit code, and stock quantities.
6. **Ambiguity Resolution Modal:** `PosMultipleMatchDialog` renders variant candidates with SKU, prices, and stock; selected candidate is returned and added.
7. **Camera Viewfinder Integration:** Header toggle button opens/closes `ThqSmartScannerView` without disrupting cart state.
8. **Direct Cart Line Insertion:** Barcode scan adds exact product to cart directly without navigating away, displaying scan confirmation banner.
9. **Cart Line Quantity Consolidation:** Repeated scan of the same barcode increments quantity to 2 (`line.quantity += 1`) without creating duplicate cart lines.
10. **Ambiguous Scan Disambiguation in POS:** Scanning barcode shared across multiple variants triggers `PosMultipleMatchDialog`; selecting a variant adds that specific item to the cart.
11. **Non-Disruptive Failure Handling:** Scanning unknown barcode displays informative not-found banner while keeping the cart intact.
12. **Static Analysis:** Zero issues (`flutter analyze apps/pos_app` passed clean with 0 warnings/errors).

---

## 7. Phase 5 Test Matrix & Execution (Mobile POS Smart Inventory Integration)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `MobilePosSmartInventoryService` Unit Suite | `apps/mobile_pos/test/mobile_pos_smart_inventory_test.dart` | 5 | 5 | **PASSED** |
| `MobilePosMultipleMatchDialog` Widget Suite | `apps/mobile_pos/test/mobile_pos_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| `BarcodeScannerScreen` Enhanced Scanner Suite | `apps/mobile_pos/test/mobile_pos_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| `MobilePosHomeScreen` Smart Inventory Suite | `apps/mobile_pos/test/mobile_pos_smart_inventory_test.dart` | 3 | 3 | **PASSED** |
| Mobile POS Full Test Suite (Regression) | `apps/mobile_pos/test/` | 17 | 17 | **PASSED** |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 83 | 83 | **PASSED** |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/pos_app` Full Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 248 | 248 | **PASSED** |

### Verified Phase 5 Capabilities:
1. **Preservation of Leading Zeros:** EAN-13 barcodes with leading zeros (`0089012345678`) are preserved without truncation throughout mobile identification.
2. **Exact SKU Manual Entry:** Typing or scanning SKU string (`SKU-CEM-PPC`) resolves to the correct product variant.
3. **Clean No-Match Handling:** Unrecognized barcodes return `ProductIdentificationStatus.noMatch` cleanly without raising exceptions or breaking the cart.
4. **Offline Fallback on RPC Failure:** Network failures automatically trigger offline lookup against the local SQLite store (`MobilePosLocalStore`), resolving cached catalog products.
5. **Product Resolution to `MobileProduct`:** `resolveProduct` constructs valid `MobileProduct` models with sales units, price, and stock quantities.
6. **Mobile Ambiguity Resolution:** `MobilePosMultipleMatchDialog` renders variant candidates in a compact touch-friendly sheet, returning the user's selected candidate.
7. **Enhanced Mobile Scanner:** `BarcodeScannerScreen` supports continuous scanning, torch toggle, camera flip, and modal manual code entry with clean controller lifecycle management.
8. **Direct Mobile Cart Addition:** Barcode scans add exact products directly to the mobile cart, displaying non-intrusive `ThqNotify` confirmation.
9. **Quantity Consolidation on Repeated Scans:** Repeated scans of the same barcode automatically increment the existing cart line's quantity (`line.quantity += step`) without duplicating line rows.
10. **Ambiguous Candidate Disambiguation:** Ambiguous barcodes open the disambiguation dialog; choosing a candidate variant adds that item to the active bill.
11. **Non-Disruptive Failure Handling:** Unknown codes display informative not-found notifications while preserving active cart items.
12. **Zero Database Mutation on Scan:** Scanning solely manipulates the in-memory cart; database stock records in SQLite and Supabase are untouched until sale completion.
13. **Static Analysis:** Zero issues (`flutter analyze lib test` in `apps/mobile_pos` passed with 0 warnings/errors).

---

## 8. Phase 6 Test Matrix & Execution (THQ Client Mobile Smart Inventory Integration)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `MobileSmartInventoryService` Unit Suite | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 6 | 6 | **PASSED** |
| `MobileSmartInventoryWorkspaceScreen` 5 Tabs | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| `MobileManualCodeEntryDialog` & Feedback Card | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| `MobileSmartInventoryMultipleMatchDialog` | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| Cost Price Permission Guarding Modal | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| Bulk Session Staging & History Flow | `apps/client_mobile/test/mobile_smart_inventory_test.dart` | 1 | 1 | **PASSED** |
| Client Mobile Full Test Suite (Regression) | `apps/client_mobile/test/` | 46 | 46 | **PASSED** (Baseline 35 + 11 New) |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 83 | 83 | **PASSED** |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 248 | 248 | **PASSED** |
| `apps/pos_app` Full Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `apps/mobile_pos` Full Suite (Regression) | `apps/mobile_pos/test/` | 17 | 17 | **PASSED** |

### Verified Phase 6 Capabilities:
1. **Exact Barcode Resolution:** `MobileSmartInventoryService.identifyCode` accurately identifies products through Supabase RPC `inventory_product_lookup_v482` and broadcasts to `activityStream`.
2. **Ambiguity Resolution:** Barcodes mapping to multiple variants return `ProductIdentificationStatus.ambiguous` and display `MobileSmartInventoryMultipleMatchDialog` with touch-friendly selection.
3. **Clean Unknown Code Handling:** Unregistered identifiers return `isNotFound` cleanly without exceptions or UI stalls.
4. **Offline Error Transparency:** Network dropouts return a descriptive error informing the user that Client Mobile requires live network access.
5. **Multi-Field Catalog Search:** `searchCatalog` evaluates queries against name, SKU, barcode, part number, and brand across RPC results.
6. **In-Memory Bulk Staging Lifecycle:** Starting a session, scanning items with consolidation, logging unresolved scans, and finishing to history operates reliably in-memory.
7. **Strict Non-Mutating Stock Invariant:** Bulk sessions and scanning operations are purely observational and staging; zero stock adjustments or ledger modifications occur.
8. **5-Tab Mobile Workspace:** Overview, Scan, Lookup, Bulk, and History tabs render cleanly and navigate smoothly.
9. **Touch-Optimized Camera Viewfinder:** `ThqSmartScannerView` with continuous/single scan modes, torch toggle, camera flip, and manual entry shortcut.
10. **Cost Price Protection:** `MobileProductDetailModal` hides cost price behind a restricted banner unless the user is an owner or holds the `inventory.manage` permission.
11. **Static Analysis:** Zero issues (`flutter analyze` on new Smart Inventory files completed with 0 warnings or errors).

---

## 9. Phase 7 Test Matrix & Execution (Smart Excel / CSV Product Import Engine)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `SmartCsvParser` Unit Suite | `packages/erp_core/test/smart_import_test.dart` | 4 | 4 | **PASSED** |
| `SmartXlsxParser` Unit Suite | `packages/erp_core/test/smart_import_test.dart` | 3 | 3 | **PASSED** |
| `SmartColumnMapper` Unit Suite | `packages/erp_core/test/smart_import_test.dart` | 2 | 2 | **PASSED** |
| `SmartImportValidator` Unit Suite | `packages/erp_core/test/smart_import_test.dart` | 4 | 4 | **PASSED** |
| `SmartDuplicateDetector` Unit Suite | `packages/erp_core/test/smart_import_test.dart` | 2 | 2 | **PASSED** |
| `SmartImportEngine` Lifecycle Suite | `packages/erp_core/test/smart_import_test.dart` | 1 | 1 | **PASSED** |
| `SmartInventoryImportTab` Widget Suite | `apps/client_app/test/smart_inventory_import_test.dart` | 7 | 7 | **PASSED** |
| `SmartInventoryWorkspaceScreen` 6-Tab Suite | `apps/client_app/test/smart_inventory_workspace_test.dart` | 6 | 6 | **PASSED** |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 99 | 99 | **PASSED** (Baseline 83 + 16 New) |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 255 | 255 | **PASSED** (Baseline 248 + 7 New) |
| `apps/pos_app` Full Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `apps/mobile_pos` Full Suite (Regression) | `apps/mobile_pos/test/` | 17 | 17 | **PASSED** |
| `apps/client_mobile` Full Suite (Regression) | `apps/client_mobile/test/` | 46 | 46 | **PASSED** |

### Verified Phase 7 Capabilities:
1. **RFC 4180 CSV Parsing:** `SmartCsvParser` successfully parses valid CSVs with UTF-8 BOM, multiline fields, commas in quoted strings, escaped quotes (`""`), and auto-senses delimiters (`,`, `;`, `\t`).
2. **Pure Dart XLSX Parsing:** `SmartXlsxParser` accurately enumerates worksheets, reads headers and cell data, and preserves integers and text codes without truncation or spurious decimals (`.0`).
3. **Leading Zero Preservation:** Numerical identifiers with leading zeros (e.g. `0012345678905`) are treated as strict strings without truncation.
4. **Intelligent Synonym Auto-Mapping:** `SmartColumnMapper` auto-maps supplier columns against 17 destination fields with high confidence for common supplier conventions (`Item Name`, `Product Name`, `SKU`, `Barcode / EAN`, `Sale Price`).
5. **Required Field Verification:** Accurately flags missing required fields (`Product Name`, `SKU`) and alerts the user.
6. **In-Memory Validation Dry-Run:** `SmartImportValidator` checks mandatory fields, rejects negative prices, validates tax percentages, and suppresses cost prices for restricted personnel.
7. **Opening Stock Non-Mutating Warning:** Opening stock columns trigger an explicit non-mutating warning ensuring live stock is never modified.
8. **Intra-File Duplicate Detection:** Subsequent rows with repeated SKUs or barcodes within the same file are classified as duplicates with detailed reasoning.
9. **Live Catalog Duplicate Detection:** Checks existing database records via `ProductIdentificationRepository` and marks catalog matches.
10. **Sample Template Generation:** Generates valid, downloadable UTF-8 CSV with BOM and stylized Excel (.xlsx) templates with formatted headers and sample rows.
11. **Desktop 7-Step Import UI:** `SmartInventoryImportTab` in `apps/client_app` provides a clean desktop workflow: upload, worksheet selection, column mapping, dry-run validation, visual data table preview with filters, duplicate resolution strategy, and batch import execution.
12. **Downloadable Failure CSV:** Produces an RFC 4180 CSV error report listing row number, product name, SKU, and error reason for failed rows.
13. **Static Analysis:** Zero issues (`flutter analyze` on `erp_core` and `client_app` passed clean with 0 warnings/errors).

---

## 10. Phase 8 Test Matrix & Execution (Smart Barcode Studio & Label Printing Engine)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `BarcodeValidator` EAN-13 Suite | `packages/erp_core/test/barcode_studio_test.dart` | 4 | 4 | **PASSED** |
| `BarcodeValidator` UPC-A Suite | `packages/erp_core/test/barcode_studio_test.dart` | 2 | 2 | **PASSED** |
| `BarcodeValidator` Code128 & QR Suite | `packages/erp_core/test/barcode_studio_test.dart` | 2 | 2 | **PASSED** |
| `BarcodeGenerator` Generation Suite | `packages/erp_core/test/barcode_studio_test.dart` | 4 | 4 | **PASSED** |
| `LabelTemplate` & Presets Suite | `packages/erp_core/test/barcode_studio_test.dart` | 3 | 3 | **PASSED** |
| `LabelPrintingService` Batch PDF Suite | `apps/client_app/test/smart_barcode_studio_test.dart` | 3 | 3 | **PASSED** |
| `SmartBarcodeStudioTab` Widget Suite | `apps/client_app/test/smart_barcode_studio_test.dart` | 3 | 3 | **PASSED** |
| `SmartInventoryWorkspaceScreen` 7-Tab Suite | `apps/client_app/test/smart_inventory_workspace_test.dart` | 6 | 6 | **PASSED** |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 114 | 114 | **PASSED** (Baseline 99 + 15 New) |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 261 | 261 | **PASSED** (Baseline 255 + 6 New) |
| `apps/pos_app` Full Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `apps/mobile_pos` Full Suite (Regression) | `apps/mobile_pos/test/` | 17 | 17 | **PASSED** |
| `apps/client_mobile` Full Suite (Regression) | `apps/client_mobile/test/` | 46 | 46 | **PASSED** |

### Verified Phase 8 Capabilities:
1. **Modulo-10 Check Digit Calculation:** EAN-13 alternating 1/3 weighting and UPC-A alternating 3/1 weighting verified against known GS1 benchmark barcodes.
2. **Symbology Validation:** `BarcodeValidator` accurately accepts valid lengths/characters and rejects corrupted or miscalculated check digits.
3. **In-Store Barcode Generation:** `BarcodeGenerator.generateInternalEan13` produces guaranteed non-colliding barcodes with prefix `28` and correct check digits.
4. **UPC-A & Code 128 Generation:** In-store UPC-A generation with prefix `2` and sanitized Code 128 formatting verified.
5. **Structured THQ QR Payload:** `BarcodeGenerator.generateThqQrPayload` formats standardized `THQ:PRODUCT:<variant_short_id>:<sku>` strings.
6. **Thermal Roll PDF Generation:** `LabelPrintingService` generates 1 page per label copy with vector barcodes, store name, product title, SKU, and price.
7. **A4 Multi-Label Grid Generation:** Multi-item batches accurately flow across columns and rows with automatic pagination.
8. **Interactive Studio UI:** Fast search, missing barcode filtering, batch selection, quantity counters, live visual preview, and print actions verified.
9. **Zero Stock Balance Mutation:** Studio strictly performs catalogue and printing operations without touching live stock or accounting balances.

---

## 11. Phase 9 Test Matrix & Execution (Physical Stock Counting & Reconciliation Engine)

| Test Target | Test File | Planned | Executed | Status |
| :--- | :--- | :--- | :--- | :--- |
| `StockCountItem` Model Suite | `packages/erp_core/test/stock_count_models_test.dart` | 3 | 3 | **PASSED** |
| `StockCountSummary` Suite | `packages/erp_core/test/stock_count_models_test.dart` | 1 | 1 | **PASSED** |
| `StockCountSession` Workflow Suite | `packages/erp_core/test/stock_count_models_test.dart` | 2 | 2 | **PASSED** |
| `StockCountingService` Unit Suite | `apps/client_app/test/smart_stock_count_test.dart` | 3 | 3 | **PASSED** |
| `SmartInventoryStockCountTab` Widget Suite | `apps/client_app/test/smart_stock_count_test.dart` | 6 | 6 | **PASSED** |
| `SmartInventoryWorkspaceScreen` 8-Tab Suite | `apps/client_app/test/smart_inventory_workspace_test.dart` | 6 | 6 | **PASSED** |
| `packages/erp_core` Full Suite (Regression) | `packages/erp_core/test/` | 120 | 120 | **PASSED** (Baseline 114 + 6 New) |
| `packages/thq_ui` Full Suite (Regression) | `packages/thq_ui/test/` | 73 | 73 | **PASSED** |
| `apps/client_app` Full Suite (Regression) | `apps/client_app/test/` | 270 | 270 | **PASSED** (Baseline 261 + 9 New) |
| `apps/pos_app` Full Suite (Regression) | `apps/pos_app/test/` | 39 | 39 | **PASSED** |
| `apps/mobile_pos` Full Suite (Regression) | `apps/mobile_pos/test/` | 17 | 17 | **PASSED** |
| `apps/client_mobile` Full Suite (Regression) | `apps/client_mobile/test/` | 46 | 46 | **PASSED** |

### Verified Phase 9 Capabilities:
1. **Snapshot Capture:** `inventory_stock_count_snapshot_v485` loads current stock balances, tracking modes, reserved, damaged, quarantine, and available quantities without locking or mutating balances.
2. **Variance Classification:** Calculates `Variance = Counted - System` and accurately tags items as Matched (`== 0`), Shortage (`< 0`), Excess (`> 0`), or Uncounted.
3. **Session Container & Unstocked Discovery:** `StockCountSession` dynamically accumulates scans, maps to snapshot lines, and captures unstocked items discovered on physical shelves with `systemQuantity = 0.0`.
4. **Unresolved Scans Tracking:** Scans unresolvable in catalogue are recorded in `unresolvedScans` with raw code, scanner source, and timestamps.
5. **Interactive Counting Controls:** Desktop stepper `[-] [count] [+]`, manual SKU/barcode search with auto-increment, and one-click "Match" button verified.
6. **Concurrent Stock Movement Detection:** Pre-flight check warns the operator if sales or purchase receipts occurred during the counting process.
7. **Discrepancy Review & Separation of Duties:** Review dialog displays discrepancy breakdowns, requires explicit checkbox confirmation, and checks `inventory.stock_count` / `inventory.manage` / `owner` permissions before enabling post actions.
8. **Idempotent Reconciliation Posting:** Submits adjustments through `public.inventory_stock_count_post_v485` with RFC 4122 v4 UUID `p_request_id`, updating the movement ledger and location balances atomically while preventing duplicate adjustment entries.
9. **Audit Trail Review:** Lists past counts from `stock_counts_list_v485` displaying count numbers, locations, line counts, status, and variance totals.
10. **Zero Regression:** All 270 client_app tests, 120 erp_core tests, 73 thq_ui tests, 39 pos_app tests, 17 mobile_pos tests, and 46 client_mobile tests pass with 0 errors.

---

## 12. Phase 10 Test Matrix & Execution (Smart Purchase Receiving & Inventory Inward Engine)

### 12.1 Automated Test Execution Summary
- **`packages/erp_core/test/purchase_receiving_models_test.dart`:** 6 / 6 tests passing.
  - `PurchaseReceivingItem`: calculates `remainingExpectedQuantity`, `excessQuantity`, `isFullyReceived`, `isMissing`, and discrepancy flags.
  - `increment`, `decrement`, and `matchRemaining`: correctly update received counts, accepted balances, and tracking timestamps.
  - `fromPoItemMap`: correctly deserializes line items from `purchase_order_detail_v484`.
  - `toGrnItemMap`: formats payload for `goods_receipt_create_v484` with accepted, damaged, and rejected balances.
  - `PurchaseReceivingSummary`: computes ordered, received, accepted, damaged, rejected, line breakdown, and completion percentage.
  - `PurchaseReceivingSession`: manages items, scan matching, unresolved scans, and payload formatting.
- **`apps/client_app/test/smart_purchase_receiving_test.dart`:** 12 / 12 tests passing.
  - `listReceivablePurchaseOrders`: parses open PO records correctly.
  - `fetchReceivingItemsForPo`: retrieves line items with remaining expected quantities.
  - `createGoodsReceipt`: creates draft GRN via RPC `goods_receipt_create_v484`.
  - `postGoodsReceipt`: posts GRN atomically to ledger via RPC `goods_receipt_post_v484`.
  - `createAndPostGoodsReceipt`: chains draft creation and posting atomically.
  - `listPastGoodsReceipts`: retrieves historical GRN audit records.
  - `renders Setup view`: Open POs tab, Direct Inward tab, and Past GRN subtabs.
  - `tapping "Receive Goods"`: loads PO items and transitions into active receiving session.
  - `Receive All button`: matches all line items to remaining expected quantities (100% completion).
  - `Stepper increment & decrement`: adjusts received quantity line by line.
  - `Manual barcode entry`: increments matching item count.
  - `Review & Post Inward dialog`: validates discrepancies, captures delivery note, requires explicit confirmation checkbox, and completes inward receipt atomically.
- **`apps/client_app/test/smart_inventory_workspace_test.dart`:** 6 / 6 tests passing.
  - Verifies all 9 tabs rendered: Overview, Scan Center, Product Lookup, Bulk Scanning, Scan History, Product Import, Barcode Studio, Stock Count, Purchase Receiving.
  - Verifies "Receive Goods" quick action card in Overview tab.
- **Regression Suite:** All packages and applications pass with 0 errors (583 tests total).

---

## 13. Phase 11 Test Matrix & Execution (Phone-to-PC Wireless Smart Scanner)

### 13.1 Automated Test Execution Summary
- **`packages/erp_core/test/wireless_scanner_test.dart`:** 24 / 24 tests passing.
  - `BarcodeAccuracyVerifier`: Validates EAN-13 check digit via Modulo 10 algorithm and preserves leading zeros.
  - `BarcodeAccuracyVerifier`: Rejects corrupted/glitched check digits and truncated 11/12-digit frames.
  - `BarcodeAccuracyVerifier`: Validates UPC-A check digit; rejects corrupted UPC-A barcodes.
  - `BarcodeAccuracyVerifier`: Validates Code 128 within printable ASCII (32..126); rejects control characters.
  - `BarcodeAccuracyVerifier`: Validates QR code and Data Matrix payloads without character distortion.
  - `WirelessScannerPairingPayload`: Serializes to standardized JSON string and deserializes accurately.
  - `WirelessScannerPairingPayload`: Throws `FormatException` on expired or invalid QR strings.
  - `WirelessScannerPairingPayload`: Single-use pairing consumption guarantees credential cannot be consumed twice.
  - `WirelessScanMessage`: Computes and verifies HMAC-SHA256 signatures; rejects tampered payloads.
  - `WirelessScanMessage`: Stale or delayed scan messages (> 30s) are rejected for message freshness.
  - `WirelessScannerCoordinator`: Desktop starts hosting session in `pairingPending` state with 256-bit entropy secret (44 chars).
  - `WirelessScannerCoordinator`: Mobile phone joins session transitioning state to `connected`.
  - `WirelessScannerCoordinator`: Transmitted scan is received with exact string fidelity and leading zero preservation.
  - `WirelessScannerCoordinator`: Duplicate suppression blocks rapid repeated identical scans within window (900ms).
  - `WirelessScannerCoordinator`: Duplicate scan within suppression window replies with explicit duplicate ACK (`isDuplicate: true`).
  - `WirelessScannerCoordinator`: Replay attack protection rejects duplicated `messageId`.
  - `WirelessScannerCoordinator`: Desktop acknowledges scan with product name, echoed `receivedCode`, and signed HMAC; phone receives ACK.
  - `WirelessScannerCoordinator`: Cryptographically signed ACK verifies origin and detects tampering.
  - `WirelessScannerCoordinator`: Zero secrets logged: `toString()` masks sensitive cryptographic tokens (`sec: [PROTECTED]`, `sig: [PROTECTED]`).
  - `WirelessScannerCoordinator`: Unpair cleanly terminates session and revokes secret.
- **`packages/thq_ui/test/thq_wireless_scanner_dialog_test.dart`:** 5 / 5 tests passing.
  - `ThqPairingQrView`: Renders vector QR canvas correctly with pairing payload.
  - `ThqPairingQrView`: Displays fallback text when data is empty.
  - `ThqWirelessScannerDialog`: Displays pairing QR, instructions, and countdown timer in `pairingPending` state.
  - `ThqWirelessScannerDialog`: Transitions to connected view with device metadata when phone pairs.
  - `ThqWirelessScannerDialog`: Unpair button resets session to fresh pairing state.
- **`packages/thq_ui/test/mobile_wireless_scanner_screen_test.dart`:** 6 / 6 tests passing.
  - `ThqMobileWirelessScannerScreen`: Renders in pairing mode with instructions when unpaired.
  - `ThqMobileWirelessScannerScreen`: Direct payload joins session and displays connected header.
  - `ThqMobileWirelessScannerScreen`: Manual barcode entry transmits scan through transport with HMAC signature and displays desktop ACK banner.
  - `ThqMobileWirelessScannerScreen`: Unpair confirmation disconnects cleanly and returns to pairing screen.
  - `ThqMobileWirelessScannerScreen`: Acknowledgement timeout marks pending scan as failed after 5s if desktop does not sign ACK.
  - `ThqMobileWirelessScannerScreen`: Duplicate ACK displays "Duplicate Scan Suppressed" banner.
- **`packages/thq_ui/test/thq_smart_scanner_view_test.dart`:** 2 / 2 tests passing.
  - `ThqSmartScannerView`: Renders desktop guidance card when camera is unsupported on desktop OS.
  - `ThqSmartScannerView`: Integrates with `SmartScannerController` cleanly and notifies on corrupt frame reads.
- **`apps/pos_app/test/pos_smart_inventory_test.dart`:** 12 / 12 tests passing.
  - Phone scanner header icon renders and opens `ThqWirelessScannerDialog`.
  - Wireless scan received from paired phone executes `_handleScanCode(code, source: ScannerSource.remotePhone)`.
  - Identified product is added to active POS cart and bi-directional HMAC-signed ACK with product name and echoed code is sent back to phone.
- **`apps/client_app/test/smart_inventory_workspace_test.dart`:** 7 / 7 tests passing.
  - Workspace header displays "Pair Scanner" button and opens dialog.
  - Paired phone connection updates header badge to "Phone Scanner".
  - Transmitted scan from phone is received and acknowledged.

---

## 14. Phase 12 Test Matrix & Execution (External Product Intelligence & GS1 Barcode Lookup)

### 14.1 Automated Test Execution Summary
- **`packages/erp_core/test/external_product_intelligence_test.dart`:** 12 / 12 tests passing.
  - `ExternalProductCandidate`: Serializes to and from JSON, preserves leading zeros, supports barcode matching with zero-tolerance.
  - `CatalogueComparison`: Detects value conflicts between existing THQ product and external suggestions; conflicting fields default to unaccepted.
  - `CatalogueComparison`: Strictly protects operational accounting invariants (cost price, selling price, tax rate, stock quantity); cannot be accepted or exported in enrichment payloads.
  - `CatalogueComparison`: Generates immutable audit provenance metadata with provider ID, source name, user ID, accepted field list, and raw payload.
  - `OpenProductFactsProvider`: Parses product name, brand, category, manufacturer, image URL, and specifications under ODbL terms with `MockProductIntelligenceHttpClient`.
  - `OpenProductFactsProvider`: Gracefully handles 404 / product not found (`ExternalLookupStatus.noMatch`).
  - `OpenProductFactsProvider`: Gracefully handles 429 rate limit (`ExternalLookupStatus.rateLimited`).
  - `Gs1RegistryProvider`: Validates GTIN format and Modulo 10 check digits mathematically for EAN-13 and UPC-A barcodes.
  - `Gs1RegistryProvider`: Returns `unauthorized` status with educational message when GS1 Member Organization credentials are unconfigured.
  - `Gs1RegistryProvider`: When configured with API credentials, queries GS1 GRP endpoints and maps official GTIN attributes.
  - `MockExternalProductProvider`: Pre-seeded with building materials (UltraTech Cement), groceries (Bru Instant Coffee), electrical components (Havells Socket), and stationery (Classmate Notebook); supports text queries.
  - `ExternalProductIntelligenceEngine`: Coalesces in-flight concurrent lookups, caches results in memory for 15 minutes, and supports manual cache eviction.
- **`packages/thq_ui/test/thq_catalogue_comparison_view_test.dart`:** 2 / 2 tests passing.
  - `ThqCatalogueComparisonView`: Renders candidate header, verified badge, match confidence, conflict warning banner, and protected accounting invariant notice.
  - `ThqCatalogueComparisonView`: Protected field rows show "PROTECTED" badges and lock icons.
  - `ThqCatalogueComparisonView`: "Accept Non-Conflicting" selects empty/non-conflicting fields while leaving conflicting fields unapproved.
  - `ThqCatalogueComparisonView`: Allows manual checkbox approval of conflicting fields and calls `onApplyEnrichment` with accepted non-protected values.
- **`apps/client_app/test/smart_product_intelligence_tab_test.dart`:** 4 / 4 tests passing.
  - `SmartProductIntelligenceTab`: Renders search bar, provider selection dropdown, and quick sample chips.
  - `SmartProductIntelligenceTab`: Tapping quick chips triggers lookup and transitions to side-by-side comparison view.
  - `SmartProductIntelligenceTab`: Receives wireless phone scans from `WirelessScannerCoordinator` and initiates automated lookup.
  - `SmartProductIntelligenceTab`: Evict cache button clears in-memory cache and displays snackbar notification.
- **`apps/client_app/test/smart_inventory_workspace_test.dart`:** 8 / 8 tests passing.
  - `SmartInventoryWorkspaceScreen`: Renders all 10 tabs, including Tab 10: "Product Intelligence".
  - Overview tab displays "Product Intelligence" quick launcher card and navigates directly to Tab 10.
  - Switching to Tab 10 displays search input, provider filters, and quick chips.

### 14.2 Static Analysis & Quality Verification
- `packages/erp_core`: 0 errors, 0 warnings (`No issues found!`).
- `packages/thq_ui`: 0 errors, 0 warnings.
- `apps/client_app`: 0 errors, 0 warnings (`No issues found!`).
- `apps/pos_app`: 0 errors, 0 warnings (`No issues found!`).

---

## 15. Phase 13: Permissions, Security, Offline & Synchronization Hardening Test Plan

### 15.1 Focused Security & Synchronization Tests
- **`packages/erp_core/test/phase13_security_and_hardening_test.dart`:** 4 / 4 tests passing.
  - `CatalogueComparison masks costPrice when canViewCostPrice is false`: Validates that cost price is masked as `[Restricted]` for unauthorized roles (cashiers, viewers), and that `buildEnrichmentPayload` never includes `costPrice`.
  - `Wireless scanner rejects cross-tenant pairing`: Verifies `WirelessScannerCoordinator` and transport layer reject pairing attempts where client tenant does not match QR payload tenant.
  - `Wireless scanner rejects cross-location pairing`: Verifies pairing is rejected when client location does not match QR payload location.
  - `Wireless scanner accepts matching tenant and location`: Verifies successful pairing when tenant and location match.
- **`packages/thq_ui/test/thq_catalogue_comparison_view_test.dart`:** 2 / 2 tests passing.
  - Verifies comparison view respects `canManage` flag and disables enrichment button with permission tooltip when user lacks required permission.
- **`packages/thq_ui/test/mobile_wireless_scanner_screen_test.dart`:** 6 / 6 tests passing.
  - Verifies location isolation and transport interaction on mobile scanner.
- **`apps/client_app/test/smart_stock_count_test.dart`:** 7 / 7 tests passing.
  - Verifies stock count approval and posting guards.
- **`apps/client_app/test/smart_purchase_receiving_test.dart`:** 6 / 6 tests passing.
  - Verifies goods receipt and direct inward posting guards.
- **`apps/pos_app/test/pos_smart_inventory_test.dart`:** 12 / 12 tests passing.
  - Verifies POS offline cache fallback, product identification, and phone-to-PC wireless scanning.
- **`apps/mobile_pos/test/mobile_pos_smart_inventory_test.dart`:** 10 / 10 tests passing.
  - Verifies Mobile POS offline product cache, multiple match handling, and offline queue resiliency.

### 15.2 Static Analysis & Quality Verification
- `packages/erp_core`: 0 errors (`No issues found!`).
- `packages/thq_ui`: 0 errors.
- `apps/client_app`: 0 errors (`No issues found!`).
- `apps/pos_app`: 0 errors (`No issues found!`).
- `apps/mobile_pos`: 0 errors (`No issues found!`).






