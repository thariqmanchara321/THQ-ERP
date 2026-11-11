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



