import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/database/app_database.dart';
import 'package:orvia/core/database/native_transfer_archive.dart';
import 'package:orvia/core/database/native_transfer_exporter.dart';

void main() {
  group('NativeTransferExporter', () {
    test(
      'exports a consistent Drift snapshot with conversation revisions',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'orvia-native-export-test-',
        );
        final databaseFile = File(
          '${directory.path}/${AppDatabase.databaseFileName}',
        );
        final database = AppDatabase.open(file: databaseFile);
        final createdAt = DateTime.utc(2026, 10, 1, 12);

        try {
          await database
              .into(database.conversationRows)
              .insert(
                ConversationRowsCompanion.insert(
                  id: 'conversation-one',
                  title: 'Migration fixture',
                  createdAt: createdAt,
                  updatedAt: createdAt,
                  assistantId: const Value('assistant-one'),
                  versionSelectionsJson: const Value('{"group-one":1}'),
                ),
              );
          await database
              .into(database.messageRows)
              .insert(
                MessageRowsCompanion.insert(
                  id: 'message-one',
                  conversationId: 'conversation-one',
                  role: 'user',
                  timestamp: createdAt,
                  messageOrder: 0,
                  groupId: const Value('group-one'),
                  version: const Value(1),
                ),
              );
          await database
              .into(database.messagePartRows)
              .insert(
                MessagePartRowsCompanion.insert(
                  conversationId: 'conversation-one',
                  revisionId: 'message-one',
                  ordinal: 0,
                  kind: 'text',
                  payload: 'Hello from Flutter Orvia',
                  createdAt: createdAt,
                  updatedAt: createdAt,
                ),
              );
        } finally {
          await database.close();
        }

        try {
          final bytes = await NativeTransferExporter.exportCurrentInstallation(
            sourceAppVersion: 'test-fixture',
            appDataDirectory: directory,
          );
          final transfer = NativeTransferArchive.decode(bytes);
          final conversationEntries = transfer.entries.entries
              .where((entry) => entry.key.startsWith('conversations/'))
              .toList();

          expect(conversationEntries, hasLength(1));
          final payload =
              jsonDecode(utf8.decode(conversationEntries.single.value))
                  as Map<String, dynamic>;
          expect(payload['conversation']['id'], 'conversation-one');
          expect(payload['messages'], hasLength(1));
          expect(payload['messages'].single['id'], 'message-one');
          expect(payload['messages'].single['group_id'], 'group-one');
          expect(payload['messageParts'], hasLength(1));
          expect(
            payload['messageParts'].single['payload'],
            'Hello from Flutter Orvia',
          );
          final entityCounts = Map<String, Object?>.from(
            transfer.manifest['entityCounts']! as Map,
          );
          expect(entityCounts['conversations'], 1);
          expect(entityCounts['messages'], 1);
        } finally {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        }
      },
    );

    test('redacts nested credentials but preserves ordinary settings', () {
      final redactedFields = <String>[];
      final result = NativeTransferExporter.redactSecretsForTesting(
        <String, Object?>{
          'provider_api_key': 'provider-secret',
          'rawConfig':
              '{"apiKey":"nested-secret","baseUrl":"https://example.invalid"}',
          'apiBaseUrl': 'https://example.invalid/v1',
          'tokenCount': 12,
          'settings': <String, Object?>{
            'accessToken': 'access-secret',
            'refresh_token': 'refresh-secret',
            'theme': 'dark',
          },
          'tools': <Object?>[
            <String, Object?>{
              'authorization': 'Bearer private',
              'name': 'calendar',
            },
          ],
        },
        redactedFields: redactedFields,
      );

      expect(result, {
        'apiBaseUrl': 'https://example.invalid/v1',
        'rawConfig': '{"baseUrl":"https://example.invalid"}',
        'tokenCount': 12,
        'settings': {'theme': 'dark'},
        'tools': [
          {'name': 'calendar'},
        ],
      });
      expect(redactedFields, hasLength(5));
      expect(
        redactedFields,
        containsAll([
          'root.provider_api_key',
          'root.rawConfig.apiKey',
          'root.settings.accessToken',
          'root.settings.refresh_token',
          'root.tools[0].authorization',
        ]),
      );
    });

    test('removes local device paths inside nested JSON settings', () {
      final result = NativeTransferExporter.redactDevicePathsForTesting(
        <String, Object?>{
          'workspace': <String, Object?>{
            'name': 'Project',
            'rootPath': '/data/user/0/com.example/files/project',
          },
          'serializedMounts':
              '[{"name":"shared","mountPath":"/storage/emulated/0"}]',
          'apiBaseUrl': 'https://example.invalid/v1',
        },
      );

      expect(result, {
        'workspace': {'name': 'Project'},
        'serializedMounts': '[{"name":"shared"}]',
        'apiBaseUrl': 'https://example.invalid/v1',
      });
    });

    test('redacts credential containers recursively in lists', () {
      final redactedFields = <String>[];
      final result = NativeTransferExporter.redactSecretsForTesting(
        <String, Object?>{
          'accounts': <Object?>[
            <String, Object?>{
              'username': 'person@example.invalid',
              'credentials': <String, Object?>{
                'password': 'hidden',
                'client_secret': 'hidden-too',
              },
            },
          ],
        },
        redactedFields: redactedFields,
      );

      expect(result, {
        'accounts': [
          {'username': 'person@example.invalid'},
        ],
      });
      expect(redactedFields, hasLength(1));
      expect(redactedFields.single, 'root.accounts[0].credentials');
    });
  });
}
