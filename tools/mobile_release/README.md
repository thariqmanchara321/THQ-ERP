# THQ Mobile production signing

Build 13 keeps production signing fail-closed from Android release builds. Debug builds remain unchanged.

## Recommended keystore location

Keep the keystore outside the Git repository, for example:

`%USERPROFILE%\.thq\keys\thq-mobile-release.jks`

Use two aliases in the keystore:

- `thq-client-mobile`
- `thq-mobile-pos`

Create aliases with the JDK `keytool` command. Let `keytool` prompt interactively for passwords so passwords do not appear in shell history.

## Configuration option A — ignored key.properties

For each app, copy:

- `apps/client_mobile/android/key.properties.example` -> `apps/client_mobile/android/key.properties`
- `apps/mobile_pos/android/key.properties.example` -> `apps/mobile_pos/android/key.properties`

Replace placeholders. These real `key.properties` files are ignored by Git.

## Configuration option B — environment variables

Shared:

- `THQ_ANDROID_KEYSTORE_PATH`
- `THQ_ANDROID_KEYSTORE_PASSWORD`

Client Mobile:

- `THQ_CLIENT_KEY_ALIAS`
- `THQ_CLIENT_KEY_PASSWORD`

Mobile POS:

- `THQ_POS_KEY_ALIAS`
- `THQ_POS_KEY_PASSWORD`

Environment variables override values in `key.properties`.

## Build

From PowerShell:

`& .\tools\mobile_release\BUILD_THQ_MOBILE_RELEASE.ps1 -ProjectRoot "D:\ERP\flexi_erp" -Format both`

Signed APK/AAB files are copied outside the repository to:

`%USERPROFILE%\THQ_Releases\v6.2.8-build13`

The script also writes SHA256SUMS.txt.

Release builds intentionally fail if production signing is missing or if the configured keystore path does not exist. There is no debug-signing fallback.
