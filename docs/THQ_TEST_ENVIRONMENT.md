# THQ ERP test workspace

Production: Git `main`, Supabase `flexi-erp-dev` (`yguzrxcdvyimjrfvtcvp`).
Testing: Git `staging`, Supabase `THQ-ERP-MIGRATION-TEST` (`krejepenqgcmnsugbpmv`).

The staging source starts at checkpoint `5207aa5`, which includes the saved local Material Yard changes beyond `main` (`da03972`). Local changes made after that checkpoint, including the newest report screens if not pushed, must be brought into staging before they can be tested or promoted. The test backend was recovered through production's October 4 Reports V5 database changes. Source and database release readiness are separate checks.

## Create your separate Windows workspace once

Run in PowerShell:

```powershell
cd D:\ERP\flexi_erp
git fetch origin
git worktree add D:\ERP\THQ_ERP_TEST staging
cd D:\ERP\THQ_ERP_TEST
```

If Git says the branch is already checked out, use its existing staging worktree. Do not switch your daily production checkout or overwrite local edits. To update the test checkout later, run `git pull --ff-only` there after committing your test work.

## Create a test login once

The test project contained one test business and zero Auth users at setup. Production logins are separate and will not work here.

1. Open https://supabase.com/dashboard/project/krejepenqgcmnsugbpmv/auth/users and create a confirmed user with a separate test password.
2. In `tools/environments/REGISTER_TEST_ADMIN.sql`, replace the placeholder email with that user's email.
3. Run that SQL in the TEST project's SQL editor. Its private environment marker blocks accidental execution against production.
4. Start the test Admin app and sign in as `thq_test_admin` with the password you selected. Use Admin to create/manage test businesses, users, modules and activation codes.

Do not store the test password in Git. Business users and activation codes must be issued in TEST, just as in a real installation. The SQL only registers an already-created Auth user; it does not copy production users or credentials.

## Run or build

From `D:\ERP\THQ_ERP_TEST`:

```powershell
.\tools\environments\START_THQ_TEST.ps1 -App admin_panel
.\tools\environments\START_THQ_TEST.ps1 -App client_app
.\tools\environments\START_THQ_TEST.ps1 -App pos_app
.\tools\environments\START_THQ_TEST.ps1 -App client_mobile -Target android
.\tools\environments\START_THQ_TEST.ps1 -App mobile_pos -Target android
```

Add `-Build` to create a release EXE folder or APK. Windows builds require your existing Flutter/Visual Studio environment. Android builds require your Android SDK and signing setup. Preserve the complete Windows `build/windows/x64/runner/Release` folder and run it from a separate TEST folder; do not copy it over a client's install.

The script enables `.test` Android application IDs, so test APKs can install beside normal apps. Always use this script or the GitHub test workflow for Android test packages. A direct manual Flutter build that omits `THQ_TEST_BUILD=1` will not receive the separate application ID.

All five apps display a yellow TEST strip and reject a test configuration pointing at production before starting Supabase. Production remains the default for normal release builds. Activation credentials and POS offline databases use separate test storage. The test project keeps its own Auth sessions and data.

GitHub pushes to `staging` run CI and **Build THQ TEST** for Windows Client/POS/Admin and Android Client Mobile/Mobile POS. Successful build jobs upload ZIP artifacts containing the EXE folder or APK under the Actions run. A green source syntax check is not a substitute for a successful Flutter build and signed-in transaction testing.

## Edit modules and promote

Make code changes in the test worktree, commit them on `staging`, then push:

```powershell
git push origin staging
```

Use the test Admin app to enable and configure modules for test businesses. UI changes, new module behavior and schema changes must also be recorded in source/migrations; changing test database rows alone does not create a production release.

To prepare source promotion:

```powershell
.\tools\environments\PROMOTE_THQ_TEST.ps1
```

This opens https://github.com/thariqmanchara321/THQ-ERP/compare/main...staging?expand=1 to create/review a PR. It promotes the entire staging diff, including checkpoint changes. Keep unrelated experiments on feature branches and merge only ready modules into staging.

After the workflow file first reaches the default branch, **Prepare THQ promotion to main** is also available under Actions: select `staging` and run it to open/reuse a draft PR. It never merges automatically.

Before releasing: confirm CI and platform builds, test transactions and balances, review the complete PR, prepare only new production migrations and Edge Function changes, and synchronize release versions/installers. Merging source does not deploy SQL or update installed clients. Test invoices, balances, users, passwords and activation codes are never copied to production by these tools.

The live database history and certified fresh-install history use different migration versions and shapes. Do not run a blind `supabase db push` of the full certified baseline against production, or replay test-recovery SQL there. For future database work, create a new timestamp migration with `supabase migration new`, rehearse it in TEST, then deploy that specific reviewed change to production as part of the release. Automated production database deployment remains disabled until a canonical production migration chain is reconciled.

## Backend recovery evidence

The 12 test-only recovery batches, menu seed/completion, function reconciliation, activation triggers and private test marker were retained in a local recovery checkpoint, excluded from the public GitHub staging branch. The five certified migrations were preserved. The test project migration history is the authoritative applied record.

The recovery was based on 126 missing migration-name entries. Four commercial constraint migrations were excluded because equivalent constraints were already present; one production tenant's specific price correction was omitted. Fourteen differing function bodies and two missing functions were subsequently recovered with explicit matching execution grants. Verification found every one of production's 1,218 public/private function bodies present and matching after whitespace normalization; test also retains a few existing bootstrap helpers. This verifies function-body parity, not complete table/constraint/RLS parity.

Six live Edge Function sources were deployed to TEST: `thq-api`, `username-login`, `device-activate`, `manage-business-users-v31`, `manage-tenant-users-v32`, and `delete-business-v41`. Their project-specific URLs/keys come from each function's Supabase environment. Protected functions retain JWT verification; login and activation retain their existing public entrypoint settings and internal validation.

HTTP checks returned 401 for unauthenticated `thq-api` and 400 validation responses for empty login/activation requests. These are endpoint checks, not a successful signed-in business workflow.

Security advisors reported no ERROR-level findings, INFO notices for RPC-only RLS tables without policies, and WARN notices for authenticated SECURITY DEFINER functions. This retains the existing ERP RPC architecture; it does not certify all authorization paths. Review those notices at https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable before production release.
