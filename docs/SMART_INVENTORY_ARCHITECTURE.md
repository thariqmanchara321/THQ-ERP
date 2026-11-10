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
