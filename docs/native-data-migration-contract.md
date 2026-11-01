# Orvia Flutter → native LastChat data migration contract

**Status:** the version-1 ZIP codec and a Flutter-side snapshot exporter exist. The exporter uses a consistent temporary SQLite snapshot, applies `BackupPortability` only to that snapshot, serializes conversations/business data/assets, and redacts credentials and device paths. The codec and redaction helpers have unit tests. A typed Flutter-to-Room converter, native importer, importer UI, and end-to-end exporter fixture tests are still outstanding.

## Why this is a separate migration

The two applications do not share a database schema and their SQLite files must never be copied over one another.

- Flutter Orvia uses Drift tables such as `conversation_rows`, `message_rows`, `message_part_rows`, `provider_artifact_rows`, `asset_rows`, `message_asset_rows`, `assistant_rows`, and normalized business-entity tables.
- The pinned LastChat build uses Room. A native `ConversationEntity` stores a JSON `nodes` field representing a list of `MessageNode` values. Each node can hold multiple `UIMessage` versions and a selected index.
- LastChat's own ZIP backup contains its Room database, settings, preference snapshots and managed files. It is not a Flutter Orvia backup format.

The migration therefore needs an explicit model-to-model converter. A raw SQLite restore, table rename, or copying the database file is prohibited.

## Transfer archive

The Flutter-side codec currently enforces:
- format ID `orvia.native-transfer`, version 1;
- a strict path allowlist for conversations, business data, assistants, providers, settings and SHA-256-addressed assets;
- SHA-256 and exact byte-size verification for every payload, plus ZIP CRC verification;
- bounds of 64 MiB compressed archive, 128 MiB aggregate uncompressed payload, 32 MiB per entry and 10,000 payload entries;
- rejection of absolute paths, parent traversal, backslashes, drive prefixes, duplicate entries, unknown formats and mismatched manifest entries.

The codec only packages and validates byte entries; `NativeTransferExporter` is the separate read-only Drift snapshot exporter. It does not write to LastChat Room. The exporter currently preserves source rows and relationships in versioned JSON documents rather than converting them to native `MessageNode` values. A passing codec/redaction test is not evidence that native import is ready.

Use a versioned, self-describing ZIP archive, independent of either application's live database:

```text
manifest.json
conversations/<sha256-of-source-id>.json
assistants.json
providers.json
business-data/<kind>.json
assets/<content-sha256>
```

The manifest must declare:
- format identifier `orvia.native-transfer` and format version;
- source application version and Drift schema version;
- export timestamp and selected content categories;
- entity counts, unsupported-record diagnostics, and SHA-256 hashes plus byte sizes for every payload and asset;
- required importer capabilities and any unsupported source record counts.

The exporter stores each conversation's original ID, title, assistant reference, created/updated timestamps, pin state, truncation/summary metadata, message rows, every stored revision, version-selection JSON, message parts, per-conversation MCP links, generation runs, provider artifacts, message prompts, and asset references. It preserves the source Drift row values and relationships without converting them to native nodes. Flutter timestamps are microseconds since epoch; native LastChat timestamps are milliseconds, so the future converter must handle conversion explicitly and deterministically.

Message conversion must be type-specific. Text, reasoning, tool calls/results, image, document, audio and video parts may only be imported when their payload and attachment semantics have a tested native mapping. Unknown or malformed parts must be reported and must not silently disappear. If a conversation cannot be represented without losing content, mark it as requiring review and exclude it from automatic import.

## Business data mapping

The exporter reads business entities through `BusinessRepository.readSnapshot()`, not by scraping preference keys. The importer must explicitly map each supported kind:

- assistants and assistant tags;
- provider definitions and provider groups;
- MCP server definitions and per-conversation selections;
- world books/lorebooks, memories, skills and quick phrases;
- search, TTS and instruction-injection settings;
- user profile fields.

A kind without a tested native equivalent is reported as unsupported. Never pretend an upstream LastChat screen is equivalent to an Orvia feature just because both apps have a screen with a similar label.

Provider credentials and OAuth tokens are excluded by default. A separate, clearly labelled user opt-in may be designed later; secrets must never be placed in plaintext transfer JSON. Imported credentials must be stored through the native secure-secret store and must not be copied into logs, previews or tool-facing JSON.

## Device and workspace safety

Reuse the intent of Flutter's existing `BackupPortability` sanitation:
- exclude device-only environment and scheduled-task state;
- do not transfer linked workspace host paths, mount grants, current working directories, shell-approval flags, or external mounts;
- never transfer accessibility or notification-access enablement;
- do not replay phone-control actions, background jobs or scheduled tasks on import;
- do not restore a source device's permission grants on the destination device.

Portable workspace metadata may be offered separately, but the destination user must choose a new local folder and grant access on that device. Rootfs images and temporary/cache folders are not part of chat migration.

## Import semantics

The initial native migration must be **append-only**:
1. Create a verified pre-import native backup.
2. Parse the entire archive in a temporary workspace and validate format version, hashes, path containment, payload shape, entity references and supported-part coverage.
3. Show a preview with counts for importable, skipped and review-required records.
4. Import in a transaction, remapping colliding IDs while preserving a source-ID → native-ID map.
5. Verify persisted counts, relationships, message order and selected revisions before writing an idempotency receipt.
6. Leave the original Flutter app and its database untouched. A failed import must roll back and leave the native database unchanged.

No replace-all/overwrite mode is permitted in the first migration release. Re-importing the same archive must be idempotent and must not duplicate chats or business entities.

## Current exporter limitations

- Unit tests cover archive validation, recursive credential redaction, and nested device-path scrubbing. A fixture-based end-to-end snapshot/export test is still needed.
- Attachments over 32 MiB and transfers exceeding the archive limits are rejected by the codec; unsupported or unavailable attachment data is reported rather than copying arbitrary host paths.
- Provider credentials are intentionally omitted. Reconnecting providers/MCP servers on the destination remains a user action.
- The exported source rows have not yet been transformed into LastChat `Conversation` / `MessageNode` / `UIMessage` objects.

## Required tests before enabling the importer

- Fixture round-trips for empty, long and multi-branch conversations.
- Selected and unselected message revisions, interrupted generations, tool calls/results and reasoning.
- Image/document/audio/video assets, missing files and URL/path remapping.
- Assistant/provider/MCP/world-book/memory reference mapping.
- Credential exclusion and secret-redaction checks.
- Workspace path, external mount, environment and permission non-transfer checks.
- Corrupt JSON, unknown part kinds, unsupported entity kinds, invalid hashes, ZIP path traversal and oversized-entry rejection.
- Duplicate import, ID collision, interrupted transaction and rollback.
- Persisted-state validation against expected counts and relationships.

## Release gate

This contract does not enable or claim data migration. The native preview remains a separate application with a separate package ID until the exporter, importer, fixtures, device verification and a supported update/signing plan are complete. Keep the stable Flutter branch untouched throughout.
