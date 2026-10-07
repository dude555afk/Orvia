<div align="center">

<img src="docs/orvia-logo.png" alt="Orvia orbital logo" width="144" height="144" />

# Orvia

**An open-source AI chat and workspace app with powerful tools, flexible models, and deep customization.**

Bring your own models, customize your conversations, and connect tools through MCP.

[Roadmap](https://github.com/dude555afk/Orvia/issues/1) · [Releases](https://github.com/dude555afk/Orvia/releases) · [Builds](https://github.com/dude555afk/Orvia/actions) · [Report a bug](https://github.com/dude555afk/Orvia/issues)

</div>

## About

Orvia is a Flutter-based AI chat and workspace client built around user-controlled models, tools, memory, search, voice, attachments, and local workspaces.

## Features

- **Flexible model connections** — OpenAI-compatible endpoints, OpenAI, Gemini, Claude, and other supported providers, with configurable model capabilities and reasoning controls.
- **Conversations and memory** — assistants, conversation branches, response versions, temporary chats, long-term memory, world books, and context compression.
- **Tools and workspaces** — file operations, shell commands, skills, and workspace environments. Android uses PRoot; desktop workspaces use the native shell.
- **MCP connections** — HTTP, SSE, and STDIO transports, configuration import, OAuth support, tool approval controls, and the built-in `@orvia/fetch` server.
- **Search, voice, and attachments** — configurable search services, text-to-speech, speech recognition, images, and documents, depending on the selected provider and platform.
- **Customizable interface** — light and dark themes, dynamic colors, wallpapers, fonts, and message styling.
- **Local data and backups** — local conversations and settings, with local-file, WebDAV, and S3-compatible backup options.

Provider availability, authentication, pricing, and limits are set by the services you choose. Orvia does not include an unlimited AI subscription.

## Project status

Track implementation and verification in [issue #1](https://github.com/dude555afk/Orvia/issues/1).

| Area | Status |
| --- | --- |
| Orvia identity | Active |
| Android package | `com.dude555afk.orvia` |
| Dart package | `orvia` |
| UI language | English |
| Android release builds | Signed split APKs |
| MCP | HTTP, SSE, STDIO, OAuth, built-in `@orvia/fetch` |
| Workspaces | Android PRoot and desktop native shell |

## Getting started

1. Install Orvia from this repository's [Releases](https://github.com/dude555afk/Orvia/releases), or use an artifact from a successful [Actions run](https://github.com/dude555afk/Orvia/actions).
2. Open **Settings → Providers**, add your provider or compatible endpoint, and configure any required credentials.
3. Select a model and start a conversation.
4. Configure search, voice, MCP, and workspace tools as needed. Review each connection and its permissions before enabling it.

## Data and permissions

Conversations and settings are stored locally. Requests to cloud models, search services, MCP servers, or cloud voice providers send the relevant data to those services. Optional remote backups upload data to the destination you configure.

Keep credentials out of source control and review tool calls before granting access. Desktop workspace commands run with your user account's permissions and are not sandboxed.

## Build from source

Use Flutter **3.44.9** to match CI. The package requires Dart **3.12.1 or later within Dart 3**.

For Android, install the Android SDK and a compatible Java toolchain. The PRoot setup also uses `bash`, `python3`, `curl`, and `tar`; Gradle invokes the download script.

```bash
git clone https://github.com/dude555afk/Orvia.git
cd Orvia
flutter pub get
flutter run
```

Build an ARM64 Android debug APK:

```bash
flutter build apk --debug --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

Several packages are vendored in [dependencies/](dependencies) and referenced by path. Other platforms require their corresponding native toolchains.

## Contributing

Read [AGENTS.md](AGENTS.md) for architecture and contribution guidelines.

For code changes, run:

```bash
dart format lib test
dart analyze --fatal-infos lib test integration_test
flutter test
```

Localization lives in [lib/l10n/](lib/l10n), with `app_en.arb` as the template. Run `flutter gen-l10n` after editing localization resources and commit generated output.

## License and third-party notices

Orvia is distributed under the **GNU Affero General Public License v3.0**. See [LICENSE](LICENSE).

Third-party software retains its own copyright and license notices. Required notices stay with the relevant components, including [iOS sandbox notices](ios/sandbox/NOTICE) and [Android native notices](android/app/src/main/jniLibs/NOTICE).
