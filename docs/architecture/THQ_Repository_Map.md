# THQ ERP — Complete Repository Architecture & Source Map

**Project:** THQ ERP  
**Repository:** `thariqmanchara321/THQ-ERP`  
**Primary Working Architecture:** `feat/gst-nongst-final-architecture` / `main`  
**Generated Date:** 2026-11-09  

---

## 1. High-Level Repository Architecture

THQ ERP is organized as a high-performance Flutter/Dart monorepo supporting 5 dedicated client/terminal applications, 3 shared core packages, a PostgreSQL 17 backend managed via Supabase, Deno TypeScript Edge Functions, Windows Inno Setup release builders, and automated GitHub Actions CI/CD workflows.

```
D:\ERP\flexi_erp\
├── .github/
│   └── workflows/                # Automated CI/CD, Signing, and Release pipelines
│       ├── thq-ci.yml            # Monorepo linting, test suite, and static analysis
│       ├── thq-release-windows.yml # Windows release builder, Inno Setup compiler & publisher
│       └── thq-signing-preflight.yml # Fail-closed Authenticode validation check
├── apps/                         # 5 Dedicated Flutter Applications
│   ├── admin_panel/              # Platform Superadmin & Multi-tenant Manager (Web/Desktop)
│   ├── client_app/               # Primary THQ Business ERP Client (Windows Flutter / Web)
│   ├── pos_app/                  # High-throughput THQ POS Desktop Terminal (Windows Flutter)
│   ├── client_mobile/            # Executive & Warehouse Mobile ERP Companion (Android/iOS)
│   └── mobile_pos/               # Handheld Waiter / Floor POS Terminal (Android/iOS)
├── packages/                     # 3 Shared Business & UI Packages
│   ├── erp_core/                 # Core domain models, session contracts, math engines, release API
│   ├── thq_ui/                   # Unified futuristic design system, tokens, tables, brand experience
│   └── thq_logistics/            # Shared logistics models, trip structures, vehicle runs
├── supabase/                     # Backend Database & Edge Infrastructure
│   ├── functions/                # Deno Edge Functions (Auth, Activation, Release, API)
│   ├── migrations/               # 314 Immutable SQL Migrations (PostgreSQL 17)
│   └── config.toml               # Supabase project configuration
├── tools/                        # Automation & Release Engineering Utilities
│   ├── release/                  # Python release managers, E2E acceptance suites, migration tests
│   └── windows_release/          # Inno Setup (.iss) scripts, detached coordinator, build runners
└── docs/                         # Technical documentation, audit history, and architecture blueprints
```

---

## 2. Applications Inventory & Technical Profiles

### 2.1 THQ Business (`apps/client_app`)
- **Primary Target:** Windows x64 Desktop (Flutter), Web, Desktop Linux/macOS.
- **Role:** The comprehensive enterprise back-office management system for business owners, accountants, inventory managers, and logistics dispatchers.
- **Size:** 226 Dart source files, 88 screens, 73 services.
- **Entrypoint:** `apps/client_app/lib/main.dart` -> `client_bootstrap_screen.dart` -> `client_login_screen.dart` -> `client_home_screen.dart`.
- **Core Modules & Capabilities:**
  - **Accounting & Finance:** Chart of accounts, multi-ledger accounting, journal generation, bank reconciliation (`bank_reconciliation_v500_screen.dart`), daily detailed accounts report, financial vouchers, expense change audit.
  - **GST Compliance:** Authorized GST and Non-GST engine separation (`v716`), GSTR-1, GSTR-2B ITC document matching, state master mapping, e-Way bill and invoice snapshot series (`gst_invoice_series_v632`).
  - **Inventory & Warehouse:** Multi-location stock balance, batch allocations, serial number tracking, warranty tracking, warehouse transfer allocations (`v485`), barcode workbench.
  - **Material Yard & Aggregate Operations:** Raw material truck load registers, CFT volume calculators (inches/feet/metres), tare/gross weight calculation, driver settlement, material daily rate board (`material_daily_rate_history_v708`).
  - **Purchases & Suppliers:** Purchase requisitions, purchase orders (`v480`), goods receipt notes (`v484`), purchase invoices, supplier ledger statements, supplier payment allocation.
  - **Sales & Distribution:** Wholesale and commercial sales invoices, price list resolution, customer-specific pricing (`v482`), sales returns, commercial charges catalog (`v610`).
  - **Customer Relationship (CRM):** Customer groups, loyalty ledger (`v500`), credit balance management, statements.
  - **Logistics & Transportation:** Trip hub (`v611`), vehicle profiles, stop evidence capture, route variance tracking.
  - **Workforce Management:** Staff attendance, daily earnings, workforce account settlements (`v630`).

