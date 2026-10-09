import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/features/home/controllers/home_view_model.dart';

ChatMessage _message({
  required String id,
  required String role,
  required String content,
  String? groupId,
  int version = 0,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: content,
    conversationId: 'conversation-1',
    groupId: groupId ?? id,
    version: version,
  );
}

void main() {
  group('buildCompressContextContent', () {
    test(
      'Short content remains unchanged within limit',
      () {
        const joined = 'User: hello\n\nAssistant: hi';

        expect(
          buildCompressContextContent(
            joined,
            const CompressContextOptions(
              mode: CompressContextLimitMode.start,
              maxChars: 6000,
            ),
          ),
          joined,
        );
      },
    );

    test('Oversized content can preserve the beginning', () {
      final early = 'User: first round\n\nAssistant: early answer\n\n';
      final middle = 'x' * 6000;
      final latest = '\n\nUser: thirtieth round\n\nAssistant: latest answer';
      final joined = '$early$middle$latest';

      final content = buildCompressContextContent(
        joined,
        const CompressContextOptions(
          mode: CompressContextLimitMode.start,
          maxChars: 6000,
        ),
      );

      expect(content.length, 6000);
      expect(content, contains('first round'));
      expect(content, isNot(contains('thirtieth round')));
    });

    test(
      'Oversized content can preserve the recent tail',
      () {
        final early = 'User: first round\n\nAssistant: early answer\n\n';
        final middle = 'x' * 6000;
        final latest = '\n\nUser: thirtieth round\n\nAssistant: latest answer';
        final joined = '$early$middle$latest';

        final content = buildCompressContextContent(
          joined,
          const CompressContextOptions(
            mode: CompressContextLimitMode.recent,
            maxChars: 6000,
          ),
        );

        expect(content.length, 6000);
        expect(content, isNot(contains('first round')));
        expect(content, contains('thirtieth round'));
      },
    );

    test('Unlimited mode preserves complete content', () {
      final joined = 'a' * 7000;

      final content = buildCompressContextContent(
        joined,
        const CompressContextOptions(mode: CompressContextLimitMode.unlimited),
      );

      expect(content, joined);
    });

    test(
      'keepRecent preserves original input without character-window truncation',
      () {
        final joined = 'a' * 7000;

        final content = buildCompressContextContent(
          joined,
          const CompressContextOptions(
            mode: CompressContextLimitMode.keepRecent,
            keepUserMessages: 2,
          ),
        );

        expect(content, joined);
      },
    );

    test('Truncation does not split emoji surrogate pairs', () {
      // '😀' occupies two UTF-16 code units. A raw cut at 4 would tear it.
      const joined = 'abc😀def';

      final start = buildCompressContextContent(
        joined,
        const CompressContextOptions(
          mode: CompressContextLimitMode.start,
          maxChars: 4,
        ),
      );
      expect(start, 'abc');
      expect(() => jsonEncode(start), returnsNormally);

      final recent = buildCompressContextContent(
        joined,
        const CompressContextOptions(
          mode: CompressContextLimitMode.recent,
          maxChars: 4,
        ),
      );
      expect(recent, 'def');
      expect(() => jsonEncode(recent), returnsNormally);
    });
  });

  group('buildConversationTextForCompression', () {
    test(
      'Uses full history to build compression text',
      () {
        final visibleWindow = [
          _message(id: 'u80', role: 'user', content: 'visible user'),
          _message(id: 'a81', role: 'assistant', content: 'visible assistant'),
        ];
        final completeHistory = [
          _message(id: 'u0', role: 'user', content: 'earliest user'),
          _message(id: 'a1', role: 'assistant', content: 'earliest assistant'),
          ...visibleWindow,
        ];

        final text = buildConversationTextForCompression(completeHistory);

        expect(text, contains('User: earliest user'));
        expect(text, contains('Assistant: earliest assistant'));
        expect(text, contains('User: visible user'));
        expect(text, contains('Assistant: visible assistant'));
      },
    );

    test(
      'Compression text skips messages with empty content',
      () {
        final text = buildConversationTextForCompression([
          _message(id: 'u1', role: 'user', content: '  '),
          _message(id: 'a1', role: 'assistant', content: 'answer'),
        ]);

        expect(text, 'Assistant: answer');
      },
    );
  });

  group('HomeViewModel.computeClearContextRemainingMessageCount', () {
    test(
      'Counts persisted total independent of window cache',
      () {
        final count = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: -1,
        );

        expect(count, 100);
      },
    );

    test(
      'Existing clear point counts from persisted truncation position',
      () {
        final count = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: 90,
        );

        expect(count, 10);
      },
    );

    test(
      'Out-of-range truncation position is treated as uncleared',
      () {
        final beyond = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: 101,
        );
        final atEnd = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: 100,
        );

        expect(beyond, 100);
        expect(atEnd, 0);
      },
    );
  });

  group('selectKeepRecentMessages', () {
    test(
      'Retains last N user messages and everything following from user boundary',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: 'a1'),
          _message(id: 'u2', role: 'user', content: 'q2'),
          _message(id: 'a2', role: 'assistant', content: 'a2'),
          _message(id: 'u3', role: 'user', content: 'q3'),
          _message(id: 'a3', role: 'assistant', content: 'a3'),
        ];

        final kept = selectKeepRecentMessages(messages, 2);

        expect(kept.map((m) => m.id).toList(), ['u2', 'a2', 'u3', 'a3']);
      },
    );

    test(
      'Retained region may contain unanswered trailing user message',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: 'a1'),
          _message(id: 'u2', role: 'user', content: 'q2'),
        ];

        final kept = selectKeepRecentMessages(messages, 1);

        expect(kept.map((m) => m.id).toList(), ['u2']);
      },
    );

    test(
      'Returns full list when N covers all user messages',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: 'a1'),
          _message(id: 'u2', role: 'user', content: 'q2'),
        ];

        final kept = selectKeepRecentMessages(messages, 3);

        expect(kept.length, messages.length);
      },
    );

    test(
      'User messages with empty content do not count',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: 'a1'),
          _message(id: 'u2', role: 'user', content: '   '),
          _message(id: 'u3', role: 'user', content: 'q3'),
          _message(id: 'a3', role: 'assistant', content: 'a3'),
        ];

        final kept = selectKeepRecentMessages(messages, 1);

        expect(kept.map((m) => m.id).toList(), ['u3', 'a3']);
      },
    );

    test(
      'Preserves empty assistant tool-call message in retained region',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: ''),
          _message(id: 'u2', role: 'user', content: 'q2'),
          _message(id: 'a2', role: 'assistant', content: ''),
        ];

        final kept = selectKeepRecentMessages(messages, 1);

        expect(kept.map((m) => m.id).toList(), ['u2', 'a2']);
      },
    );

    test('Empty input, no user or N at most zero yields empty', () {
      expect(
        selectKeepRecentMessages([
          _message(id: 'a1', role: 'assistant', content: 'a1'),
        ], 1),
        isEmpty,
      );
      expect(selectKeepRecentMessages(const [], 1), isEmpty);

      final messages = [
        _message(id: 'u1', role: 'user', content: 'q1'),
        _message(id: 'a1', role: 'assistant', content: 'a1'),
      ];
      expect(selectKeepRecentMessages(messages, 0), isEmpty);
      expect(selectKeepRecentMessages(messages, -1), isEmpty);
    });
  });

  group('countUserMessages', () {
    test(
      'Counts only user messages with nonempty content',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', content: 'q1'),
          _message(id: 'a1', role: 'assistant', content: 'a1'),
          _message(id: 'u2', role: 'user', content: '   '),
          _message(id: 'u3', role: 'user', content: 'q3'),
        ];

        expect(countUserMessages(messages), 2);
      },
    );
  });

  group('defaultKeepUserMessageCountFor', () {
    test(
      'Defaults to one when fewer than five user messages',
      () {
        expect(defaultKeepUserMessageCountFor(0), 1);
        expect(defaultKeepUserMessageCountFor(1), 1);
        expect(defaultKeepUserMessageCountFor(2), 1);
        expect(defaultKeepUserMessageCountFor(4), 1);
      },
    );

    test('Defaults to two with five to nine user messages', () {
      expect(defaultKeepUserMessageCountFor(5), 2);
      expect(defaultKeepUserMessageCountFor(9), 2);
    });

    test(
      'Defaults to three with ten or more user messages',
      () {
        expect(defaultKeepUserMessageCountFor(10), 3);
        expect(defaultKeepUserMessageCountFor(100), 3);
      },
    );
  });

  group('estimateCompressionTokens', () {
    test(
      'Retained region estimates tokens by length ratio',
      () {
        final est = estimateCompressionTokens(
          totalText: 'a' * 1000,
          keptText: 'b' * 250,
        );

        // tokenx: 1000 lowercase letters → ceil(1000/7) = 143
        expect(est.totalTokens, 143);
        expect(est.keptTokens, 36);
        expect(est.minResultTokens, 47);
        expect(est.maxResultTokens, 68);
      },
    );

    test('CJK uses tokenx ideograph weighting', () {
      final est = estimateCompressionTokens(
        totalText: '\u4E2D' * 400,
        keptText: '\u4E2D' * 100,
      );

      expect(est.totalTokens, 348);
      expect(est.keptTokens, 87);
    });

    test(
      'Mixed text uses tokenx CJK weighting for matching text',
      () {
        final est = estimateCompressionTokens(
          totalText: '\u4E2D' * 200 + 'a' * 400,
          keptText: '',
        );

        expect(est.totalTokens, 522);
      },
    );

    test('Empty text returns all zero estimates', () {
      final est = estimateCompressionTokens(totalText: '', keptText: '');

      expect(est.totalTokens, 0);
      expect(est.keptTokens, 0);
      expect(est.minResultTokens, 0);
      expect(est.maxResultTokens, 0);
    });

    test('Upper interval bound is never below lower bound', () {
      final est = estimateCompressionTokens(
        totalText: 'a' * 5000,
        keptText: 'b' * 100,
      );

      expect(est.minResultTokens, lessThanOrEqualTo(est.maxResultTokens));
      expect(est.keptTokens, lessThanOrEqualTo(est.totalTokens));
    });
  });

  group('buildBoundedConversationText', () {
    test(
      'start matches concatenate-then-truncate on typical lengths',
      () {
        final messages = [
          _message(id: 'u1', role: 'user', content: 'first round'),
          _message(id: 'a1', role: 'assistant', content: 'early answer'),
          _message(id: 'u2', role: 'user', content: 'x' * 7000),
          _message(id: 'a2', role: 'assistant', content: 'thirtieth round'),
        ];
        const options = CompressContextOptions(
          mode: CompressContextLimitMode.start,
          maxChars: 6000,
        );
        final joined = buildConversationTextForCompression(messages);

        expect(
          buildBoundedConversationText(
            messages,
            mode: CompressContextLimitMode.start,
            maxChars: 6000,
          ),
          buildCompressContextContent(joined, options),
        );
      },
    );

    test(
      'recent matches concatenate-then-truncate on typical lengths',
      () {
        final messages = [
          _message(id: 'u1', role: 'user', content: 'first round'),
          _message(id: 'a1', role: 'assistant', content: 'early answer'),
          _message(id: 'u2', role: 'user', content: 'x' * 7000),
          _message(id: 'a2', role: 'assistant', content: 'thirtieth round'),
        ];
        const options = CompressContextOptions(
          mode: CompressContextLimitMode.recent,
          maxChars: 6000,
        );
        final joined = buildConversationTextForCompression(messages);

        expect(
          buildBoundedConversationText(
            messages,
            mode: CompressContextLimitMode.recent,
            maxChars: 6000,
          ),
          buildCompressContextContent(joined, options),
        );
      },
    );

    test(
      'Incrementally truncates long history within window without joining all text',
      () {
        final messages = [
          for (var i = 0; i < 200; i++)
            _message(
              id: 'm$i',
              role: i.isEven ? 'user' : 'assistant',
              content: 'block-$i ${'x' * 500}',
            ),
        ];

        final start = buildBoundedConversationText(
          messages,
          mode: CompressContextLimitMode.start,
          maxChars: 6000,
        );
        expect(start.length, lessThanOrEqualTo(6000));
        expect(start, contains('block-0'));
        expect(start, isNot(contains('block-199')));

        final recent = buildBoundedConversationText(
          messages,
          mode: CompressContextLimitMode.recent,
          maxChars: 6000,
        );
        expect(recent.length, lessThanOrEqualTo(6000));
        expect(recent, contains('block-199'));
        expect(recent, isNot(contains('block-0')));
      },
    );
  });

  group('chunkMessagesForCompression', () {
    test(
      'Splits messages over budget into chunks at message boundaries',
      () {
        final messages = [
          _message(id: 'u1', role: 'user', content: 'aaa'),
          _message(id: 'a1', role: 'assistant', content: 'bbb'),
          _message(id: 'u2', role: 'user', content: 'ccc'),
        ];

        final chunks = chunkMessagesForCompression(messages, maxChars: 20);

        expect(chunks, hasLength(greaterThan(1)));
        expect(chunks.every((chunk) => chunk.length <= 20), isTrue);
        expect(chunks.join('\n\n'), contains('User: aaa'));
        expect(chunks.join('\n\n'), contains('User: ccc'));
      },
    );

    test(
      'Splits single long message safely on UTF-16 boundaries',
      () {
        const emoji = '😀';
        final messages = [
          _message(id: 'u1', role: 'user', content: 'aa$emoji${'b' * 30}'),
        ];
        final line = conversationLineForCompression(messages.single)!;

        final chunks = chunkMessagesForCompression(messages, maxChars: 9);

        expect(chunks, hasLength(greaterThan(1)));
        expect(chunks.join(), line);
        expect(chunks.join(), contains(emoji));
        for (final chunk in chunks) {
          expect(() => jsonEncode(chunk), returnsNormally);
        }
      },
    );
  });

  group('buildCompressRequestContents', () {
    test(
      'unlimited chunks beyond safety limit without losing messages',
      () {
        final messages = [
          for (var i = 0; i < 5; i++)
            _message(id: 'u$i', role: 'user', content: 'msg-$i ${'x' * 40}'),
        ];

        final chunks = buildCompressRequestContents(
          messages,
          const CompressContextOptions(
            mode: CompressContextLimitMode.unlimited,
          ),
          safeRequestChars: 50,
        );

        expect(chunks, hasLength(greaterThan(1)));
        expect(chunks.every((chunk) => chunk.length <= 50), isTrue);
        expect(chunks.join('\n\n'), contains('msg-0'));
        expect(chunks.join('\n\n'), contains('msg-4'));
      },
    );

    test(
      'keepRecent older side obeys safety limit',
      () {
        final messages = [
          for (var i = 0; i < 4; i++)
            _message(id: 'u$i', role: 'user', content: 'old-$i ${'y' * 40}'),
        ];

        final chunks = buildCompressRequestContents(
          messages,
          const CompressContextOptions(
            mode: CompressContextLimitMode.keepRecent,
            keepUserMessages: 1,
          ),
          safeRequestChars: 50,
        );

        expect(chunks, hasLength(greaterThan(1)));
        expect(chunks.join('\n\n'), contains('old-0'));
      },
    );
  });

  group('compressRequestCharBudget', () {
    test('unknown context uses the conservative 32k default', () {
      expect(compressRequestCharBudget(), 35840);
      expect(compressRequestCharBudget(contextWindowTokens: 0), 35840);
      expect(compressRequestCharBudget(contextWindowTokens: -1), 35840);
    });

    test('32k window stays at window-minus-reserves', () {
      const window = 32000;
      final budget = compressRequestCharBudget(contextWindowTokens: window);
      final maxInputTokens =
          (window * (1 - CompressContextOptions.contextReserveFraction))
              .floor();

      expect(budget, 35840);
      expect(budget, lessThan(window * CompressContextOptions.charsPerToken));
      expect(
        (budget / CompressContextOptions.charsPerToken).ceil(),
        lessThanOrEqualTo(maxInputTokens),
      );
    });

    test('128k+ is larger than the 32k default but still hard-capped', () {
      final budget128k = compressRequestCharBudget(contextWindowTokens: 128000);
      final budget1m = compressRequestCharBudget(contextWindowTokens: 1000000);

      expect(budget128k, greaterThan(compressRequestCharBudget()));
      expect(budget128k, CompressContextOptions.safeRequestChars);
      expect(budget1m, CompressContextOptions.safeRequestChars);
      expect(
        budget128k,
        lessThanOrEqualTo(CompressContextOptions.safeRequestChars),
      );
    });
  });

  group('resolveCompressContextModel', () {
    test('Prefers explicitly chosen compression model', () {
      final resolved = resolveCompressContextModel(
        compressProvider: 'OpenAI',
        compressModelId: 'gpt-4o-mini',
        summaryProvider: 'Gemini',
        summaryModelId: 'gemini-2.5-flash',
        currentProvider: 'DeepSeek',
        currentModelId: 'deepseek-chat',
      );

      expect(resolved.providerKey, 'OpenAI');
      expect(resolved.modelId, 'gpt-4o-mini');
    });

    test(
      'Falls back summary, title, assistant, current when compression model absent',
      () {
        expect(
          resolveCompressContextModel(
            summaryProvider: 'Gemini',
            summaryModelId: 'gemini-2.5-flash',
            titleProvider: 'OpenAI',
            titleModelId: 'gpt-4o-mini',
            currentProvider: 'DeepSeek',
            currentModelId: 'deepseek-chat',
          ),
          (providerKey: 'Gemini', modelId: 'gemini-2.5-flash'),
        );
        expect(
          resolveCompressContextModel(
            titleProvider: 'OpenAI',
            titleModelId: 'gpt-4o-mini',
            assistantProvider: 'Claude',
            assistantModelId: 'claude-sonnet',
            currentProvider: 'DeepSeek',
            currentModelId: 'deepseek-chat',
          ),
          (providerKey: 'OpenAI', modelId: 'gpt-4o-mini'),
        );
        expect(
          resolveCompressContextModel(
            assistantProvider: 'Claude',
            assistantModelId: 'claude-sonnet',
            currentProvider: 'DeepSeek',
            currentModelId: 'deepseek-chat',
          ),
          (providerKey: 'Claude', modelId: 'claude-sonnet'),
        );
        expect(
          resolveCompressContextModel(
            currentProvider: 'DeepSeek',
            currentModelId: 'deepseek-chat',
          ),
          (providerKey: 'DeepSeek', modelId: 'deepseek-chat'),
        );
      },
    );

    test('Returns null when all models are unset', () {
      final resolved = resolveCompressContextModel();

      expect(resolved.providerKey, isNull);
      expect(resolved.modelId, isNull);
    });
  });

  group('isContextLengthError', () {
    test('matches likely input-token overflow phrases', () {
      const overflowing = <String>[
        'HTTP 400: context_length_exceeded',
        "This model's maximum context length is 8192 tokens",
        'The request exceeds the context window',
        'max context size exceeded',
        'too many tokens in the prompt',
        'prompt is too long: 40000 tokens > 32000 maximum',
        'prompt too long',
        'input is too long',
        'input too long for this model',
        'Please reduce the length of the messages',
        'Please reduce the length of the prompt',
        'The input token count exceeds the maximum number of tokens allowed',
        'HttpException: max_tokens exceeded for this request',
      ];
      for (final message in overflowing) {
        expect(
          isContextLengthError(Exception(message)),
          isTrue,
          reason: message,
        );
      }
    });

    test('does not match unrelated or max_tokens config errors', () {
      const unrelated = <String>[
        '401 unauthorized',
        'rate limit exceeded',
        'empty_summary',
        'max_tokens is required',
        'max_tokens must be at least 1',
        'invalid api key',
        'network timeout',
      ];
      for (final message in unrelated) {
        expect(
          isContextLengthError(Exception(message)),
          isFalse,
          reason: message,
        );
      }
    });
  });

  group('summarizeWithContextRetry', () {
    test('splits on a context error, retries each half, then merges', () async {
      final calls = <String>[];
      final result = await summarizeWithContextRetry(
        'A' * 32,
        minSplitChars: 4,
        summarize: (text) async {
          calls.add(text);
          if (text.contains('A') && text.length > 16) {
            throw Exception('maximum context length exceeded');
          }
          if (text.contains('S:')) return 'M';
          return 'S:${text.length}';
        },
      );

      expect(calls, ['A' * 32, 'A' * 16, 'A' * 16, 'S:16\n\nS:16']);
      expect(result, 'M');
    });

    test('UTF-16 halves stay valid when naive mid would tear a pair', () async {
      final text = 'x${'😀' * 20}';
      expect(text.length ~/ 2, 20);
      final naive = text.substring(0, text.length ~/ 2);
      final naiveLast = naive.codeUnitAt(naive.length - 1);
      expect(naiveLast >= 0xD800 && naiveLast <= 0xDBFF, isTrue);

      final seen = <String>[];
      final result = await summarizeWithContextRetry(
        text,
        minSplitChars: 4,
        summarize: (chunk) async {
          seen.add(chunk);
          _expectValidUtf16(chunk);
          if (chunk == text) {
            throw Exception('context_length_exceeded');
          }
          return 'ok';
        },
      );

      expect(seen.length, 4);
      expect(seen.first, text);
      expect('${seen[1]}${seen[2]}', text);
      expect(result, 'ok');
    });

    test('does not split-retry non-context errors', () async {
      var calls = 0;
      await expectLater(
        summarizeWithContextRetry(
          'A' * 32,
          minSplitChars: 4,
          summarize: (text) async {
            calls++;
            throw Exception('401 unauthorized');
          },
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            contains('401 unauthorized'),
          ),
        ),
      );
      expect(calls, 1);
    });

    test('stops after the split budget instead of looping', () async {
      var calls = 0;
      var splits = 0;
      await expectLater(
        summarizeWithContextRetry(
          'A' * 32,
          maxSplits: 2,
          minSplitChars: 4,
          onSplitRetry: (e, st, text) => splits++,
          summarize: (text) async {
            calls++;
            throw Exception('prompt is too long');
          },
        ),
        throwsA(isA<Exception>()),
      );
      expect(splits, 2);
      expect(calls, 3);
    });

    test('does not split when a half would be below minSplitChars', () async {
      var calls = 0;
      await expectLater(
        summarizeWithContextRetry(
          'A' * 20,
          minSplitChars: 16,
          summarize: (text) async {
            calls++;
            throw Exception('too many tokens');
          },
        ),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });
  });
}

void _expectValidUtf16(String value) {
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      expect(
        i + 1 < value.length &&
            value.codeUnitAt(i + 1) >= 0xDC00 &&
            value.codeUnitAt(i + 1) <= 0xDFFF,
        isTrue,
        reason: 'lone high surrogate at $i',
      );
      i++;
    } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
      fail('lone low surrogate at $i');
    }
  }
}
