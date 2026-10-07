import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/services/mcp/orvia_mcp_presets.dart';

void main() {
  test('starter catalogue has unique valid HTTPS endpoints', () {
    expect(orviaMcpPresets, isNotEmpty);
    final names = <String>{};
    final urls = <String>{};

    for (final preset in orviaMcpPresets) {
      expect(preset.name.trim(), isNotEmpty);
      expect(preset.description.trim(), isNotEmpty);
      final uri = Uri.parse(preset.url);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.userInfo, isEmpty);
      expect(uri.query, isEmpty);
      expect(uri.fragment, isEmpty);
      expect(names.add(preset.name.toLowerCase()), isTrue);
      expect(urls.add(preset.url.toLowerCase()), isTrue);
    }
  });

  test('catalogue identifies presets requiring credentials', () {
    expect(
      orviaMcpPresets.where((preset) => preset.requiresAuth).map((p) => p.name),
      contains('Jina AI'),
    );
  });
}
