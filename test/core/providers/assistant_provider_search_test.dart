import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:orvia/core/providers/assistant_provider.dart';

import '../../support/business_preferences_test_harness.dart';

Future<AssistantProvider> _createLoadedAssistantProvider({
  required BusinessPreferencesTestSession session,
  required List<Map<String, Object?>> assistants,
  String currentAssistantId = 'assistant-a',
  bool? legacySearchEnabled,
}) async {
  await session.preferences.setString('assistants_v1', jsonEncode(assistants));
  await session.preferences.setString(
    'current_assistant_id_v1',
    currentAssistantId,
  );
  if (legacySearchEnabled != null) {
    await session.preferences.setBool('search_enabled_v1', legacySearchEnabled);
  }

  final provider = AssistantProvider(preferences: session.preferences);
  for (var i = 0; i < 25; i++) {
    if (provider.assistants.length == assistants.length) return provider;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BusinessPreferencesTestHarness harness;
  late BusinessPreferencesTestSession session;

  setUp(() async {
    harness = await BusinessPreferencesTestHarness.create();
    session = await harness.open();
  });

  tearDown(() => harness.dispose());

  group('AssistantProvider per-assistant search', () {
    test('does not apply the legacy global preference at runtime', () async {
      final provider = await _createLoadedAssistantProvider(
        session: session,
        legacySearchEnabled: true,
        assistants: const [
          {'id': 'assistant-a', 'name': 'A'},
          {'id': 'assistant-b', 'name': 'B'},
        ],
      );

      expect(provider.assistants.map((a) => a.searchEnabled), [
        isFalse,
        isFalse,
      ]);
    });

    test(
      'keeps explicit assistant search values without consulting legacy state',
      () async {
        final provider = await _createLoadedAssistantProvider(
          session: session,
          legacySearchEnabled: true,
          assistants: const [
            {'id': 'assistant-a', 'name': 'A', 'searchEnabled': false},
            {'id': 'assistant-b', 'name': 'B'},
          ],
        );

        expect(provider.getById('assistant-a')?.searchEnabled, isFalse);
        expect(provider.getById('assistant-b')?.searchEnabled, isFalse);
      },
    );

    test(
      'concurrent MCP toggles persist without overwriting each other',
      () async {
        final provider = await _createLoadedAssistantProvider(
          session: session,
          assistants: const [
            {'id': 'assistant-a', 'name': 'A'},
          ],
        );

        await Future.wait([
          provider.setMcpServerEnabledForAssistant(
            'assistant-a',
            'github',
            true,
          ),
          provider.setMcpServerEnabledForAssistant(
            'assistant-a',
            'search',
            true,
          ),
        ]);

        final selected = provider.getById('assistant-a')!.mcpServerIds.toSet();
        expect(selected, {'github', 'search'});

        final restarted = AssistantProvider(preferences: session.preferences);
        await restarted.loaded;
        final restored = restarted.getById('assistant-a')!.mcpServerIds.toSet();
        expect(restored, {'github', 'search'});
      },
    );

    test(
      'MCP switches stay on across assistant changes and cold reload',
      () async {
        final provider = await _createLoadedAssistantProvider(
          session: session,
          assistants: const [
            {'id': 'assistant-a', 'name': 'A'},
            {'id': 'assistant-b', 'name': 'B'},
          ],
        );
        await provider.loaded;

        await provider.setMcpServerEnabledForAssistant(
          'assistant-a',
          'github',
          true,
        );
        expect(provider.getById('assistant-b')!.mcpServerIds, ['github']);
        await provider.setCurrentAssistant('assistant-b');

        final reloaded = AssistantProvider(preferences: session.preferences);
        await reloaded.loaded;
        expect(reloaded.stickyMcpServerIds, ['github']);
        expect(reloaded.getById('assistant-a')!.mcpServerIds, ['github']);
        expect(reloaded.getById('assistant-b')!.mcpServerIds, ['github']);

        final newId = await reloaded.addAssistant(name: 'New');
        expect(reloaded.getById(newId)!.mcpServerIds, ['github']);

        await reloaded.setMcpServerEnabledForAssistant(
          'assistant-b',
          'github',
          false,
        );
        final afterDisabled = AssistantProvider(
          preferences: session.preferences,
        );
        await afterDisabled.loaded;
        expect(afterDisabled.stickyMcpServerIds, isEmpty);
        expect(
          afterDisabled.assistants.every((a) => a.mcpServerIds.isEmpty),
          isTrue,
        );
      },
    );

    test(
      'editing from a stale assistant snapshot never switches MCP off',
      () async {
        final provider = await _createLoadedAssistantProvider(
          session: session,
          assistants: const [
            {'id': 'assistant-a', 'name': 'A'},
            {'id': 'assistant-b', 'name': 'B'},
          ],
        );
        await provider.loaded;
        final stale = provider.getById('assistant-b')!;
        await provider.setMcpServerEnabledForAssistant(
          'assistant-a',
          'github',
          true,
        );
        await provider.updateAssistant(stale.copyWith(name: 'Updated'));
        expect(provider.getById('assistant-b')!.mcpServerIds, ['github']);

        await provider.setStickyMcpServerIds(['github', 'search']);
        final reloaded = AssistantProvider(preferences: session.preferences);
        await reloaded.loaded;
        expect(reloaded.stickyMcpServerIds.toSet(), {'github', 'search'});

        await reloaded.setStickyMcpServerIds(const <String>[]);
        final disabled = AssistantProvider(preferences: session.preferences);
        await disabled.loaded;
        expect(disabled.stickyMcpServerIds, isEmpty);
      },
    );

    test('migrates saved chat MCP selection when assistant has none', () async {
      await session.preferences.setStringList(
        'conversation_default_mcp_server_ids_v1',
        ['github', 'search'],
      );
      final provider = await _createLoadedAssistantProvider(
        session: session,
        assistants: const [
          {'id': 'assistant-a', 'name': 'A'},
        ],
      );
      await provider.loaded;
      expect(provider.stickyMcpServerIds.toSet(), {'github', 'search'});
      expect(provider.getById('assistant-a')!.mcpServerIds.toSet(), {
        'github',
        'search',
      });
    });

    test('updates only the current assistant search value', () async {
      final provider = await _createLoadedAssistantProvider(
        session: session,
        assistants: const [
          {'id': 'assistant-a', 'name': 'A'},
          {'id': 'assistant-b', 'name': 'B'},
        ],
      );

      await provider.setSearchEnabledForCurrentAssistant(true);

      expect(provider.getById('assistant-a')?.searchEnabled, isTrue);
      expect(provider.getById('assistant-b')?.searchEnabled, isFalse);

      await provider.setCurrentAssistant('assistant-b');

      expect(provider.currentSearchEnabled, isFalse);
    });
  });
}
