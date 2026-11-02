# Orvia native migration: feature parity checklist

**Scope:** comparison of the Flutter Orvia application in this repository with the isolated native preview built from the pinned `native-v2/lastchat` submodule.

**Baseline:** PR [#38](https://github.com/dude555afk/Orvia/pull/38), built from the pinned LastChat submodule commit `b8a2cb52311ea31719f9c20d44f35c5ee8e52f98`. This checklist records what is explicitly wired by the preview build overlays. It does not treat the presence of an upstream LastChat screen or a settings toggle as proof that an Orvia feature works.

## Verified in the native build overlays

| Capability | Native preview evidence | Verification still needed |
| --- | --- | --- |
| Orvia identity cleanup | `apply_orvia_feature_overlay.py` renames inherited `LastChat` / `lastChat` source identifiers and user-facing strings across app/shared UI/platform source roots, including font/theme helpers and About UI; source URL is redirected to Orvia | Confirm the font picker and all About/export surfaces on a physical device; preserve legal notices and compatibility IDs |
| Kilo anonymous gateway | Provider preset, onboarding entry, default `kilo-auto/free` model, blank-key request behavior | Live model discovery and prompt/streaming requests on device/network |
| Provider cleanup | Orvia-retired China-focused presets are filtered from the provider picker | Verify every provider category and imported/custom provider behavior |
| Orvia orbital intro | Compose orbital splash; pure launcher policy only shows on an unrestored launcher cold start, skips deep links/restored activities, and exposes the 1,050 ms animation + 220 ms settle timing | CI unit tests cover launch policy/timing; verify skip, lifecycle and first-launch behavior on emulator and physical device |
| App-wide MCP selection | Sticky selection in DataStore, one-time migration from the active assistant's previous selection, explicit empty-set persistence and stale-snapshot protection | Native regression tests cover migration, explicit disable, assistant switching and stale updates; confirm latest CI and cold-start persistence |
| Edge Neural TTS | Native Edge provider, token utility, settings/playback overlay; token compatibility unit test | Real-device playback, interruptions, background audio, language/voice list, and failure handling |
| Email integration | Native IMAP/SMTP service, encrypted account settings, settings page, assistant email tools, approval gate for sending; CI unit tests cover password redaction, account serialization round-trip, provider TLS defaults, and input validation | End-to-end connect, live TLS verification, inbox/search/read, compose approval, send, reply, multi-account, and credential lifecycle |

A passing workflow proves only the exact commit it built. It does not prove external-account/device flows or full feature parity; check PR #38's latest run before treating a preview APK as verified.

## Orvia features requiring a native parity audit/port

The Flutter source tree contains these feature areas. The native preview must be checked against the actual Orvia behavior and data contracts in each area; merely having an upstream LastChat equivalent is not enough.

| Orvia capability | Flutter source of truth | Native migration status |
| --- | --- | --- |
| Chat, conversation lifecycle, branches, response versions, attachments | `lib/features/chat/`, `lib/core/database/` | Audit/port parity, persistence, and migration behavior |
| Assistants, assistant import/export, prompt and tool configuration | `lib/features/assistant/` | Audit/port |
| Provider/model catalog, model capabilities, reasoning controls, key management | `lib/features/provider/`, `lib/features/model/`, `lib/core/services/model_catalog/`, `lib/core/services/api_key_manager.dart` | Kilo and selected catalog cleanup are wired; full parity not established |
| Memory, memory traces, world books, instruction injection | `lib/core/services/memory/`, `lib/features/world_book/`, `lib/features/instruction_injection/` | Audit/port; persistence and prompt injection need explicit tests |
| MCP transports, OAuth, configuration import, permissions, built-in Orvia Fetch | `lib/features/mcp/`, `lib/core/services/mcp/` | Audit/port; HTTP, SSE, STDIO, OAuth, tool approval, and fetch behavior not certified |
| Search providers and search orchestration | `lib/features/search/`, `lib/core/services/search/` | Audit/port |
| Translation and scanning | `lib/features/translate/`, `lib/features/scan/` | Audit/port |
| Speech recognition / ASR and voice services | `lib/core/services/asr/`, `lib/core/services/tts/`, `lib/features/settings/pages/tts_services_page.dart` | Edge Neural TTS overlay exists; full TTS/ASR parity not established |
| Backups, restore, WebDAV/S3, portability, migrations | `lib/features/backup/`, `lib/core/services/backup/`, `lib/core/database/backup_portability.dart` | Audit/port; cross-version restore tests required |
| Workspace, PRoot, terminal, skills, file/document tools | `lib/features/workspace/`, `lib/core/services/workspace/`, `android/app/src/main/kotlin/com/dude555afk/orvia/workspace/` | Root Flutter Android PRoot implementation is not automatically included in the LastChat-based preview; port and test |
| Background generation/overlay and scheduled tasks | `lib/core/services/mobile_background.dart`, `lib/features/settings/pages/background_overlay_settings_page.dart`, `lib/features/scheduled_tasks/`, `android/app/src/main/kotlin/com/dude555afk/orvia/background/`, `android/app/src/main/kotlin/com/dude555afk/orvia/scheduled/` | Root Orvia host services are not automatically included; port and test lifecycle/restart behavior |
| Phone control, notifications, location, incoming shares, OAuth callbacks | `lib/features/settings/pages/phone_control_settings_page.dart`, `android/app/src/main/kotlin/com/dude555afk/orvia/` | Native accessibility-driven phone-control service and assistant tool are ported with explicit opt-in and per-call approval; location/screen-time/calendar are ported as `orvia_device_tools`; notification access exists in the native manifest/base tools. Still audit feature parity and test permissions/actions on device. Incoming shares and OAuth callback/browser handlers remain unported |
| Scheduled tasks, quick phrases, statistics | `lib/features/scheduled_tasks/`, `lib/features/quick_phrase/`, `lib/features/stats/` | Audit/port |
| UI customization: themes, colors, wallpapers, fonts, message styles, language, accessibility | `lib/features/settings/`, `lib/theme/`, `lib/core/services/fonts/` | Audit/port; verify font picker labels and persisted settings |
| Email | `lib/features/settings/pages/email_integration_page.dart`, `lib/core/services/email/` | Native service/UI overlay and assistant tools present; credential redaction/serialization/TLS-default/input-validation unit tests are added; end-to-end testing remains |
| Native data migration | `lib/core/database/`, `lib/core/database/backup_portability.dart` | Not implemented. The [native data migration contract](native-data-migration-contract.md) specifies a versioned transfer ZIP, typed conversion, append-only import, validation, rollback and idempotency requirements |

## Android-native host modules that must not be silently dropped

These are Orvia-owned integrations in the Flutter Android host tree, not inherited from the LastChat submodule:

- `DeviceLocalToolsHandler.kt`
- `IncomingShareHandler.kt`
- `LocationToolHandler.kt`
- `OAuthHandler.kt`, `OAuthCallbackActivity.kt`, and `OAuthBrowserService.kt`
- `PhoneControlService.kt`
- `background/BackgroundRuntime.kt` and related foreground service/overlay code
- `scheduled/ScheduledTasks.kt`, receivers, and task runner
- `workspace/WorkspacePlugin.kt` and the PRoot / terminal / document-provider classes

The current native workflow builds `native-v2/lastchat`; files under the root `android/app/` are not included simply because they exist in the same Git repository. Each required integration must be ported or replaced with a behaviorally equivalent implementation and covered by tests.

## Definition of done

1. Every Orvia feature above has an explicit decision: ported, intentionally omitted with reason, or unsupported on the target platform.
2. Every port is connected to its UI, persistence, permissions, model/tool orchestration, and backup/restore path. No dead settings-only controls.
3. Existing Orvia data has a tested import/migration path; preview and production package IDs/signing are handled safely.
4. Unit/integration tests cover critical flows; emulator smoke tests cover startup/navigation; physical-device tests cover speech, permissions, background execution, notifications, and external accounts.
5. A final source/resource scan finds no inherited user-facing LastChat brand. Required third-party attribution, license notices, and compatibility identifiers remain intact.
