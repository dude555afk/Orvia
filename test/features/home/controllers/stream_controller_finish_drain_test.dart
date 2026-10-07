import "../../../support/business_test_harness.dart";
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/features/home/controllers/stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  const messageId = 'assistant-message';

  StreamController buildController(SettingsProvider settings) {
    return StreamController(
      onStateChanged: () {},
      getSettingsProvider: () => settings,
      getCurrentConversationId: () => 'conversation-1',
    );
  }

  /// Feeds a burst the smoothing buffer cannot show in a single tick.
  void scheduleBurst(StreamController controller, String content) {
    controller.scheduleThrottledUpdate(
      messageId,
      'conversation-1',
      () => content,
      updateMessageInList: (_, _, _) {},
      totalTokens: 10,
    );
  }

  testWidgets(
    '\u7ED3\u675F\u65F6\u5148\u6392\u7A7A\u5E73\u6ED1\u7F13\u51B2，\u907F\u514D\u5C3E\u90E8\u4E00\u6B21\u6027\u8DF3\u53D8',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      final controller = buildController(settings);
      final notifier = controller.streamingContentNotifier.getNotifier(
        messageId,
      );
      final published = <int>[];
      notifier.addListener(() => published.add(notifier.value.content.length));

      final content = 'x' * 2000;
      scheduleBurst(controller, content);
      // A few ticks of a burst the smoother is still catching up with.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final backlogBeforeFinish =
          content.length - notifier.value.content.length;
      expect(
        backlogBeforeFinish,
        greaterThan(200),
        reason:
            'the burst must still be buffered for this test to mean anything',
      );

      final drain = controller.drainSmoothStream(messageId);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await drain;
      final backlogAfterDrain = content.length - notifier.value.content.length;

      controller.cleanupTimers(messageId);
      final finalJump = content.length - (published..removeLast()).last;

      // Without the drain the whole backlog lands in the frame the reply ends,
      // which a bottom-pinned timeline shows as one large jump.
      expect(backlogAfterDrain, lessThan(backlogBeforeFinish));
      expect(finalJump, lessThan(backlogBeforeFinish));
      controller.dispose();
    },
  );

  testWidgets(
    '\u6392\u7A7A\u53D7\u65F6\u95F4\u9884\u7B97\u7EA6\u675F，\u4E0D\u4F1A\u62D6\u4F4F\u7ED3\u675F\u6D41\u7A0B',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      final controller = buildController(settings);
      controller.streamingContentNotifier.getNotifier(messageId);

      // Content that keeps outpacing the smoother for far longer than the budget.
      scheduleBurst(controller, 'x' * 400000);

      var completed = false;
      unawaited(
        controller
            .drainSmoothStream(
              messageId,
              budget: const Duration(milliseconds: 100),
            )
            .then((_) => completed = true),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(completed, isTrue);
      controller.dispose();
    },
  );
}
