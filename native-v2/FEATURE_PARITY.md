# Orvia Android-native feature parity audit

This audit is for the isolated Android-native build, not the stable Flutter app.
It deliberately separates inherited code from features that have been verified.
A screen or setting being present does not count as a working end-to-end feature.

## Rebrand and launch experience

| Item | Change in this branch | Verification |
|---|---|---|
| User-facing app name and copy | Source/resource overlay replaces `LastChat` and `lastChat` branding with `Orvia`; launcher label is Orvia | Pending build and APK inspection |
| Font/theme naming | Shared typography and font-family identifiers are rebranded, without changing the font binary or font behavior | Pending build |
| About screen mark | Replaces the inherited launcher image with an Orvia orbital mark drawn in Compose | Pending build |
| Intro | One-shot launcher cold-start overlay; particles spiral into a cyan/violet orbital mark; 1.3-second target; Skip intro button | Pending emulator test |
| Legal attribution | Third-party license/notice files are excluded from mass rebranding and must remain with the relevant components | Must be rechecked in packaged notices |

The app's lowercase package/deep-link namespaces are intentionally retained in this pass to avoid breaking existing links or Android compatibility. They are not displayed as app branding.

## Feature-parity status

| Orvia feature area | Native implementation evidence | Current status |
|---|---|---|
| Chat, streaming, model selection | Native preview is based on a mature Kotlin/Compose chat client; Orvia-specific provider presets are overlaid | Present in inherited source; parity and regression tests still required |
| Provider setup and model catalogue | Kilo anonymous gateway preset and `kilo-auto/free` seed are overlaid; retired China-focused vendor presets are filtered | Orvia-specific additions exist; live catalogue/provider behavior needs validation |
| Reasoning controls, assistants, chat history, branches and response versions | Available in the inherited client source | Must be compared against Flutter Orvia and tested, not assumed equivalent |
| Memory, world books/lorebooks, context handling | Available in inherited client source | Must be compared and tested |
| Tool calling, skills and MCP transports/OAuth | Much of the tool/MCP surface exists in inherited client source | Must verify Orvia-specific tools, approvals, import/export and `@orvia/fetch` behavior |
| Search and web/page access | Search and WebView code exists in inherited source | Must verify Orvia's provider choices and actual page extraction/read flow |
| Attachments, image generation and documents | Related surfaces exist in inherited source | Must verify supported formats, permissions and end-to-end operations |
| Text-to-speech | Native Edge neural provider, voice setting, Android playback dispatch and token compatibility unit test are overlaid | Implemented in source; only token compatibility has a CI unit test so far, not a complete service-level test |
| Speech recognition | Inherited source contains speech/STT infrastructure | Must compare providers and test end-to-end |
| Email integration | Native IMAP/SMTP service, settings page, assistant tools and approval before sending are overlaid | Implemented in source; needs provider-by-provider integration tests before being called reliable |
| Android integrations and background work | Inherited native handlers/services exist for sharing, shortcuts, notifications and scheduled/background work | Must compare with Orvia's exact behavior and permission expectations |
| Linux/PRoot workspace | Native workspace, rootfs, terminal and file handling modules exist in the Orvia repository | Build/runtime behavior and parity still need device testing |
| Themes, fonts, wallpaper and UI customization | Inherited theme and font settings are present; branding identifiers are being cleaned up | Must test persistence and verify no upstream branding remains on visible surfaces |
| Local chats/settings and portable backups | Native database and backup functionality exists in the inherited client | **No migration from the installed Flutter Orvia app is implemented** |
| Release/update continuity | Native preview uses a separate application ID and preview signing path | **Not an in-place update**; stable Flutter branch is untouched |

## Release blockers before claiming feature parity

1. Build and inspect the new APK, including a recursive visible-string scan and launcher/About imagery.
2. Run native unit tests and the emulator launch smoke test; add a test for splash skip, timing, and repeat behavior.
3. Compare every Orvia screen and capability with the Flutter implementation, including provider/settings behavior and error states.
4. Add integration tests for Edge TTS playback and IMAP/SMTP read/search/send approval. Never send a real email in automated CI.
5. Test on a physical ARM64 Android device for keyboard/IME behavior, permissions, lifecycle, background work, and crashes.
6. Implement or explicitly scope out data migration, then document backup/restore compatibility.
7. Only after those checks pass, consider a stable signing/update path. Do not merge this preview into stable by accident.

## Non-negotiable boundaries

- Keep stable Flutter Orvia unchanged until migration and regression checks pass.
- Do not delete upstream license/notice files to make a text scan look clean.
- Do not claim feature parity from a successful compile or a settings page alone.
- Do not ship a preview artifact as an in-place update for the production package.
