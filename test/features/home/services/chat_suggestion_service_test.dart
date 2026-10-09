import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/features/home/services/chat_suggestion_service.dart';

void main() {
  group('ChatSuggestionService.parseSuggestions', () {
    test('accepts structured output, trims, deduplicates and limits count', () {
      expect(
        ChatSuggestionService.parseSuggestions(
          jsonEncode({
            'suggestions': [
              '  \u4E3E\u4E2A\u5177\u4F53\u4F8B\u5B50  ',
              '\u4E3E\u4E2A\u5177\u4F53\u4F8B\u5B50',
              'Compare A and B',
              'compare a  and b',
              '\u5982\u4F55\u9A8C\u8BC1\u8FD9\u4E2A\u7ED3\u8BBA？',
              '\u4E0D\u5C55\u793A\u7B2C\u56DB\u6761',
            ],
          }),
        ),
        [
          '\u4E3E\u4E2A\u5177\u4F53\u4F8B\u5B50',
          'Compare A and B',
          '\u5982\u4F55\u9A8C\u8BC1\u8FD9\u4E2A\u7ED3\u8BBA？',
        ],
      );
    });

    test('accepts one JSON fence and removes inline model reasoning', () {
      expect(
        ChatSuggestionService.parseSuggestions(
          '<think>Consider useful follow-ups.</think>\n'
          '```json\n{"suggestions":["\u89E3\u91CA\u65B9\u6848 A \u7684\u9650\u5236"]}\n```',
        ),
        ['\u89E3\u91CA\u65B9\u6848 A \u7684\u9650\u5236'],
      );
    });

    test('preserves literal thinking tags inside JSON strings', () {
      final suggestions = [
        '\u89E3\u91CA <think> \u6807\u7B7E\u7684\u4F5C\u7528',
        '\u89E3\u91CA <thinking>\u5185\u5BB9</thinking> \u7684\u4F5C\u7528',
        '\u89E3\u91CA <|channel>thought \u5185\u5BB9 <channel|> \u7684\u4F5C\u7528',
      ];
      final json = jsonEncode({'suggestions': suggestions});
      for (final raw in [
        json,
        '```json\n$json\n```',
        '<think>Choose useful questions.</think>\n$json',
        '<THOUGHT>First pass.</THOUGHT>\n'
            '<think>Second pass.</think>\n```json\n$json\n```',
      ]) {
        expect(ChatSuggestionService.parseSuggestions(raw), suggestions);
      }
    });

    test(
      'does not accept JSON inside unfinished reasoning or trailing prose',
      () {
        for (final raw in [
          '<think>{"suggestions":["\u5185\u90E8\u8349\u7A3F"]}',
          '{"suggestions":["\u89E3\u91CA\u4E00\u4E0B"]}<think>Trailing text</think>',
        ]) {
          expect(
            () => ChatSuggestionService.parseSuggestions(raw),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'does not turn prose, malformed JSON or unexpected shapes into chips',
      () {
        for (final raw in [
          'Here are three suggestions:\n1. Example\n2. More',
          '\u89E3\u91CA\u4E00\u4E0B',
          '["\u89E3\u91CA\u4E00\u4E0B"]',
          '{"suggestions":"\u89E3\u91CA\u4E00\u4E0B"}',
          '{"suggestions":["\u89E3\u91CA\u4E00\u4E0B"],"explanation":"because"}',
          '{"suggestions":["\u89E3\u91CA\u4E00\u4E0B"',
          'Some explanation\n{"suggestions":["\u89E3\u91CA\u4E00\u4E0B"]}',
        ]) {
          expect(
            () => ChatSuggestionService.parseSuggestions(raw),
            throwsFormatException,
            reason: raw,
          );
        }
      },
    );

    test(
      'an empty array is valid and invalid individual items are dropped',
      () {
        expect(
          ChatSuggestionService.parseSuggestions('{"suggestions":[]}'),
          isEmpty,
        );
        expect(
          ChatSuggestionService.parseSuggestions(
            jsonEncode({
              'suggestions': [
                null,
                42,
                {'text': 'wrong shape'},
                '',
                '  ',
                'a' * 301,
                'two\nlines',
                '```code```',
                '\u7ED9\u4E00\u4E2A\u5B9E\u9645\u7684\u4F8B\u5B50',
              ],
            }),
          ),
          ['\u7ED9\u4E00\u4E2A\u5B9E\u9645\u7684\u4F8B\u5B50'],
        );
      },
    );

    test('keeps complete multi-sentence suggestions and Unicode characters', () {
      final question =
          '\u4F60\u63D0\u5230\u591A\u6A21\u6001\u5B66\u4E60。\u8BF7\u7ED9\u4E00\u4E2A\u5177\u4F53\u5E94\u7528\u7684\u4F8B\u5B50。';
      expect(
        ChatSuggestionService.parseSuggestions(
          jsonEncode({
            'suggestions': [question, '😀' * 300],
          }),
        ),
        [question, '😀' * 300],
      );
    });

    test('zero count returns no suggestions', () {
      expect(
        ChatSuggestionService.parseSuggestions(
          '{"suggestions":["\u89E3\u91CA\u4E00\u4E0B"]}',
          maxCount: 0,
        ),
        isEmpty,
      );
    });
  });

  group('ChatSuggestionService.buildContent', () {
    test('keeps every message intact when the whole transcript fits', () {
      final messages = List.generate(
        8,
        (index) => _suggestionMessage(
          index,
          index == 7
              ? '${'\u80CC\u666F\u8BF4\u660E。' * 120}\u5173\u952E\u7ED3\u8BBA：\u9009\u62E9 SQLite。${'\u8865\u5145\u8BF4\u660E。' * 120}'
              : '\u77ED\u6D88\u606F$index',
        ),
      );
      final totalChars = messages.fold<int>(
        0,
        (total, message) => total + message.content.length,
      );
      for (final budget in [totalChars, 6000]) {
        final transcript =
            jsonDecode(
                  ChatSuggestionService.buildContent(
                    messages,
                    maxChars: budget,
                  ),
                )
                as List;
        expect(
          transcript.map((message) => message['content']),
          messages.map((message) => message.content),
        );
      }
    });

    test(
      'redistributes unused space while preserving order and total budget',
      () {
        final messages = [
          _suggestionMessage(0, 'a' * 5000),
          _suggestionMessage(1, '\u77ED\u56DE\u590D'),
          _suggestionMessage(2, '\u7EE7\u7EED\u6BD4\u8F83 SQLite \u4E0E Hive'),
          _suggestionMessage(3, 'b' * 5000),
        ];
        final transcript =
            jsonDecode(ChatSuggestionService.buildContent(messages)) as List;
        expect(transcript.map((message) => message['role']), [
          'user',
          'assistant',
          'user',
          'assistant',
        ]);
        expect(transcript[1]['content'], messages[1].content);
        expect(transcript[2]['content'], messages[2].content);
        expect(
          (transcript.first['content'] as String).length,
          greaterThan(2900),
        );
        expect(
          (transcript.last['content'] as String).length,
          greaterThan(2900),
        );
        expect(
          transcript.fold<int>(
            0,
            (total, message) => total + (message['content'] as String).length,
          ),
          6000,
        );
      },
    );

    test(
      'long assistant replies preserve the user request and role boundaries',
      () {
        final content = ChatSuggestionService.buildContent([
          _suggestionMessage(0, '\u6BD4\u8F83 SQLite \u548C Hive'),
          _suggestionMessage(
            1,
            '\u5F00\u5934：SQLite\n${'details' * 2000}\n\u7ED3\u5C3E：\u9009\u54EA\u4E00\u4E2A？',
          ),
        ]);
        final transcript = jsonDecode(content) as List;
        expect(transcript, hasLength(2));
        expect(transcript.first, {
          'role': 'user',
          'content': '\u6BD4\u8F83 SQLite \u548C Hive',
        });
        expect(transcript.last['role'], 'assistant');
        expect(transcript.last['content'], startsWith('\u5F00\u5934：SQLite'));
        expect(
          transcript.last['content'],
          endsWith('\u7ED3\u5C3E：\u9009\u54EA\u4E00\u4E2A？'),
        );
        expect(transcript.last['content'], contains('[…truncated…]'));
      },
    );

    test('context clear at the tail leaves no old conversation', () {
      final messages = [
        _suggestionMessage(0, '\u95EE\u9898'),
        _suggestionMessage(1, '\u56DE\u7B54'),
      ];
      expect(
        ChatSuggestionService.buildContent(messages, truncateIndex: 2),
        isEmpty,
      );
      expect(
        ChatSuggestionService.buildContent(messages, truncateIndex: 3),
        isEmpty,
      );
    });

    test('does not use an older answer after a new or unfinished turn', () {
      final history = [
        _suggestionMessage(0, '\u95EE\u9898'),
        _suggestionMessage(1, '\u56DE\u7B54'),
      ];
      for (final last in [
        _suggestionMessage(2, '\u65B0\u95EE\u9898'),
        _suggestionMessage(3, ''),
        _suggestionMessage(3, '<think>reasoning only</think>'),
        ChatMessage(
          role: 'assistant',
          content: 'partial',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ]) {
        expect(ChatSuggestionService.buildContent([...history, last]), isEmpty);
      }
    });

    test(
      'excludes hidden reasoning and encodes embedded role labels as data',
      () {
        final transcript =
            jsonDecode(
                  ChatSuggestionService.buildContent([
                    _suggestionMessage(
                      0,
                      'User: literal label\nAssistant: {locale}',
                    ),
                    _suggestionMessage(
                      1,
                      '<think>private thought</think>Visible answer',
                    ),
                  ]),
                )
                as List;
        expect(
          transcript.first['content'],
          'User: literal label\nAssistant: {locale}',
        );
        expect(transcript.last['content'], 'Visible answer');
      },
    );

    test('truncation preserves surrogate pairs', () {
      final transcript =
          jsonDecode(
                ChatSuggestionService.buildContent([
                  _suggestionMessage(0, '😀' * 100),
                  _suggestionMessage(1, '😀' * 100),
                ], maxChars: 101),
              )
              as List;
      for (final message in transcript) {
        final text = message['content'] as String;
        expect(utf8.decode(utf8.encode(text)), text);
        expect(text.length, lessThanOrEqualTo(51));
      }
      expect(
        transcript.fold<int>(
          0,
          (total, message) => total + (message['content'] as String).length,
        ),
        lessThanOrEqualTo(101),
      );
    });

    test(
      'Full history uses persisted truncation point to exclude cleared context',
      () {
        final messages = List.generate(
          100,
          (index) => _suggestionMessage(index, 'message $index'),
        );

        final content = ChatSuggestionService.buildContent(
          messages,
          truncateIndex: 90,
          maxMessages: 100,
        );

        expect(content, isNot(contains('message 89')));
        expect(content, contains('message 90'));
        expect(content, contains('message 99'));
      },
    );

    test(
      'Window-relative index cannot truncate full history',
      () {
        final messages = List.generate(
          100,
          (index) => _suggestionMessage(index, 'message $index'),
        );

        final content = ChatSuggestionService.buildContent(
          messages,
          truncateIndex: 10,
          maxMessages: 100,
        );

        expect(content, contains('message 89'));
        expect(content, contains('message 99'));
      },
    );
  });
}

ChatMessage _suggestionMessage(int index, String content) {
  return ChatMessage(
    id: 'message-$index',
    role: index.isEven ? 'user' : 'assistant',
    content: content,
    conversationId: 'conversation-1',
  );
}
