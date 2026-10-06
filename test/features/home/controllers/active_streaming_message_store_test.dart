import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/controllers/active_streaming_message_store.dart';
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
      '\u53D6\u6D88\u76EE\u6807\u4E0D\u4F9D\u8D56\u6D88\u606F\u662F\u5426\u4ECD\u5728\u52A0\u8F7D\u7A97\u53E3',
      () {
        final store = ActiveStreamingMessageStore();
        final active = _message(id: 'off-window', conversationId: 'chat');
        store.put(active);

        final target = store.cancellationTarget('chat', const []);

        expect(target?.id, 'off-window');
      },
    );

    test(
      '\u517C\u5BB9\u56DE\u9000\u53EA\u9009\u62E9\u76EE\u6807\u4F1A\u8BDD\u5185\u6700\u540E\u4E00\u4E2A streaming assistant',
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
      '\u65E7\u7EC8\u6001\u4E0D\u80FD\u79FB\u9664\u540C\u4F1A\u8BDD\u4E2D\u5DF2\u7ECF\u66FF\u6362\u7684\u65B0 generation',
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
      '\u53D6\u6D88\u79FB\u9664 active \u540E\u65E7 prepare \u4E0D\u80FD\u91CD\u65B0\u5F00\u59CB generation',
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
