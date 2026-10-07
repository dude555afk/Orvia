import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/database_installation_gate.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('DatabaseInstallationGate', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'kelivo_database_installation_',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    File databaseFile(Directory root) =>
        File(p.join(root.path, AppDatabase.databaseFileName));

    test(
      '\u9996\u6B21\u5B89\u88C5\u521B\u5EFA\u5E26 identity \u7684\u6570\u636E\u5E93\u4E0E receipt',
      () async {
        final receipt = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );

        expect(await databaseFile(directory).exists(), isTrue);
        final info = ChatDatabaseRepository.inspectInstalledDatabase(
          databaseFile(directory),
        );
        expect(info.databaseId, receipt.databaseId);
        expect(
          (await DatabaseInstallationGate.read(
            appDataDirectory: directory,
          ))?.installationId,
          receipt.installationId,
        );
      },
    );

    test(
      '\u6B8B\u7559\u7684 publish \u4E34\u65F6\u6587\u4EF6\u4E0D\u4F1A\u963B\u585E\u9996\u6B21\u5B89\u88C5',
      () async {
        // Simulate a crash between temp creation and rename during a previous
        // publish attempt, using the legacy fixed temp name. The leftover must
        // not brick the next launch and should be swept.
        final legacyTemp = File(
          p.join(directory.path, '.database_installation_receipt.tmp'),
        );
        await legacyTemp.create();

        final receipt = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );

        expect(receipt.databaseId, isNotEmpty);
        // The stale temp is swept and a real receipt is published.
        expect(await legacyTemp.exists(), isFalse);
        final receiptCount = directory
            .listSync()
            .where(
              (entity) =>
                  p
                      .basename(entity.path)
                      .startsWith('database_installation_receipt_') &&
                  entity.path.endsWith('.json'),
            )
            .length;
        expect(receiptCount, 1);
      },
    );

    test(
      'identity \u4E00\u81F4\u7684\u91CD\u590D\u542F\u52A8\u4E0D\u6539 receipt',
      () async {
        final first = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );
        final second = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );

        expect(second.installationId, first.installationId);
        expect(second.databaseId, first.databaseId);
      },
    );

    test(
      '\u5347\u7EA7\u65F6 adoption \u5DF2\u6709\u6709\u6548\u6570\u636E\u5E93\u4E14\u4E0D\u6E05\u7A7A\u6570\u636E',
      () async {
        final repository = ChatDatabaseRepository.open(
          file: databaseFile(directory),
        );
        try {
          await repository.ensureReady();
        } finally {
          await repository.close();
        }
        final before = sqlite.sqlite3.open(databaseFile(directory).path);
        before.execute(
          'INSERT INTO chat_storage_meta_rows (key, value) VALUES (?, ?);',
          ['upgrade_sentinel', 'keep'],
        );
        before.close();

        final receipt = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );

        expect(receipt.databaseId, isNotEmpty);
        expect(
          ChatDatabaseRepository.inspectInstalledDatabase(
            databaseFile(directory),
          ).databaseId,
          receipt.databaseId,
        );
        final after = sqlite.sqlite3.open(
          databaseFile(directory).path,
          mode: sqlite.OpenMode.readOnly,
        );
        try {
          expect(
            after.select(
              'SELECT value FROM chat_storage_meta_rows WHERE key = ?;',
              ['upgrade_sentinel'],
            ).single['value'],
            'keep',
          );
        } finally {
          after.close();
        }
      },
    );

    test(
      '\u5DF2\u6709 receipt \u4F46\u6570\u636E\u5E93\u7F3A\u5931\u65F6\u62D2\u7EDD\u4E14\u4E0D\u521B\u5EFA\u7A7A\u5E93',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        await databaseFile(directory).delete();

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'database_missing',
            ),
          ),
        );
        expect(await databaseFile(directory).exists(), isFalse);
      },
    );

    test(
      '\u635F\u574F\u6570\u636E\u5E93\u5728\u65E0 receipt \u5347\u7EA7\u573A\u666F\u4E5F\u62D2\u7EDD\u4E14\u4E0D\u8986\u76D6',
      () async {
        final file = databaseFile(directory);
        await file.writeAsString('not a sqlite database');

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'database_corrupt',
            ),
          ),
        );
        expect(await file.readAsString(), 'not a sqlite database');
      },
    );

    test(
      '\u9AD8\u4E8E\u5F53\u524D schema \u7684\u6570\u636E\u5E93\u62D2\u7EDD down migration',
      () async {
        final file = databaseFile(directory);
        final raw = sqlite.sqlite3.open(file.path);
        raw.userVersion = AppDatabase.currentSchemaVersion + 1;
        raw.close();

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'database_schema_too_new',
            ),
          ),
        );
      },
    );

    test(
      '\u635F\u574F installation receipt \u65F6\u62D2\u7EDD\u6253\u5F00\u6570\u636E\u5E93',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final receipt = directory.listSync().whereType<File>().singleWhere(
          (file) => p
              .basename(file.path)
              .startsWith('database_installation_receipt_'),
        );
        await receipt.writeAsString('{broken');

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      '\u672A\u6388\u6743\u7684\u6570\u636E\u5E93 identity \u66FF\u6362\u88AB\u62D2\u7EDD',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final originalReceipt = await DatabaseInstallationGate.read(
          appDataDirectory: directory,
        );
        final replacementRoot = await Directory.systemTemp.createTemp(
          'kelivo_database_replacement_',
        );
        addTearDown(() async {
          if (await replacementRoot.exists()) {
            await replacementRoot.delete(recursive: true);
          }
        });
        await DatabaseInstallationGate.ensureReady(
          appDataDirectory: replacementRoot,
        );
        await databaseFile(directory).delete();
        await databaseFile(replacementRoot).copy(databaseFile(directory).path);

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'database_identity_mismatch',
            ),
          ),
        );
        expect(
          File(
            p.join(
              directory.path,
              'database_installation_receipt_${originalReceipt!.databaseId}.json',
            ),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'identity \u66FF\u6362\u4E0D\u4EE5\u5168\u5E93 FK \u626B\u63CF\u963B\u585E\u542F\u52A8\u95E8',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final replacementRoot = await Directory.systemTemp.createTemp(
          'kelivo_database_replacement_corrupt_',
        );
        addTearDown(() async {
          if (await replacementRoot.exists()) {
            await replacementRoot.delete(recursive: true);
          }
        });
        await DatabaseInstallationGate.ensureReady(
          appDataDirectory: replacementRoot,
        );
        final replacement = databaseFile(replacementRoot);
        final raw = sqlite.sqlite3.open(replacement.path);
        raw.execute(
          'INSERT INTO conversation_mcp_server_rows '
          '(conversation_id, server_id, ordinal) VALUES (?, ?, ?);',
          ['missing-conversation', 'server', 0],
        );
        raw.close();
        await databaseFile(directory).delete();
        await replacement.copy(databaseFile(directory).path);

        await expectLater(
          DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'database_identity_mismatch',
            ),
          ),
        );
      },
    );

    test(
      '\u5DF2\u9A8C\u8BC1 restore \u53EF\u8F6E\u6362 database identity \u5E76\u4FDD\u7559 installation',
      () async {
        final original = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );
        final replacementRoot = await Directory.systemTemp.createTemp(
          'kelivo_database_restore_',
        );
        addTearDown(() async {
          if (await replacementRoot.exists()) {
            await replacementRoot.delete(recursive: true);
          }
        });
        final replacement = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: replacementRoot,
        );
        await databaseFile(directory).delete();
        await databaseFile(replacementRoot).copy(databaseFile(directory).path);

        final updated = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
          allowDatabaseIdentityChange: true,
        );

        expect(updated.installationId, original.installationId);
        expect(updated.databaseId, replacement.databaseId);
      },
    );

    test(
      '\u5E9F\u5F03\u7684 session receipt \u4E0D\u53C2\u4E0E\u542F\u52A8\u5224\u5B9A',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final sessionFile = File(
          p.join(directory.path, '.database_session_receipt.json'),
        );
        await sessionFile.writeAsString('{broken', flush: true);

        final receipt = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );

        expect(receipt.databaseId, isNotEmpty);
        expect(await databaseFile(directory).exists(), isTrue);
        expect(await sessionFile.readAsString(), '{broken');
      },
    );

    group('recoveryActionFor', () {
      test(
        'database_schema_too_new \u6620\u5C04\u4E3A\u5347\u7EA7\u63D0\u793A',
        () async {
          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_too_new'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.promptUpgrade);
        },
      );

      test(
        '\u4E0E\u6570\u636E\u5E93\u65E0\u5173\u7684\u9519\u8BEF\u4E0D\u89E6\u53D1\u6062\u590D',
        () async {
          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('filesystem'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u5DF2\u6709 receipt \u7684\u635F\u574F\u5E93\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_corrupt'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u65E0\u6CD5\u89E3\u6790\u7684 receipt \u540C\u6837\u963B\u6B62\u81EA\u52A8\u91CD\u5EFA',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final receipt = directory.listSync().whereType<File>().singleWhere(
            (file) => p
                .basename(file.path)
                .startsWith('database_installation_receipt_'),
          );
          await receipt.writeAsString('{broken');

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_corrupt'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u65E0 receipt \u4E14 Hive \u6E90\u5728\u65F6\u5F15\u5BFC\u91CD\u8FC1\u79FB',
        () async {
          await databaseFile(directory).writeAsString('not a sqlite database');

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_corrupt'),
            legacyHiveDataPresent: true,
          );

          expect(action, DatabaseRecoveryAction.promptRemigration);
        },
      );

      test(
        '\u539F\u59CB sqlite \u9519\u8BEF\u4EC5\u5728\u53EF\u91CD\u8FC1\u79FB\u65F6\u5F15\u5BFC',
        () async {
          final rawError = sqlite.SqliteException(
            extendedResultCode: 11,
            message: 'database disk image is malformed',
          );

          final withHive = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: rawError,
            legacyHiveDataPresent: true,
          );
          final withoutHive = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: rawError,
            legacyHiveDataPresent: false,
          );

          expect(withHive, DatabaseRecoveryAction.promptRemigration);
          expect(withoutHive, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u9996\u542F\u534A\u6210\u54C1\u5E93（userVersion=0）\u53EF\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.rebuildAutomatically);
        },
      );

      test(
        '\u5217\u51FA\u6539\u540D\u526F\u672C\u65F6\u6309\u65F6\u95F4\u5012\u5E8F\u5E76\u7B97\u4E0A\u6574\u4E2A family',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final base = databaseFile(directory);
          await File('${base.path}-wal').writeAsBytes(List<int>.filled(32, 7));

          for (final receipt in await directory.list().toList()) {
            if (p.basename(receipt.path).startsWith('database_installation_')) {
              await receipt.delete();
            }
          }
          await DatabaseInstallationGate.rebuildFresh(
            appDataDirectory: directory,
          );

          final copies = await DatabaseInstallationGate.listDisplacedDatabases(
            appDataDirectory: directory,
          );

          expect(copies, hasLength(1));
          expect(copies.single.displacedAt, isNotNull);
          expect(await copies.single.file.exists(), isTrue);
          // -wal \u4E5F\u7B97\u8FDB\u53BB，\u4E0D\u7136\u663E\u793A\u7684\u5927\u5C0F\u4F1A\u5C0F\u4E8E\u771F\u6B63\u5360\u7684\u7A7A\u95F4。
          expect(
            copies.single.bytes,
            greaterThan(await copies.single.file.length()),
          );
        },
      );

      test(
        '\u5220\u9664\u5355\u4EFD\u6539\u540D\u526F\u672C\u4F1A\u8FDE sidecar \u4E00\u8D77\u6E05\u6389',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final base = databaseFile(directory);
          await File('${base.path}-wal').writeAsBytes(List<int>.filled(32, 7));
          for (final receipt in await directory.list().toList()) {
            if (p.basename(receipt.path).startsWith('database_installation_')) {
              await receipt.delete();
            }
          }
          await DatabaseInstallationGate.rebuildFresh(
            appDataDirectory: directory,
          );
          final copy = (await DatabaseInstallationGate.listDisplacedDatabases(
            appDataDirectory: directory,
          )).single;

          await DatabaseInstallationGate.deleteDisplacedDatabase(
            appDataDirectory: directory,
            stamp: copy.stamp,
          );

          expect(
            await DatabaseInstallationGate.listDisplacedDatabases(
              appDataDirectory: directory,
            ),
            isEmpty,
          );
          expect(await File('${copy.file.path}-wal').exists(), isFalse);
          expect(
            await DatabaseInstallationGate.hasDisplacedDatabases(
              appDataDirectory: directory,
            ),
            isFalse,
          );
        },
      );

      test('\u62D2\u7EDD\u4F2A\u9020\u7684 stamp', () async {
        await expectLater(
          DatabaseInstallationGate.deleteDisplacedDatabase(
            appDataDirectory: directory,
            stamp: '../../etc',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        '\u65E0\u6CD5\u8BFB\u53D6 userVersion \u7684\u6587\u4EF6\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          // "Unreadable right now" is also what a healthy database looks like
          // while the OS denies the read, so it may never authorise a delete.
          await databaseFile(directory).writeAsString('not a sqlite database');

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_corrupt'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u5B58\u5728\u975E\u7A7A WAL \u65F6\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();
          await File(
            '${databaseFile(directory).path}-wal',
          ).writeAsBytes(List<int>.filled(64, 0));

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u5B58\u5728\u7528\u6237\u6587\u4EF6\u65F6\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();
          final images = Directory(p.join(directory.path, 'images'));
          await images.create(recursive: true);
          await File(
            p.join(images.path, 'img_1.png'),
          ).writeAsBytes(const [1, 2]);

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u5B58\u5728\u672C\u5730\u526F\u672C\u65F6\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();
          final snapshots = Directory(
            p.join(directory.path, LocalSnapshotPaths.directoryName),
          );
          await snapshots.create(recursive: true);
          await File(
            p.join(
              snapshots.path,
              LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 5, 1)),
            ),
          ).writeAsString('archive');

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u7A7A\u7684\u7528\u6237\u76EE\u5F55\u4E0D\u7B97\u4F7F\u7528\u75D5\u8FF9',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();
          await Directory(p.join(directory.path, 'images')).create();
          await Directory(p.join(directory.path, 'upload')).create();

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.rebuildAutomatically);
        },
      );

      test(
        '\u5148\u524D\u7684 displaced \u526F\u672C\u963B\u6B62\u518D\u6B21\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.close();
          await File(
            '${databaseFile(directory).path}'
            '${DatabaseInstallationGate.displacedDatabasePrefix}'
            '0000000000000001',
          ).writeAsString('older generation');

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );

      test(
        '\u5DF2\u5EFA schema \u7684\u5E93\u5373\u4F7F\u65E0 receipt \u4E5F\u4E0D\u81EA\u52A8\u91CD\u5EFA',
        () async {
          final repository = ChatDatabaseRepository.open(
            file: databaseFile(directory),
          );
          try {
            await repository.ensureReady();
          } finally {
            await repository.close();
          }
          final raw = sqlite.sqlite3.open(databaseFile(directory).path);
          raw.userVersion = 1;
          raw.close();

          final action = await DatabaseInstallationGate.recoveryActionFor(
            appDataDirectory: directory,
            error: StateError('database_schema_version'),
            legacyHiveDataPresent: false,
          );

          expect(action, DatabaseRecoveryAction.none);
        },
      );
    });

    group('rebuildFresh', () {
      List<String> displacedNames(Directory root) =>
          root
              .listSync(followLinks: false)
              .map((entity) => p.basename(entity.path))
              .where(
                (name) => name.startsWith(
                  '${AppDatabase.databaseFileName}'
                  '${DatabaseInstallationGate.displacedDatabasePrefix}',
                ),
              )
              .toList()
            ..sort();

      test(
        '\u66FF\u6362\u6B8B\u7F3A\u5E93\u5E76\u7B7E\u53D1\u65B0 receipt',
        () async {
          final file = databaseFile(directory);
          await file.writeAsString('not a sqlite database');
          await File('${file.path}-wal').writeAsString('stale wal');

          final receipt = await DatabaseInstallationGate.rebuildFresh(
            appDataDirectory: directory,
          );

          final info = ChatDatabaseRepository.inspectInstalledDatabase(file);
          expect(info.databaseId, receipt.databaseId);
          expect(
            (await DatabaseInstallationGate.read(
              appDataDirectory: directory,
            ))?.installationId,
            receipt.installationId,
          );
        },
      );

      test(
        '\u9ED8\u8BA4\u4FDD\u7559\u6574\u5957\u65E7\u5E93\u800C\u4E0D\u662F\u5220\u9664',
        () async {
          final file = databaseFile(directory);
          await file.writeAsString('not a sqlite database');
          await File('${file.path}-wal').writeAsString('stale wal');
          await File('${file.path}-shm').writeAsString('stale shm');

          await DatabaseInstallationGate.rebuildFresh(
            appDataDirectory: directory,
          );

          final names = displacedNames(directory);
          expect(names, hasLength(3));
          final base = names.firstWhere(
            (name) => !name.endsWith('-wal') && !name.endsWith('-shm'),
          );
          expect(
            await File(p.join(directory.path, base)).readAsString(),
            'not a sqlite database',
          );
          expect(
            await File(p.join(directory.path, '$base-wal')).readAsString(),
            'stale wal',
          );
        },
      );

      test(
        'preserveDisplacedCopy=false \u4E0D\u7559\u526F\u672C\u5E76\u6E05\u6389\u65E7\u526F\u672C',
        () async {
          final file = databaseFile(directory);
          await file.writeAsString('not a sqlite database');
          await File(
            '${file.path}${DatabaseInstallationGate.displacedDatabasePrefix}'
            '0000000000000001',
          ).writeAsString('older generation');

          await DatabaseInstallationGate.rebuildFresh(
            appDataDirectory: directory,
            preserveDisplacedCopy: false,
          );

          expect(displacedNames(directory), isEmpty);
        },
      );

      test(
        '\u526F\u672C\u4EE3\u6570\u6709\u4E0A\u9650，\u4F46\u6700\u65E7\u7684\u90A3\u4EE3\u6C38\u8FDC\u4FDD\u7559',
        () async {
          // The oldest generation holds what was on disk before anything started
          // displacing; a retrying caller must not be able to walk it off the
          // end of the window.
          for (var generation = 0; generation < 5; generation++) {
            // rebuildFresh is only ever reached with no receipt on disk (see
            // recoveryActionFor and StartupRecoveryService.reset), so clear the
            // one the previous round issued.
            for (final entity in directory.listSync(followLinks: false)) {
              if (p
                  .basename(entity.path)
                  .startsWith('database_installation_receipt_')) {
                entity.deleteSync();
              }
            }
            await databaseFile(
              directory,
            ).writeAsString('generation $generation');
            await DatabaseInstallationGate.rebuildFresh(
              appDataDirectory: directory,
            );
          }

          final names = displacedNames(directory);
          final bases = names
              .where((name) => !name.endsWith('-wal') && !name.endsWith('-shm'))
              .toList();
          expect(bases, hasLength(3));
          final contents = <String>[
            for (final base in bases)
              await File(p.join(directory.path, base)).readAsString(),
          ];
          expect(contents, contains('generation 0'));
          expect(contents, contains('generation 4'));
          expect(contents, isNot(contains('generation 1')));
        },
      );
    });

    group('\u8FC1\u79FB\u524D\u526F\u672C\u7684\u6E05\u626B', () {
      File backupFor(File database) => File(
        '${database.path}${ChatDatabaseRepository.premigrationBackupPrefix}1',
      );

      test(
        '\u6570\u636E\u5E93\u5065\u5EB7\u65F6\u5220\u9664\u526F\u672C',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);

          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          expect(await backup.exists(), isFalse);
        },
      );

      test(
        '\u6570\u636E\u5E93\u7F3A\u5931\u65F6\u7528\u526F\u672C\u6062\u590D，\u800C\u4E0D\u662F\u628A\u526F\u672C\u5220\u6389',
        () async {
          final receipt = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          // A crash after the rollback removed the database but before it wrote
          // the copy back: the copy is the only surviving good state.
          await file.delete();

          final recovered = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          expect(recovered.databaseId, receipt.databaseId);
          expect(await backup.exists(), isFalse);
          expect(
            ChatDatabaseRepository.inspectInstalledDatabase(file).databaseId,
            receipt.databaseId,
          );
        },
      );

      test(
        '\u6570\u636E\u5E93\u635F\u574F\u65F6\u540C\u6837\u7528\u526F\u672C\u6062\u590D',
        () async {
          final receipt = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          // A torn copy-back leaves a truncated file behind.
          await file.writeAsBytes(
            (await backup.readAsBytes()).sublist(0, 512),
            flush: true,
          );

          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          expect(await backup.exists(), isFalse);
          expect(
            ChatDatabaseRepository.inspectInstalledDatabase(file).databaseId,
            receipt.databaseId,
          );
        },
      );

      test(
        '\u7ED3\u6784\u7F3A\u5931（quick_check \u4ECD ok）\u65F6\u4E0D\u5220\u526F\u672C，\u800C\u662F\u56DE\u6EDA',
        () async {
          // A migration that commits but leaves the schema incomplete is
          // physically sound, so quick_check passes. Deleting the copy here
          // would throw away the only way back moments before
          // migrateInstalledDatabase notices the structure is wrong.
          final receipt = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          final raw = sqlite.sqlite3.open(file.path);
          try {
            raw.execute('DROP TABLE preference_rows;');
            raw.execute('PRAGMA wal_checkpoint(TRUNCATE);');
            final check = raw.select('PRAGMA quick_check;');
            expect(
              check.single.values.single,
              'ok',
              reason:
                  'the premise: physical integrity says nothing about schema',
            );
            expect(raw.userVersion, AppDatabase.currentSchemaVersion);
          } finally {
            raw.close();
          }

          final recovered = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          expect(recovered.databaseId, receipt.databaseId);
          expect(await backup.exists(), isFalse);
          final after = sqlite.sqlite3.open(
            file.path,
            mode: sqlite.OpenMode.readOnly,
          );
          try {
            expect(
              after
                  .select(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .map((row) => row['name']),
              contains('preference_rows'),
            );
          } finally {
            after.close();
          }
        },
      );

      test(
        '\u7A7A\u5E93（userVersion 0）\u7B97\u635F\u574F\u800C\u4E0D\u662F\u672A\u77E5\u7248\u672C',
        () async {
          final receipt = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          // A copy interrupted at the very start: a valid, empty SQLite file.
          await file.delete();
          final empty = sqlite.sqlite3.open(file.path);
          empty.close();

          final recovered = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          expect(recovered.databaseId, receipt.databaseId);
          expect(await backup.exists(), isFalse);
        },
      );

      test(
        '\u964D\u7EA7\u8FD0\u884C\u65F6\u4E0D\u62FF\u65E7\u526F\u672C\u8986\u76D6\u66F4\u9AD8\u7248\u672C\u7684\u6570\u636E\u5E93',
        () async {
          // A newer build migrated the database and crashed before deleting its
          // copy; this older build must not mistake "version I do not know" for
          // "damaged" and roll the user back.
          final receipt = await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          final raw = sqlite.sqlite3.open(file.path);
          try {
            raw.execute('CREATE TABLE future_rows (id TEXT PRIMARY KEY);');
            raw.userVersion = AppDatabase.currentSchemaVersion + 1;
          } finally {
            raw.close();
          }

          await expectLater(
            DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                'database_schema_too_new',
              ),
            ),
          );

          // Both files survive: the newer database is strictly ahead of the copy.
          expect(await backup.exists(), isTrue);
          final after = sqlite.sqlite3.open(
            file.path,
            mode: sqlite.OpenMode.readOnly,
          );
          try {
            expect(after.userVersion, AppDatabase.currentSchemaVersion + 1);
            expect(
              after
                  .select(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .map((row) => row['name']),
              contains('future_rows'),
            );
          } finally {
            after.close();
          }
          expect(receipt.databaseId, isNotEmpty);
        },
      );

      test(
        '\u56DE\u6EDA\u4E0D\u5220\u9664\u88AB\u8986\u76D6\u7684\u5E93，\u800C\u662F\u7559\u526F\u672C',
        () async {
          // classifyInstalledDatabase reports "unusable" for a file it merely
          // failed to open, so the rollback must stay reversible.
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final backup = backupFor(file);
          await file.copy(backup.path);
          await file.writeAsString('not a sqlite database');

          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );

          final displaced = directory
              .listSync(followLinks: false)
              .map((entity) => p.basename(entity.path))
              .where(
                (name) => name.startsWith(
                  '${AppDatabase.databaseFileName}'
                  '${DatabaseInstallationGate.displacedDatabasePrefix}',
                ),
              )
              .toList();
          expect(displaced, isNotEmpty);
          expect(
            await File(
              p.join(
                directory.path,
                displaced.firstWhere(
                  (name) => !name.endsWith('-wal') && !name.endsWith('-shm'),
                ),
              ),
            ).readAsString(),
            'not a sqlite database',
          );
        },
      );

      test(
        '\u56DE\u6EDA\u53CD\u590D\u5931\u8D25\u4E5F\u4E0D\u4F1A\u6324\u6389\u7528\u6237\u539F\u59CB\u6570\u636E\u90A3\u4E00\u4EE3',
        () async {
          // A rollback whose backup is itself unusable throws before deleting
          // the backup, so the sweep repeats on every launch and displaces
          // again each time. Generation 1 is the user's only real copy.
          final file = databaseFile(directory);
          await file.writeAsString('ORIGINAL USER DATA');
          await backupFor(file).writeAsString('BAD BACKUP');

          for (var attempt = 0; attempt < 5; attempt++) {
            await expectLater(
              DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
              throwsA(isA<StateError>()),
            );
          }

          final surviving = <String>[
            for (final entity in directory.listSync(followLinks: false))
              if (p
                  .basename(entity.path)
                  .startsWith(
                    '${AppDatabase.databaseFileName}'
                    '${DatabaseInstallationGate.displacedDatabasePrefix}',
                  ))
                await File(entity.path).readAsString(),
          ];
          expect(surviving, contains('ORIGINAL USER DATA'));
        },
      );

      test(
        '\u591A\u4E2A\u526F\u672C\u4E14\u6570\u636E\u5E93\u4E0D\u53EF\u7528\u65F6\u62D2\u7EDD\u731C\u6D4B',
        () async {
          await DatabaseInstallationGate.ensureReady(
            appDataDirectory: directory,
          );
          final file = databaseFile(directory);
          final first = backupFor(file);
          final second = File(
            '${file.path}${ChatDatabaseRepository.premigrationBackupPrefix}2',
          );
          await file.copy(first.path);
          await file.copy(second.path);
          await file.delete();

          await expectLater(
            DatabaseInstallationGate.ensureReady(appDataDirectory: directory),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                'database_premigration_ambiguous',
              ),
            ),
          );
          // Nothing is destroyed while the state is ambiguous.
          expect(await first.exists(), isTrue);
          expect(await second.exists(), isTrue);
        },
      );
    });
  });
}
