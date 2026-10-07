import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:orvia/core/models/workspace_directory_access.dart';
import 'package:orvia/core/providers/external_mounts_provider.dart';
import '../sandbox/sandbox_channel_harness.dart';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:orvia/core/database/app_database.dart';
import 'package:orvia/core/database/extension_entity_store.dart';
import 'package:orvia/core/models/workspace.dart';
import 'package:orvia/core/models/workspace_binding.dart';
import 'package:orvia/core/providers/workspace_provider.dart';
import 'package:orvia/core/services/workspace/file_link_resolver.dart';
import 'package:orvia/core/services/workspace/workspace_paths.dart';
import 'package:orvia/core/services/workspace/workspace_runtime.dart';
import 'package:orvia/core/services/workspace/workspace_tools_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => p.join(path, 'cache');

  @override
  Future<String?> getTemporaryPath() async => p.join(path, 'tmp');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrviaLink.tryParse', () {
    test('parses workspace, chat, skill, and terminal kinds', () {
      final workspace = OrviaLink.tryParse(
        'orvia://workspace/docs/readme.md',
      );
      expect(workspace?.kind, OrviaLinkKind.workspaceFile);
      expect(workspace?.relativePath, 'docs/readme.md');

      final attachment = OrviaLink.tryParse(
        'orvia://chat/attachments/photo.png',
      );
      expect(attachment?.kind, OrviaLinkKind.chatAttachment);
      expect(attachment?.relativePath, 'photo.png');

      final output = OrviaLink.tryParse('orvia://chat/outputs/result.json');
      expect(output?.kind, OrviaLinkKind.chatOutput);
      expect(output?.relativePath, 'result.json');

      final skill = OrviaLink.tryParse('orvia://skills/weather/SKILL.md');
      expect(skill?.kind, OrviaLinkKind.skillFile);
      expect(skill?.relativePath, 'weather/SKILL.md');

      final terminal = OrviaLink.tryParse('orvia://terminal?cmd=ls%20-la');
      expect(terminal?.kind, OrviaLinkKind.terminal);
      expect(terminal?.terminalCommand, 'ls -la');
      expect(terminal?.relativePath, '');
    });

    test('directory references retain complete guest paths for copying', () {
      const cases = {
        'orvia://workspace/reports': '/workspace/reports',
        'orvia://chat/attachments/incoming': '/chat/attachments/incoming',
        'orvia://chat/outputs/reports': '/chat/outputs/reports',
        'orvia://session/notes': '/chat/notes',
        'orvia://skills/skill-id': '/skills/skill-id',
        'orvia://tmp/build': '/tmp/build',
        'orvia://mounts/mount-id/reports': '/mounts/Renamed/reports',
      };
      for (final entry in cases.entries) {
        expect(
          OrviaLink.tryParse(
            entry.key,
          )!.guestPath(mountRoot: '/mounts/Renamed'),
          entry.value,
        );
      }
    });

    test('accepts underscores in workspace paths', () {
      final link = OrviaLink.tryParse(
        'orvia://workspace/shenyu/daily_sign.py',
      );
      expect(link?.kind, OrviaLinkKind.workspaceFile);
      expect(link?.relativePath, 'shenyu/daily_sign.py');
    });

    test('percent-decodes path segments', () {
      final link = OrviaLink.tryParse('orvia://workspace/hello%20world.txt');
      expect(link?.kind, OrviaLinkKind.workspaceFile);
      expect(link?.relativePath, 'hello world.txt');
    });

    test('accepts raw UTF-8 and encoded Chinese workspace names', () {
      final raw = OrviaLink.tryParse(
        'orvia://workspace/\u5458\u5DE5\u8868.csv',
      );
      expect(raw?.kind, OrviaLinkKind.workspaceFile);
      expect(raw?.relativePath, '\u5458\u5DE5\u8868.csv');

      final encoded = OrviaLink.tryParse(
        'orvia://workspace/${Uri.encodeComponent('\u5458\u5DE5\u8868.csv')}',
      );
      expect(encoded?.kind, OrviaLinkKind.workspaceFile);
      expect(encoded?.relativePath, '\u5458\u5DE5\u8868.csv');
    });

    test('decodes encoded directory segments', () {
      final link = OrviaLink.tryParse(
        'orvia://workspace/sub%20dir/a%20b.txt',
      );
      expect(link?.kind, OrviaLinkKind.workspaceFile);
      expect(link?.relativePath, 'sub dir/a b.txt');
    });

    test('parses orvia://chat/<id>/Chinese filename as chat output', () {
      const conversationId = 'conv-\u4E2D\u6587';
      final link = OrviaLink.tryParse(
        'orvia://chat/$conversationId/\u8F93\u51FA.png',
      );
      expect(link?.kind, OrviaLinkKind.chatOutput);
      expect(link?.conversationId, conversationId);
      expect(link?.relativePath, '\u8F93\u51FA.png');
    });

    test('rejects .. segments and encoded traversal', () {
      expect(OrviaLink.tryParse('orvia://workspace/../secret'), isNull);
      expect(
        OrviaLink.tryParse('orvia://workspace/foo/../../etc/passwd'),
        isNull,
      );
      expect(OrviaLink.tryParse('orvia://workspace/%2e%2e/secret'), isNull);
      expect(OrviaLink.tryParse('orvia://workspace/%2e%2e%2fsecret'), isNull);
      expect(OrviaLink.tryParse('orvia://chat/attachments/../x'), isNull);
      expect(OrviaLink.tryParse('orvia://skills/foo/../bar'), isNull);
    });

    test('rejects absolute-host and drive paths', () {
      expect(OrviaLink.tryParse('orvia://workspace//etc/passwd'), isNull);
      expect(
        OrviaLink.tryParse('orvia://workspace/C:/Windows/win.ini'),
        isNull,
      );
      expect(OrviaLink.tryParse('orvia:///workspace/foo'), isNull);
    });

    test('rejects unknown hosts and incomplete chat/skill paths', () {
      expect(OrviaLink.tryParse('orvia://other/foo'), isNull);
      expect(
        OrviaLink.tryParse('orvia://chat/attachments')?.relativePath,
        isEmpty,
      );
      expect(
        OrviaLink.tryParse('orvia://skills/only-id')?.relativePath,
        'only-id',
      );
      expect(OrviaLink.tryParse('https://example.com'), isNull);
      expect(OrviaLink.tryParse(''), isNull);
    });
  });

  group('FileLinkResolver.resolveToHostFile', () {
    late Directory tempDir;
    late Directory workspaceRoot;
    late Directory appData;
    late AppDatabase database;
    late WorkspaceProvider workspaces;
    late FileLinkResolver resolver;
    late Workspace workspace;
    late PathProviderPlatform previousPathProvider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('orvia_file_link_');
      workspaceRoot = Directory(p.join(tempDir.path, 'ws'));
      appData = Directory(p.join(tempDir.path, 'app'));
      await workspaceRoot.create(recursive: true);
      await appData.create(recursive: true);

      previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(appData.path);

      database = AppDatabase(NativeDatabase.memory());
      await database.customSelect('SELECT 1;').getSingle();
      workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
      await workspaces.loaded;
      workspace = await workspaces.create(
        name: 'tmp',
        kind: WorkspaceKind.linked,
        hostPath: workspaceRoot.path,
      );
      resolver = FileLinkResolver(workspaces: workspaces);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    WorkspaceBinding binding() => WorkspaceBinding(workspaceId: workspace.id);

    test('resolves a workspace file under the host root', () async {
      final file = File(p.join(workspaceRoot.path, 'foo.txt'));
      await file.writeAsString('hello');

      final link = OrviaLink.tryParse('orvia://workspace/foo.txt');
      expect(link, isNotNull);
      final resolved = await resolver.resolveToHostFile(
        link!,
        conversationId: 'conv-1',
        binding: binding(),
      );
      expect(resolved?.path, file.path);
    });

    test('returns null when workspace is unbound', () async {
      final file = File(p.join(workspaceRoot.path, 'foo.txt'));
      await file.writeAsString('hello');
      final link = OrviaLink.tryParse('orvia://workspace/foo.txt')!;
      final resolved = await resolver.resolveToHostFile(
        link,
        conversationId: 'conv-1',
        binding: const WorkspaceBinding(),
      );
      expect(resolved, isNull);
    });

    test(
      'rejects constructed escape paths even if parse was bypassed',
      () async {
        final secret = File(p.join(tempDir.path, 'secret.txt'));
        await secret.writeAsString('nope');
        final link = OrviaLink(
          kind: OrviaLinkKind.workspaceFile,
          relativePath: '../secret.txt',
        );
        final resolved = await resolver.resolveToHostFile(
          link,
          conversationId: 'conv-1',
          binding: binding(),
        );
        expect(resolved, isNull);
      },
    );

    test('returns null for a missing workspace file', () async {
      final link = OrviaLink.tryParse('orvia://workspace/missing.txt')!;
      final resolved = await resolver.resolveToHostFile(
        link,
        conversationId: 'conv-1',
        binding: binding(),
      );
      expect(resolved, isNull);
    });

    test(
      'resolves chat attachments and outputs under the session root',
      () async {
        const conversationId = 'conv-42';
        final attach = File(
          p.join(
            appData.path,
            'sessions',
            conversationId,
            'attachments',
            'a.txt',
          ),
        );
        final output = File(
          p.join(appData.path, 'sessions', conversationId, 'outputs', 'b.txt'),
        );
        await attach.parent.create(recursive: true);
        await output.parent.create(recursive: true);
        await attach.writeAsString('attach');
        await output.writeAsString('out');

        final attachResolved = await resolver.resolveToHostFile(
          OrviaLink.tryParse('orvia://chat/attachments/a.txt')!,
          conversationId: conversationId,
          binding: const WorkspaceBinding(),
        );
        final outputResolved = await resolver.resolveToHostFile(
          OrviaLink.tryParse('orvia://chat/outputs/b.txt')!,
          conversationId: conversationId,
          binding: const WorkspaceBinding(),
        );
        expect(attachResolved?.path, attach.path);
        expect(outputResolved?.path, output.path);
      },
    );

    test('resolves skill files and rejects skill escapes', () async {
      final skillFile = File(
        p.join(appData.path, 'skills', 'weather', 'SKILL.md'),
      );
      await skillFile.parent.create(recursive: true);
      await skillFile.writeAsString('# skill');

      final resolved = await resolver.resolveToHostFile(
        OrviaLink.tryParse('orvia://skills/weather/SKILL.md')!,
        conversationId: 'conv-1',
        binding: const WorkspaceBinding(),
      );
      expect(resolved?.path, skillFile.path);

      final escaped = await resolver.resolveToHostFile(
        const OrviaLink(
          kind: OrviaLinkKind.skillFile,
          relativePath: 'weather/../secret.md',
        ),
        conversationId: 'conv-1',
        binding: const WorkspaceBinding(),
      );
      expect(escaped, isNull);
    });

    test(
      'linkFor Chinese filename round-trips to an existing temp file',
      () async {
        final file = File(p.join(workspaceRoot.path, '\u5458\u5DE5\u8868.csv'));
        await file.writeAsString('name,role\n');
        final paths = WorkspacePaths.sandboxed(
          workspaceHostRoot: workspaceRoot.path,
          sessionHostDir: p.join(appData.path, 'sessions', 'conv-1'),
          skillsHostDir: p.join(appData.path, 'skills'),
        );
        final href = WorkspaceToolsService.linkFor(
          ResolvedPath(
            hostPath: file.path,
            modelPath: '/workspace/\u5458\u5DE5\u8868.csv',
            zone: WorkspaceZone.workspace,
          ),
          paths: paths,
        );
        expect(href, isNotNull);
        expect(href, contains(Uri.encodeComponent('\u5458\u5DE5\u8868.csv')));
        expect(href, isNot(contains('\u5458\u5DE5\u8868')));

        final parsed = OrviaLink.tryParse(href!);
        expect(parsed?.kind, OrviaLinkKind.workspaceFile);
        expect(parsed?.relativePath, '\u5458\u5DE5\u8868.csv');
        final resolved = await resolver.resolveToHostFile(
          parsed!,
          conversationId: 'conv-1',
          binding: binding(),
        );
        expect(resolved?.path, file.path);
      },
    );

    test('resolves encoded chat output with Chinese name', () async {
      const conversationId = 'conv-42';
      final output = File(
        p.join(
          appData.path,
          'sessions',
          conversationId,
          'outputs',
          '\u8F93\u51FA.png',
        ),
      );
      await output.parent.create(recursive: true);
      await output.writeAsString('png');
      final parsed = OrviaLink.tryParse(
        'orvia://chat/$conversationId/${Uri.encodeComponent('\u8F93\u51FA.png')}',
      );
      expect(parsed, isNotNull);
      final resolved = await resolver.resolveToHostFile(
        parsed!,
        conversationId: 'other-conv',
        binding: const WorkspaceBinding(),
      );
      expect(resolved?.path, output.path);
    });

    test(
      'directory roots resolve to folders, and missing files have an explicit reason',
      () async {
        final rootLink = OrviaLink.tryParse('orvia://workspace/')!;
        final directory = await resolver.resolveToHostEntry(
          rootLink,
          conversationId: 'conv-1',
          binding: binding(),
        );
        expect(directory, isA<Directory>());
        expect(directory?.path, workspaceRoot.path);
        expect(
          await resolver.resolveToHostFile(
            rootLink,
            conversationId: 'conv-1',
            binding: binding(),
          ),
          isNull,
        );
        await expectLater(
          resolver.resolveToHostEntry(
            OrviaLink.tryParse('orvia://workspace/gone.txt')!,
            conversationId: 'conv-1',
            binding: binding(),
          ),
          throwsA(
            isA<FileLinkException>().having(
              (e) => e.reason,
              'reason',
              FileLinkFailure.missing,
            ),
          ),
        );
      },
    );

    test(
      'rejects file and directory symlinks escaping a linked root',
      () async {
        final outside = File(p.join(tempDir.path, 'secret.txt'))
          ..writeAsStringSync('private');
        Link(p.join(workspaceRoot.path, 'escape.txt')).createSync(outside.path);
        Link(p.join(workspaceRoot.path, 'escape-dir')).createSync(tempDir.path);
        for (final path in [
          'escape.txt',
          'escape-dir',
          'escape-dir/secret.txt',
        ]) {
          expect(
            await resolver.resolveToHostEntry(
              OrviaLink.tryParse('orvia://workspace/$path')!,
              conversationId: 'conv-1',
              binding: binding(),
            ),
            isNull,
          );
        }
      },
      skip: Platform.isWindows ? 'requires symlink privileges' : false,
    );

    test(
      'external references survive rename but reject revoked or removed grants',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = SandboxChannelHarness();
        final root = Directory(p.join(tempDir.path, 'external'))..createSync();
        final file = File(p.join(root.path, '\u62A5\u544A.txt'))
          ..writeAsStringSync('ok');
        var revoked = false;
        harness.handler = (call) {
          if (call.method == 'resolveDirectory') {
            if (revoked) {
              throw PlatformException(code: 'external_folder_unavailable');
            }
            return {'path': root.path, 'token': 'grant'};
          }
          return null;
        };
        harness.install();
        final mounts = ExternalMountsProvider(
          store: ExtensionEntityStore(database),
          channel: harness.channel,
        );
        try {
          await mounts.loaded;
          await mounts.add(
            WorkspaceDirectory(
              path: root.path,
              access: const WorkspaceDirectoryAccess(
                platform: 'android',
                token: 'grant',
              ),
            ),
            name: 'Data',
            readOnly: true,
          );
          final paths = WorkspacePaths.sandboxed(
            workspaceHostRoot: workspaceRoot.path,
            sessionHostDir: appData.path,
            skillsHostDir: appData.path,
            externalMounts: mounts.activeMounts,
          );
          final link = WorkspaceToolsService.linkFor(
            await paths.resolveReal(
              '/mounts/Data/\u62A5\u544A.txt',
              cwd: '/workspace',
            ),
            paths: paths,
          )!;
          final parsed = OrviaLink.tryParse(link)!;
          expect(parsed.mountId, mounts.entries.single.id);
          final mountResolver = FileLinkResolver(
            workspaces: workspaces,
            externalMounts: mounts,
          );
          await mounts.update(parsed.mountId!, name: 'Renamed', readOnly: true);
          expect(
            (await mountResolver.resolveToHostFile(
              parsed,
              conversationId: 'conv-1',
              binding: binding(),
            ))?.path,
            file.path,
          );
          final rootLink = OrviaLink.tryParse(
            'orvia://mounts/${parsed.mountId}',
          )!;
          expect(
            await mountResolver.resolveToHostEntry(
              rootLink,
              conversationId: 'conv-1',
              binding: binding(),
            ),
            isA<Directory>(),
          );
          revoked = true;
          await expectLater(
            mountResolver.resolveToHostEntry(
              parsed,
              conversationId: 'conv-1',
              binding: binding(),
            ),
            throwsA(
              isA<FileLinkException>().having(
                (e) => e.reason,
                'reason',
                FileLinkFailure.mountUnavailable,
              ),
            ),
          );
          revoked = false;
          await mounts.remove(parsed.mountId!);
          await mounts.add(
            WorkspaceDirectory(
              path: root.path,
              access: const WorkspaceDirectoryAccess(
                platform: 'android',
                token: 'grant',
              ),
            ),
            name: 'Data',
            readOnly: true,
          );
          expect(
            await mountResolver.resolveToHostFile(
              parsed,
              conversationId: 'conv-1',
              binding: binding(),
            ),
            isNull,
          );
        } finally {
          mounts.dispose();
          harness.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test('terminal links do not resolve to a file', () async {
      final resolved = await resolver.resolveToHostFile(
        OrviaLink.tryParse('orvia://terminal?cmd=pwd')!,
        conversationId: 'conv-1',
        binding: binding(),
      );
      expect(resolved, isNull);
    });
  });
}
