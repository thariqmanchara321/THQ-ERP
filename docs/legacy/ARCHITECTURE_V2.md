# Flexi ERP V2 architecture

## Decision chain

Subscription entitlement
→ Tenant enabled module
→ User role permission
→ Backend RPC/RLS authorization

Templates are only starting configurations. A tenant is not permanently coupled to its template.

## Core vs industry packs

Core data engines remain reusable:
- tenants/users/roles/permissions
- inventory
- sales
- purchases
- customers/suppliers
- expenses/accounting/reports
- POS (front-end workflow over Sales)

Industry packs extend, not fork, the core:
- Restaurant: menu/tables/KOT/orders/reservations/delivery
- Workshop: vehicles/job cards/technicians/estimates
- Healthcare: patients/appointments/consultations/admissions/prescriptions
- Pharmacy: medicine/batch/expiry extension over Inventory
- Lab: test catalogue/orders/samples/results/reports

Do not scatter `if (businessType == ...)` throughout core Flutter code. Navigation and behavior should depend on modules and settings.

## Subscription policy

No plan assigned = backward-compatible mode for existing tenants.
Trial/Active/Past Due = entitled plan modules may load.
Suspended/Cancelled = client is reduced to dashboard and displays a status warning.

Production API enforcement should call `private.erp_module_available` inside protected transactional RPCs.

## Settings hierarchy target
Platform defaults → Template defaults → Tenant settings → Location settings → User preferences

This bundle implements platform settings + template settings + tenant settings V2. Location/user overrides are future layers.
