import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/models/assistant.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/models/conversation.dart';
import 'package:orvia/features/home/controllers/chat_actions.dart';

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
      'Retry after deleting all bottom responses creates new reply rather than invalid_versioning',
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
      'Assistant as new reply uses creation path',
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
      'Existing reply group appends version instead of creating reply',
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
      'Assistant without resolvable reply group is invalid versioning',
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
      'Retry in long conversation preserves full history before target',
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
      'Retrying assistant excludes later groups from context',
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
      'Retrying user preserves earlier context and appends response placeholder',
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
      'After deleting bottom reply, null targetGroupId still attaches placeholder to user',
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
      'Projected history shorter than persisted truncation does not erase retry context',
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
      'Context before retry target ignores future truncation point',
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
      'Full history context keeps persisted truncation point',
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
