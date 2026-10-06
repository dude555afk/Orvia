import 'dart:io';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/utils/kelivo_file_uri.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('sandbox path migration version', () {
    late Directory directory;
    late File dbFile;
    late ChatDatabaseRepository repository;
    var repositoryClosed = false;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'kelivo_sandbox_path_migration_',
      );
      dbFile = File('${directory.path}/chat.sqlite');
      repository = ChatDatabaseRepository.open(file: dbFile);
      repositoryClosed = false;
      await repository.ensureReady();
      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: 'conversation',
            title: 'Paths',
            messageIds: const ['plain', 'path'],
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: 'plain',
              conversationId: 'conversation',
              role: 'user',
              content: 'plain text',
            ),
            messageOrder: 0,
          ),
          (
            message: ChatMessage(
              id: 'path',
              conversationId: 'conversation',
              role: 'user',
              parts: const [ImagePart(uri: '/old/sandboxoldtoken/a.png')],
            ),
            messageOrder: 1,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );
    });

    tearDown(() async {
      if (!repositoryClosed) await repository.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('\u9996\u6B21\u6309\u6279\u8FC1\u79FB\u5E76\u5728\u540C\u4E00\u4E8B\u52A1\u5199 version receipt', () async {
      final result = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/new',
        batchSize: 1,
        rewriteUri: (uri) =>
            uri.replaceFirst('/old/sandboxoldtoken/', '/new/sandboxnewtoken/'),
      );

      expect(result.ran, isTrue);
      expect(result.scannedMessages, 1);
      expect(result.updatedMessages, 1);
      expect(result.skippedParts, 0);
      final migrated = (await repository.getMessagesRange(
        'conversation',
        start: 0,
        limit: 10,
      )).last;
      expect(
        migrated.parts.whereType<ImagePart>().single.uri,
        '/new/sandboxnewtoken/a.png',
      );
    });

    test('\u540C\u7248\u672C\u540E\u7EED\u542F\u52A8\u4E0D\u8BFB\u53D6\u5019\u9009\u6D88\u606F', () async {
      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/same',
        rewriteUri: (uri) => uri,
      );

      final result = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/same',
        rewriteUri: (_) => throw StateError('must_not_scan'),
      );

      expect(result.ran, isFalse);
      expect(result.scannedMessages, 0);
      expect(result.skippedParts, 0);
    });

    test('rewrite \u5931\u8D25\u56DE\u6EDA\u5185\u5BB9\u4E14\u4E0D\u5199 receipt，\u53EF\u91CD\u8BD5', () async {
      await expectLater(
        repository.migrateSandboxPaths(
          targetVersion: 1,
          targetRoot: '/new',
          rewriteUri: (_) => throw StateError('rewrite_failed'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'rewrite_failed',
          ),
        ),
      );

      final retry = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/new',
        rewriteUri: (uri) =>
            uri.replaceFirst('/old/sandboxoldtoken/', '/new/sandboxnewtoken/'),
      );
      expect(retry.ran, isTrue);
      expect(retry.updatedMessages, 1);
    });

    test('\u540C\u7248\u672C\u76EE\u6807\u6839\u53D8\u5316\u65F6\u91CD\u65B0\u6267\u884C\u4E00\u6B21', () async {
      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/first',
        rewriteUri: (uri) => uri,
      );

      final result = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/second',
        rewriteUri: (uri) => uri.replaceFirst(
          '/old/sandboxoldtoken/',
          '/second/sandboxnewtoken/',
        ),
      );

      expect(result.ran, isTrue);
      expect(result.updatedMessages, 1);
    });

    test('\u635F\u574F\u9644\u4EF6\u4E0D\u963B\u585E\u8FC1\u79FB\u5E76\u4FDD\u6301\u539F payload \u4E0E dirty \u72B6\u6001', () async {
      const malformedPayload =
          '{"uri":"/old/sandboxoldtoken/a.png","mime":["/private/secret"]}';
      final database = sqlite.sqlite3.open(dbFile.path);
      try {
        database.execute(
          'UPDATE message_part_rows SET payload = ? '
          "WHERE revision_id = 'path' AND kind = 'image';",
          [malformedPayload],
        );
        database.execute(
          "DELETE FROM asset_reference_dirty_rows WHERE revision_id = 'path';",
        );
      } finally {
        database.close();
      }

      final result = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/new',
        rewriteUri: (uri) =>
            uri.replaceFirst('/old/sandboxoldtoken/', '/new/sandboxnewtoken/'),
      );

      expect(result.ran, isTrue);
      expect(result.scannedMessages, 1);
      expect(result.updatedMessages, 0);
      expect(result.skippedParts, 1);

      final verify = sqlite.sqlite3.open(dbFile.path);
      try {
        expect(
          verify
              .select(
                "SELECT payload FROM message_part_rows WHERE revision_id = 'path';",
              )
              .single['payload'],
          malformedPayload,
        );
        expect(
          verify.select(
            "SELECT 1 FROM asset_reference_dirty_rows WHERE revision_id = 'path';",
          ),
          hasLength(1),
        );
        expect(
          verify.select(
            "SELECT 1 FROM chat_storage_meta_rows "
            "WHERE key = 'sandbox_path_migration_version';",
          ),
          hasLength(1),
        );
      } finally {
        verify.close();
      }
    });

    test('\u8DEF\u5F84\u91CD\u5199\u540E ImagePart URI \u66F4\u65B0\u4E14 FTS \u7D22\u5F15\u5B8C\u6574', () async {
      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/new',
        rewriteUri: (uri) =>
            uri.replaceFirst('/old/sandboxoldtoken/', '/new/sandboxnewtoken/'),
      );

      final migrated = (await repository.getMessagesRange(
        'conversation',
        start: 0,
        limit: 10,
      )).last;
      expect(
        migrated.parts.whereType<ImagePart>().single.uri,
        '/new/sandboxnewtoken/a.png',
      );
      // Text remains searchable; attachment URIs live outside text FTS.
      expect(
        (await repository.searchConversationMatches(
          tokens: const ['plain'],
        )).single.messageId,
        'plain',
      );

      // Force FTS setup path, then integrity-check on a raw connection.
      await repository.searchConversationMatches(
        tokens: const ['__fts_integrity__'],
      );
      await repository.close();
      repositoryClosed = true;
      final database = sqlite.sqlite3.open(dbFile.path);
      try {
        database.execute(
          "INSERT INTO message_search_fts(message_search_fts) "
          "VALUES('integrity-check');",
        );
      } finally {
        database.close();
      }
    });

    test(
      'stale unavailable cleared when rewritten local file exists',
      () async {
        final newFile = File('${directory.path}/sandboxnewtoken/a.png');
        await newFile.parent.create(recursive: true);
        await newFile.writeAsBytes(const <int>[0x89, 0x50, 0x4E, 0x47]);

        await repository.putMigrationBatch(
          conversations: [
            Conversation(
              id: 'unavailable-conversation',
              title: 'Unavailable',
              messageIds: const ['unavailable-path'],
            ),
          ],
          messages: [
            (
              message: ChatMessage(
                id: 'unavailable-path',
                conversationId: 'unavailable-conversation',
                role: 'user',
                parts: [
                  ImagePart(
                    uri: '/old/sandboxoldtoken/a.png',
                    unavailable: true,
                  ),
                ],
              ),
              messageOrder: 0,
            ),
          ],
          toolEventsByMessageId: const {},
          geminiSignaturesByMessageId: const {},
        );

        await repository.migrateSandboxPaths(
          targetVersion: 1,
          targetRoot: directory.path,
          rewriteUri: (uri) => uri.replaceFirst(
            '/old/sandboxoldtoken/',
            '${directory.path}/sandboxnewtoken/',
          ),
        );

        final migrated = (await repository.getMessagesRange(
          'unavailable-conversation',
          start: 0,
          limit: 10,
        )).single;
        final image = migrated.parts.whereType<ImagePart>().single;
        expect(image.uri, newFile.path);
        expect(image.unavailable, isFalse);
      },
    );

    test('kelivo-file URI stays canonical when targetRoot changes', () async {
      final uploadDir = Directory('${directory.path}/upload')
        ..createSync(recursive: true);
      final file = File('${uploadDir.path}/canon.png')
        ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47]);
      SandboxPathResolver.debugSetDirs(docsDir: directory.path);
      addTearDown(() {
        SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
      });

      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: 'canon-conversation',
            title: 'Canon',
            messageIds: const ['canon-msg'],
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: 'canon-msg',
              conversationId: 'canon-conversation',
              role: 'user',
              parts: [
                ImagePart(
                  uri: 'kelivo-file:///upload/canon.png',
                  unavailable: true,
                ),
              ],
            ),
            messageOrder: 0,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );

      // Prior receipt with a different root forces a re-run.
      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/old-root',
        rewriteUri: (uri) => KelivoFileUri.isKelivoFileUri(uri) ? uri : uri,
      );

      final result = await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: directory.path,
        rewriteUri: (uri) => KelivoFileUri.isKelivoFileUri(uri)
            ? uri
            : SandboxPathResolver.fix(uri),
      );

      expect(result.ran, isTrue);
      final migrated = (await repository.getMessagesRange(
        'canon-conversation',
        start: 0,
        limit: 10,
      )).single;
      final image = migrated.parts.whereType<ImagePart>().single;
      expect(image.uri, 'kelivo-file:///upload/canon.png');
      expect(image.unavailable, isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('kelivo-file unavailable recomputed when file missing', () async {
      SandboxPathResolver.debugSetDirs(docsDir: directory.path);
      addTearDown(() {
        SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
      });

      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: 'missing-canon',
            title: 'Missing',
            messageIds: const ['missing-msg'],
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: 'missing-msg',
              conversationId: 'missing-canon',
              role: 'user',
              parts: const [
                ImagePart(
                  uri: 'kelivo-file:///upload/does-not-exist.png',
                  unavailable: false,
                ),
              ],
            ),
            messageOrder: 0,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );

      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: '/previous-root',
        rewriteUri: (uri) => KelivoFileUri.isKelivoFileUri(uri) ? uri : uri,
      );

      await repository.migrateSandboxPaths(
        targetVersion: 1,
        targetRoot: directory.path,
        rewriteUri: (uri) => KelivoFileUri.isKelivoFileUri(uri)
            ? uri
            : SandboxPathResolver.fix(uri),
      );

      final migrated = (await repository.getMessagesRange(
        'missing-canon',
        start: 0,
        limit: 10,
      )).single;
      final image = migrated.parts.whereType<ImagePart>().single;
      expect(image.uri, 'kelivo-file:///upload/does-not-exist.png');
      expect(image.unavailable, isTrue);
    });

    test(
      'canonicalize rewrite persists kelivo-file and skips UNC I/O',
      () async {
        final docs = Directory('${directory.path}/docs')..createSync();
        final upload = Directory('${docs.path}/upload')..createSync();
        final file = File('${upload.path}/a.png')
          ..writeAsBytesSync(const [1, 2, 3]);
        SandboxPathResolver.debugSetDirs(docsDir: docs.path);
        addTearDown(() => SandboxPathResolver.debugSetDirs());

        final now = DateTime.utc(2026, 1, 1);
        await repository.putMigrationBatch(
          conversations: [
            Conversation(
              id: 'canon-conversation',
              title: 'Canon',
              createdAt: now,
              updatedAt: now,
              messageIds: const ['canon-msg'],
            ),
          ],
          messages: [
            (
              message: ChatMessage(
                id: 'canon-msg',
                conversationId: 'canon-conversation',
                role: 'user',
                content: '',
                timestamp: now,
                parts: [
                  ImagePart(uri: file.path, mime: 'image/png'),
                  ImagePart(
                    uri: 'file://attacker/share/a.png',
                    mime: 'image/png',
                    unavailable: false,
                  ),
                ],
              ),
              messageOrder: 0,
            ),
          ],
          toolEventsByMessageId: const {},
          geminiSignaturesByMessageId: const {},
        );

        final result = await repository.migrateSandboxPaths(
          targetVersion: 1,
          targetRoot: docs.path,
          rewriteUri: SandboxPathResolver.canonicalize,
        );
        expect(result.ran, isTrue);

        final migrated = (await repository.getMessagesRange(
          'canon-conversation',
          start: 0,
          limit: 10,
        )).single;
        final parts = migrated.parts.whereType<ImagePart>().toList();
        expect(parts[0].uri, 'kelivo-file:///upload/a.png');
        expect(parts[0].unavailable, isFalse);
        expect(parts[1].uri, 'file://attacker/share/a.png');
        expect(parts[1].unavailable, isTrue);
      },
    );

    test('\u62D2\u7EDD\u9AD8\u4E8E\u5F53\u524D\u5B9E\u73B0\u7684\u5DF2\u6709 migration version', () async {
      await repository.migrateSandboxPaths(
        targetVersion: 2,
        targetRoot: '/future',
        rewriteUri: (uri) => uri,
      );

      await expectLater(
        repository.migrateSandboxPaths(
          targetVersion: 1,
          targetRoot: '/current',
          rewriteUri: (uri) => uri,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'sandbox_path_migration_version',
          ),
        ),
      );
    });
  });
}
