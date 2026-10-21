import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:orvia/core/services/chat/chat_service.dart';
import 'package:orvia/utils/sandbox_path_resolver.dart';

import '../../../support/business_test_harness.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform oldPaths;
  late BusinessTestHarness harness;
  final services = <ChatService>[];

  ChatService makeService() {
    final service = ChatService(businessPreferences: harness.preferences);
    services.add(service);
    return service;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('orvia-mcp-defaults-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(root.path);
    SandboxPathResolver.debugSetDirs(docsDir: root.path, supportDir: root.path);
    harness = await BusinessTestHarness.create();
  });

  tearDown(() async {
    for (final service in services) {
      await service.close();
    }
    services.clear();
    await harness.close();
    PathProviderPlatform.instance = oldPaths;
    SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
    await root.delete(recursive: true);
  });

  test('unsent draft MCP selections survive app restart', () async {
    final first = makeService();
    final draft = await first.createDraftConversation(title: 'Not yet sent');
    expect(first.getConversationMcpServers(draft.id), isEmpty);

    await first.setConversationMcpServers(draft.id, ['github', 'search']);
    final saved = harness.preferences.getStringList(
      'conversation_default_mcp_server_ids_v1',
    );
    expect(saved, ['github', 'search']);

    await first.close();
    services.remove(first);

    final restarted = makeService();
    final nextDraft = await restarted.createDraftConversation(title: 'New');
    final selected = restarted.getConversationMcpServers(nextDraft.id);
    expect(selected, ['github', 'search']);
  });

  test('explicitly clearing selection stays cleared on restart', () async {
    final first = makeService();
    final persisted = await first.createConversation(title: 'Old chat');
    await first.setConversationMcpServers(persisted.id, ['github']);

    final draft = await first.createDraftConversation(title: 'New draft');
    expect(first.getConversationMcpServers(draft.id), ['github']);
    await first.setConversationMcpServers(draft.id, const <String>[]);
    final saved = harness.preferences.getStringList(
      'conversation_default_mcp_server_ids_v1',
    );
    expect(saved, isEmpty);

    await first.close();
    services.remove(first);

    final restarted = makeService();
    await restarted.init();
    expect(restarted.getConversationMcpServers(persisted.id), ['github']);
    final newDraft = await restarted.createDraftConversation();
    expect(restarted.getConversationMcpServers(newDraft.id), isEmpty);
  });

  test('new chats use global sticky MCP choices after restart', () async {
    await harness.preferences.setStringList('mcp_sticky_selection_v1', [
      'github',
      'search',
    ]);
    final first = makeService();
    final initial = await first.createDraftConversation();
    expect(first.getConversationMcpServers(initial.id), ['github', 'search']);

    await first.close();
    services.remove(first);

    final reopened = makeService();
    final fresh = await reopened.createDraftConversation();
    expect(reopened.getConversationMcpServers(fresh.id), ['github', 'search']);
    // An older conversation with a saved empty list still inherits enabled
    // global tools, instead of silently showing them as off.
    await reopened.setConversationMcpServers(fresh.id, const <String>[]);
    expect(reopened.getConversationMcpServers(fresh.id), ['github', 'search']);

    await harness.preferences.setStringList(
      'mcp_sticky_selection_v1',
      const <String>[],
    );
    final cleared = await reopened.createDraftConversation();
    expect(reopened.getConversationMcpServers(cleared.id), isEmpty);
  });

  test('background conversations do not inherit active chat MCPs', () async {
    final chat = makeService();
    final draft = await chat.createDraftConversation();
    await chat.setConversationMcpServers(draft.id, ['github']);

    final background = await chat.createConversation(
      title: 'Background job',
      activate: false,
    );
    expect(background.mcpServerIds, isEmpty);

    final foreground = await chat.createConversation(title: 'Foreground');
    expect(foreground.mcpServerIds, ['github']);
  });
}
