import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/backup/local_snapshot_retention.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_schedule.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalSnapshotStore', () {
    late Directory root;
    late LocalSnapshotStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_local_snapshot_');
      store = LocalSnapshotStore(appDataDirectory: root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<File> prepared(String content) async {
      final file = File(
        p.join(root.path, 'staged_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await file.writeAsString(content);
      return file;
    }

    Future<LocalSnapshotEntry> publish({
      required DateTime at,
      int messageCount = 10,
      LocalSnapshotOrigin origin = LocalSnapshotOrigin.automatic,
      bool pinned = false,
      String content = 'archive-bytes',
    }) async => store.publish(
      prepared: await prepared(content),
      createdAtUtc: at,
      origin: origin,
      pinned: pinned,
      conversationCount: 3,
      messageCount: messageCount,
      appVersion: '1.2.4+1',
    );

    test(
      '\u53D1\u5E03\u540E\u5F52\u6863\u4E0E\u5143\u6570\u636E\u90FD\u5728，\u4E14\u80FD\u8BFB\u56DE',
      () async {
        final at = DateTime.utc(2026, 5, 1);
        final entry = await publish(at: at);

        expect(await entry.file.exists(), isTrue);
        expect(p.dirname(entry.file.path), store.directory.path);

        final listed = await store.list();
        expect(listed, hasLength(1));
        expect(listed.single.createdAt, at);
        expect(listed.single.messageCount, 10);
        expect(listed.single.conversationCount, 3);
        expect(listed.single.appVersion, '1.2.4+1');
        expect(listed.single.origin, LocalSnapshotOrigin.automatic);
      },
    );

    test(
      '\u53D1\u5E03\u6D88\u8D39\u6389\u6E90\u6587\u4EF6，\u4E0D\u7559\u4E34\u65F6\u6B8B\u9AB8',
      () async {
        final source = await prepared('archive-bytes');
        await store.publish(
          prepared: source,
          createdAtUtc: DateTime.utc(2026, 5, 1),
          origin: LocalSnapshotOrigin.manual,
          conversationCount: 1,
          messageCount: 1,
        );

        expect(await source.exists(), isFalse);
        final names = await store.directory
            .list()
            .map((entity) => p.basename(entity.path))
            .toList();
        expect(
          names.where(
            (name) => name.startsWith(LocalSnapshotPaths.temporaryPrefix),
          ),
          isEmpty,
        );
      },
    );

    test(
      '\u7A7A\u5F52\u6863\u4E0D\u4E88\u53D1\u5E03，\u4E14\u4E0D\u7559\u4E0B\u534A\u4EFD\u5143\u6570\u636E',
      () async {
        final source = await prepared('');
        await expectLater(
          store.publish(
            prepared: source,
            createdAtUtc: DateTime.utc(2026, 5, 1),
            origin: LocalSnapshotOrigin.automatic,
            conversationCount: 0,
            messageCount: 0,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await store.list(), isEmpty);
        final leftovers = await store.directory
            .list()
            .map((entity) => p.basename(entity.path))
            .toList();
        expect(leftovers, isEmpty);
      },
    );

    test(
      '\u5143\u6570\u636E\u4E22\u4E86\u4E5F\u8981\u7167\u6837\u5217\u51FA，\u4E14\u4E0D\u88AB\u5F53\u6210\u7A7A\u526F\u672C\u6E05\u6389',
      () async {
        final entry = await publish(
          at: DateTime.utc(2026, 5, 1),
          messageCount: 0,
        );
        await File(
          '${entry.file.path}${LocalSnapshotPaths.metadataSuffix}',
        ).delete();

        final listed = await store.list();
        expect(listed, hasLength(1));
        // \u672A\u77E5\u4E0D\u7B49\u4E8E\u7A7A：0 \u4F1A\u8BA9\u4FDD\u7559\u7B56\u7565\u628A\u5B83\u5F53\u4F5C\u53EF\u4E22\u5F03\u7684。
        expect(listed.single.messageCount, greaterThan(0));
      },
    );

    test(
      '\u6062\u590D\u524D\u526F\u672C\u521B\u5EFA\u65F6\u5373 pinned',
      () async {
        final entry = await publish(
          at: DateTime.utc(2026, 5, 1),
          origin: LocalSnapshotOrigin.beforeRestore,
          pinned: true,
        );
        expect(entry.retention.pinned, isTrue);
      },
    );

    test(
      '\u6062\u590D\u524D\u526F\u672C\u53EF\u4EE5\u88AB\u53D6\u6D88\u4FDD\u7559，\u4E0D\u7136\u4F1A\u6C38\u4E45\u5806\u79EF',
      () async {
        // pinned \u82E5\u4ECE origin \u53CD\u63A8，\u53D6\u6D88\u4FDD\u7559\u7684\u6309\u94AE\u5C31\u662F\u6B7B\u7684，\u800C\u4E14\u6BCF\u6062\u590D\u4E00\u6B21\u5C31\u591A
        // \u4E00\u4EFD\u4FDD\u7559\u7B56\u7565\u6C38\u8FDC\u65E0\u6743\u56DE\u6536\u7684\u526F\u672C。
        final entry = await publish(
          at: DateTime.utc(2026, 5, 1),
          origin: LocalSnapshotOrigin.beforeRestore,
          pinned: true,
        );

        await store.setPinned(entry.id, false);

        final listed = await store.list();
        expect(listed.single.pinned, isFalse);
        expect(listed.single.retention.pinned, isFalse);
      },
    );

    test(
      '\u6E05\u7406\u6309\u7B56\u7565\u5220\u9664，\u4E14\u5143\u6570\u636E\u4E00\u8D77\u5220\u6389',
      () async {
        for (var day = 1; day <= 5; day++) {
          await publish(at: DateTime.utc(2026, 5, day));
        }
        expect(await store.list(), hasLength(5));

        final removed = await store.prune(
          const LocalSnapshotRetentionPolicy(
            keepRecent: 2,
            keepWeekly: false,
            keepMonthly: false,
          ),
          now: DateTime.utc(2026, 5, 6),
        );

        expect(removed, hasLength(3));
        expect(await store.list(), hasLength(2));
        final remaining = await store.directory
            .list()
            .map((entity) => p.basename(entity.path))
            .toList();
        // \u6BCF\u4EFD\u526F\u672C\u4E00\u4E2A\u5F52\u6863 + \u4E00\u4E2A sidecar，\u6CA1\u6709\u5B64\u513F。
        expect(remaining, hasLength(4));
      },
    );

    test(
      'sweepIncomplete \u4E5F\u6E05\u6389\u6CA1\u6709\u5F52\u6863\u7684\u5B64\u513F\u5143\u6570\u636E',
      () async {
        // \u5143\u6570\u636E\u5148\u843D\u76D8、\u5F52\u6863\u540E\u6539\u540D，\u4E2D\u95F4\u5D29\u4E00\u6B21\u5C31\u4F1A\u7559\u4E0B\u4E00\u4E2A list() \u6C38\u8FDC\u770B\u4E0D\u89C1、
        // \u56E0\u6B64\u6C38\u8FDC\u6E05\u4E0D\u6389\u7684 sidecar。
        await store.ensureDirectory();
        final orphan = File(
          p.join(
            store.directory.path,
            '${LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 5, 1))}'
            '${LocalSnapshotPaths.metadataSuffix}',
          ),
        );
        await orphan.writeAsString('{}');

        await store.sweepIncomplete();

        expect(await orphan.exists(), isFalse);
      },
    );

    test(
      'sweepIncomplete \u4E0D\u78B0\u6709\u5F52\u6863\u7684\u5143\u6570\u636E',
      () async {
        final entry = await publish(at: DateTime.utc(2026, 5, 1));
        final sidecar = File(
          '${entry.file.path}${LocalSnapshotPaths.metadataSuffix}',
        );

        await store.sweepIncomplete();

        expect(await sidecar.exists(), isTrue);
        expect(await store.list(), hasLength(1));
      },
    );

    test(
      '\u5220\u4E0D\u6389\u65F6\u5982\u5B9E\u62A5\u9519，\u800C\u4E0D\u662F\u5047\u88C5\u5220\u6389\u4E86',
      () async {
        final entry = await publish(at: DateTime.utc(2026, 5, 1));
        // \u5F52\u6863\u6362\u6210\u76EE\u5F55：\u5220\u6587\u4EF6\u7684\u8C03\u7528\u5220\u4E0D\u52A8\u5B83。
        await entry.file.delete();
        await Directory(entry.file.path).create();

        await expectLater(
          store.delete(entry.id),
          throwsA(isA<FileSystemException>()),
        );

        await Directory(entry.file.path).delete();
      },
    );

    test(
      'sweepIncomplete \u6E05\u6389\u4E2D\u65AD\u7559\u4E0B\u7684\u534A\u6210\u54C1',
      () async {
        await store.ensureDirectory();
        final debris = File(
          p.join(
            store.directory.path,
            '${LocalSnapshotPaths.temporaryPrefix}'
            '${LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 5, 1))}',
          ),
        );
        await debris.writeAsString('half');

        await store.sweepIncomplete();

        expect(await debris.exists(), isFalse);
      },
    );

    test(
      '\u534A\u6210\u54C1\u4E0D\u4F1A\u88AB\u5F53\u6210\u53EF\u7528\u526F\u672C\u5217\u51FA',
      () async {
        await store.ensureDirectory();
        await File(
          p.join(
            store.directory.path,
            '${LocalSnapshotPaths.temporaryPrefix}'
            '${LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 5, 1))}',
          ),
        ).writeAsString('half');

        expect(await store.list(), isEmpty);
      },
    );

    test('setPinned \u843D\u76D8\u540E\u80FD\u8BFB\u56DE', () async {
      final entry = await publish(at: DateTime.utc(2026, 5, 1));
      await store.setPinned(entry.id, true);

      final listed = await store.list();
      expect(listed.single.pinned, isTrue);
      expect(listed.single.retention.pinned, isTrue);
    });

    test(
      '\u635F\u574F\u7684 sidecar \u4E0D\u4F1A\u8BA9\u526F\u672C\u6D88\u5931',
      () async {
        final entry = await publish(at: DateTime.utc(2026, 5, 1));
        await File(
          '${entry.file.path}${LocalSnapshotPaths.metadataSuffix}',
        ).writeAsString('{not json');

        final listed = await store.list();
        expect(listed, hasLength(1));
        expect(listed.single.messageCount, greaterThan(0));
      },
    );

    test(
      'sidecar \u8BB0\u5F55\u7684\u5B57\u6BB5\u53EF\u88AB\u5916\u90E8\u8BFB\u53D6\u6821\u9A8C',
      () async {
        final entry = await publish(at: DateTime.utc(2026, 5, 1));
        final sidecar = File(
          '${entry.file.path}${LocalSnapshotPaths.metadataSuffix}',
        );
        final decoded =
            jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;

        expect(decoded['origin'], 'automatic');
        expect(decoded['messageCount'], 10);
        expect(decoded['bytes'], await entry.file.length());
      },
    );
  });
}
