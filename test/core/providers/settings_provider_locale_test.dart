import 'package:orvia/core/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps a supported English locale before async settings load', () async {
    final harness = await createBusinessTestHarness(
      initial: const {'app_locale_v1': 'en_US'},
    );

    final settings = SettingsProvider(harness.preferences);

    expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
    await settings.loaded;
    expect(harness.preferences.get('app_locale_v1'), 'en_US');
  });

  for (final retiredLocale in <String>['zh_CN', 'zh_Hant']) {
    test('migrates saved $retiredLocale to follow system', () async {
      final harness = await createBusinessTestHarness(
        initial: {'app_locale_v1': retiredLocale},
      );
      final settings = SettingsProvider(harness.preferences);
      expect(settings.appLocaleForMaterialApp, isNull);
      await settings.loaded;
      expect(settings.appLocaleForMaterialApp, isNull);
      expect(harness.preferences.get('app_locale_v1'), 'system');
    });
  }

  test('unsupported locale requests always use the English UI', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setAppLocale(const Locale('zh', 'CN'));
    expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
    expect(harness.preferences.get('app_locale_v1'), 'en_US');
  });

  for (final testCase in <({String name, Object value})>[
    (name: 'empty string', value: ''),
    (name: 'whitespace string', value: ' '),
    (name: 'unknown string', value: 'fr_FR'),
    (name: 'non-string value', value: 1),
  ]) {
    test('follows the system before loading for ${testCase.name}', () async {
      final harness = await createBusinessTestHarness(
        initial: {'app_locale_v1': testCase.value},
      );

      final settings = SettingsProvider(harness.preferences);

      expect(settings.appLocaleForMaterialApp, isNull);
      await settings.loaded;
      expect(settings.appLocaleForMaterialApp, isNull);
      expect(harness.preferences.get('app_locale_v1'), 'system');
    });
  }
}
