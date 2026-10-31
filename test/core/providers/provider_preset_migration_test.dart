import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/providers/settings_provider.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first launch selects OpenRouter Free and keeps Kilo available', () async {
    final harness = await createBusinessTestHarness(initial: {});
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);

    await settings.loaded;

    expect(settings.currentModelProvider, 'OpenRouter');
    expect(settings.currentModelId, 'openrouter/free');
    expect(
      harness.preferences.getString('selected_model_v1'),
      'OpenRouter::openrouter/free',
    );
    expect(settings.providerConfigs.keys, containsAll(['OpenRouter', 'Kilo']));
    expect(
      settings.providerConfigs['Kilo']?.baseUrl,
      'https://ai-gateway.kilo.ai/api/v1',
    );
    expect(
      settings.providerConfigs['Kilo']?.models,
      contains('kilo-auto/free'),
    );
  });

  test('removes retired provider configs and repairs their active selection', () async {
    final retiredProviders = <String, ProviderConfig>{
      'OrviaIN': ProviderConfig.defaultsFor('OrviaIN'),
      'SiliconFlow': ProviderConfig.defaultsFor('SiliconFlow'),
      'DeepSeek': ProviderConfig.defaultsFor('DeepSeek'),
    };
    final initialConfigs = retiredProviders.map(
      (key, config) => MapEntry(key, config.toJson()),
    );
    final harness = await createBusinessTestHarness(
      initial: {
        'provider_configs_v1': jsonEncode(initialConfigs),
        'selected_model_v1': 'OrviaIN::mistral',
        'providers_order_v1': <String>[
          'OrviaIN',
          'SiliconFlow',
          'DeepSeek',
        ],
      },
    );
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);

    await settings.loaded;

    expect(
      settings.providerConfigs.keys,
      isNot(contains(anyOf('OrviaIN', 'SiliconFlow', 'DeepSeek'))),
    );
    expect(settings.currentModelProvider, 'OpenRouter');
    expect(settings.currentModelId, 'openrouter/free');
    expect(
      harness.preferences.getString('selected_model_v1'),
      'OpenRouter::openrouter/free',
    );
    expect(
      settings.providersOrder,
      isNot(contains(anyOf('OrviaIN', 'SiliconFlow', 'DeepSeek'))),
    );
  });

  test('preserves a valid model already selected by the user', () async {
    final openAi = ProviderConfig.defaultsFor('OpenAI').copyWith(
      models: const ['gpt-4o'],
      enabled: true,
    );
    final harness = await createBusinessTestHarness(
      initial: {
        'provider_configs_v1': jsonEncode({'OpenAI': openAi.toJson()}),
        'selected_model_v1': 'OpenAI::gpt-4o',
      },
    );
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);

    await settings.loaded;

    expect(settings.currentModelProvider, 'OpenAI');
    expect(settings.currentModelId, 'gpt-4o');
    expect(
      harness.preferences.getString('selected_model_v1'),
      'OpenAI::gpt-4o',
    );
  });
}
