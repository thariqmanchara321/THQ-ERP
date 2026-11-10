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
