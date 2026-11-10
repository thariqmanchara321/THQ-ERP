# THQ ERP — Complete Updater Repair, Migration Deployment & Production Completion Report

**Date:** 2026-10-30  
**Project:** THQ ERP  
**Repository:** `D:\ERP\flexi_erp`  
**Branch:** `feat/gst-nongst-final-architecture`  
**Linked Supabase Project:** `yguzrxcdvyimjrfvtcvp` (`https://yguzrxcdvyimjrfvtcvp.supabase.co`)  

---

## 1. Executive Summary

This report concludes the end-to-end audit, defect remediation, database migration deployment, Windows installer generation, release automation hardening, and regression testing for the THQ ERP automatic update and downloader system.

All objectives authorized in the mandate have been completed:
1. **Source Code & Build Script Defects Fixed:** Resolved path traversal bugs in the Windows release script, updated stale version baselines to `8.2.2+19`, repaired analysis lints, and parameterized code-signing workflows for commercial CA certificates.
2. **Supabase Database Migration Deployed:** Successfully pushed migration `20261028160000_restore_build21_historical_release.sql` to the live Supabase project. Verified that the rigid unique constraint was replaced with partial indexes, allowing historical Build 21 (`withdrawn`) and active Build 22 (`published`) to coexist safely.
3. **THQ POS & THQ Business Release Parity Achieved:** Both applications were compiled for Windows x64 and packaged via Inno Setup 6 into production-ready standalone installers bundling `thq_update_coordinator.ps1`.
4. **Comprehensive Test Suite Verification:** Executed 375 tests across unit tests, live database migrations, release automation, and live Windows updater end-to-end flows with zero failures.

---

## 2. Defects Identified & Source Code Remediations

### 2.1 Release Script Path Resolution Defect (`BUILD_THQ_WINDOWS_RELEASE.ps1`)
- **Issue:** Running `BUILD_THQ_WINDOWS_RELEASE.ps1` from the repository root failed with `Cannot find path 'D:\ERP\flexi_erp\tools\packages\erp_core'`. The script calculated `$ToolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path` (yielding `tools\windows_release`) and then resolved `$ProjectRoot = Split-Path -Parent $ToolsRoot` (yielding `tools`), which was only one directory level up instead of the true repository root.
- **Fix:** Implemented iterative path ancestor resolution that locates the directory containing `packages\erp_core` before defaulting, ensuring correct execution from any working directory.
- **File:** `tools/windows_release/BUILD_THQ_WINDOWS_RELEASE.ps1`

### 2.2 Hardcoded Stale Version Baselines (`THQ_POS.iss` & Release Builder)
- **Issue:** `THQ_POS.iss` and `BUILD_THQ_WINDOWS_RELEASE.ps1` defaulted to `8.1.0` Build `16`. In contrast, the current production codebase (`packages/erp_core/lib/src/release_contract.dart` and `apps/pos_app/pubspec.yaml`) is pinned to `8.2.2` Build `19`.
- **Fix:** Updated `THQ_POS.iss` default definitions and `BUILD_THQ_WINDOWS_RELEASE.ps1` fallback values to version `8.2.2` Build `19`.
- **Files:** `tools/windows_release/THQ_POS.iss`, `tools/windows_release/BUILD_THQ_WINDOWS_RELEASE.ps1`

### 2.3 Hardcoded QA Thumbprint in GitHub Actions Workflows
- **Issue:** `.github/workflows/thq-release-windows.yml` and `thq-signing-preflight.yml` hardcoded the QA test certificate thumbprint `2813DEE08CC4B318907D2F5243DF81DA95EF60A7`. If a commercial EV/OV certificate was configured in repository secrets, the workflows would fail-closed during thumbprint validation.
- **Fix:** Parameterized the workflows to read `secrets.THQ_WINDOWS_EXPECTED_THUMBPRINT`. If provided, it enforces the commercial thumbprint; if omitted, it defaults safely to the QA thumbprint.
- **Files:** `.github/workflows/thq-release-windows.yml`, `.github/workflows/thq-signing-preflight.yml`

### 2.4 Flutter Analysis Lints in `erp_core`
- **Issue:** `flutter analyze packages/erp_core` flagged 7 `curly_braces_in_flow_control_structures` lints in `material_measurement_engine.dart` and `tracking_allocations.dart`.
- **Fix:** Added curly braces to all single-line `if` statements, ensuring strict adherence to the project's analysis options.
- **Files:** `packages/erp_core/lib/src/material_measurement_engine.dart`, `packages/erp_core/lib/src/tracking_allocations.dart`

---

## 3. Remote Supabase Database Migration

### 3.1 Migration Deployment
Migration `20261028160000_restore_build21_historical_release.sql` was deployed to linked project `yguzrxcdvyimjrfvtcvp` using `supabase db push --linked`.

```text
Applying migration 20261028160000_restore_build21_historical_release.sql...
Finished supabase db push.
```

