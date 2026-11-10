# THQ ERP — Security & Technical Architecture Audit Report

**Date:** 2026-11-09  
**Target Environment:** Live Supabase Project `yguzrxcdvyimjrfvtcvp` (PostgreSQL 17.6) & Monorepo `thariqmanchara321/THQ-ERP`  
**Audit Scope:** Row Level Security (RLS), Edge Functions, Authentication, Tenant Isolation, Device Binding, Schema Integrity, Database Permissions.  

---

## 1. Executive Summary

This deep technical audit evaluates the security architecture, tenant isolation boundaries, database integrity constraints, and Edge Function implementations across the live THQ ERP system.

The inspection reveals a mature, defense-in-depth architecture combining:
1. **Universal RLS Activation:** 100% of public tables (260/260) have Row Level Security enabled (`rowsecurity = true`).
2. **Dual-Layer Access Control:** High-volume transaction and accounting tables operate under a **fail-closed default deny** model, delegating mutations strictly to `SECURITY DEFINER` PostgreSQL stored procedures and private schema routines.
3. **Hardware Device Binding:** POS and Client systems require physical device activation before username-based login is permitted.
4. **Authoritative GST Isolation:** Complete separation of GST and Non-GST calculation pathways.

---

## 2. Row Level Security (RLS) & Access Control Audit

### 2.1 Table RLS Coverage Analysis
- **Total Tables & Views Inspected:** 269 (260 `public`, 9 `private`).
- **RLS Status:**
  - 260 of 260 `public` tables have `rowsecurity = true` (100% coverage).
  - 6 `private` operational tables have `rowsecurity = true`, while 3 private context tables are restricted to superuser/service-role access.
- **Direct Client RLS Policies:** 79 granular policies defined across master data tables (`customers`, `suppliers`, `products`, `tenants`, `business_locations`, `roles`, `user_roles`).
- **Fail-Closed Default Deny:** Tables without explicit client policies cannot be selected or mutated directly by PostgREST clients. All operations must pass through authenticated RPCs.

### 2.2 Permissive Policy Inspection
Only 3 policies across the entire schema contain literal `true`:
1. `public.modules`: `modules_select_authenticated` (`SELECT` for role `authenticated` where `true`).
   - *Finding:* Intended. Platform module definitions are global master data that all authenticated users need to read to construct UI menus.
2. `public.permissions`: `permissions_select_authenticated` (`SELECT` for role `authenticated` where `true`).
   - *Finding:* Intended. The system permission catalog must be readable by authenticated sessions to evaluate local authorization guards.
3. `public.platform_app_update_logs`: `platform_app_update_logs_insert` (`INSERT` for role `public` where `true`).
   - *Finding:* Intended. Allows detached updater processes (`thq_update_coordinator.ps1`) to report upgrade progress, rollback events, and fatal launch errors prior to user authentication.

---

## 3. Edge Function Security & Deployment Audit

A live inspection of the 11 active Edge Functions deployed on Supabase against the 7 source functions in `supabase/functions/` revealed key architectural findings:

### 3.1 Gateway JWT Verification Analysis
- **Functions with `verify_jwt: true`:**
  - `manage-business-users-v31`
  - `manage-tenant-users-v32`
  - `delete-business-v41`
  - `thq-api`
  - `create-business-owner` (legacy)
  - `manage-business-users` (legacy)
  - `hyper-endpoint` (legacy)
  - `gst-provider-worker` (legacy)
- **Functions with `verify_jwt: false`:**
  - `username-login`
  - `device-activate`
  - `app-release-download`

*Deep Inspection Finding:*
Gateway JWT verification is intentionally disabled for `username-login` and `device-activate` because they serve as initial entrypoint authentication handlers before a user session token exists. Both implement strict application-level cryptography:
- `device-activate` requires `business_code` and `activation_code`, computes SHA-256 hashes, and claims tokens through `system_claim_activation_v47`.
- `username-login` verifies `deviceId` and `deviceSecret` against SHA-256 hashes in `business_devices` before translating tenant-scoped usernames to internal Supabase Auth emails.
- `app-release-download` verifies signed release tokens before streaming installer binaries from private Supabase Storage buckets.

---

## 4. Multi-Tenant Isolation & Business Hierarchy Security

1. **Tenant Separation:**
   - Every core operational table enforces a `tenant_id UUID` column linked to `public.tenants(id)`.
   - RLS policies universally enforce:
     ```sql
     tenant_id IN (
       SELECT tm.tenant_id 
       FROM tenant_memberships tm 
       WHERE tm.user_id = auth.uid() AND tm.status = 'active'
     )
     ```
2. **Location Scope Access:**
   - Store managers and cashiers are restricted to designated locations via `business_user_location_access`.
   - PostgreSQL routines (`v500_ensure_main_location`, `v500_document_location`) prevent users from recording stock movements or sales outside their authorized location.
3. **Device Binding Security:**
   - Client desktop and POS desktop systems store a cryptographic `device_secret` in local secure storage.
   - The server stores only the SHA-256 hash (`device_secret_hash`).
   - If an unauthorized machine attempts to use valid employee credentials, login is rejected with code `DEVICE_ACTIVATION_REQUIRED` or `DEVICE_INVALID`.

---

## 5. Categorized Audit Findings & Action Items

### 5.1 Verified Issues
1. **Legacy Edge Functions Active on Remote Backend:**
   - *Issue:* 4 legacy/superseded Edge Functions (`create-business-owner`, `manage-business-users`, `hyper-endpoint`, `gst-provider-worker`) remain deployed and active in the Supabase project, but have been replaced in source control by `manage-business-users-v31`, `manage-tenant-users-v32`, and updated backend routines.
   - *Impact:* Minimal security risk if not actively invoked, but increases surface area.
   - *Remediation:* Decommission and delete the 4 legacy Edge Functions from the remote Supabase project via `supabase functions delete <slug>`.

### 5.2 Potential Risks
1. **Commercial Authenticode Signing for Customer Distribution:**
   - *Risk:* In-app updates fail-closed if the digital signature does not evaluate to `Valid`. Installers signed with the internal QA self-signed certificate will fail on customer PCs that lack the imported QA root CA.
   - *Remediation:* Configure an OV/EV code-signing certificate or Microsoft Azure Trusted Signing in GitHub repository secrets (`THQ_WINDOWS_SIGN_PFX_BASE64`, `THQ_WINDOWS_EXPECTED_THUMBPRINT`).
2. **`platform_app_update_logs` Public Insert Rate Limiting:**
   - *Risk:* The `platform_app_update_logs` table allows anonymous inserts to log updater telemetry. While read access is strictly denied, an unauthenticated actor could theoretically insert spurious update logs.
   - *Remediation:* Add a lightweight rate-limiting trigger or IP throttle in PostgreSQL.

### 5.3 Items Requiring Manual Verification
1. **External GST Portal API Credentials:**
   - When enabling live GST e-Way Bill and e-Invoice synchronization (`gst-provider-worker` / `gst_provider_jobs_v600`), verify that production GST Suvidha Provider (GSP) client credentials are stored in encrypted Supabase Vault secrets and not in plain environment variables.
2. **Thermal Receipt Printer USB/COM Port Mapping:**
   - Local hardware configuration for ESC/POS thermal receipt printers on physical POS cash registers must be validated on-site.

