# THQ ERP Windows Release Tooling — v6.1.6 Build 9

Default output:
`%USERPROFILE%\THQ_Releases\v6.1.6-build9-windows`

Expected:
- THQ-Business-v6.1.6-build9-windows-x64-portable.zip
- THQ-Business-v6.1.6-build9-windows-x64.exe
- THQ-POS-v6.1.6-build9-windows-x64-portable.zip
- THQ-POS-v6.1.6-build9-windows-x64.exe
- SHA256SUMS.txt
- RELEASE_INFO.txt

Required:
- Flutter Windows desktop toolchain / Visual Studio C++ workload
- Inno Setup 7 or 6 for installer builds
- Windows SDK SignTool only when Authenticode signing is enabled

Unsigned QA:
`& .\tools\windows_release\BUILD_THQ_WINDOWS_RELEASE.ps1 -ProjectRoot "D:\ERP\flexi_erp" -Format both`

Production signing supports either:
- `THQ_WINDOWS_SIGN_PFX`
- `THQ_WINDOWS_SIGN_PASSWORD` (secure prompt is used if omitted)
- `THQ_WINDOWS_TIMESTAMP_URL`

or:
- `THQ_WINDOWS_SIGN_THUMBPRINT`
- `THQ_WINDOWS_SIGN_MACHINE_STORE=1` only for Local Machine store
- `THQ_WINDOWS_TIMESTAMP_URL`

Fail-closed production:
`& .\tools\windows_release\BUILD_THQ_WINDOWS_RELEASE.ps1 -ProjectRoot "D:\ERP\flexi_erp" -Format both -RequireSigning`

The build signs the THQ executable before packaging. Inno Setup uses the same signing wrapper when signing is enabled, so Setup and its generated uninstaller are signed during compilation.

By default Microsoft's current x64 Visual C++ Redistributable is downloaded and bundled. Use `-SkipVcRedist` only if your deployment policy guarantees the runtime is already installed.

No transaction, GST, accounting, inventory or sync writer is modified by this tooling.
