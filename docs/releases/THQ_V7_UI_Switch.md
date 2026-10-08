# THQ ERP 7.0.1 Build 15 — Classic / V7 UI

Based on pushed checkpoint `8faa7b942435c59e993ad422bc99cd7dc670fa7c`.
Original desktop/mobile theme definitions recovered from `0c668648b984624cfd66bf7f565ba2b84560c0b7`.

All five apps offer Classic and V7. V7 remains the default. The choice is saved per app on each device; Admin web remembers it in that browser profile. Classic restores the original Aurora desktop and original mobile colours, typography and component styles, plus the original expanded desktop sidebar widths. Both appearances use the current screens, permissions, services and transaction writers. Client New Sale retains the single scrolling signature invoice. The POS footer remains Sign Out, Collapse/Expand and version in both modes. Current table/responsive fixes and THQ startup branding remain available.

Use the palette button on login, Client/Admin headers and Client Mobile headers. POS uses Terminal actions > Classic UI / V7 UI. Mobile POS uses POS menu > Classic UI / V7 UI. Switching does not restart the app, replace Navigator, reload session/transaction data or clear drafts. It works offline. No Supabase schema or data change is required.

Persistence uses the existing shared_preferences 2.5.5 package, now explicitly declared by thq_ui. Keys are `thq.ui.appearance.v1.<appKey>`; unrelated session/activation/transaction preferences are untouched. Restore errors/timeouts keep V7 available; write failures keep the selected UI active and show a retry message. Queued writes preserve the last selected choice.

Validation: all five apps and three shared packages analyze without errors or warnings. Existing info-only lints remain unchanged (Client 4, POS 4, Client Mobile 2). 182 tests passed across the seven projects containing tests; thq_logistics has no test directory and passed analysis. This includes actual New Sale loaded-cart quantity/rate/totals, notes/payment retention, no extra RPC reads on switching, eight responsive cases, both-mode compact POS footer at 150% text size, saved choices, failure/retry, queued writes, Navigator/dialog/focus continuity and login drafts at narrow/short sizes. Admin release web build passed. Windows and Android native builds must run on the appropriate machine using the supplied verifier.

Validation runtime: Flutter 3.47.6 / Dart 3.13.5; PowerShell 7.6.6 on Linux. All required project packages were resolved from existing lockfiles; missing archives were checked against their pinned SHA-256 hashes. No dependency overrides or unrelated SDK-generated changes are included. Windows PowerShell 5.1 execution and native Windows/Android builds were not run here.

Sources: https://pub.dev/packages/shared_preferences/versions/2.5.5 and https://api.flutter.dev/flutter/material/MaterialApp/builder.html .