### 2.2 THQ POS (`apps/pos_app`)
- **Primary Target:** Windows x64 Desktop (Flutter).
- **Role:** High-speed, resilient retail point-of-sale and restaurant checkout terminal engineered for continuous high-throughput billing with complete offline operation.
- **Size:** 139 Dart source files, 48 screens, 53 services.
- **Entrypoint:** `apps/pos_app/lib/main.dart` -> `pos_bootstrap_screen.dart` -> `pos_login_screen.dart` -> `pos_screen.dart`.
- **Core Modules & Capabilities:**
  - **High-Speed Billing:** Fast barcode lookup, quick tender shortcuts, multi-payment tender (Cash, Card, UPI, Split Payment, Store Credit).
  - **Offline SQLite Architecture:** Powered by `OfflinePosService` (`thq_pos_offline_v486.sqlite`) using WAL mode. Stores products, customers, available serials, offline counters, and invoice queue.
  - **Shift & Cash Drawer Management:** Cashier shift sign-in/sign-out, float declaration, cash drops, petty cash payouts, shift reconciliation reports (`cashier_shift_screen.dart`).
  - **Held Sales & Kitchen Orders:** Hold/recall transaction carts, restaurant table ordering, KOT generation (`mobile_pos_kot_requests_v488`).
  - **Offline Synchronization:** `OfflinePosSyncService` synchronizes completed invoices via FIFO queue with deterministic idempotency keys (`request_id`). Detects price/tax/serial conflicts and surfaces resolution prompts.
  - **Hardware Peripheral Integration:** Thermal receipt printers (ESC/POS), barcode scanners (raw HID keyboard wedge), pole displays, cash drawers (RJ11/RJ12 kick pulse).

### 2.3 THQ Admin Panel (`apps/admin_panel`)
- **Primary Target:** Web, Windows Desktop.
- **Role:** Multi-tenant platform superadministration console used exclusively by THQ Platform Engineers.
- **Size:** 53 Dart source files, 27 screens.
- **Entrypoint:** `apps/admin_panel/lib/main.dart` -> `login_screen.dart` -> `admin_dashboard_v600.dart`.
- **Core Modules & Capabilities:**
  - **Tenant & Business Provisioning:** Create new businesses, register initial owner credentials, generate activation codes, manage business divisions.
  - **Subscription Plans & Module Entitlements:** Configure plan tiers (Starter, Professional, Enterprise), grant/revoke module access, configure billing periods.
  - **Hardware & Device Lifecycle:** View registered business devices, monitor heartbeat telemetry, revoke compromised device tokens, issue hardware activation credentials.
  - **Release Engineering & OTA Publishing:** Manage `platform_app_releases`, upload Windows installer binaries, set release channels (stable, beta), monitor update telemetry (`platform_app_update_logs`).
  - **System Audit & Security:** View `platform_audit_log`, error telemetry (`platform_error_logs_screen.dart`), active PostgreSQL connection statistics, and RLS security health.

### 2.4 THQ Client Mobile (`apps/client_mobile`)
- **Primary Target:** Android (APK / AAB), iOS.
- **Role:** Executive companion and warehouse mobile manager for business owners on the go.
- **Size:** 28 Dart source files.
- **Capabilities:** Real-time KPI dashboards, sales summaries, stock balance inquiries, material yard load confirmation, purchase order approval workflows, push notifications.

### 2.5 THQ Mobile POS (`apps/mobile_pos`)
- **Primary Target:** Android (Handheld POS terminals / Mobile phones), iOS.
- **Role:** Mobile waiter terminal, table-side ordering system, and floor-level queue buster.
- **Size:** 30 Dart source files.
- **Capabilities:** Table selection, table-side KOT dispatch, mobile receipt printing via Bluetooth ESC/POS printers, offline queue synchronization (`mobile_pos_sync_service.dart`).

---

## 3. Shared Packages Architecture

### 3.1 `packages/erp_core`
The foundation domain package shared across all 5 applications.
- **Files:** 19 Dart source files.
- **Key Modules:**
  - `release_contract.dart`: Central single source of truth for application versions (`8.2.2`), build numbers (`19`), database compatibility markers (`migration 213`), and API versions (`v1`).
  - `material_measurement_engine.dart`: Ultra-precise CFT (Cubic Feet) dimensional calculation engine supporting fractional inches, feet, centimetres, and metric meters with heap volume adjustments.
  - `tracking_allocations.dart`: Batch number and serial number string parsers and split allocation validators.
  - `software_update.dart`: Semver comparison logic, SHA-256 binary validation, and detached coordinator session models.
  - `erp_update_readiness.dart`: Safety guard preventing updates while uncommitted offline records or active cashier shifts exist.
  - `module_customization.dart`: Universal navigation and scope resolver mapping module visibility across 5 application scopes (`businessDesktop`, `posDesktop`, `clientMobile`, `mobilePos`, `adminPanel`).

