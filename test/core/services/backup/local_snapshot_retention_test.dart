import 'package:Kelivo/core/services/backup/local_snapshot_retention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalSnapshotRetentionPolicy', () {
    final now = DateTime.utc(2026, 6, 1, 12);

    SnapshotRetentionEntry entry(
      String id, {
      required Duration age,
      int messageCount = 100,
      int bytes = 1000,
      bool pinned = false,
    }) => SnapshotRetentionEntry(
      id: id,
      createdAt: now.subtract(age),
      bytes: bytes,
      messageCount: messageCount,
      pinned: pinned,
    );

    List<String> deleted(
      LocalSnapshotRetentionPolicy policy,
      List<SnapshotRetentionEntry> entries,
    ) => policy
        .selectForDeletion(entries, now: now)
        .map((entry) => entry.id)
        .toList();

    test('\u5355\u4EFD\u526F\u672C\u6C38\u8FDC\u4E0D\u5220', () {
      expect(
        deleted(LocalSnapshotRetentionPolicy.gfsLite, [
          entry('only', age: const Duration(days: 400)),
        ]),
        isEmpty,
      );
    });

    test('GFS-lite \u4FDD\u7559 \u8FD1\u671F3 + \u5468 + \u6708', () {
      final entries = [
        entry('d0', age: const Duration(hours: 1)),
        entry('d1', age: const Duration(days: 1)),
        entry('d2', age: const Duration(days: 2)),
        entry('d3', age: const Duration(days: 3)),
        entry('d5', age: const Duration(days: 5)),
        entry('w1', age: const Duration(days: 8)),
        entry('w2', age: const Duration(days: 20)),
        entry('m1', age: const Duration(days: 40)),
        entry('m2', age: const Duration(days: 200)),
      ];

      // \u8FD1\u671F d0/d1/d2；\u5468\u69FD\u53D6"\u6700\u65B0\u7684\u4E00\u4EFD >=7 \u5929"= w1；\u6708\u69FD\u53D6"\u6700\u65B0\u7684\u4E00\u4EFD >=30 \u5929"= m1。
      expect(deleted(LocalSnapshotRetentionPolicy.gfsLite, entries), [
        'm2',
        'w2',
        'd5',
        'd3',
      ]);
    });

    test('\u5468/\u6708\u69FD\u53D6\u7684\u662F\u6700\u65B0\u4E00\u4EFD\u591F\u9F84\u7684，\u4E0D\u662F\u6700\u8001\u7684\u90A3\u4EFD', () {
      final entries = [
        entry('new', age: const Duration(hours: 1)),
        entry('week-fresh', age: const Duration(days: 7, hours: 1)),
        entry('week-stale', age: const Duration(days: 25)),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['week-stale']);
    });

    test('\u7A7A\u526F\u672C\u6324\u4E0D\u6389\u6700\u540E\u4E00\u4EFD\u6709\u5185\u5BB9\u7684', () {
      final entries = [
        entry('empty2', age: const Duration(hours: 1), messageCount: 0),
        entry('empty1', age: const Duration(hours: 2), messageCount: 0),
        entry('real', age: const Duration(hours: 3), messageCount: 5000),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['empty1']);
    });

    test('\u5185\u5BB9\u9AA4\u964D\u65F6\u9489\u4F4F\u9AD8\u6C34\u4F4D\u90A3\u4E00\u4EFD', () {
      final entries = [
        entry('after2', age: const Duration(hours: 1), messageCount: 10),
        entry('after1', age: const Duration(hours: 2), messageCount: 10),
        entry('before', age: const Duration(hours: 3), messageCount: 5000),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['after1']);
    });

    test('\u5185\u5BB9\u5E73\u7A33\u53D8\u5316\u4E0D\u89E6\u53D1\u9AD8\u6C34\u4F4D\u4FDD\u62A4', () {
      final entries = [
        entry('c', age: const Duration(hours: 1), messageCount: 900),
        entry('b', age: const Duration(hours: 2), messageCount: 950),
        entry('a', age: const Duration(hours: 3), messageCount: 1000),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['a', 'b']);
    });

    test('\u9AD8\u6C34\u4F4D\u4FDD\u62A4\u6709\u671F\u9650，\u4E0D\u4F1A\u6C38\u4E45\u7559\u7740\u5DF2\u5220\u7684\u6570\u636E', () {
      final entries = [
        entry('after', age: const Duration(days: 1), messageCount: 10),
        entry('before', age: const Duration(days: 120), messageCount: 5000),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['before']);
    });

    test('pinned \u7684\u526F\u672C\u4E0D\u53C2\u4E0E\u81EA\u52A8\u6E05\u7406', () {
      final entries = [
        entry('new', age: const Duration(hours: 1)),
        entry('old', age: const Duration(days: 300)),
        entry('pinned', age: const Duration(days: 400), pinned: true),
      ];

      final policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
      );
      expect(deleted(policy, entries), ['old']);
    });

    test('\u8D85\u51FA\u603B\u91CF\u4E0A\u9650\u65F6\u7EE7\u7EED\u780D\u69FD\u4F4D，\u4F46\u4E0D\u52A8\u53D7\u4FDD\u62A4\u7684', () {
      final entries = [
        entry('d0', age: const Duration(hours: 1), bytes: 400),
        entry('d1', age: const Duration(days: 1), bytes: 400),
        entry('d2', age: const Duration(days: 2), bytes: 400),
      ];

      const policy = LocalSnapshotRetentionPolicy(
        keepRecent: 3,
        keepWeekly: false,
        keepMonthly: false,
        maximumTotalBytes: 500,
      );
      // \u9884\u7B97\u53EA\u653E\u5F97\u4E0B\u4E00\u4EFD，\u4F46 d0（\u6700\u65B0）\u53D7\u4FDD\u62A4，\u6240\u4EE5\u505C\u5728\u8FD9\u91CC\u800C\u4E0D\u662F\u6E05\u7A7A。
      expect(deleted(policy, entries), ['d2', 'd1']);
    });

    test('\u603B\u91CF\u4E0A\u9650\u538B\u4E0D\u6389\u6700\u540E\u4E00\u4EFD\u6709\u5185\u5BB9\u7684\u526F\u672C', () {
      final entries = [
        entry(
          'empty',
          age: const Duration(hours: 1),
          bytes: 900,
          messageCount: 0,
        ),
        entry(
          'real',
          age: const Duration(days: 1),
          bytes: 900,
          messageCount: 42,
        ),
      ];

      const policy = LocalSnapshotRetentionPolicy(
        keepRecent: 1,
        keepWeekly: false,
        keepMonthly: false,
        maximumTotalBytes: 1000,
      );
      expect(deleted(policy, entries), isEmpty);
    });
  });
}
