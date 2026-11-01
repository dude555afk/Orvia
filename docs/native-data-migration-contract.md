# Orvia Flutter → native LastChat data migration contract

**Status:** design contract only. No migration is implemented by the native preview yet.

## Why this is a separate migration

The two applications do not share a database schema and their SQLite files must never be copied over one another.

- Flutter Orvia uses Drift tables such as `conversation_rows`, `message_rows`, `message_part_rows`, `provider_artifact_rows`, `asset_rows`, `message_asset_rows`, `assistant_rows`, and normalized business-entity tables.
- The pinned LastChat build uses Room. A native `ConversationEntity` stores a JSON `nodes` field representing a list of `MessageNode` values. Each node can hold multiple `UIMessage` versions and a selected index.
- LastChat's own ZIP backup contains its Room database, settings, preference snapshots and managed files. It is not a Flutter Orvia backup format.

The migration therefore needs an explicit model-to-model converter. A raw SQLite restore, table rename, or copying the database file is prohibited.

## Transfer archive

Use a versioned, self-describing ZIP archive, independent of either application's live database:

```text
manifest.json
conversations/<source-id>.json
assistants.json
providers.json
business-data/<kind>.json
assets/<content-sha256>
```

The manifest must declare:
- format identifier `orvia.native-transfer` and format version;
- source application version and Drift schema version;
- export timestamp and selected content categories;
- entity counts and SHA-256 hashes for every payload and asset;
- required importer capabilities and any unsupported source record counts.

Each conversation export must contain its original ID, title, assistant reference, created/updated timestamps, pin/fork state, truncation/context metadata, ordered message groups, every stored revision, selected revision, message parts, provider artifacts, and asset references. Preserve message ordering and version relationships. Flutter timestamps are microseconds since epoch; native LastChat timestamps are milliseconds, so conversion must be explicit and deterministic.

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