### 3.2 `packages/thq_ui`
The shared design system providing consistent futuristic visual identity and layout mechanics.
- **Files:** 42 Dart source files.
- **Key Modules:**
  - `thq_theme.dart` & `thq_tokens.dart`: Dark/light high-contrast color palettes, typography scales, border radii, spacing tokens.
  - `thq_data_table.dart`: Compact, dense enterprise data grid with virtualized scrolling, sticky column headers, and column resize capabilities.
  - `thq_brand_experience.dart`: Unified splash screen, logo animation, and brand identity components.
  - `thq_feedback.dart`: Toast notifications, confirmation sheets, dialog foundations.

### 3.3 `packages/thq_logistics`
Specialized domain models for transportation, aggregate fleets, and distribution.
- **Files:** 4 Dart source files.
- **Key Modules:**
  - Vehicle profiles, driver contracts, trip stops, and transit route definitions.

---

## 4. Edge Functions Architecture

Located in `supabase/functions/` (Deno TypeScript runtime):

| Function Slug | Version | Verify JWT | Entrypoint | Core Responsibility |
| :--- | :--- | :--- | :--- | :--- |
| **`device-activate`** | v3 | False | `device-activate/index.ts` | Validates business code + activation code; issues cryptographically secure `device_secret` via `system_claim_activation_v47`. |
| **`username-login`** | v8 | False | `username-login/index.ts` | Translates tenant-scoped `username` to Supabase Auth email, verifies device secret SHA-256 hash, and issues user session tokens. |
| **`manage-business-users-v31`** | v8 | True | `manage-business-users-v31/index.ts` | Admin user provisioning: creates user accounts, assigns roles, and configures location access. |
| **`manage-tenant-users-v32`** | v6 | True | `manage-tenant-users-v32/index.ts` | Tenant-scoped user management with division support. |
| **`delete-business-v41`** | v6 | True | `delete-business-v41/index.ts` | Audited, authorization-guarded deletion and cascade teardown of tenant resources. |
| **`app-release-download`** | v2 | False | `app-release-download/index.ts` | Secure, authenticated download proxy streaming installer binaries from private Supabase Storage buckets. |
| **`thq-api`** | v9 | True | `thq-api/index.ts` | External REST API gateway for 3rd-party integrations (orders, inventory sync, webhooks). |

---

## 5. Development Environment & Build Commands

### 5.1 System Prerequisites
- **Flutter SDK:** Version 3.32.x or higher (`channel stable`)
- **Dart SDK:** Version 3.8.x or higher
- **Python:** Version 3.12 or higher (used for release automation and testing)
- **Supabase CLI:** Version 2.120.x or higher
- **Inno Setup:** Version 6.4.x (required for Windows EXE installer packaging)
- **Visual Studio 2022:** C++ Desktop Development workload (required for Flutter Windows compilation)

### 5.2 Application Run Commands
```powershell
# Run THQ Business (Client Desktop) on Windows
cd D:\ERP\flexi_erp\apps\client_app
flutter run -d windows

# Run THQ POS Desktop Terminal on Windows
cd D:\ERP\flexi_erp\apps\pos_app
flutter run -d windows

# Run THQ Admin Panel on Chrome Web
cd D:\ERP\flexi_erp\apps\admin_panel
flutter run -d chrome

# Run Mobile Companion on connected Android Device
cd D:\ERP\flexi_erp\apps\client_mobile
flutter run -d android
```

### 5.3 Windows Installer Build Commands
```powershell
# Build THQ POS Windows Installer
cd D:\ERP\flexi_erp
powershell -ExecutionPolicy Bypass -File tools/windows_release/BUILD_THQ_WINDOWS_RELEASE.ps1 -TargetApp pos -Format installer -SkipVcRedist

# Build THQ Business Windows Installer
cd D:\ERP\flexi_erp
powershell -ExecutionPolicy Bypass -File tools/windows_release/BUILD_THQ_WINDOWS_RELEASE.ps1 -TargetApp client -Format installer -SkipVcRedist
```

### 5.4 Automated Test Suites
```powershell
# Run Flutter unit tests
flutter test packages/erp_core
flutter test apps/pos_app
flutter test apps/client_app

# Run Release Automation Safety Suite
python -m unittest tools/release/test_release_automation.py

# Run PostgreSQL Migration Acceptance Suite
python -m unittest tools/release/test_postgresql_migration_cases.py

# Run Live Windows Updater End-to-End Suite
python -m unittest tools/release/test_windows_updater_e2e.py
```

