# THQ ERP Windows Release Tooling

## One-Click Release Launcher
To build, check, or publish releases with automated versioning:

### Double-Click:
Run `RELEASE_THQ_BUSINESS.bat` in the repository root or in `D:\ERP\`.

### PowerShell CLI:
```powershell
# 1. Build locally without publishing
.\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode BuildOnly

# 2. Pre-flight check (branch, tags, version uniqueness, credentials)
.\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode CheckRelease

# 3. Publish internal QA update to authorized test PC CLIENT-BC8AEE
.\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode PublishQA

# 4. View latest active release and GitHub Actions workflow runs
.\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode ViewLatest
```

See [docs/ONE_CLICK_RELEASE_GUIDE.md](file:///D:/ERP/flexi_erp/docs/ONE_CLICK_RELEASE_GUIDE.md) for complete details.

---

## Standalone Compilation Scripts
- `BUILD_THQ_WINDOWS_RELEASE.ps1`: Multi-target (client, pos, both) compilation script used in CI/CD.
- `D:\ERP\THQ_Business_Inno_Setup_Source\BUILD_THQ_BUSINESS_SETUP.ps1`: Dedicated Inno Setup build script for THQ Business installer packages.

Required:
- Flutter Windows desktop toolchain / Visual Studio C++ workload
- Inno Setup 7 or 6 (`ISCC.exe`) for installer builds
- Windows SDK SignTool only when Authenticode signing is enabled

Production signing supports either:
- `THQ_WINDOWS_SIGN_PFX`
- `THQ_WINDOWS_SIGN_PASSWORD` (secure prompt is used if omitted)
- `THQ_WINDOWS_TIMESTAMP_URL`

or:
- `THQ_WINDOWS_SIGN_THUMBPRINT`
- `THQ_WINDOWS_SIGN_MACHINE_STORE=1` only for Local Machine store
- `THQ_WINDOWS_TIMESTAMP_URL`

No transaction, GST, accounting, inventory or sync writer is modified by this tooling.

