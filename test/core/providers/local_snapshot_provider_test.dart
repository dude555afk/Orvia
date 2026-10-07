import 'dart:async';
import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/providers/local_snapshot_provider.dart';
import 'package:Kelivo/core/services/backup/backup_cancel_token.dart';
import 'package:Kelivo/core/services/backup/backup_task_progress.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_schedule.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_service.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_settings.dart';
import 'package:Kelivo/core/services/backup/local_snapshot_store.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSnapshotProvider', () {
    late Directory root;
    late AppDatabase database;
    late BusinessPreferences businessPreferences;
    late LocalSnapshotPreferences snapshotPreferences;
    Object? packError;
    var packCount = 0;

    Future<PreparedBackupArchive> buildArchive({
      BackupProgressSink? onProgress,
      BackupCancelToken? cancelToken,
    }) async {
      packCount++;
      final error = packError;
      if (error != null) throw error;
      final file = File(
        p.join(root.path, 'packed_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await file.writeAsString('archive');
      return (
        file: file,
        info: (
          schemaVersion: AppDatabase.currentSchemaVersion,
          conversationCount: 1,
          messageCount: 9,
        ),
        appVersion: '1.2.4+1',
      );
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_snapshot_provider_');
      database = AppDatabase(NativeDatabase.memory());
      businessPreferences = BusinessPreferences(BusinessRepository(database));
      await businessPreferences.load();
      snapshotPreferences = LocalSnapshotPreferences(businessPreferences);
      packError = null;
      packCount = 0;
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    LocalSnapshotProvider build() => LocalSnapshotProvider(
      appDataDirectory: root,
      chatService: ChatService(),
      businessRepository: BusinessRepository(database),
      businessPreferences: businessPreferences,
      autoLoad: false,
      debugBuildArchive: buildArchive,
    );

    test(
      '\u624B\u52A8\u5907\u4EFD\u5931\u8D25\u4F1A\u88AB\u8BB0\u5F55，\u8F6C\u5230\u540E\u53F0\u4E5F\u7559\u5F97\u4E0B\u75D5\u8FF9',
      () async {
        // \u7528\u6237\u70B9\u4E86"\u8F6C\u5230\u540E\u53F0\u7EE7\u7EED"\u4E4B\u540E，\u5F39\u7A97\u5DF2\u7ECF\u5378\u8F7D，\u5F02\u6B65\u9519\u8BEF\u53EA\u88AB\u7528\u4E8E\u91CA\u653E\u8D44\u6E90。
        // \u4E0D\u8BB0\u7684\u8BDD\u7528\u6237\u53EA\u770B\u5230"\u6B63\u5728\u540E\u53F0\u5907\u4EFD"，\u4E4B\u540E\u65E2\u65E0\u6210\u529F\u4E5F\u65E0\u5931\u8D25。
        packError = StateError('device is full');
        final vm = build();

        await expectLater(vm.takeNow(), throwsA(isA<StateError>()));

        final state = snapshotPreferences.readState();
        expect(state.failureStreak, 1);
        expect(state.lastFailureMessage, contains('device is full'));
      },
    );

    test(
      '\u7528\u6237\u4E3B\u52A8\u53D6\u6D88\u4E0D\u7B97\u5931\u8D25',
      () async {
        packError = const BackupCancelledException();
        final vm = build();

        await expectLater(
          vm.takeNow(),
          throwsA(isA<BackupCancelledException>()),
        );

        expect(snapshotPreferences.readState().failureStreak, 0);
        expect(snapshotPreferences.readState().lastFailureMessage, isNull);
      },
    );

    test(
      '\u6B63\u5728\u6062\u590D\u526F\u672C\u65F6，\u5B9A\u65F6\u4EFB\u52A1\u8BA9\u8DEF\u800C\u4E0D\u662F\u53BB\u526A\u679D',
      () async {
        final vm = build();
        await vm.takeNow();
        expect(packCount, 1);

        // \u6A21\u62DF\u6062\u590D\u671F\u95F4：\u526F\u672C\u6B63\u88AB\u6309\u8DEF\u5F84\u8BFB\u53D6。
        final gate = Completer<void>();
        final holding = vm.whileHoldingCopies(() => gate.future);

        final result = await vm.runIfDue();
        expect(result, isA<LocalSnapshotSkipped>());
        expect(
          (result as LocalSnapshotSkipped).reason,
          LocalSnapshotSkipReason.busy,
        );
        expect(packCount, 1);

        gate.complete();
        await holding;
      },
    );

    test(
      '\u6062\u590D\u524D\u90A3\u4EFD\u526F\u672C\u53EF\u4EE5\u53D6\u6D88\u4FDD\u7559',
      () async {
        final vm = build();
        final entry = await vm.takeNow(
          origin: LocalSnapshotOrigin.beforeRestore,
          pinned: true,
          prune: false,
        );
        await vm.refresh();
        expect(vm.copies.single.pinned, isTrue);

        await vm.setPinned(vm.copies.single, false);

        expect(vm.copies.single.pinned, isFalse);
        expect(entry.origin, LocalSnapshotOrigin.beforeRestore);
      },
    );
  });
}
