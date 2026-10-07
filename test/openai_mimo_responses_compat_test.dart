import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/services/api/chat_api_service.dart';
import 'support/collect_generation.dart';
import 'support/legacy_reasoning.dart';

ProviderConfig _mimoConfig(String baseUrl) {
  return ProviderConfig(
    id: 'XiaomiMiMo',
    enabled: true,
    name: 'Xiaomi MiMo',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: true,
  );
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  return jsonDecode(await utf8.decoder.bind(request).join())
      as Map<String, dynamic>;
}

void main() {
  group('Xiaomi MiMo Responses compatibility', () {
    test('streams reasoning text and cached token usage', () async {
      late Map<String, dynamic> requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requestBody = await _readJsonBody(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: ${jsonEncode({'type': 'response.reasoning_text.delta', 'sequence_number': 1, 'output_index': 0, 'content_index': 0, 'item_id': 'reasoning-mimo', 'delta': '\u5148\u6BD4\u8F83\u4E24\u4E2A\u5C0F\u6570。'})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'sequence_number': 2, 'output_index': 1, 'content_index': 0, 'item_id': 'message-mimo', 'delta': '9.8 \u66F4\u5927。'})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({
            'type': 'response.completed',
            'sequence_number': 3,
            'response': {
              'status': 'completed',
              'output': const [],
              'usage': {
                'input_tokens': 100,
                'input_tokens_details': {'cached_tokens': 64},
                'output_tokens': 30,
                'output_tokens_details': {'reasoning_tokens': 20},
                'total_tokens': 130,
              },
            },
          })}\n\n',
        );
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      final chunks = await ChatApiService.sendMessageStream(
        config: _mimoConfig(baseUrl),
        modelId: 'mimo-v2.5-pro',
        messages: const [
          {'role': 'user', 'content': '9.11 \u548C 9.8 \u54EA\u4E2A\u5927？'},
        ],
        reasoning: legacyBudget(2000),
      ).toList();

      expect(requestBody['reasoning'], {'effort': 'low'});
      expect(requestBody.containsKey('thinking'), isFalse);
      expect(requestBody.containsKey('reasoning_effort'), isFalse);
      expect(
        chunks.joinedReasoning,
        '\u5148\u6BD4\u8F83\u4E24\u4E2A\u5C0F\u6570。',
      );
      expect(chunks.joinedContent, contains('9.8 \u66F4\u5927。'));
      expect(chunks.isGenerationDone, isTrue);
      expect(chunks.lastUsage?.cachedTokens, 64);
      expect(chunks.lastUsage?.reasoningTokens, 20);
      expect(chunks.lastUsage?.totalTokens, 130);
    });

    test(
      'non-stream returns reasoning and uses default thinking mode',
      () async {
        late Map<String, dynamic> requestBody;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          requestBody = await _readJsonBody(request);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'resp-mimo',
              'object': 'response',
              'status': 'completed',
              'output': [
                {
                  'id': 'reasoning-mimo',
                  'type': 'reasoning',
                  'status': 'completed',
                  'content': [
                    {
                      'type': 'reasoning_text',
                      'text': '\u5148\u5206\u6790\u95EE\u9898。',
                    },
                  ],
                },
                {
                  'id': 'message-mimo',
                  'type': 'message',
                  'status': 'completed',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': '\u8FD9\u662F\u7B54\u6848。',
                    },
                  ],
                },
              ],
              'output_text': '\u8FD9\u662F\u7B54\u6848。',
              'usage': {
                'input_tokens': 50,
                'input_tokens_details': {'cached_tokens': 32},
                'output_tokens': 10,
                'output_tokens_details': {'reasoning_tokens': 6},
                'total_tokens': 60,
              },
            }),
          );
          await request.response.close();
        });

        final baseUrl = 'http://${server.address.address}:${server.port}/v1';
        final chunks = await ChatApiService.sendMessageStream(
          config: _mimoConfig(baseUrl),
          modelId: 'mimo-v2.5-pro',
          messages: const [
            {'role': 'user', 'content': '\u8BF7\u56DE\u7B54\u95EE\u9898'},
          ],
          stream: false,
        ).toList();

        expect(requestBody.containsKey('reasoning'), isFalse);
        expect(requestBody.containsKey('thinking'), isFalse);
        expect(chunks.joinedContent, '\u8FD9\u662F\u7B54\u6848。');
        expect(chunks.joinedReasoning, '\u5148\u5206\u6790\u95EE\u9898。');
        expect(chunks.lastUsage?.cachedTokens, 32);
        expect(chunks.lastUsage?.totalTokens, 60);
      },
    );

    test('off reasoning sends effort none', () async {
      late Map<String, dynamic> requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        requestBody = await _readJsonBody(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'resp-mimo',
            'object': 'response',
            'status': 'completed',
            'output': const [],
            'output_text': 'ok',
            'usage': {
              'input_tokens': 1,
              'input_tokens_details': {'cached_tokens': 0},
              'output_tokens': 1,
              'output_tokens_details': {'reasoning_tokens': 0},
              'total_tokens': 2,
            },
          }),
        );
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      final chunks = await ChatApiService.sendMessageStream(
        config: _mimoConfig(baseUrl),
        modelId: 'mimo-v2.5-pro',
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        reasoning: legacyBudget(0),
        stream: false,
      ).toList();

      expect(chunks.isGenerationDone, isTrue);
      expect(requestBody['reasoning'], {'effort': 'none'});
      expect(requestBody.containsKey('thinking'), isFalse);
      expect(requestBody.containsKey('reasoning_effort'), isFalse);
    });
  });
}
