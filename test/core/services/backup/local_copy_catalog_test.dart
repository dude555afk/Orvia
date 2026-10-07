import 'dart:io';

import 'package:orvia/core/database/app_database.dart';
import 'package:orvia/core/database/database_installation_gate.dart';
import 'package:orvia/core/services/backup/local_copy_catalog.dart';
import 'package:orvia/core/services/backup/local_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalCopyCatalog', () {
    late Directory root;
    late LocalSnapshotStore store;
    late LocalCopyCatalog catalog;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('orvia_local_copies_');
      store = LocalSnapshotStore(appDataDirectory: root);
      catalog = LocalCopyCatalog(appDataDirectory: root, store: store);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> publishSnapshot(DateTime at) async {
      final staged = File(
        p.join(root.path, 'staged_${at.microsecondsSinceEpoch}'),
      );
      await staged.writeAsString('archive');
      await store.publish(
        prepared: staged,
        createdAtUtc: at,
        origin: LocalSnapshotOrigin.automatic,
        conversationCount: 2,
        messageCount: 20,
      );
    }

    /// Produces a displaced family the way crash recovery does.
    Future<void> displaceOnce() async {
      await DatabaseInstallationGate.ensureReady(appDataDirectory: root);
      await for (final entity in root.list(followLinks: false)) {
        if (p.basename(entity.path).startsWith('database_installation_')) {
          await entity.delete();
        }
      }
      await DatabaseInstallationGate.rebuildFresh(appDataDirectory: root);
    }

    test(
      '\u4E24\u79CD\u526F\u672C\u5408\u6210\u4E00\u4E2A\u5217\u8868，\u6309\u65F6\u95F4\u5012\u5E8F',
      () async {
        await displaceOnce();
        await publishSnapshot(DateTime.utc(2020, 1, 1));

        final copies = await catalog.list();

        expect(copies, hasLength(2));
        // \u6539\u540D\u526F\u672C\u662F\u521A\u521A\u4EA7\u751F\u7684，\u6240\u4EE5\u6392\u5728 2020 \u5E74\u90A3\u4EFD\u5FEB\u7167\u524D\u9762。
        expect(copies.first.kind, LocalCopyKind.displaced);
        expect(copies.last.kind, LocalCopyKind.snapshot);
      },
    );

    test(
      '\u5FEB\u7167\u5E26\u5185\u5BB9\u8BA1\u6570，\u6539\u540D\u526F\u672C\u4E0D\u731C',
      () async {
        await displaceOnce();
        await publishSnapshot(DateTime.utc(2026, 5, 1));

        final copies = await catalog.list();
        final snapshot = copies.firstWhere(
          (copy) => copy.kind == LocalCopyKind.snapshot,
        );
        final displaced = copies.firstWhere(
          (copy) => copy.kind == LocalCopyKind.displaced,
        );

        expect(snapshot.messageCount, 20);
        expect(snapshot.isArchive, isTrue);
        expect(displaced.messageCount, isNull);
        expect(displaced.isArchive, isFalse);
      },
    );

    test(
      '\u5220\u9664\u6309\u79CD\u7C7B\u5206\u53D1\u5230\u5404\u81EA\u7684\u5F52\u5C5E\u5904',
      () async {
        await displaceOnce();
        await publishSnapshot(DateTime.utc(2026, 5, 1));

        for (final copy in await catalog.list()) {
          await catalog.delete(copy);
        }

        expect(await catalog.list(), isEmpty);
        expect(
          await DatabaseInstallationGate.hasDisplacedDatabases(
            appDataDirectory: root,
          ),
          isFalse,
        );
        // \u6D3B\u5E93\u4E0D\u53D7\u5F71\u54CD。
        expect(
          await File(p.join(root.path, AppDatabase.databaseFileName)).exists(),
          isTrue,
        );
      },
    );

    test(
      '\u7A7A\u76EE\u5F55\u8FD4\u56DE\u7A7A\u5217\u8868\u800C\u4E0D\u662F\u629B\u9519',
      () async {
        expect(await catalog.list(), isEmpty);
        expect(await catalog.totalBytes(), 0);
      },
    );
  });
}
