import 'package:orvia/core/services/backup/local_snapshot_retention.dart';
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

    test('Never deletes sole snapshot', () {
      expect(
        deleted(LocalSnapshotRetentionPolicy.gfsLite, [
          entry('only', age: const Duration(days: 400)),
        ]),
        isEmpty,
      );
    });

    test('GFS-lite retains three recent plus weekly and monthly', () {
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

    test(
      'Weekly and monthly slots choose newest eligible rather than oldest',
      () {
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
      },
    );

    test(
      'Empty snapshot cannot evict last populated copy',
      () {
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
      },
    );

    test(
      'Sudden data shrink protects high-water snapshot',
      () {
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
      },
    );

    test(
      'Stable data changes do not trigger high-water protection',
      () {
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
      },
    );

    test(
      'High-water protection expires instead of retaining deleted data forever',
      () {
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
      },
    );

    test(
      'Pinned snapshots are excluded from automatic cleanup',
      () {
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
      },
    );

    test(
      'Over quota removes additional slots without touching protected snapshots',
      () {
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
      },
    );

    test(
      'Total size cap cannot remove last populated snapshot',
      () {
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
      },
    );
  });
}
