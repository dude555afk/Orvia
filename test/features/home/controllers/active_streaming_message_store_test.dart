import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/features/home/controllers/active_streaming_message_store.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _message({
  required String id,
  required String conversationId,
  bool isStreaming = true,
}) {
  return ChatMessage(
    id: id,
    role: 'assistant',
    content: id,
    conversationId: conversationId,
    isStreaming: isStreaming,
  );
}

void main() {
  group('ActiveStreamingMessageStore', () {
    test(
      'Cancellation target survives eviction from the loaded message window',
      () {
        final store = ActiveStreamingMessageStore();
        final active = _message(id: 'off-window', conversationId: 'chat');
        store.put(active);

        final target = store.cancellationTarget('chat', const []);

        expect(target?.id, 'off-window');
      },
    );

    test(
      'Fallback selects the last streaming assistant only in the target conversation',
      () {
        final store = ActiveStreamingMessageStore();
        final target = store.cancellationTarget('chat', [
          _message(id: 'other', conversationId: 'other-chat'),
          _message(id: 'finished', conversationId: 'chat', isStreaming: false),
          _message(id: 'expected', conversationId: 'chat'),
        ]);

        expect(target?.id, 'expected');
      },
    );

    test(
      'Old terminal state cannot remove a newer generation in the same conversation',
      () {
        final store = ActiveStreamingMessageStore();
        final old = _message(id: 'old', conversationId: 'chat');
        final replacement = _message(id: 'replacement', conversationId: 'chat');
        store
          ..put(old)
          ..put(replacement)
          ..removeIfMatches(old);

        expect(store['chat']?.id, 'replacement');
        store.removeIfMatches(replacement);
        expect(store['chat'], isNull);
      },
    );

    test(
      'Stale prepare cannot restart generation after cancellation removed active entry',
      () {
        final store = ActiveStreamingMessageStore();
        final preparing = _message(id: 'preparing', conversationId: 'chat');
        store.put(preparing);
        expect(store.isActive(preparing), isTrue);

        store.removeIfMatches(preparing);

        expect(store.isActive(preparing), isFalse);
      },
    );
  });
}
