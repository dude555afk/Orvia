# Orvia 2.0 Android-native preview

This work stays isolated from the stable Flutter application. The current preview
workflow builds the pinned LastChat Kotlin/Jetpack Compose source in
`native-v2/lastchat`; the older `native-v2/app` skeleton is not the source used
for the current APK.

## Current preview build

- Separate preview application ID: `com.dude555afk.orvia.nativev2.dev`.
- Orvia branding and ARM64-only release packaging with R8/resource shrinking.
- CI checks the packaged APK's ABI, archive integrity, size and sensitive
  permissions, then installs and launches an x86_64 smoke-test build in an
  Android emulator.
- `native-v2/patches/apply_orvia_feature_overlay.py` applies asserted
  Orvia-specific changes to the pinned LastChat checkout during CI only. The
  upstream LastChat repository/submodule is not edited.
- The overlay adds Kilo to settings and guided first-run setup at
  `https://ai-gateway.kilo.ai/api/v1`, seeds `kilo-auto/free` without requiring
  an API key, and omits Authorization entirely for blank-key requests.
- China-focused chat-provider presets retired by Orvia's provider cleanup are
  hidden from the native provider picker. The About/onboarding surfaces and
  app name use Orvia branding; the upstream LastChat source remains pinned and
  unmodified.

## Still not migration-complete

The native preview is not a replacement for installed Flutter Orvia yet.
Orvia-only features such as its secure IMAP/SMTP email integration and Edge TTS
must be ported and tested before feature parity can be claimed. Existing chats,
settings, credentials and other user data are not migrated. Device testing on a
real phone and a stable signing/update path are also outstanding.

## Release safety

- Keep the stable Flutter branch untouched until feature parity and regression
  checks pass.
- Preview builds use a separate package ID and temporary/debug signing; they
  are not in-place updates for the installed Flutter app.
- Preserve the upstream LastChat AGPL-3.0 license and required attribution.
