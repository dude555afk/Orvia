import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/services/api/chat_api_helpers.dart';

void main() {
  group('anonymous OpenAI-compatible gateway headers', () {
    test('omits an empty Bearer authorization header', () {
      final kilo = ProviderConfig.defaultsFor('Kilo');

      final headers = customHeaders(
        kilo,
        'kilo-auto/free',
        baseHeaders: const {'Authorization': 'Bearer '},
      );

      expect(headers.keys, isNot(contains('Authorization')));
    });

    test('preserves a non-empty authorization token', () {
      final openRouter = ProviderConfig.defaultsFor('OpenRouter');

      final headers = customHeaders(
        openRouter,
        'openrouter/free',
        baseHeaders: const {'Authorization': 'Bearer test-token'},
      );

      expect(headers['Authorization'], 'Bearer test-token');
    });
  });
}
