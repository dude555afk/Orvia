import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';

ChatMessage _message({
  required String id,
  required String role,
  required String groupId,
  required int version,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: '$role-$id',
    conversationId: 'conversation-1',
    groupId: groupId,
    version: version,
  );
}

void main() {
  test('unlimited context reads the complete persisted conversation', () {
    expect(
      ChatActions.contextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Unlimited',
          limitContextMessages: false,
        ),
        persistedMessageCount: 1507,
      ),
      1507,
    );
    expect(
      ChatActions.contextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Limited',
          contextMessageSize: 64,
          limitContextMessages: true,
        ),
        persistedMessageCount: 1507,
      ),
      64,
    );
    // Default assistants leave context unlimited (D-30 / 5d42eebc).
    expect(
      ChatActions.contextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Default unlimited',
          contextMessageSize: 64,
        ),
        persistedMessageCount: 1507,
      ),
      1507,
    );
    expect(
      ChatActions.contextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Unlimited with missing count',
          limitContextMessages: false,
        ),
        persistedMessageCount: 0,
      ),
      Assistant.maxContextMessageSize,
    );
  });

  test('unknown sentinel must not be passed into contextReadLimit', () {
    expect(
      () => ChatActions.contextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Unlimited',
          limitContextMessages: false,
        ),
        persistedMessageCount: -1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test(
    'resolveContextReadLimit awaits real count for unlimited assistants',
    () async {
      var resolveCalls = 0;
      final limit = await ChatActions.resolveContextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Unlimited',
          limitContextMessages: false,
        ),
        resolvePersistedCount: () async {
          resolveCalls += 1;
          return 1507;
        },
      );
      expect(limit, 1507);
      expect(resolveCalls, 1);
      expect(limit, isNot(Assistant.maxContextMessageSize));
    },
  );

  test(
    'resolveContextReadLimit skips count lookup when context is limited',
    () async {
      var resolveCalls = 0;
      final limit = await ChatActions.resolveContextReadLimit(
        assistant: const Assistant(
          id: 'assistant-1',
          name: 'Limited',
          contextMessageSize: 64,
          limitContextMessages: true,
        ),
        resolvePersistedCount: () async {
          resolveCalls += 1;
          return 1507;
        },
      );
      expect(limit, 64);
      expect(resolveCalls, 0);
    },
  );

  test('send/regenerate/continue paths await context limit resolution', () {
    final source = File(
      'lib/features/home/controllers/chat_actions.dart',
    ).readAsStringSync();
    expect(
      'await _contextReadLimit(assistant, conversation)'
          .allMatches(source)
          .length,
      3,
      reason: 'send, regenerate, and continue must each await resolved counts',
    );
    expect(source.contains('maxMessages: _contextReadLimit('), isFalse);
    expect(source.contains('maxMessages: contextLimit + 2'), isTrue);
  });

  group('ChatActions.shouldBeginNewAssistantReply', () {
    test(
      '\u5220\u6389\u5E95\u90E8\u5168\u90E8\u56DE\u590D\u540E\u4ECE\u7528\u6237\u6D88\u606F\u91CD\u8BD5\u4F1A\u65B0\u5EFA\u56DE\u590D\u800C\u4E0D\u662F\u62A5 invalid_versioning',
      () {
        expect(
          ChatActions.shouldBeginNewAssistantReply(
            role: 'user',
            targetGroupId: null,
            assistantAsNewReply: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'assistant \u5F53\u4F5C\u65B0\u56DE\u590D\u65F6\u8D70\u65B0\u5EFA\u56DE\u590D\u8DEF\u5F84',
      () {
        expect(
          ChatActions.shouldBeginNewAssistantReply(
            role: 'assistant',
            targetGroupId: null,
            assistantAsNewReply: true,
          ),
          isTrue,
        );
      },
    );

    test(
      '\u5DF2\u6709\u56DE\u590D\u7EC4\u65F6\u8D70\u7248\u672C\u8FFD\u52A0\u800C\u4E0D\u662F\u65B0\u5EFA\u56DE\u590D',
      () {
        expect(
          ChatActions.shouldBeginNewAssistantReply(
            role: 'user',
            targetGroupId: 'a1',
            assistantAsNewReply: false,
          ),
          isFalse,
        );
        expect(
          ChatActions.shouldBeginNewAssistantReply(
            role: 'assistant',
            targetGroupId: 'a1',
            assistantAsNewReply: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'assistant \u5374\u7B97\u4E0D\u51FA\u56DE\u590D\u7EC4\u4ECD\u89C6\u4E3A\u975E\u6CD5 versioning',
      () {
        expect(
          ChatActions.shouldBeginNewAssistantReply(
            role: 'assistant',
            targetGroupId: null,
            assistantAsNewReply: false,
          ),
          isFalse,
        );
      },
    );
  });

  test('only temporary regeneration physically removes trailing messages', () {
    expect(
      ChatActions.shouldPhysicallyRemoveRegenerationTail(
        deleteTrailingEnabled: false,
        isTemporaryConversation: false,
      ),
      isFalse,
    );
    expect(
      ChatActions.shouldPhysicallyRemoveRegenerationTail(
        deleteTrailingEnabled: true,
        isTemporaryConversation: false,
      ),
      isFalse,
    );
    expect(
      ChatActions.shouldPhysicallyRemoveRegenerationTail(
        deleteTrailingEnabled: true,
        isTemporaryConversation: true,
      ),
      isTrue,
    );
  });

  group('ChatActions.buildRegenerationMessages', () {
    test(
      '\u957F\u4F1A\u8BDD\u7A97\u53E3\u91CD\u8BD5\u4F1A\u4FDD\u7559\u76EE\u6807\u6D88\u606F\u4E4B\u524D\u7684\u5B8C\u6574\u5386\u53F2\u524D\u7F00',
      () {
        final messages = <ChatMessage>[
          for (var i = 0; i < 90; i++)
            _message(
              id: 'm$i',
              role: i.isEven ? 'user' : 'assistant',
              groupId: 'm$i',
              version: 0,
            ),
        ];
        final placeholder = _message(
          id: 'm85-v1',
          role: 'assistant',
          groupId: 'm85',
          version: 1,
        ).copyWith(content: '', isStreaming: true);

        final result = ChatActions.buildRegenerationMessages(
          messages: messages,
          lastKeep: 85,
          targetGroupId: 'm85',
          assistantPlaceholder: placeholder,
        );

        expect(result.first.id, 'm0');
        expect(result.map((message) => message.id), contains('m10'));
        expect(result.map((message) => message.id), contains('m84'));
        expect(result.last.id, 'm85-v1');
        expect(result, hasLength(87));
      },
    );

    test(
      '\u91CD\u8BD5 assistant \u65F6\u4E0D\u4F1A\u628A\u540E\u7EED\u5206\u7EC4\u5E26\u5165\u4E0A\u4E0B\u6587',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', groupId: 'u1', version: 0),
          _message(id: 'a1-v0', role: 'assistant', groupId: 'a1', version: 0),
          _message(id: 'u2', role: 'user', groupId: 'u2', version: 0),
          _message(id: 'a2-v0', role: 'assistant', groupId: 'a2', version: 0),
          _message(id: 'a1-v1', role: 'assistant', groupId: 'a1', version: 1),
        ];
        final placeholder = _message(
          id: 'a1-v2',
          role: 'assistant',
          groupId: 'a1',
          version: 2,
        ).copyWith(content: '', isStreaming: true);

        final result = ChatActions.buildRegenerationMessages(
          messages: messages,
          lastKeep: 1,
          targetGroupId: 'a1',
          assistantPlaceholder: placeholder,
        );

        expect(result.map((message) => message.id).toList(), [
          'u1',
          'a1-v0',
          'a1-v1',
          'a1-v2',
        ]);
      },
    );

    test(
      '\u91CD\u8BD5 user \u65F6\u53EA\u4FDD\u7559\u8BE5\u7528\u6237\u6D88\u606F\u4E4B\u524D\u7684\u4E0A\u4E0B\u6587\u5E76\u8FFD\u52A0\u65B0\u7684\u56DE\u590D\u5360\u4F4D',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', groupId: 'u1', version: 0),
          _message(id: 'a1-v0', role: 'assistant', groupId: 'a1', version: 0),
          _message(id: 'u2', role: 'user', groupId: 'u2', version: 0),
          _message(id: 'a2-v0', role: 'assistant', groupId: 'a2', version: 0),
          _message(id: 'u3', role: 'user', groupId: 'u3', version: 0),
          _message(id: 'a3-v0', role: 'assistant', groupId: 'a3', version: 0),
        ];
        final placeholder = _message(
          id: 'a2-v1',
          role: 'assistant',
          groupId: 'a2',
          version: 1,
        ).copyWith(content: '', isStreaming: true);

        final result = ChatActions.buildRegenerationMessages(
          messages: messages,
          lastKeep: 3,
          targetGroupId: 'a2',
          assistantPlaceholder: placeholder,
        );

        expect(result.map((message) => message.id).toList(), [
          'u1',
          'a1-v0',
          'u2',
          'a2-v0',
          'a2-v1',
        ]);
      },
    );

    test(
      '\u5220\u6389\u5E95\u90E8\u56DE\u590D\u540E targetGroupId \u4E3A\u7A7A\u4ECD\u80FD\u628A\u5360\u4F4D\u63A5\u5230\u7528\u6237\u6D88\u606F\u540E\u9762',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', groupId: 'u1', version: 0),
        ];
        final placeholder = _message(
          id: 'a1',
          role: 'assistant',
          groupId: 'a1',
          version: 0,
        ).copyWith(content: '', isStreaming: true);

        final result = ChatActions.buildRegenerationMessages(
          messages: messages,
          lastKeep: 0,
          targetGroupId: null,
          assistantPlaceholder: placeholder,
        );

        expect(result.map((message) => message.id).toList(), ['u1', 'a1']);
      },
    );
  });

  group('ChatActions.conversationForMessageContext', () {
    test(
      '\u6295\u5F71\u5386\u53F2\u77ED\u4E8E\u6301\u4E45\u5316\u622A\u65AD\u70B9\u65F6\u4E0D\u622A\u7A7A\u91CD\u8BD5\u4E0A\u4E0B\u6587',
      () {
        final messages = <ChatMessage>[
          for (var i = 0; i < 20; i++)
            _message(
              id: 'm$i',
              role: i.isEven ? 'user' : 'assistant',
              groupId: 'm$i',
              version: 0,
            ),
        ];

        final conversation = ChatActions.conversationForMessageContext(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Long chat',
            truncateIndex: 50,
          ),
          messages: messages,
        );

        expect(conversation.truncateIndex, -1);
      },
    );

    test(
      '\u91CD\u8BD5\u76EE\u6807\u4E4B\u524D\u7684\u4E0A\u4E0B\u6587\u4E0D\u4F7F\u7528\u672A\u6765\u622A\u65AD\u70B9',
      () {
        final messages = <ChatMessage>[
          for (var i = 0; i < 60; i++)
            _message(
              id: 'm$i',
              role: i.isEven ? 'user' : 'assistant',
              groupId: 'm$i',
              version: 0,
            ),
        ];

        final conversation = ChatActions.conversationForMessageContext(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Long chat',
            truncateIndex: 50,
          ),
          messages: messages,
          maxRawTruncateIndex: 40,
        );

        expect(conversation.truncateIndex, -1);
      },
    );

    test(
      '\u5B8C\u6574\u5386\u53F2\u4E0A\u4E0B\u6587\u4FDD\u7559\u6301\u4E45\u5316\u622A\u65AD\u70B9',
      () {
        final messages = <ChatMessage>[
          for (var i = 0; i < 80; i++)
            _message(
              id: 'm$i',
              role: i.isEven ? 'user' : 'assistant',
              groupId: 'm$i',
              version: 0,
            ),
        ];

        final conversation = ChatActions.conversationForMessageContext(
          conversation: Conversation(
            id: 'conversation-1',
            title: 'Long chat',
            truncateIndex: 50,
          ),
          messages: messages,
        );

        expect(conversation.truncateIndex, 50);
      },
    );
  });
}
