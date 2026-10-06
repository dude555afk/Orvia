import 'dart:io';

import 'package:Kelivo/core/services/backup/local_snapshot_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DatabaseChangeFingerprint', () {
    late Directory root;
    late File database;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_fingerprint_');
      database = File(p.join(root.path, 'kelivo.db'));
      await database.writeAsString('contents');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      '\u540C\u4E00\u4EFD\u672A\u6539\u52A8\u7684\u6570\u636E\u5E93\u524D\u540E\u4E00\u81F4',
      () async {
        final first = await DatabaseChangeFingerprint.read(database);
        final second = await DatabaseChangeFingerprint.read(database);
        expect(second.matches(first), isTrue);
      },
    );

    test(
      '\u6CA1\u6709 -wal \u4E5F\u7B97"\u6CA1\u53D8"，\u800C\u4E0D\u662F\u6BCF\u6B21\u90FD\u5F53\u4F5C\u53D8\u4E86',
      () async {
        // \u5DF2 checkpoint \u7684\u5E93\u65C1\u8FB9\u6CA1\u6709 -wal。\u82E5\u628A"\u6587\u4EF6\u4E0D\u5B58\u5728"\u5F53\u6210"\u8BFB\u4E0D\u51FA\u6765"，
        // \u6BCF\u6B21\u542F\u52A8\u90FD\u4F1A\u91CD\u65B0\u5907\u4EFD\u4E00\u904D，\u65F6\u95F4\u7EB5\u6DF1\u4F1A\u88AB\u540C\u4E00\u5929\u7684\u591A\u4EFD\u526F\u672C\u6324\u6CA1。
        expect(await File('${database.path}-wal').exists(), isFalse);
        final first = await DatabaseChangeFingerprint.read(database);
        expect(
          (await DatabaseChangeFingerprint.read(database)).matches(first),
          isTrue,
        );
      },
    );

    test('WAL \u51FA\u73B0\u5373\u89C6\u4E3A\u6709\u6539\u52A8', () async {
      final first = await DatabaseChangeFingerprint.read(database);
      await File('${database.path}-wal').writeAsBytes(List<int>.filled(64, 1));
      expect(
        (await DatabaseChangeFingerprint.read(database)).matches(first),
        isFalse,
      );
    });

    test(
      '\u6570\u636E\u5E93\u53D8\u5927\u5373\u89C6\u4E3A\u6709\u6539\u52A8',
      () async {
        final first = await DatabaseChangeFingerprint.read(database);
        await database.writeAsString('contents and more');
        expect(
          (await DatabaseChangeFingerprint.read(database)).matches(first),
          isFalse,
        );
      },
    );

    test(
      '\u8BFB\u4E0D\u51FA\u6765\u7684\u4E00\u5F8B\u4E0D\u7B97"\u6CA1\u53D8"',
      () async {
        final unreadable = DatabaseChangeFingerprint.decode('-1:-1:-1:-1');
        expect(unreadable, isNotNull);
        expect(unreadable!.matches(unreadable), isFalse);
      },
    );

    test('\u7F16\u89E3\u7801\u5F80\u8FD4', () async {
      final original = await DatabaseChangeFingerprint.read(database);
      final decoded = DatabaseChangeFingerprint.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.matches(original), isTrue);
    });

    test(
      '\u635F\u574F\u7684\u8BB0\u5F55\u89E3\u4E0D\u51FA\u6765，\u4E5F\u5C31\u4E0D\u4F1A\u88AB\u8BEF\u5224\u4E3A\u4E00\u81F4',
      () {
        expect(DatabaseChangeFingerprint.decode(null), isNull);
        expect(DatabaseChangeFingerprint.decode('1:2:3'), isNull);
        expect(DatabaseChangeFingerprint.decode('a:b:c:d'), isNull);
      },
    );
  });

  group('LocalSnapshotSchedule', () {
    final now = DateTime.utc(2026, 5, 10, 12);

    test('\u5173\u95ED\u65F6\u76F4\u63A5\u8BF4\u660E\u539F\u56E0', () {
      expect(
        LocalSnapshotSchedule.dueSkipReason(
          now: now,
          enabled: false,
          interval: const Duration(days: 1),
        ),
        LocalSnapshotSkipReason.disabled,
      );
    });

    test('\u4ECE\u672A\u5907\u4EFD\u8FC7\u5C31\u662F\u5230\u671F', () {
      expect(
        LocalSnapshotSchedule.dueSkipReason(
          now: now,
          enabled: true,
          interval: const Duration(days: 1),
        ),
        isNull,
      );
    });

    test('\u672A\u6EE1\u5468\u671F\u4E0D\u8DD1', () {
      expect(
        LocalSnapshotSchedule.dueSkipReason(
          now: now,
          enabled: true,
          interval: const Duration(days: 1),
          lastSuccessAt: now.subtract(const Duration(hours: 5)),
        ),
        LocalSnapshotSkipReason.notDue,
      );
    });

    test('\u5931\u8D25\u9000\u907F\u7A97\u53E3\u5185\u4E0D\u91CD\u8BD5', () {
      expect(
        LocalSnapshotSchedule.dueSkipReason(
          now: now,
          enabled: true,
          interval: const Duration(days: 1),
          lastFailureAt: now.subtract(const Duration(minutes: 20)),
        ),
        LocalSnapshotSkipReason.backoff,
      );
    });

    test(
      '\u65F6\u949F\u5F80\u56DE\u8DF3\u4E0D\u4F1A\u628A\u65E5\u7A0B\u5361\u5728\u672A\u6765',
      () {
        // \u4E0A\u6B21\u6210\u529F\u65F6\u95F4\u5728"\u73B0\u5728"\u4E4B\u540E，\u8BF4\u660E\u65F6\u949F\u88AB\u6539\u8FC7；\u6B64\u65F6\u5E94\u5F53\u7167\u5E38\u5907\u4EFD，
        // \u800C\u4E0D\u662F\u7B49\u5230\u90A3\u4E2A\u672A\u6765\u65F6\u95F4\u70B9\u8FC7\u53BB。
        expect(
          LocalSnapshotSchedule.dueSkipReason(
            now: now,
            enabled: true,
            interval: const Duration(days: 1),
            lastSuccessAt: now.add(const Duration(days: 30)),
          ),
          isNull,
        );
        expect(
          LocalSnapshotSchedule.dueSkipReason(
            now: now,
            enabled: true,
            interval: const Duration(days: 1),
            lastFailureAt: now.add(const Duration(days: 30)),
          ),
          isNull,
        );
      },
    );

    test(
      '\u9884\u4F30\u6240\u9700\u7A7A\u95F4\u968F\u5E93\u5927\u5C0F\u589E\u957F\u4E14\u5927\u4E8E\u5E93\u672C\u8EAB',
      () {
        const bytes = 1024 * 1024 * 1024;
        expect(
          LocalSnapshotSchedule.estimatedSpaceRequired(bytes),
          greaterThan(bytes),
        );
      },
    );
  });

  group('LocalSnapshotPaths', () {
    test(
      '\u6587\u4EF6\u540D\u6309\u65F6\u95F4\u5B57\u5178\u5E8F\u6392\u5217',
      () {
        final earlier = LocalSnapshotPaths.fileNameFor(
          DateTime.utc(2026, 1, 1),
        );
        final later = LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 6, 1));
        expect(earlier.compareTo(later), lessThan(0));
      },
    );

    test('\u6587\u4EF6\u540D\u53EF\u89E3\u56DE\u65F6\u95F4', () {
      final at = DateTime.utc(2026, 5, 1, 8, 30);
      expect(
        LocalSnapshotPaths.createdAtFromFileName(
          LocalSnapshotPaths.fileNameFor(at),
        ),
        at,
      );
    });

    test(
      '\u4E0D\u8BA4\u5F97\u7684\u540D\u5B57\u8FD4\u56DE null，\u4E0D\u4F1A\u88AB\u5F53\u6210\u526F\u672C',
      () {
        expect(LocalSnapshotPaths.createdAtFromFileName('kelivo.db'), isNull);
        expect(
          LocalSnapshotPaths.createdAtFromFileName(
            '${LocalSnapshotPaths.filePrefix}nonsense'
            '${LocalSnapshotPaths.fileSuffix}',
          ),
          isNull,
        );
        expect(
          LocalSnapshotPaths.createdAtFromFileName(
            '${LocalSnapshotPaths.temporaryPrefix}'
            '${LocalSnapshotPaths.fileNameFor(DateTime.utc(2026, 5, 1))}',
          ),
          isNull,
        );
      },
    );
  });
}
