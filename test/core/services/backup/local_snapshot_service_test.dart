import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/services/backup/backup_cancel_token.dart';
import 'package:Kelivo/core/services/backup/backup_task_progress.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_schedule.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_service.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_settings.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalSnapshotService', () {
    late Directory root;
    late AppDatabase database;
    late BusinessPreferences businessPreferences;
    late LocalSnapshotPreferences preferences;
    late File liveDatabase;
    var packCount = 0;
    Object? packError;
    var messageCount = 100;

    Future<void> Function()? duringPack;

    Future<PreparedBackupArchive> buildArchive({
      BackupProgressSink? onProgress,
      BackupCancelToken? cancelToken,
    }) async {
      packCount++;
      final error = packError;
      if (error != null) throw error;
      await duringPack?.call();
      final file = File(
        p.join(root.path, 'packed_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await file.writeAsString('archive');
      return (
        file: file,
        info: (
          schemaVersion: AppDatabase.currentSchemaVersion,
          conversationCount: 4,
          messageCount: messageCount,
        ),
        appVersion: '1.2.4+1',
      );
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_snapshot_service_');
      database = AppDatabase(NativeDatabase.memory());
      businessPreferences = BusinessPreferences(BusinessRepository(database));
      await businessPreferences.load();
      preferences = LocalSnapshotPreferences(businessPreferences);
      liveDatabase = File(p.join(root.path, AppDatabase.databaseFileName));
      await liveDatabase.writeAsString('live database contents');
      packCount = 0;
      packError = null;
      messageCount = 100;
      duringPack = null;
      // The grace period is a first-run concern; every other test wants the
      // schedule to behave as it does on an install that has already settled.
      await preferences.recordFirstObserved(DateTime.utc(2020));
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    LocalSnapshotService build({
      LocalSnapshotBusyCheck? isBusy,
      Future<int?> Function()? freeBytes,
    }) => LocalSnapshotService(
      appDataDirectory: root,
      preferences: preferences,
      buildArchive: buildArchive,
      isBusy: isBusy,
      freeBytes: freeBytes ?? () async => null,
    );

    /// Forces the next run to see a database that has changed.
    Future<void> touchDatabase() async {
      await liveDatabase.writeAsString(
        'live database contents ${DateTime.now().microsecondsSinceEpoch}',
      );
    }

    test(
      '\u5347\u7EA7\u540E\u7684\u7B2C\u4E00\u6B21\u542F\u52A8\u4E0D\u7ACB\u523B\u5F00\u8DD1，\u53EA\u662F\u8BB0\u4E0B\u65F6\u95F4',
      () async {
        // \u88C5\u4E86\u8FD9\u4E2A\u7248\u672C\u7684\u6240\u6709\u7528\u6237\u90FD\u6CA1\u6709\u5907\u4EFD\u8BB0\u5F55。\u82E5\u4E0D\u7ED9\u5BBD\u9650\u671F，\u6BCF\u4E2A\u4EBA\u90FD\u4F1A\u5728
        // \u66F4\u65B0\u540E\u7B2C\u4E00\u6B21\u542F\u52A8\u7684\u7B2C 8 \u79D2\u5403\u4E00\u6B21\u5B8C\u6574 vacuum + \u6253\u5305——\u5927\u5E93\u4E0A\u5C31\u662F\u51E0\u5206\u949F。
        await businessPreferences.remove(
          LocalSnapshotPreferences.firstObservedAtKey,
        );
        final service = build();

        final first = await service.runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(
          (first as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.notDue,
        );
        expect(packCount, 0);
        expect(preferences.readState().firstObservedAt, isNotNull);

        // \u5BBD\u9650\u671F\u5185\u518D\u68C0\u67E5\u4E5F\u4E0D\u52A8\u624B。
        final second = await service.runIfDue(
          now: DateTime.utc(2026, 5, 1, 0, 5),
        );
        expect(
          (second as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.notDue,
        );
        expect(packCount, 0);

        // \u8FC7\u4E86\u5C31\u6B63\u5E38\u5907\u4EFD。
        final third = await service.runIfDue(now: DateTime.utc(2026, 5, 1, 1));
        expect(third, isA<LocalSnapshotCreated>());
        expect(packCount, 1);
      },
    );

    test(
      '\u5BBD\u9650\u671F\u53EA\u7BA1\u7B2C\u4E00\u6B21，\u4E4B\u540E\u6309\u5468\u671F\u8D70',
      () async {
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));
        expect(packCount, 1);
        await touchDatabase();

        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 2, 1));

        expect(result, isA<LocalSnapshotCreated>());
        expect(packCount, 2);
      },
    );

    test(
      '\u88AB\u5360\u7528\u65F6\u4E5F\u628A\u539F\u56E0\u8BB0\u4E0B\u6765',
      () async {
        await build(
          isBusy: () => LocalSnapshotSkipReason.generating,
        ).runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(
          preferences.readState().lastSkipReason,
          LocalSnapshotSkipReason.generating,
        );
      },
    );

    test(
      '\u9996\u6B21\u8FD0\u884C\u5C31\u4EA7\u4E00\u4EFD\u526F\u672C',
      () async {
        final result = await build().runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(result, isA<LocalSnapshotCreated>());
        expect(packCount, 1);
        final entry = (result as LocalSnapshotCreated).entry;
        expect(entry.messageCount, 100);
        expect(entry.origin, LocalSnapshotOrigin.automatic);
        expect(await entry.file.exists(), isTrue);
      },
    );

    test('\u672A\u5230\u5468\u671F\u4E0D\u91CD\u590D\u4EA7', () async {
      final service = build();
      await service.runIfDue(now: DateTime.utc(2026, 5, 1));
      await touchDatabase();

      final result = await service.runIfDue(now: DateTime.utc(2026, 5, 1, 6));

      expect(result, isA<LocalSnapshotSkipped>());
      expect(
        (result as LocalSnapshotSkipped).reason,
        LocalSnapshotSkipReason.notDue,
      );
      expect(packCount, 1);
    });

    test(
      '\u6570\u636E\u6CA1\u53D8\u5C31\u6574\u8F6E\u8DF3\u8FC7，\u4E0D\u505A\u4EFB\u4F55\u6253\u5305',
      () async {
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));

        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 3));

        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.unchanged,
        );
        expect(packCount, 1);
      },
    );

    test(
      '\u8DF3\u8FC7"\u6CA1\u53D8"\u4E0D\u63A8\u8FDB\u4E0A\u6B21\u6210\u529F\u65F6\u95F4，\u6539\u52A8\u540E\u7ACB\u523B\u5C31\u80FD\u4EA7',
      () async {
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));
        await service.runIfDue(now: DateTime.utc(2026, 5, 3));

        await touchDatabase();
        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 3, 1));

        expect(result, isA<LocalSnapshotCreated>());
        expect(packCount, 2);
      },
    );

    test('\u5173\u95ED\u540E\u4E0D\u8DD1', () async {
      await preferences.writeSettings(
        const LocalSnapshotSettings(enabled: false),
      );

      final result = await build().runIfDue(now: DateTime.utc(2026, 5, 1));

      expect(
        (result as LocalSnapshotSkipped).reason,
        LocalSnapshotSkipReason.disabled,
      );
      expect(packCount, 0);
    });

    test(
      '\u6B63\u5728\u751F\u6210\u65F6\u8BA9\u8DEF，\u4E0D\u4E0E\u7528\u6237\u62A2 IO',
      () async {
        final result = await build(
          isBusy: () => LocalSnapshotSkipReason.generating,
        ).runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.generating,
        );
        expect(packCount, 0);
      },
    );

    test(
      '\u5269\u4F59\u7A7A\u95F4\u4E0D\u8DB3\u65F6\u4E0D\u52A8\u624B',
      () async {
        final result = await build(
          freeBytes: () async => LocalSnapshotSchedule.freeSpaceFloor,
        ).runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.insufficientSpace,
        );
        expect(packCount, 0);
        expect(
          preferences.readState().lastSkipReason,
          LocalSnapshotSkipReason.insufficientSpace,
        );
      },
    );

    test(
      '\u63A2\u6D4B\u4E0D\u5230\u5269\u4F59\u7A7A\u95F4\u65F6\u7167\u5E38\u8FDB\u884C',
      () async {
        final result = await build(
          freeBytes: () async => null,
        ).runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(result, isA<LocalSnapshotCreated>());
      },
    );

    test(
      '\u6253\u5305\u5931\u8D25\u88AB\u8BB0\u5F55\u4E0B\u6765，\u4E14\u4E0D\u629B\u7ED9\u8C03\u7528\u65B9',
      () async {
        packError = StateError('disk on fire');

        final result = await build().runIfDue(now: DateTime.utc(2026, 5, 1));

        expect(result, isA<LocalSnapshotFailed>());
        final state = preferences.readState();
        expect(state.failureStreak, 1);
        expect(state.lastFailureMessage, contains('disk on fire'));
        expect(state.lastSuccessAt, isNull);
      },
    );

    test(
      '\u8FDE\u7EED\u5931\u8D25\u9000\u907F\u8D8A\u6765\u8D8A\u4E45，\u4E0D\u662F\u6BCF\u6B21 resume \u90FD\u767D\u8DD1',
      () async {
        packError = StateError('nope');
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));

        // \u4E00\u5C0F\u65F6\u5185\u4E0D\u91CD\u8BD5。
        var result = await service.runIfDue(
          now: DateTime.utc(2026, 5, 1, 0, 30),
        );
        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.backoff,
        );
        expect(packCount, 1);

        // \u9000\u907F\u7A97\u53E3\u8FC7\u540E\u91CD\u8BD5，\u518D\u5931\u8D25\u4E00\u6B21\u7A97\u53E3\u7FFB\u500D。
        result = await service.runIfDue(now: DateTime.utc(2026, 5, 1, 2));
        expect(result, isA<LocalSnapshotFailed>());
        expect(preferences.readState().failureStreak, 2);

        result = await service.runIfDue(now: DateTime.utc(2026, 5, 1, 3, 30));
        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.backoff,
        );
      },
    );

    test('\u6210\u529F\u540E\u6E05\u7A7A\u5931\u8D25\u8BA1\u6570', () async {
      packError = StateError('nope');
      final service = build();
      await service.runIfDue(now: DateTime.utc(2026, 5, 1));
      packError = null;

      await service.runIfDue(now: DateTime.utc(2026, 5, 1, 2));

      final state = preferences.readState();
      expect(state.failureStreak, 0);
      expect(state.lastFailureAt, isNull);
      expect(state.lastSuccessAt, isNotNull);
    });

    test(
      '\u4EA7\u5B8C\u987A\u5E26\u6309\u7B56\u7565\u6E05\u7406，\u4F46\u4E0D\u78B0\u6700\u65B0\u4E00\u4EFD\u6709\u5185\u5BB9\u7684',
      () async {
        await preferences.writeSettings(
          const LocalSnapshotSettings(
            keepRecent: 1,
            keepWeekly: false,
            keepMonthly: false,
          ),
        );
        final service = build();

        await service.runIfDue(now: DateTime.utc(2026, 5, 1));
        await touchDatabase();
        await service.runIfDue(now: DateTime.utc(2026, 5, 3));
        await touchDatabase();
        messageCount = 0;
        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 5));

        expect(result, isA<LocalSnapshotCreated>());
        final remaining = await service.store.list();
        // \u6700\u65B0\u7684\u90A3\u4EFD\u662F\u7A7A\u7684，\u6240\u4EE5\u6700\u540E\u4E00\u4EFD\u6709\u5185\u5BB9\u7684\u5FC5\u987B\u7559\u7740。
        expect(remaining, hasLength(2));
        expect(remaining.first.messageCount, 0);
        expect(remaining.last.messageCount, greaterThan(0));
      },
    );

    test('\u5927\u5E93\u9ED8\u8BA4\u62C9\u957F\u5468\u671F', () async {
      expect(
        LocalSnapshotSchedule.defaultIntervalFor(10 * 1024 * 1024),
        const Duration(days: 1),
      );
      expect(
        LocalSnapshotSchedule.defaultIntervalFor(500 * 1024 * 1024),
        const Duration(days: 3),
      );
      expect(
        LocalSnapshotSchedule.defaultIntervalFor(2 * 1024 * 1024 * 1024),
        const Duration(days: 7),
      );
    });

    test(
      '\u7528\u6237\u8BBE\u5B9A\u7684\u5468\u671F\u8986\u76D6\u81EA\u9002\u5E94\u9ED8\u8BA4\u503C',
      () async {
        await preferences.writeSettings(
          const LocalSnapshotSettings(intervalDays: 7),
        );
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));
        await touchDatabase();

        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 4));

        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.notDue,
        );
      },
    );

    test(
      '\u5907\u4EFD\u8FDB\u884C\u5F53\u4E2D\u5199\u5165\u7684\u6570\u636E，\u4E0B\u4E00\u8F6E\u4ECD\u4F1A\u88AB\u5F53\u4F5C\u6709\u6539\u52A8',
      () async {
        // \u8BB0\u5F55\u7684\u6307\u7EB9\u5FC5\u987B\u63CF\u8FF0"\u8FD9\u4EFD\u526F\u672C\u88C5\u7684\u662F\u54EA\u4E2A\u72B6\u6001"，\u4E5F\u5C31\u662F\u5907\u4EFD\u5F00\u59CB\u4E4B\u524D\u90A3\u4E2A。
        // \u82E5\u8BB0\u6210\u5907\u4EFD\u7ED3\u675F\u540E\u7684\u72B6\u6001，\u5907\u4EFD\u8FDB\u884C\u671F\u95F4\u5199\u8FDB\u53BB\u7684\u6570\u636E\u4F1A\u88AB"\u6CA1\u53D8\u5316"\u8FD9\u9053\u95F8
        // \u6C38\u8FDC\u6321\u5728\u5916\u9762——\u9664\u975E\u4E4B\u540E\u53C8\u6070\u597D\u6709\u522B\u7684\u6539\u52A8，\u5426\u5219\u518D\u4E5F\u4E0D\u4F1A\u88AB\u5907\u4EFD\u5230。
        final service = build();
        duringPack = touchDatabase;
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));
        expect(packCount, 1);
        duringPack = null;

        final result = await service.runIfDue(now: DateTime.utc(2026, 5, 3));

        expect(result, isA<LocalSnapshotCreated>());
        expect(packCount, 2);
      },
    );

    test(
      '\u624B\u52A8\u5907\u4EFD\u5931\u8D25\u4E5F\u8981\u7559\u4E0B\u8BB0\u5F55，\u5426\u5219\u8F6C\u540E\u53F0\u5931\u8D25\u5C31\u65E0\u58F0\u65E0\u606F',
      () async {
        // \u8F6C\u5230\u540E\u53F0\u4E4B\u540E\u5F39\u7A97\u5DF2\u7ECF\u5378\u8F7D，\u5F02\u6B65\u9519\u8BEF\u88AB\u6D88\u8D39\u6389\u53EA\u7528\u4E8E\u91CA\u653E\u8D44\u6E90。
        // \u82E5\u8FD9\u91CC\u4E0D\u8BB0，\u7528\u6237\u53EA\u4F1A\u770B\u5230"\u6B63\u5728\u540E\u53F0\u5907\u4EFD"，\u7136\u540E\u518D\u65E0\u4E0B\u6587。
        packError = StateError('device is full');
        final service = build();

        await expectLater(
          service.take(origin: LocalSnapshotOrigin.manual),
          throwsA(isA<StateError>()),
        );

        // \u670D\u52A1\u5C42\u53EA\u8D1F\u8D23\u629B；\u8BB0\u5F55\u53D1\u751F\u5728 provider \u5C42（\u89C1 local_snapshot_provider）。
        expect(await service.store.list(), isEmpty);
      },
    );

    test(
      '\u624B\u52A8\u4E00\u4EFD\u6807\u6210 manual，\u4E14\u4E0D\u53D7\u5468\u671F\u9650\u5236',
      () async {
        final service = build();
        await service.runIfDue(now: DateTime.utc(2026, 5, 1));

        final entry = await service.take(origin: LocalSnapshotOrigin.manual);

        expect(entry.origin, LocalSnapshotOrigin.manual);
        expect(await service.store.list(), hasLength(2));
      },
    );

    test(
      '\u6253\u5305\u4EA7\u7269\u5728\u53D1\u5E03\u540E\u4E0D\u6B8B\u7559\u5728\u4E34\u65F6\u4F4D\u7F6E',
      () async {
        final service = build();
        await service.take(origin: LocalSnapshotOrigin.manual);

        final strays = await root
            .list()
            .where((entity) => p.basename(entity.path).startsWith('packed_'))
            .toList();
        expect(strays, isEmpty);
      },
    );
  });
}
