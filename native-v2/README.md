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
  hidden from the native provider picker.
- Native overlays now add Edge Neural TTS, secure IMAP/SMTP email tools, an
  opt-in Android accessibility phone-control service, and approval-gated device
  tools for location, screen-time summaries and calendar events. These source
  ports are still under CI and device validation.
- The build overlay rebrands visible `LastChat`/font-family identifiers to Orvia,
  replaces the inherited About-page image with an orbital mark, and shows a
  lightweight, skippable orbital intro only on a cold launcher start.
- The inherited source checkout remains pinned and is modified only during CI;
  required third-party license and attribution notices are preserved.
- See [FEATURE_PARITY.md](FEATURE_PARITY.md) for the feature matrix, unverified
  inherited functionality, migration blockers and release gates.

## Still not migration-complete

The native preview is not a replacement for installed Flutter Orvia yet.
Several Orvia-only features now have first native source ports, including email,
Edge TTS, phone control, and location/screen-time/calendar tools, but their
end-to-end behavior still needs emulator and physical-device validation.
Existing chats, settings, credentials and other user data are not migrated.
A stable signing/update path is also outstanding. Do not install this preview
expecting it to update the stable Flutter package in place.

## Release safety

- Keep the stable Flutter branch untouched until feature parity and regression
  checks pass.
- Preview builds use a separate package ID and temporary/debug signing; they
  are not in-place updates for the installed Flutter app.
- Preserve the upstream LastChat AGPL-3.0 license and required attribution.
