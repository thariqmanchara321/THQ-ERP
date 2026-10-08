# THQ ERP TEST Environment Guide

Welcome to the hardened **THQ ERP TEST** environment. This workspace (`D:\ERP\THQ_ERP_TEST`) is a genuinely isolated, safe development environment where you can freely build, break, migrate, and test all 5 THQ ERP applications without risking the live production ERP.

---

## 1. Architectural Architecture & Separation

```
GitHub THQ-ERP
      │
      ├────────────────── main
      │                     │
      │               PRODUCTION (D:\ERP\flexi_erp)
      │               [STRICTLY READ-ONLY during development]
      │                     │
      │                     ▼
      │             Production Supabase
      │             (Ref: yguzrxcdvyimjrfvtcvp)
      │
      └────────────────── staging
                            │
                      TEST WORKSPACE (D:\ERP\THQ_ERP_TEST)
                            │
               ┌────────────┴────────────┐
               │                         │
      feature/accounting        feature/attendance
               │                         │
               └────────────┬────────────┘
                            │
                            ▼
                     Test Supabase
              (Ref: krejepenqgcmnsugbpmv)
```

### The Two Golden Safety Invariants
1. **Source Isolation**: `D:\ERP\flexi_erp` is **READ-ONLY**. All daily development happens exclusively in `D:\ERP\THQ_ERP_TEST`.
2. **Backend Isolation**: TEST apps **never** write into the production Supabase database. They default automatically to `krejepenqgcmnsugbpmv`.

---

## 2. Quick Environment Health Check

Before starting or after modifying modules, run the health check from the test workspace root:

```powershell
# Inside D:\ERP\THQ_ERP_TEST
.\CHECK_THQ_TEST.ps1
```

This verifies:
- Path and branch isolation (guarantees production `main` is not targeted)
- Git worktree separation
- Live connectivity to test Supabase (`krejepenqgcmnsugbpmv`)
- Windows desktop & Android configurations for all 5 apps
- Default test configuration in `supabase_config.dart`
- All 61 migration files for ordering and safety
- Environment isolation unit tests across all 5 apps

If everything is healthy, it outputs:
```
THQ TEST ENVIRONMENT: SAFE
```

---

## 3. Starting Each Application

Dedicated launcher scripts are located in `tools\environments\`:

| Application | Command | Target Platform |
| :--- | :--- | :--- |
| **Desktop Client** | `.\tools\environments\START_TEST_CLIENT.ps1` | Windows Desktop |
| **POS App** | `.\tools\environments\START_TEST_POS.ps1` | Windows Desktop |
| **Admin Panel** | `.\tools\environments\START_TEST_ADMIN.ps1` | Windows Desktop (or `-Target web`) |
| **Client Mobile** | `.\tools\environments\START_TEST_CLIENT_MOBILE.ps1` | Android |
| **Mobile POS** | `.\tools\environments\START_TEST_MOBILE_POS.ps1` | Android |

### Unified Launcher
You can also launch any application using the unified runner:
```powershell
.\tools\environments\START_THQ_TEST.ps1 -App client_app -Target windows
.\tools\environments\START_THQ_TEST.ps1 -App pos_app -Target windows
.\tools\environments\START_THQ_TEST.ps1 -App admin_panel -Target windows
```

### Built-in Launch Guards
Each script automatically:
- Refuses to run if accidentally executed inside `flexi_erp`
- Refuses to run if the active branch is `main`
- Enforces `THQ_ENV=test` and `SUPABASE_URL=https://krejepenqgcmnsugbpmv.supabase.co`
- Runs `flutter pub get` automatically if dependencies are needed

---

## 4. Visual Test Indicators

When running in TEST mode:
1. **Window Title**: Displays `THQ Business TEST`, `THQ POS TEST`, etc.
2. **Top Banner**: A persistent amber banner appears across the top of all screens:
   ```
   THQ ERP TEST • Separate test database • Test transactions only
   ```
3. **Database Guard**: Release builds and runtime code fail closed with `StateError` if test builds attempt to contact production URLs or keys.

---

## 5. Test Login & Device Activation

### A. One-Time Test Database Setup
To seed the test database with a test business, store location, and pre-authorized device activation codes:
1. Open the Supabase Dashboard for the **test project** (`krejepenqgcmnsugbpmv`).
2. Go to **SQL Editor**.
3. Run [`tools/environments/SEED_TEST_BUSINESS_AND_DEVICES.sql`](tools/environments/SEED_TEST_BUSINESS_AND_DEVICES.sql).
   *(Includes safety guard: aborts if executed on any database other than `krejepenqgcmnsugbpmv`)*

