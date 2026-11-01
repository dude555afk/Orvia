import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../utils/app_directories.dart';
import 'app_database.dart';
import 'backup_portability.dart';
import 'business_data.dart';
import 'business_repository.dart';
import 'chat_database_repository.dart';
import 'native_transfer_archive.dart';

/// Exports a portable, credential-redacted snapshot of the current Flutter
/// installation for a future native LastChat importer.
///
/// The live database is never mutated. A consistent SQLite snapshot is made
/// first, and device-specific state is removed only from that temporary copy.
final class NativeTransferExporter {
  NativeTransferExporter._();

  static const _activeGenerationStates = {
    'preparing',
    'requesting',
    'streaming',
    'waiting_tool',
  };

  static const _sensitiveKeys = {
    'apikey',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'authtoken',
    'bearertoken',
    'clientsecret',
    'secret',
    'password',
    'authorization',
    'privatekey',
    'credential',
    'credentials',
  };

  static const _businessFileNames = <BusinessEntityKind, String>{
    BusinessEntityKind.providerGroup: 'provider_groups',
    BusinessEntityKind.mcpServer: 'mcp_servers',
    BusinessEntityKind.worldBook: 'world_books',
    BusinessEntityKind.assistantMemory: 'assistant_memories',
    BusinessEntityKind.quickPhrase: 'quick_phrases',
    BusinessEntityKind.searchService: 'search_services',
    BusinessEntityKind.ttsService: 'tts_services',
    BusinessEntityKind.instructionInjection: 'instruction_injections',
    BusinessEntityKind.assistantTag: 'assistant_tags',
    BusinessEntityKind.memoryEntry: 'memory_entries',
    BusinessEntityKind.workspace: 'workspaces',
    BusinessEntityKind.skill: 'skills',
    BusinessEntityKind.userProfileField: 'user_profile_fields',
  };

