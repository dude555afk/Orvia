import 'package:Kelivo/features/settings/search/settings_search_index.dart';
import 'package:Kelivo/l10n/app_localizations_zh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Run explicitly; benchmarks are excluded from the default test suite.
void main() {
  test('settings search index and keystroke timings', () {
    final build = Stopwatch()..start();
    final index = SettingsSearchIndex(
      AppLocalizationsZh(),
      platform: TargetPlatform.macOS,
    );
    build.stop();
    const queries = [
      '\u5B57',
      '\u5B57\u4F53',
      '\u8BED\u8A00',
      'font size',
      'tool cards',
      '\u804A\u5929',
      '\u4E0D\u5B58\u5728\u7684\u8BBE\u7F6E',
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
