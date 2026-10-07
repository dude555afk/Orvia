import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';

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
      '\u77ED\u5185\u5BB9\u5728\u9650\u5236\u5185\u4FDD\u6301\u539F\u6837',
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

    test('\u8D85\u957F\u5185\u5BB9\u53EF\u4FDD\u7559\u5F00\u5934', () {
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
      '\u8D85\u957F\u5185\u5BB9\u53EF\u4FDD\u7559\u6700\u8FD1\u5C3E\u90E8',
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

    test('\u65E0\u9650\u5236\u4FDD\u7559\u5B8C\u6574\u5185\u5BB9', () {
      final joined = 'a' * 7000;

      final content = buildCompressContextContent(
        joined,
        const CompressContextOptions(mode: CompressContextLimitMode.unlimited),
      );

      expect(content, joined);
    });

    test(
      'keepRecent \u76F4\u901A\u539F\u6587，\u4E0D\u6309\u5B57\u7B26\u7A97\u622A\u65AD',
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

    test('\u622A\u65AD\u4E0D\u5288\u5F00 emoji \u4EE3\u7406\u5BF9', () {
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
      '\u4F7F\u7528\u5B8C\u6574\u5386\u53F2\u751F\u6210\u538B\u7F29\u6587\u672C',
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
      '\u538B\u7F29\u6587\u672C\u4F1A\u5FFD\u7565\u7A7A\u5185\u5BB9\u6D88\u606F',
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
      '\u8BA1\u6570\u6765\u81EA\u6301\u4E45\u5316\u603B\u6570，\u4E0E\u7A97\u53E3\u7F13\u5B58\u65E0\u5173',
      () {
        final count = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: -1,
        );

        expect(count, 100);
      },
    );

    test(
      '\u5DF2\u6709\u6E05\u7A7A\u70B9\u65F6\u4ECE\u6301\u4E45\u5316\u622A\u65AD\u4F4D\u7F6E\u5F00\u59CB\u8BA1\u6570',
      () {
        final count = HomeViewModel.computeClearContextRemainingMessageCount(
          totalMessages: 100,
          truncateIndex: 90,
        );

        expect(count, 10);
      },
    );

    test(
      '\u622A\u65AD\u4F4D\u7F6E\u8D8A\u754C\u65F6\u6309\u672A\u6E05\u7A7A\u5904\u7406',
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
      '\u4FDD\u7559\u6700\u8FD1 N \u6761\u7528\u6237\u6D88\u606F\u53CA\u5176\u540E\u7684\u5168\u90E8\u6D88\u606F，\u8FB9\u754C\u4EE5\u7528\u6237\u6D88\u606F\u5F00\u59CB',
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
      '\u4FDD\u7559\u533A\u53EF\u5305\u542B\u672A\u7B54\u590D\u7684\u5C3E\u90E8\u7528\u6237\u6D88\u606F',
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
      'N \u8986\u76D6\u5168\u90E8\u7528\u6237\u6D88\u606F\u65F6\u8FD4\u56DE\u5B8C\u6574\u5217\u8868（\u65E0\u53EF\u538B\u7F29\u5185\u5BB9）',
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
      '\u7A7A\u5185\u5BB9\u7684\u7528\u6237\u6D88\u606F\u4E0D\u53C2\u4E0E\u8BA1\u6570',
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
      '\u4FDD\u7559\u533A\u5185\u7684\u7A7A\u5185\u5BB9\u52A9\u624B\u6D88\u606F（\u7EAF\u5DE5\u5177\u8C03\u7528）\u4E25\u683C\u4FDD\u7559\u4E3A\u7A7A\u6C14\u6CE1',
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

    test('\u7A7A\u8F93\u5165 / \u65E0 user / N ≤ 0 \u8FD4\u56DE\u7A7A', () {
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
      '\u53EA\u7EDF\u8BA1\u5185\u5BB9\u975E\u7A7A\u7684\u7528\u6237\u6D88\u606F',
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
      '\u5C11\u4E8E 5 \u6761\u7528\u6237\u6D88\u606F\u65F6\u9ED8\u8BA4 1',
      () {
        expect(defaultKeepUserMessageCountFor(0), 1);
        expect(defaultKeepUserMessageCountFor(1), 1);
        expect(defaultKeepUserMessageCountFor(2), 1);
        expect(defaultKeepUserMessageCountFor(4), 1);
      },
    );

    test('5-9 \u6761\u7528\u6237\u6D88\u606F\u65F6\u9ED8\u8BA4 2', () {
      expect(defaultKeepUserMessageCountFor(5), 2);
      expect(defaultKeepUserMessageCountFor(9), 2);
    });

    test(
      '10 \u6761\u53CA\u4EE5\u4E0A\u7528\u6237\u6D88\u606F\u65F6\u9ED8\u8BA4 3',
      () {
        expect(defaultKeepUserMessageCountFor(10), 3);
        expect(defaultKeepUserMessageCountFor(100), 3);
      },
    );
  });

  group('estimateCompressionTokens', () {
    test(
      '\u4FDD\u7559\u533A\u6309\u957F\u5EA6\u5360\u6BD4\u6298\u7B97 token',
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

    test('CJK \u8D70 tokenx \u6C49\u5B57\u6743\u91CD', () {
      final est = estimateCompressionTokens(
        totalText: '\u4E2D' * 400,
        keptText: '\u4E2D' * 100,
      );

      expect(est.totalTokens, 348);
      expect(est.keptTokens, 87);
    });

    test(
      '\u6DF7\u5408\u6587\u672C\u8D70 tokenx（\u6574\u6BB5\u547D\u4E2D CJK \u5219\u6309\u6C49\u5B57\u8BA1\u4EF7）',
      () {
        final est = estimateCompressionTokens(
          totalText: '\u4E2D' * 200 + 'a' * 400,
          keptText: '',
        );

        expect(est.totalTokens, 522);
      },
    );

    test('\u7A7A\u6587\u672C\u8FD4\u56DE\u5168\u96F6', () {
      final est = estimateCompressionTokens(totalText: '', keptText: '');

      expect(est.totalTokens, 0);
      expect(est.keptTokens, 0);
      expect(est.minResultTokens, 0);
      expect(est.maxResultTokens, 0);
    });

    test('\u533A\u95F4\u4E0A\u754C\u4E0D\u4F4E\u4E8E\u4E0B\u754C', () {
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
      'start \u4E0E\u5148\u62FC\u63A5\u518D\u622A\u65AD\u5728\u5E38\u89C4\u957F\u5EA6\u4E0A\u8BED\u4E49\u4E00\u81F4',
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
      'recent \u4E0E\u5148\u62FC\u63A5\u518D\u622A\u65AD\u5728\u5E38\u89C4\u957F\u5EA6\u4E0A\u8BED\u4E49\u4E00\u81F4',
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
      '\u8D85\u957F\u5386\u53F2\u589E\u91CF\u622A\u65AD\u4E14\u4E0D\u8D85\u8FC7\u7A97\u53E3，\u65E0\u9700\u5148\u62FC\u63A5\u5168\u6587',
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
      '\u8D85\u8FC7\u9884\u7B97\u7684\u591A\u6761\u6D88\u606F\u6309\u6D88\u606F\u8FB9\u754C\u62C6\u6210\u591A\u5757',
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
      '\u5355\u6761\u8D85\u957F\u6D88\u606F\u6309 UTF-16 \u5B89\u5168\u5207\u5206\u4E14\u4E0D\u5288\u5F00 emoji',
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
      'unlimited \u8D85\u8FC7\u5B89\u5168\u4E0A\u9650\u65F6\u6309\u6D88\u606F\u8FB9\u754C\u5206\u5757\u4E14\u4E0D\u4E22\u5185\u5BB9',
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
      'keepRecent \u65E7\u4FA7\u540C\u6837\u53D7\u5B89\u5168\u4E0A\u9650\u7EA6\u675F',
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
    test('\u4F18\u5148\u4F7F\u7528\u663E\u5F0F\u538B\u7F29\u6A21\u578B', () {
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
      '\u672A\u8BBE\u7F6E\u538B\u7F29\u6A21\u578B\u65F6\u6309 summary → title → assistant → current \u56DE\u9000',
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

    test('\u5168\u90E8\u672A\u8BBE\u7F6E\u65F6\u8FD4\u56DE\u7A7A', () {
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
