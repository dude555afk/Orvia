import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/database/business_restore_service.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

Map<String, Object?> _entryFrom(File archiveFile, String name) {
  final archive = ZipDecoder().decodeBytes(archiveFile.readAsBytesSync());
  final entry = archive.findFile(name);
  if (entry == null) throw StateError(name);
  return jsonDecode(utf8.decode(entry.readBytes()!)) as Map<String, Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataSync.prepareBackupFileFromDatabase', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_foreign_db_');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      PackageInfo.setMockInitialValues(
        appName: 'Kelivo',
        packageName: 'Kelivo',
        version: '1.0.0-test',
        buildNumber: '1',
        buildSignature: 'test',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    /// Writes a standalone database carrying [secret], the way a set-aside
    /// copy on a user's device would look.
    Future<File> writeDatabase(String name, String secret) async {
      final file = File('${root.path}/$name');
      final database = AppDatabase.open(file: file);
      try {
        await BusinessRestoreService(BusinessRepository(database)).overwrite({
          'provider_configs_v1': jsonEncode({
            'only': {'id': 'only', 'name': 'Only', 'apiKey': secret},
          }),
          'providers_order_v1': <String>['only'],
        });
      } finally {
        await database.close();
      }
      return file;
    }

    test('\u628A\u4E00\u4EFD\u72EC\u7ACB\u6570\u636E\u5E93\u6253\u6210\u6807\u51C6\u5907\u4EFD\u5F52\u6863', () async {
      final source = await writeDatabase('kelivo.db.displaced-0001', 'aside');
      final live = await writeDatabase('live.sqlite', 'current');
      final liveDatabase = AppDatabase.open(file: live);
      File? archive;
      try {
        archive = await DataSync(
          chatService: ChatService(),
          businessRepository: BusinessRepository(liveDatabase),
        ).prepareBackupFileFromDatabase(source);

        final manifest = _entryFrom(archive, 'manifest.json');
        expect(manifest['format'], 'kelivo-backup');
        expect(manifest['payloadKind'], 'sqlite');
        expect(manifest['includeChats'], isTrue);
        // \u9644\u4EF6\u4E0D\u8FDB\u672C\u5730\u526F\u672C：\u5B83\u4EEC\u548C\u6D3B\u5E93\u5728\u540C\u4E00\u5757\u76D8\u4E0A。
        expect(manifest['includeFiles'], isFalse);
        expect(
          (manifest['database'] as Map)['schemaVersion'],
          AppDatabase.currentSchemaVersion,
        );

        final settings = _entryFrom(archive, 'settings.json');
        final providers =
            jsonDecode(settings['provider_configs_v1'] as String) as Map;
        // \u5173\u952E：\u8BBE\u7F6E\u5FC5\u987B\u6765\u81EA\u88AB\u6253\u5305\u7684\u90A3\u4EFD\u5E93，\u800C\u4E0D\u662F\u5F53\u524D\u6D3B\u7740\u7684\u90A3\u4EFD。
        expect((providers['only'] as Map)['apiKey'], 'aside');
      } finally {
        await liveDatabase.close();
        await DataSync.cleanupTemporaryBackupFile(archive);
      }
    });

    test('\u5F52\u6863\u81EA\u5E26\u6570\u636E\u5E93，\u4E0D\u5F15\u7528\u539F\u6587\u4EF6', () async {
      final source = await writeDatabase('kelivo.db.displaced-0002', 'aside');
      final live = await writeDatabase('live.sqlite', 'current');
      final liveDatabase = AppDatabase.open(file: live);
      File? archive;
      try {
        archive = await DataSync(
          chatService: ChatService(),
          businessRepository: BusinessRepository(liveDatabase),
        ).prepareBackupFileFromDatabase(source);

        final entries = ZipDecoder()
            .decodeBytes(await archive.readAsBytes())
            .files
            .map((file) => file.name)
            .toSet();
        expect(entries, contains('database/kelivo.db'));
        expect(entries, contains('settings.json'));
        expect(entries, contains('manifest.json'));
      } finally {
        await liveDatabase.close();
        await DataSync.cleanupTemporaryBackupFile(archive);
      }
    });

    test('\u4E0D\u4FEE\u6539\u6E90\u526F\u672C', () async {
      final source = await writeDatabase('kelivo.db.displaced-0003', 'aside');
      final before = await source.readAsBytes();
      final live = await writeDatabase('live.sqlite', 'current');
      final liveDatabase = AppDatabase.open(file: live);
      File? archive;
      try {
        archive = await DataSync(
          chatService: ChatService(),
          businessRepository: BusinessRepository(liveDatabase),
        ).prepareBackupFileFromDatabase(source);
        expect(await source.readAsBytes(), before);
      } finally {
        await liveDatabase.close();
        await DataSync.cleanupTemporaryBackupFile(archive);
      }
    });

    test('\u6E90\u6587\u4EF6\u4E0D\u5B58\u5728\u65F6\u660E\u786E\u62A5\u9519', () async {
      final live = await writeDatabase('live.sqlite', 'current');
      final liveDatabase = AppDatabase.open(file: live);
      try {
        await expectLater(
          DataSync(
            chatService: ChatService(),
            businessRepository: BusinessRepository(liveDatabase),
          ).prepareBackupFileFromDatabase(File('${root.path}/missing.db')),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await liveDatabase.close();
      }
    });
  });
}
