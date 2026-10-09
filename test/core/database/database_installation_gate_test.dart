import 'dart:io';

import 'package:orvia/core/database/app_database.dart';
import 'package:orvia/core/database/chat_database_repository.dart';
import 'package:orvia/core/database/database_installation_gate.dart';
import 'package:orvia/core/services/backup/local_snapshot_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('DatabaseInstallationGate', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'orvia_database_installation_',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    File databaseFile(Directory root) =>
        File(p.join(root.path, AppDatabase.databaseFileName));

    test(
      'First installation creates database with identity and receipt',
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
      'Stale publish temp files do not block first installation',
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
      'Restart with matching identity preserves receipt',
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
      'Upgrade adopts a valid existing database without clearing data',
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
      'Existing receipt with missing database rejects without creating empty database',
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
      'Corrupt database without receipt is rejected without overwrite during upgrade',
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
      'Database with newer schema rejects downgrade migration',
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
      'Corrupt installation receipt prevents opening database',
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
      'Unauthorized database identity replacement is rejected',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final originalReceipt = await DatabaseInstallationGate.read(
          appDataDirectory: directory,
        );
        final replacementRoot = await Directory.systemTemp.createTemp(
          'orvia_database_replacement_',
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
      'Identity replacement does not block installation gate on full FK scan',
      () async {
        await DatabaseInstallationGate.ensureReady(appDataDirectory: directory);
        final replacementRoot = await Directory.systemTemp.createTemp(
          'orvia_database_replacement_corrupt_',
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
      'Verified restore rotates database identity while preserving installation',
      () async {
        final original = await DatabaseInstallationGate.ensureReady(
          appDataDirectory: directory,
        );
        final replacementRoot = await Directory.systemTemp.createTemp(
          'orvia_database_restore_',
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
      'Obsolete session receipt does not affect startup decision',
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
        'database_schema_too_new maps to upgrade prompt',
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
        'Unrelated errors do not trigger recovery',
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
        'Corrupt database with receipt is not auto-rebuilt',
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
        'Unreadable receipt also blocks auto-rebuild',
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
        'Missing receipt with Hive source prompts re-migration',
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
        'Raw SQLite errors prompt re-migration only when possible',
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
        'Incomplete first-run database with userVersion zero can be rebuilt',
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
        'Lists renamed copies newest-first including sidecars',
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
          // Include -wal in reported size to avoid undercounting disk use.
          expect(
            copies.single.bytes,
            greaterThan(await copies.single.file.length()),
          );
        },
      );

      test(
        'Deleting renamed copy removes its sidecars',
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

      test('Rejects forged stamp', () async {
        await expectLater(
          DatabaseInstallationGate.deleteDisplacedDatabase(
            appDataDirectory: directory,
            stamp: '../../etc',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        'Unreadable userVersion prevents auto-rebuild',
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
        'Nonempty WAL prevents auto-rebuild',
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
        'Existing user files prevent auto-rebuild',
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
        'Existing local copies prevent auto-rebuild',
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
        'Empty user directory does not count as usage',
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
        'Displaced copy prevents another auto-rebuild',
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
        'Initialized schema is not rebuilt even without receipt',
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
        'Replaces incomplete database and issues new receipt',
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
        'Preserves old database family instead of deleting by default',
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
        'preserveDisplacedCopy false removes old copies',
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
        'Limits copy generations while preserving the oldest',
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

    group('Pre-migration backup cleanup', () {
      File backupFor(File database) => File(
        '${database.path}${ChatDatabaseRepository.premigrationBackupPrefix}1',
      );

      test(
        'Deletes backup when database is healthy',
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
        'Restores backup when database is missing instead of deleting it',
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
        'Restores backup when database is corrupt',
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
        'Rolls back missing schema even when quick_check passes',
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
        'Treats empty userVersion zero database as corrupt',
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
        'Downgrade does not overwrite a newer database with older copy',
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
        'Rollback preserves replaced database copy',
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
        'Repeated rollback failures never discard original user data',
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
        'Refuses to guess between copies when database is unavailable',
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
