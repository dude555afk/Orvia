import 'package:orvia/features/settings/search/settings_search_index.dart';
import 'package:orvia/l10n/app_localizations_en.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Run explicitly; benchmarks are excluded from the default test suite.
void main() {
  test('settings search index and keystroke timings', () {
    final build = Stopwatch()..start();
    final index = SettingsSearchIndex(
      AppLocalizationsEn(),
      platform: TargetPlatform.macOS,
    );
    build.stop();
    const queries = [
      'font',
      'font size',
      'language',
      'tool cards',
      'chat',
      'message style',
      'nonexistent setting',
      'api key',
    ];
    for (var i = 0; i < 100; i++) {
      index.search(queries[i % queries.length]);
    }
    final samples = <int>[];
    final timer = Stopwatch();
    for (var i = 0; i < 2000; i++) {
      timer.reset();
      timer.start();
      index.search(queries[i % queries.length]);
      timer.stop();
      samples.add(timer.elapsedMicroseconds);
    }
    samples.sort();
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    debugPrint(
      'Settings search: ${index.entries.length} entries; '
      'build ${build.elapsedMicroseconds} us; '
      'mean ${mean.toStringAsFixed(1)} us; '
      'p95 ${samples[(samples.length * 0.95).floor()]} us; '
      'max ${samples.last} us (debug test runtime).',
    );
  });
}