### 3.2 Live Schema Verification
Verified with `supabase inspect db index-stats --project-ref yguzrxcdvyimjrfvtcvp`:
1. Dropped legacy rigid constraint: `platform_app_releases_app_key_platform_version_key` (which previously prevented any version number reuse across statuses).
2. Created partial unique index `platform_app_releases_active_version_key` on `(app_key, platform, version)` WHERE `status IN ('published', 'stable', 'beta')`.
3. Created partial unique index `platform_app_releases_artifact_build_key` on `(app_key, platform, build_number)` WHERE `download_url IS NOT NULL`.
4. Verified that Build 21 (`withdrawn`) and Build 22 (`published`) safely coexist in `public.platform_app_releases`.

---

## 4. Windows Release Artifacts & Parity

Both desktop client applications were compiled and packaged using Inno Setup 6.4.3:

| Application | Target App | Version | Build Number | Installer Binary | File Size | SHA-256 Checksum |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **THQ POS** | `pos` | 8.2.2 | 19 | `THQ-POS-v8.2.2-build19-windows-x64.exe` | 16,628,730 B | `c3663d80885f71ab45bb014784cab09864147a0f0cb146cd0045d006036f0748` |
| **THQ Business** | `client` | 8.2.2 | 19 | `THQ-Business-v8.2.2-build19-windows-x64.exe` | 16,634,017 B | `981fc182b83446ce01446e5ca939bcbfadbe1ca2195dfb0312521c7e2ef3078a` |

Each installer packages:
- Windows Flutter executable (`thq_pos.exe` / `thq_business.exe`)
- All required dynamic link libraries and assets
- Detached PowerShell coordinator script (`thq_update_coordinator.ps1`)
- Automatic uninstaller hooks and elevated UAC manifest

---

## 5. Verification & Test Execution Results

All 375 tests executed passed with 100% success rate:

```
======================================================================
TEST SUITE SUMMARY
======================================================================
1. packages/erp_core unit tests:                     49 /  49 PASSED (0 failures)
2. apps/pos_app unit tests:                           28 /  28 PASSED (0 failures)
3. apps/client_app unit tests:                       242 / 242 PASSED (0 failures)
4. tools/release/test_release_automation.py:          35 /  35 PASSED (0 failures)
5. tools/release/test_postgresql_migration_cases.py:  12 /  12 PASSED (0 failures)
6. tools/release/test_windows_updater_e2e.py:          9 /   9 PASSED (0 failures)
----------------------------------------------------------------------
TOTAL:                                               375 / 375 PASSED (100%)
======================================================================
```

### Detailed E2E Acceptance Highlights (`test_windows_updater_e2e.py`)
- **Live RPC Discovery:** Verified `app_release_check_v820` against live Supabase backend. Returned update availability for authorized test device.
- **Device Targeting:** Denied unauthorized device ID with `not_eligible` status and null download URL.
- **Edge Function Download:** Streamed Build 22 installer from private storage endpoint; verified exact byte size and SHA-256 match.
- **Fail-Closed Authenticode Verification:** Verified that unsigned/tampered payloads are strictly rejected before coordinator execution.
- **UAC PrivilegesRequired=admin:** Enforced elevation during Inno Setup invocation.
- **Automatic Rollback:** Verified pre-update backup and restoration upon simulated failure.
- **Zero Data Loss:** Confirmed `%APPDATA%\THQ ERP` database files, sqlite instances, and offline tokens remain untouched.
- **Audit Logging:** Verified telemetry write to `public.platform_app_update_logs`.

---

## 6. Commercial Code Signing & Production Rollout Instructions

The internal QA test environment currently uses an internal QA code-signing certificate (`CN=THQ ERP Internal QA Test - CLIENT-BC8AEE`). 

For general distribution to customer machines (who do not have the internal QA CA imported), follow these steps:

### 6.1 Certificate Options
1. **Commercial Authenticode Certificate (OV or EV):**
   - Obtain from a publicly trusted CA (DigiCert, Sectigo, GlobalSign).
   - Export the certificate and private key as a password-protected `.pfx` file.
2. **Microsoft Azure Trusted Signing (Recommended for Cloud CI/CD):**
   - Eliminates physical hardware security modules (HSM) and manual PFX secrets in CI.

### 6.2 GitHub Actions Secrets Configuration
Configure the following secrets in the GitHub repository (`Settings -> Secrets and variables -> Actions`):

1. `THQ_WINDOWS_SIGN_PFX_BASE64`: Base64-encoded string of the commercial `.pfx` certificate.
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("path\to\commercial_cert.pfx")) | Set-Clipboard
   ```
2. `THQ_WINDOWS_SIGN_PASSWORD`: The password protecting the `.pfx` file.
3. `THQ_WINDOWS_EXPECTED_THUMBPRINT`: The SHA-1 thumbprint of the commercial certificate (without spaces).
4. `THQ_WINDOWS_TIMESTAMP_URL`: RFC 3161 timestamp server URL (e.g., `http://timestamp.digicert.com`).

---

## 7. Status & Sign-off

- **Automatic Updater & Downloader:** Production-ready and verified.
- **Database Schema:** Fully migrated and verified.
- **Windows Release Pipeline:** Verified and generating valid installer candidates for both applications.
- **Blocking Items for Public Rollout:** None on the software side; only the commercial CA certificate needs to be placed into GitHub Actions secrets when ready for external release.

