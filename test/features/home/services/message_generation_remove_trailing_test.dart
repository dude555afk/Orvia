import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';

ChatMessage _message({
  required String id,
  required String role,
  required String groupId,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: '$role-$id',
    conversationId: 'conversation-1',
    groupId: groupId,
  );
}

void main() {
  group('MessageGenerationService.collectTrailingMessageIdsForRemoval', () {
    test(
      '\u5220\u9664\u622A\u65AD\u70B9\u4E4B\u540E\u4E0D\u5C5E\u4E8E\u4FDD\u7559\u5206\u7EC4\u7684\u6D88\u606F',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', groupId: 'u1'),
          _message(id: 'a1-v0', role: 'assistant', groupId: 'a1'),
          _message(id: 'u2', role: 'user', groupId: 'u2'),
          _message(id: 'a2-v0', role: 'assistant', groupId: 'a2'),
          _message(id: 'a1-v1', role: 'assistant', groupId: 'a1'),
        ];

        final result =
            MessageGenerationService.collectTrailingMessageIdsForRemoval(
              messages: messages,
              lastKeep: 1,
              targetGroupId: 'a1',
            );

        expect(result, ['u2', 'a2-v0']);
      },
    );

    test(
      '\u622A\u65AD\u70B9\u5DF2\u7ECF\u5728\u5E95\u90E8\u65F6\u4E0D\u5220\u9664\u6D88\u606F',
      () {
        final messages = <ChatMessage>[
          _message(id: 'u1', role: 'user', groupId: 'u1'),
          _message(id: 'a1-v0', role: 'assistant', groupId: 'a1'),
        ];

        final result =
            MessageGenerationService.collectTrailingMessageIdsForRemoval(
              messages: messages,
              lastKeep: 1,
              targetGroupId: 'a1',
            );

        expect(result, isEmpty);
      },
    );
  });
}