### B. Device Activation Credentials
When `client_app` or `pos_app` starts for the first time, it requests activation:
- **Business Code**: `THQTEST`
- **Activation Code**: `123456`

### C. Admin & User Logins
- **Admin Panel**:
  1. Create a user under Supabase Dashboard > Authentication > Users (e.g. `admin@example.com`).
  2. Run [`tools/environments/REGISTER_TEST_ADMIN.sql`](tools/environments/REGISTER_TEST_ADMIN.sql) with that email.
  3. Log in with username `thq_test_admin`.
- **Client & POS Users**:
  1. Create a user in Supabase Auth (e.g. `cashier@example.com`).
  2. Run [`tools/environments/REGISTER_TEST_USER.sql`](tools/environments/REGISTER_TEST_USER.sql) with that email.
  3. Log in with username `thq_test_cashier`.

---

## 6. Daily Feature Development Workflow

### Step 1: Create a Feature Branch
Always develop inside `D:\ERP\THQ_ERP_TEST`:
```powershell
cd D:\ERP\THQ_ERP_TEST
git checkout staging
git pull origin staging
git checkout -b feature/accounting-cleanup
```

### Step 2: Develop and Test Freely
- Modify UI, business logic, accounting, inventory, etc.
- Run tests:
  ```powershell
  cd apps/client_app
  flutter test
  flutter analyze
  ```

### Step 3: Commit Changes
```powershell
cd D:\ERP\THQ_ERP_TEST
git add .
git commit -m "feat(accounting): clean up general ledger and round-off logic"
```

### Step 4: Integrate into Staging
```powershell
git checkout staging
git merge --ff-only feature/accounting-cleanup
git push origin staging
```

---

## 7. Database Migrations Workflow

1. Create a new migration file inside `supabase/migrations/`:
   ```
   supabase/migrations/<YYYYMMDDHHMMSS>_<descriptive_name>.sql
   ```
2. Validate the migration before applying:
   ```powershell
   .\tools\environments\VALIDATE_MIGRATIONS.ps1
   ```
   *Checks for correct timestamp sequence, duplicate IDs, destructive SQL (`DROP TABLE`, `TRUNCATE`), and accidental production references.*
3. Apply to the **test database** (`krejepenqgcmnsugbpmv`) via Supabase CLI or SQL Editor.
4. Test all affected applications in TEST.

---

## 8. Safe Promotion to Production

Once your feature and migrations have been verified in TEST:

### Step 1: Run Pre-Flight Promotion Check
```powershell
# Inside D:\ERP\THQ_ERP_TEST
.\CHECK_BEFORE_PROMOTE.ps1
```
This shows:
- Commits being promoted
- Files changed and diff stat
- Affected applications and shared packages
- Migrations included
- Static analysis status (`flutter analyze`)

### Step 2: Run Promotion Helper
```powershell
.\PREPARE_PROMOTION.ps1
```
*Note: This script never executes destructive merges into production automatically.*

### Step 3: Promote via Approved Method

#### Option A: Pull Request (Recommended)
Open a PR on GitHub to compare `main` and `staging`:
[Compare main...staging](https://github.com/thariqmanchara321/THQ-ERP/compare/main...staging?expand=1)
Review the changes and merge into `main`.

#### Option B: Fast-Forward Git Merge in Production Workspace
Only when explicitly authorized, open `D:\ERP\flexi_erp`:
```powershell
cd D:\ERP\flexi_erp
git checkout main
git pull origin main
git merge --ff-only staging
```

#### Step 4: Apply Production Migrations
If database migrations were part of the change, apply the approved migration script deliberately to the **production Supabase project** (`yguzrxcdvyimjrfvtcvp`).

---

## 9. Updating TEST from Production

To synchronize your TEST workspace with changes made upstream:
```powershell
cd D:\ERP\THQ_ERP_TEST
git fetch origin
git checkout staging
git merge origin/main
```

---

## 10. Rollback and Recovery

Because your worktree is independent:
- **Discard uncommitted experimental changes**:
  ```powershell
  cd D:\ERP\THQ_ERP_TEST
  git restore .
  git clean -fd
  ```
- **Abandon an experimental feature branch**:
  ```powershell
  git checkout staging
  git branch -D feature/experimental-idea
  ```
- **Production Safety**:
  No action taken in `D:\ERP\THQ_ERP_TEST` will ever alter `D:\ERP\flexi_erp`.
