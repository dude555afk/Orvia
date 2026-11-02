# Orvia 2.0 Android-native preview

This is an isolated Android-native migration track. The preview APK is built from the pinned Kotlin/Jetpack Compose LastChat upstream checkout in `native-v2/lastchat`, with reproducible Orvia overlays applied during CI. It is **not yet a feature-complete replacement** for the Flutter Orvia app.

## Current native preview integrations

- Orvia user-facing identity cleanup runs over app, shared UI, and platform source/resources before compilation. It renames inherited `LastChat` UI identifiers/copy, including the font-family helper and About surface, and points the About source link to Orvia.
- The overlay adds Kilo's anonymous gateway at `https://ai-gateway.kilo.ai/api/v1`, seeds `kilo-auto/free`, and omits the Authorization header when the API key is blank.
- China-focused chat-provider presets removed from Orvia's provider catalog are hidden from the native provider picker.
- Edge Neural TTS is added through a native provider and playback dispatch overlay. Token compatibility has a unit test; real-device voice playback still requires device verification.
- Native IMAP/SMTP email settings and assistant tools are added through a separate asserted overlay. The Android preview build compiles and launches, but mailbox authentication, search, read, send-approval, and reply flows still require end-to-end account testing.
- ARM64 release packaging uses R8/resource shrinking and CI checks archive integrity, ABI contents, APK size, and final manifest capabilities. An x86_64 emulator smoke build is installed and launched separately.

The upstream source remains pinned and is not directly edited. Preserve the upstream AGPL-3.0 license and third-party notices. Internal package namespaces and submodule paths may retain upstream identifiers for compatibility/provenance; these are not user-facing branding.

## Feature parity: not complete

The Flutter app remains the feature reference. The root repository contains Orvia-specific implementations across chat, assistants, providers/models, memory/world books, MCP, search, translation, scanning, email, speech, backup/restore, workspace/PRoot, scheduled tasks, background execution, phone control, stats, quick phrases, and UI customization.

The native preview does **not** automatically inherit the Flutter app's code. In particular, the Orvia Android host integrations under `android/app/src/main/kotlin/com/dude555afk/orvia/` are not part of the LastChat-based native build unless explicitly ported. The detailed source-backed checklist is in [docs/native-orvia-feature-parity.md](../docs/native-orvia-feature-parity.md). Until each item is ported and tested, do not claim parity.

Existing Flutter chats, settings, credentials, and other user data are not migrated by this preview. Preview builds use a separate application ID and signing path; they are not in-place updates for the installed Flutter app.

## Release safety

- Keep the stable Flutter application and its release branch untouched.
- Keep native work on the isolated preview branch until feature parity and regression checks pass.
- Do not remove or rewrite required upstream copyright, license, or third-party attribution.
- Do not replace stable package/data identifiers until a tested migration strategy exists.
