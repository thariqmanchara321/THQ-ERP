# Validation for THQ ERP 7.0.0 Build 14

Source baseline: `0c668648b984624cfd66bf7f565ba2b84560c0b7`, `checkpoint/material-yard-local-source`.

| Suite | Passing tests |
| --- | ---: |
| Shared UI | 25 |
| ERP core | 12 |
| Client | 97 |
| POS | 9 |
| Admin | 1 |
| Client Mobile | 7 |
| Mobile POS | 7 |
| Total | **158** |

All five apps and the three shared packages pass `flutter analyze --no-pub --no-fatal-infos` with zero errors or warnings. The existing info-level findings are the relative test imports in Client/POS and two unbraced statements in untouched Client Mobile auth code. The logistics package has no test directory.

The suites cover existing stock/unit calculations, tracking and conversion validation, GST snapshot writers, staff/payroll separation, material-yard payment validation and retry behavior, permissions, report ordering and exports. Added UI tests cover customer input/focus retention through state edits, dialog result/focus restoration, system reduced motion, tenant palette overrides, dense-table fitting, small product headers with full touch targets, readable invoice paper within the dark theme, and transaction sections at narrow sizes, larger text and keyboard insets.

The production inventory report screen also passes dark-theme layout/detail checks at 1366×768, 1024×650, 640×480 and 360×800 with 150% text scaling. The PNG previews were inspected for readable labels, quantity rows and controls. Previews use a fake report service and shared shell; they are rendering fixtures.

An audit confirmed **752** service, model, configuration, native-platform and existing migration files are byte-identical to the baseline. No financial RPC, authentication, permission, stock, tax, settlement or offline service implementation was edited. All five app pubspec versions and active app release contracts are `7.0.0+14`. Existing dependency specifications and lockfiles are preserved.

Supabase: `flexi-erp-dev`, project `yguzrxcdvyimjrfvtcvp`. Two active optional V7 presets and five optional beta releases were registered. Existing defaults and assignments are unchanged. Public function fingerprint before/after: `052c6f66939bc2a3e69757175ba5195a`; public policy fingerprint before/after: `4a0448ceb07ae7accb894a64cee434e1`. The receipt contains the verified rows.

The validation host used Flutter 3.47.6 and Dart 3.13.5 on Linux. Dependency resolution used available cached packages plus upstream source checkouts at the pinned package versions, using release tags where available, for unavailable scanner/storage/SQLite/printing packages and Windows printing FFI. These temporary overrides are excluded from the update. Your verification script resolves the original hosted dependencies.

Windows and Android binaries and the Admin web bundle were **not built here**. Scanner, hardware printing and live financial posting were not exercised on devices. The included verification switches build the requested platform targets locally. This update remains an optional beta registration until those checks are complete.

Installer regression results are recorded in `INSTALLER_TESTS.txt`. Apply, hash validation, BOM/CRLF compatibility, backups, repeated application, local conflicts, staging and failed-verification guards were checked with PowerShell 7.6.6. Restore rejects subsequent edits and corrupted backups. Complete removal of the newly introduced files could not be confirmed consistently on this Linux filesystem; the restore script checks the complete result and reports incomplete restoration while retaining the backups. A full restore should be checked on Windows before relying on it. The scripts target Windows PowerShell 5.1 syntax; that runtime was not available here.
