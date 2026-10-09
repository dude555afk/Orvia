import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/models/auto_retry_options.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/services/api/chat_api_service.dart';

void main() {
  test(
    'Kilo-compatible streaming retains free model ID and sends once',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      Map<String, dynamic>? seenBody;
      String? seenPath;
      server.listen((request) async {
        requests++;
        seenPath = request.uri.path;
        seenBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"id":"test","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      final config = ProviderConfig(
        id: 'KiloGateway',
        enabled: true,
        name: 'Kilo Gateway',
        apiKey: '',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        providerType: ProviderKind.openai,
      );

      await for (final _ in ChatApiService.sendMessageStream(
        config: config,
        modelId: 'stepfun/step-5-preview-free',
        messages: const <Map<String, dynamic>>[
          {'role': 'user', 'content': 'Hello'},
        ],
        retryOverride: const AutoRetryOptions.defaults(),
      )) {}

      expect(requests, 1);
      expect(seenPath, '/v1/chat/completions');
      expect(seenBody?['model'], 'stepfun/step-5-preview-free');
      expect(seenBody?['stream'], true);
    },
  );
}
