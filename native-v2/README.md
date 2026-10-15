# Orvia 2.0 Android-native preview

Isolated **Jetpack Compose** prototype for the future Orvia Android client.
Current Orvia Flutter application remains in place and untouched.

## Current milestone
- Native Kotlin/Compose Android app skeleton
- Orvia-branded dark Material 3 palette and floating composer
- Local-only prototype message list; sending does **not** invoke an AI model
- Separate application ID so this preview does not replace the installed Orvia app

## Not yet implemented
Real model streaming, settings, accounts, persistence, LastChat feature integration, MCP, TTS, chat migration and release workflows.

## Build
This folder is an independent Gradle Android project. Open `native-v2/` in Android Studio (JDK 17, Android SDK 35), use Gradle 8.11.1 or newer, and run `:app:assembleDebug`.
A Gradle wrapper is not yet committed and no build has been verified.

## Migration gates
1. Audit LastChat and Orvia screens, features, permissions, license obligations, and data formats.
2. Preserve existing branding and required third-party notices.
3. Validate real feature parity and user-data migration on test devices.
4. Keep this app separate until regression checks and signed update-path verification pass.

License: AGPL-3.0, consistent with the repository root. This prototype does not contain transplanted LastChat source.