  /// Creates the v1 transfer archive from the live installation.
  ///
  /// The caller supplies the app version so this core database layer does not
  /// depend on package-info or UI startup.
  static Future<Uint8List> exportCurrentInstallation({
    required String sourceAppVersion,
    Directory? appDataDirectory,
  }) async {
    final root = appDataDirectory ?? await AppDirectories.getAppDataDirectory();
    if (!await root.exists()) {
      throw FileSystemException(
        'Orvia app data directory is missing',
        root.path,
      );
    }

    final sourceDatabase = File(
      p.join(root.path, AppDatabase.databaseFileName),
    );
    if (await FileSystemEntity.type(sourceDatabase.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Orvia database is missing or is not a regular file',
        sourceDatabase.path,
      );
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'orvia-native-transfer-',
    );
    final snapshotFile = File(
      p.join(temporaryDirectory.path, 'orvia-snapshot.db'),
    );

    try {
      await ChatDatabaseRepository.createConsistentSnapshot(
        sourceFile: sourceDatabase,
        destinationFile: snapshotFile,
      );

      final snapshotDatabase = AppDatabase.open(file: snapshotFile);
      late final BusinessSnapshot businessSnapshot;
      late final List<Map<String, Object?>> conversations;
      late final List<Map<String, Object?>> assetRows;
      late final List<Map<String, Object?>> extensionEntityRows;
      late final List<Map<String, Object?>> tombstoneRows;

      try {
        // This modifies only the temporary snapshot. It removes linked
        // workspace paths, external mounts, and device-only preferences.
        await BackupPortability.sanitizeDatabase(snapshotDatabase);
        businessSnapshot = BackupPortability.portable(
          await BusinessRepository(snapshotDatabase).readSnapshot(),
        );
        conversations = await _selectRows(
          snapshotDatabase,
          'SELECT * FROM conversation_rows ORDER BY created_at, id;',
        );
        assetRows = await _selectRows(
          snapshotDatabase,
          'SELECT * FROM asset_rows;',
        );
        extensionEntityRows = await _selectRows(
          snapshotDatabase,
          'SELECT * FROM extension_entity_rows ORDER BY kind, sort_order, id;',
        );
        tombstoneRows = await _selectRows(
          snapshotDatabase,
          'SELECT * FROM tombstone_rows ORDER BY scope, entity_id;',
        );
      } finally {
        await snapshotDatabase.close();
      }

      final entries = <String, List<int>>{};
      final unsupported = <String>[];
      final redactedFields = <String>[];

      entries['settings.json'] = utf8.encode(
        jsonEncode(
          _redactSecrets(
            businessSnapshot.preferences,
            redactedFields: redactedFields,
            path: 'settings',
          ),
        ),
      );

      final businessCounts = <String, int>{};
      for (final kind in BusinessEntityKind.values) {
        final rows =
            businessSnapshot.entities[kind] ?? const <BusinessEntityValue>[];
        businessCounts[kind.sourceKey] = rows.length;
        if (kind == BusinessEntityKind.assistant ||
            kind == BusinessEntityKind.provider) {
          final fileName = kind == BusinessEntityKind.assistant
              ? 'assistants.json'
              : 'providers.json';
          entries[fileName] = utf8.encode(
            jsonEncode(
              _serializeBusinessRows(
                kind,
                rows,
                redactedFields: redactedFields,
                unsupported: unsupported,
              ),
            ),
          );
          continue;
        }

        final name = _businessFileNames[kind];
        if (name == null) {
          unsupported.add('business_kind_not_exported:${kind.sourceKey}');
          continue;
        }
        entries['business-data/$name.json'] = utf8.encode(
          jsonEncode(
            _serializeBusinessRows(
              kind,
              rows,
              redactedFields: redactedFields,
              unsupported: unsupported,
            ),
          ),
        );
      }

      entries['business-data/extension_entities.json'] = utf8.encode(
        jsonEncode(
          _serializeExtensionEntities(
            extensionEntityRows,
            redactedFields: redactedFields,
            unsupported: unsupported,
          ),
        ),
      );
      entries['business-data/tombstones.json'] = utf8.encode(
        jsonEncode(
          _serializeTombstones(
            tombstoneRows,
            redactedFields: redactedFields,
            unsupported: unsupported,
          ),
        ),
      );

      final assetRowsById = <String, Map<String, Object?>>{
        for (final row in assetRows)
          if (row['id'] is String) row['id']! as String: row,
      };
      final rootPath = await root.resolveSymbolicLinks();
      var messageCount = 0;
      var assetCount = 0;
      var activeGenerationCount = 0;
      final rowsDatabase = AppDatabase.open(file: snapshotFile);

      try {
        for (final conversation in conversations) {
          final conversationId = conversation['id'];
          if (conversationId is! String || conversationId.isEmpty) {
            unsupported.add('conversation_without_valid_id');
            continue;
          }

          final conversationVariables = <Variable<Object>>[
            Variable<String>(conversationId),
          ];
          final messageRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM message_rows WHERE conversation_id = ? '
            'ORDER BY message_order, id;',
            variables: conversationVariables,
          );
          final partRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM message_part_rows WHERE conversation_id = ? '
            'ORDER BY revision_id, ordinal;',
            variables: conversationVariables,
          );
          final mcpLinks = await _selectRows(
            rowsDatabase,
            'SELECT * FROM conversation_mcp_server_rows '
            'WHERE conversation_id = ? ORDER BY ordinal, server_id;',
            variables: conversationVariables,
          );
          final generationRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM generation_run_rows WHERE conversation_id = ? '
            'ORDER BY created_at, id;',
            variables: conversationVariables,
          );
          final artifactRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM provider_artifact_rows WHERE conversation_id = ? '
            'ORDER BY revision_id, kind;',
            variables: conversationVariables,
          );
          final promptRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM message_prompt_rows WHERE conversation_id = ? '
            'ORDER BY created_at, revision_id;',
            variables: conversationVariables,
          );
          final messageAssetRows = await _selectRows(
            rowsDatabase,
            'SELECT * FROM message_asset_rows WHERE conversation_id = ? '
            'ORDER BY revision_id, asset_id, kind;',
            variables: conversationVariables,
          );

          final referencedAssetIds = <String>{
            for (final row in messageAssetRows)
              if (row['asset_id'] is String) row['asset_id']! as String,
            for (final row in partRows) ..._assetIdsFromPart(row),
          };
          final exportedAssets = await _exportAssets(
            rootPath: rootPath,
            assetIds: referencedAssetIds,
            assetRowsById: assetRowsById,
            entries: entries,
            unsupported: unsupported,
          );

          final safeParts = <Map<String, Object?>>[
            for (final part in partRows)
              _portableMessagePart(
                part,
                availableAssetIds: exportedAssets.availableIds,
                unsupported: unsupported,
              ),
          ];

          final safeMessages = <Map<String, Object?>>[
            for (final row in messageRows)
              <String, Object?>{
                ...row,
                if (row['is_streaming'] == true || row['is_streaming'] == 1)
                  'is_streaming': false,
              },
          ];

          final safeGenerationRows = <Map<String, Object?>>[];
          for (final row in generationRows) {
            final state = row['state'];
            if (state is String && _activeGenerationStates.contains(state)) {
              activeGenerationCount++;
              safeGenerationRows.add({
                ...row,
                'state': 'interrupted',
                'terminal_at': DateTime.now().toUtc().microsecondsSinceEpoch,
                'error_code': 'native_transfer_not_resumable',
              });
            } else {
              safeGenerationRows.add(row);
            }
          }

          final payload = <String, Object?>{
            'format': 'orvia.flutter-conversation',
            'version': 1,
            'sourceId': conversationId,
            'conversation': conversation,
            'mcpServerLinks': mcpLinks,
            'messages': safeMessages,
            'messageParts': safeParts,
            'generationRuns': safeGenerationRows,
            'providerArtifacts': artifactRows,
            'messagePrompts': promptRows,
            'messageAssets': messageAssetRows,
            'assets': exportedAssets.metadata,
          };
          final archiveName = sha256
              .convert(utf8.encode(conversationId))
              .toString();
          entries['conversations/$archiveName.json'] = utf8.encode(
            jsonEncode(payload),
          );
          messageCount += safeMessages.length;
        }
      } finally {
        await rowsDatabase.close();
      }

      assetCount = entries.keys
          .where((path) => path.startsWith('assets/'))
          .length;
      if (redactedFields.isNotEmpty) {
        unsupported.add('credential_fields_redacted:${redactedFields.length}');
      }
      if (activeGenerationCount > 0) {
        unsupported.add(
          'active_generation_runs_marked_interrupted:$activeGenerationCount',
        );
      }

      return NativeTransferArchive.encode(
        sourceAppVersion: sourceAppVersion,
        sourceSchemaVersion: AppDatabase.currentSchemaVersion,
        exportedAt: DateTime.now().toUtc(),
        entityCounts: <String, int>{
          'conversations': conversations.length,
          'messages': messageCount,
          'assets': assetCount,
          'extensionEntities': extensionEntityRows.length,
          'tombstones': tombstoneRows.length,
          ...businessCounts,
        },
        unsupportedRecords: unsupported,
        entries: entries,
      );
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  /// Pure recursive credential filter. Exposed for focused tests.
  @visibleForTesting
  static Object? redactSecretsForTesting(
    Object? value, {
    required List<String> redactedFields,
  }) => _redactSecrets(value, redactedFields: redactedFields, path: 'root');

  static bool _isSensitiveKey(String normalized) {
    return _sensitiveKeys.contains(normalized) ||
        normalized.endsWith('token') ||
        normalized.endsWith('apikey') ||
        normalized.endsWith('password') ||
        normalized.endsWith('authorization') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('credentials') ||
        normalized == 'secret' ||
        normalized.endsWith('secret') ||
        normalized.startsWith('secret');
  }

  static Object? _redactSecrets(
    Object? value, {
    required List<String> redactedFields,
    required String path,
  }) {
    if (value is Map) {
      final out = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (_isSensitiveKey(normalized)) {
          redactedFields.add('$path.$key');
          continue;
        }
        out[key] = _redactSecrets(
          entry.value,
          redactedFields: redactedFields,
          path: '$path.$key',
        );
      }
      return out;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map || decoded is List) {
            return jsonEncode(
              _redactSecrets(
                decoded,
                redactedFields: redactedFields,
                path: path,
              ),
            );
          }
        } catch (_) {
          // Preserve ordinary strings and malformed JSON verbatim.
        }
      }
      return value;
    }
    if (value is List) {
      return <Object?>[
        for (var index = 0; index < value.length; index++)
          _redactSecrets(
            value[index],
            redactedFields: redactedFields,
            path: '$path[$index]',
          ),
      ];
    }
    return value;
  }

  static List<Map<String, Object?>> _serializeBusinessRows(
    BusinessEntityKind kind,
    List<BusinessEntityValue> rows, {
    required List<String> redactedFields,
    required List<String> unsupported,
  }) {
    final output = <Map<String, Object?>>[];
    for (final row in rows) {
      late final Object? decoded;
      try {
        decoded = jsonDecode(row.payload);
      } catch (_) {
        unsupported.add(
          'malformed_business_payload:${kind.sourceKey}:${row.id}',
        );
        continue;
      }
      output.add({
        'id': row.id,
        'sortOrder': row.sortOrder,
        if (row.assistantId != null) 'assistantId': row.assistantId,
        'data': _redactSecrets(
          decoded,
          redactedFields: redactedFields,
          path: '${kind.sourceKey}/${row.id}',
        ),
      });
    }
    return output;
  }

  static List<Map<String, Object?>> _serializeExtensionEntities(
    List<Map<String, Object?>> rows, {
    required List<String> redactedFields,
    required List<String> unsupported,
  }) {
    final output = <Map<String, Object?>>[];
    for (final row in rows) {
      final payload = row['payload'];
      if (payload is! String) {
        unsupported.add('invalid_extension_entity_payload');
        continue;
      }
      try {
        final decoded = jsonDecode(payload);
        output.add({
          'kind': row['kind'],
          'id': row['id'],
          'sortOrder': row['sort_order'],
          if (row['owner_id'] != null) 'ownerId': row['owner_id'],
          'updatedAt': row['updated_at'],
          'data': _redactDevicePaths(
            _redactSecrets(
              decoded,
              redactedFields: redactedFields,
              path: 'extension/${row['kind']}/${row['id']}',
            ),
          ),
        });
      } catch (_) {
        unsupported.add('malformed_extension_entity_payload');
      }
    }
    return output;
  }

  static List<Map<String, Object?>> _serializeTombstones(
    List<Map<String, Object?>> rows, {
    required List<String> redactedFields,
    required List<String> unsupported,
  }) {
    final output = <Map<String, Object?>>[];
    for (final row in rows) {
      final payload = row['payload'];
      if (payload is! String) {
        unsupported.add('invalid_tombstone_payload');
        continue;
      }
      try {
        final decoded = jsonDecode(payload);
        output.add({
          'scope': row['scope'],
          'entityId': row['entity_id'],
          'deletedAt': row['deleted_at'],
          'data': _redactDevicePaths(
            _redactSecrets(
              decoded,
              redactedFields: redactedFields,
              path: 'tombstone/${row['scope']}/${row['entity_id']}',
            ),
          ),
        });
      } catch (_) {
        unsupported.add('malformed_tombstone_payload');
      }
    }
    return output;
  }

  @visibleForTesting
  static Object? redactDevicePathsForTesting(Object? value) =>
      _redactDevicePaths(value);

  static Object? _redactDevicePaths(Object? value) {
    const devicePathKeys = {
      'path',
      'filepath',
      'absolutepath',
      'hostpath',
      'rootpath',
      'cwd',
      'workingdirectory',
      'mountpath',
      'mountpoint',
      'externalmounts',
      'localpath',
      'workingdir',
      'localuri',
      'fileuri',
      'mountroot',
      'storagepath',
      'termuxpath',
    };
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (!devicePathKeys.contains(
            entry.key.toString().toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            ),
          ))
            entry.key.toString(): _redactDevicePaths(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _redactDevicePaths(item)];
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map || decoded is List) {
            return jsonEncode(_redactDevicePaths(decoded));
          }
        } catch (_) {
          // Preserve normal text and malformed JSON as-is.
        }
      }
    }
    return value;
  }

  static Future<List<Map<String, Object?>>> _selectRows(
    AppDatabase database,
    String sql, {
    List<Variable<Object>> variables = const <Variable<Object>>[],
  }) async {
    final rows = await database.customSelect(sql, variables: variables).get();
    return <Map<String, Object?>>[
      for (final row in rows) Map<String, Object?>.from(row.data),
    ];
  }

  static Set<String> _assetIdsFromPart(Map<String, Object?> row) {
    if (row['kind'] != 'image' && row['kind'] != 'file') {
      return const <String>{};
    }
    final payload = row['payload'];
    if (payload is! String) return const <String>{};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['assetId'] is String) {
        final id = (decoded['assetId'] as String).trim();
        return id.isEmpty ? const <String>{} : <String>{id};
      }
    } catch (_) {}
    return const <String>{};
  }

  static Map<String, Object?> _portableMessagePart(
    Map<String, Object?> row, {
    required Set<String> availableAssetIds,
    required List<String> unsupported,
  }) {
    if (row['kind'] != 'image' && row['kind'] != 'file') return row;
    final payload = row['payload'];
    if (payload is! String) {
      unsupported.add('malformed_attachment_part');
      return _unavailableAttachmentPart(row);
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        unsupported.add('malformed_attachment_part');
        return _unavailableAttachmentPart(row, sourcePayload: payload);
      }
      final safePayload = Map<String, Object?>.from(decoded);
      final assetId = safePayload['assetId'];
      final uri = safePayload['uri'];
      if (row['kind'] == 'file' &&
          (safePayload['name'] is! String ||
              (safePayload['name'] as String).isEmpty)) {
        safePayload['name'] = 'Unavailable attachment';
      }
      if (assetId is String && assetId.trim().isNotEmpty) {
        safePayload['uri'] = 'asset://${assetId.trim()}';
        if (!availableAssetIds.contains(assetId.trim())) {
          safePayload['unavailable'] = true;
          unsupported.add('attachment_asset_unavailable');
        }
      } else if (uri is String &&
          (uri.startsWith('http://') ||
              uri.startsWith('https://') ||
              uri.startsWith('data:') ||
              uri.startsWith('asset://'))) {
        // Remote/data URIs are portable and do not expose an app-local path.
      } else {
        safePayload['uri'] = 'orvia-unavailable://attachment';
        safePayload['unavailable'] = true;
        unsupported.add('attachment_local_path_redacted');
      }
      return <String, Object?>{...row, 'payload': jsonEncode(safePayload)};
    } catch (_) {
      // Preserve a stable fingerprint without copying a malformed payload
      // that could contain a machine-local file path.
      unsupported.add('malformed_attachment_part');
      return _unavailableAttachmentPart(row, sourcePayload: payload);
    }
  }

  static Map<String, Object?> _unavailableAttachmentPart(
    Map<String, Object?> row, {
    String? sourcePayload,
  }) {
    final payload = <String, Object?>{
      'uri': 'orvia-unavailable://attachment',
      'unavailable': true,
      if (row['kind'] == 'file') 'name': 'Unavailable attachment',
      if (sourcePayload != null)
        'sourcePayloadSha256': sha256
            .convert(utf8.encode(sourcePayload))
            .toString(),
    };
    return <String, Object?>{...row, 'payload': jsonEncode(payload)};
  }

  static Future<_ExportedAssets> _exportAssets({
    required String rootPath,
    required Set<String> assetIds,
    required Map<String, Map<String, Object?>> assetRowsById,
    required Map<String, List<int>> entries,
    required List<String> unsupported,
  }) async {
    final metadata = <Map<String, Object?>>[];
    final availableIds = <String>{};
    for (final assetId in assetIds) {
      final row = assetRowsById[assetId];
      if (row == null) {
        unsupported.add('attachment_asset_metadata_missing');
        metadata.add({'id': assetId, 'available': false});
        continue;
      }

      final hash = row['content_hash'];
      final storedPath = row['path'];
      final byteSize = row['byte_size'];
      var available = false;
      if (hash is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) &&
          storedPath is String &&
          storedPath.isNotEmpty &&
          byteSize is int &&
          byteSize >= 0 &&
          byteSize <= NativeTransferArchive.maxSingleEntryBytes) {
        try {
          final candidatePath = p.normalize(
            p.isAbsolute(storedPath)
                ? storedPath
                : p.join(rootPath, storedPath),
          );
          if (p.isWithin(rootPath, candidatePath)) {
            final candidate = File(candidatePath);
            if (await FileSystemEntity.type(
                  candidate.path,
                  followLinks: false,
                ) ==
                FileSystemEntityType.file) {
              final resolvedPath = await candidate.resolveSymbolicLinks();
              if (p.isWithin(rootPath, resolvedPath)) {
                final size = await candidate.length();
                if (size == byteSize) {
                  final bytes = await candidate.readAsBytes();
                  final actualHash = sha256.convert(bytes).toString();
                  if (actualHash == hash) {
                    entries.putIfAbsent('assets/$hash', () => bytes);
                    available = true;
                    availableIds.add(assetId);
                  }
                }
              }
            }
          }
        } catch (_) {
          // Treat unreadable, external, symlinked, or changed assets as missing.
        }
      }

      if (!available) {
        unsupported.add('attachment_asset_not_portable');
      }
      metadata.add({
        'id': assetId,
        'contentHash': hash,
        'byteSize': byteSize,
        'width': row['width'],
        'height': row['height'],
        'createdAt': row['created_at'],
        'available': available,
      });
    }

    return _ExportedAssets(metadata: metadata, availableIds: availableIds);
  }
}

final class _ExportedAssets {
  const _ExportedAssets({required this.metadata, required this.availableIds});

  final List<Map<String, Object?>> metadata;
  final Set<String> availableIds;
}
