import "../../../support/business_test_harness.dart";
import 'dart:ui';

import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/providers/assistant_provider.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/providers/tts_provider.dart';
import 'package:orvia/core/providers/user_provider.dart';
import 'package:orvia/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:orvia/features/home/controllers/stream_controller.dart'
    as stream_ctrl;
import 'package:orvia/features/home/controllers/streaming_content_notifier.dart';
import 'package:orvia/features/home/services/ask_user_interaction_service.dart';
import 'package:orvia/features/home/services/tool_approval_service.dart';
import 'package:orvia/features/home/utils/chat_layout_constants.dart';
import 'package:orvia/features/home/widgets/message_list_view.dart';
import 'package:orvia/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'conversation footer follows the final message and scrolls away with history',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(
        _PrependingMessageListHarness(key: key, showFooter: true),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final footer = find.byKey(const ValueKey('conversation-footer'));
      expect(state.listController.numberOfItems, state.messages.length);
      expect(footer.hitTestable(), findsNothing);

      Future<void> revealTail() async {
        state.listController.jumpToItem(
          index: state.messages.length - 1,
          scrollController: state.scrollController,
          alignment: 1,
        );
        await tester.pumpAndSettle();
      }

      await revealTail();
      expect(footer.hitTestable(), findsOneWidget);
      state.replaceMessages([
        ...state.messages,
        ChatMessage(
          id: 'new-tail',
          role: 'user',
          content: 'Next message',
          conversationId: 'conversation-1',
        ),
      ]);
      await tester.pumpAndSettle();
      await revealTail();
      expect(footer, findsOneWidget);
      expect(
        tester.getTopLeft(footer).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('new-tail'))).dy,
        ),
      );
      expect(state.listController.numberOfItems, state.messages.length);

      state.scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsNothing);
      state.replaceMessages([]);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conversation footer is hidden until the actual end of a paged history',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(
        _PrependingMessageListHarness(
          key: key,
          showFooter: true,
          hasMoreAfter: true,
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      state.listController.jumpToItem(
        index: state.messages.length - 1,
        scrollController: state.scrollController,
        alignment: 1,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversation-footer')), findsNothing);
      expect(state.listController.numberOfItems, state.messages.length);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'macOS message list scroll preserves text selection focus',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: const [],
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
              ),
            ),
          ),
        );

        final listView = tester.widget<SuperListView>(
          find.byType(SuperListView),
        );
        expect(
          listView.keyboardDismissBehavior,
          ScrollViewKeyboardDismissBehavior.manual,
        );
        expect(listView.delayPopulatingCacheArea, isFalse);
        expect(listView.clipBehavior, Clip.hardEdge);
        // SuperListView 0.4.1 still forwards this constructor value through the
        // legacy ScrollView property on current Flutter.
        // ignore: deprecated_member_use
        expect(listView.cacheExtent, 600);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        scrollController.dispose();
        listController.dispose();
        processingFilesMessageId.dispose();
      }
    },
  );

  testWidgets(
    'Android message list scroll still hides keyboard',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: const [],
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
              ),
            ),
          ),
        );

        final listView = tester.widget<SuperListView>(
          find.byType(SuperListView),
        );
        expect(
          listView.keyboardDismissBehavior,
          ScrollViewKeyboardDismissBehavior.onDrag,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        scrollController.dispose();
        listController.dispose();
        processingFilesMessageId.dispose();
      }
    },
  );

  testWidgets(
    'Bottom padding uses supplied composer overlay height',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageListView(
              scrollController: scrollController,
              listController: listController,
              messages: const [],
              byGroup: const {},
              versionSelections: const {},
              reasoning: const {},
              reasoningSegments: const {},
              contentSplits: const {},
              toolParts: const {},
              translations: const {},
              selecting: false,
              selectedItems: const {},
              dividerPadding: EdgeInsets.zero,
              processingFilesMessageId: processingFilesMessageId,
              bottomContentPadding: 144,
            ),
          ),
        ),
      );

      final listView = tester.widget<SuperListView>(find.byType(SuperListView));
      expect((listView.padding as EdgeInsets).bottom, 144);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
    },
  );

  testWidgets(
    'Top padding uses supplied navigation overlay height',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageListView(
              scrollController: scrollController,
              listController: listController,
              messages: const [],
              byGroup: const {},
              versionSelections: const {},
              reasoning: const {},
              reasoningSegments: const {},
              contentSplits: const {},
              toolParts: const {},
              translations: const {},
              selecting: false,
              selectedItems: const {},
              dividerPadding: EdgeInsets.zero,
              processingFilesMessageId: processingFilesMessageId,
              topContentPadding: 88,
              bottomContentPadding: 144,
            ),
          ),
        ),
      );

      final listView = tester.widget<SuperListView>(find.byType(SuperListView));
      expect((listView.padding as EdgeInsets).top, 88);
      expect((listView.padding as EdgeInsets).bottom, 144);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
    },
  );

  testWidgets(
    'Pinned streaming indicator reserves extra bottom space',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageListView(
              scrollController: scrollController,
              listController: listController,
              messages: const [],
              byGroup: const {},
              versionSelections: const {},
              reasoning: const {},
              reasoningSegments: const {},
              contentSplits: const {},
              toolParts: const {},
              translations: const {},
              selecting: false,
              selectedItems: const {},
              dividerPadding: EdgeInsets.zero,
              processingFilesMessageId: processingFilesMessageId,
              isPinnedIndicatorActive: true,
              bottomContentPadding: 144,
            ),
          ),
        ),
      );

      final listView = tester.widget<SuperListView>(find.byType(SuperListView));
      expect((listView.padding as EdgeInsets).bottom, 156);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
    },
  );

  testWidgets(
    'Streaming reasoning update without start time preserves timer origin',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final streamingNotifier = StreamingContentNotifier();
      const messageId = 'reasoning-streaming-message';
      final startAt = DateTime.now().subtract(const Duration(seconds: 7));
      final reasoning = <String, stream_ctrl.ReasoningData>{
        messageId: stream_ctrl.ReasoningData()
          ..text = 'initial thinking'
          ..startAt = startAt
          ..expanded = false,
      };
      final messages = <ChatMessage>[
        ChatMessage(
          id: messageId,
          role: 'assistant',
          content: '',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ];
      streamingNotifier.getNotifier(messageId);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: reasoning,
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                bottomContentPadding: 16,
                streamingContentNotifier: streamingNotifier,
              ),
            ),
          ),
        ),
      );

      streamingNotifier.updateReasoning(
        messageId,
        reasoningText: 'updated thinking',
      );
      await tester.pump();

      expect(reasoning[messageId]!.startAt, startAt);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
      streamingNotifier.dispose();
    },
  );

  testWidgets(
    'Scrolling inside reasoning card does not pause streamed response updates',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final streamingNotifier = StreamingContentNotifier();
      const messageId = 'nested-reasoning-scroll-message';
      final reasoningText = List.filled(40, 'reasoning line').join('\n');
      final messages = <ChatMessage>[
        ChatMessage(
          id: messageId,
          role: 'assistant',
          content: 'initial nested answer',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ];
      final reasoning = <String, stream_ctrl.ReasoningData>{
        messageId: stream_ctrl.ReasoningData()
          ..text = reasoningText
          ..startAt = DateTime.now().subtract(const Duration(seconds: 3))
          ..expanded = false,
      };
      streamingNotifier.getNotifier(messageId);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: reasoning,
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                bottomContentPadding: 16,
                streamingContentNotifier: streamingNotifier,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 320));

      final innerScroll = find.byType(SingleChildScrollView).first;
      await tester.drag(innerScroll, const Offset(0, 40));
      await tester.pump();

      streamingNotifier.updateContent(
        messageId,
        'updated after nested reasoning scroll',
        3,
      );
      await tester.pump();

      expect(
        find.text('updated after nested reasoning scroll'),
        findsOneWidget,
      );

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
      streamingNotifier.dispose();
    },
  );

  testWidgets(
    'Dragging away from bottom pauses applying streamed updates',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final streamingNotifier = StreamingContentNotifier();
      final messages = <ChatMessage>[
        for (var i = 0; i < 18; i++)
          ChatMessage(
            id: 'message-$i',
            role: 'assistant',
            content: '\n\n\n\n\n\n\n\n',
            conversationId: 'conversation-1',
          ),
        ChatMessage(
          id: 'streaming-message',
          role: 'assistant',
          content: 'initial stream content',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ];
      streamingNotifier.getNotifier('streaming-message');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                bottomContentPadding: 16,
                streamingContentNotifier: streamingNotifier,
              ),
            ),
          ),
        ),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperListView)),
      );
      await gesture.moveBy(const Offset(0, 96));
      await tester.pump();

      streamingNotifier.updateContent(
        'streaming-message',
        'updated while dragging',
        3,
      );
      await tester.pump();

      expect(find.text('initial stream content'), findsOneWidget);
      expect(find.text('updated while dragging'), findsNothing);

      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('initial stream content'), findsOneWidget);
      expect(find.text('updated while dragging'), findsNothing);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.text('updated while dragging'), findsOneWidget);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
      streamingNotifier.dispose();
    },
  );

  testWidgets(
    'Near-bottom user scrolling records intent and resumes streaming after release',
    (tester) async {
      var userIntentCalls = 0;
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final streamingNotifier = StreamingContentNotifier();
      final messages = <ChatMessage>[
        for (var i = 0; i < 18; i++)
          ChatMessage(
            id: 'bottom-message-$i',
            role: 'assistant',
            content: '\n\n\n\n\n\n\n\n',
            conversationId: 'conversation-1',
          ),
        ChatMessage(
          id: 'bottom-streaming-message',
          role: 'assistant',
          content: 'initial bottom stream content',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ];
      streamingNotifier.getNotifier('bottom-streaming-message');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                bottomContentPadding: 16,
                streamingContentNotifier: streamingNotifier,
                onUserScrollIntent: () => userIntentCalls++,
              ),
            ),
          ),
        ),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperListView)),
      );
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump();

      expect(userIntentCalls, 0);
      expect(
        scrollController.position.maxScrollExtent - scrollController.offset,
        lessThanOrEqualTo(56),
      );

      streamingNotifier.updateContent(
        'bottom-streaming-message',
        'updated while still near bottom',
        3,
      );
      await tester.pump();

      expect(find.text('updated while still near bottom'), findsNothing);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 220));
      expect(userIntentCalls, 1);
      expect(find.text('updated while still near bottom'), findsOneWidget);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
      streamingNotifier.dispose();
    },
  );

  testWidgets(
    'Mouse wheel scrolling pauses applying streamed updates',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final streamingNotifier = StreamingContentNotifier();
      final messages = <ChatMessage>[
        for (var i = 0; i < 18; i++)
          ChatMessage(
            id: 'wheel-message-$i',
            role: 'assistant',
            content: '\n\n\n\n\n\n\n\n',
            conversationId: 'conversation-1',
          ),
        ChatMessage(
          id: 'wheel-streaming-message',
          role: 'assistant',
          content: 'initial wheel stream content',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      ];
      streamingNotifier.getNotifier('wheel-streaming-message');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                bottomContentPadding: 16,
                streamingContentNotifier: streamingNotifier,
              ),
            ),
          ),
        ),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(SuperListView))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -96)));
      await tester.pump();

      streamingNotifier.updateContent(
        'wheel-streaming-message',
        'updated while wheel scrolling',
        3,
      );
      await tester.pump();

      expect(find.text('initial wheel stream content'), findsOneWidget);
      expect(find.text('updated while wheel scrolling'), findsNothing);

      await tester.pump(const Duration(milliseconds: 220));

      expect(find.text('updated while wheel scrolling'), findsOneWidget);

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
      streamingNotifier.dispose();
    },
  );

  testWidgets(
    'Unlaid-out long messages estimate height from length instead of 100 pixels',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);
      final longBody = List<String>.filled(
        120,
        '\u8FD9\u662F\u4E00\u6BB5\u7528\u4E8E\u6491\u9AD8\u6D88\u606F\u6C14\u6CE1\u7684\u957F\u6587\u672C，\u91CD\u590D\u51FA\u73B0\u4EE5\u4FBF\u4F30\u7B97\u9AD8\u5EA6。',
      ).join('\n');
      final messages = <ChatMessage>[
        for (var i = 0; i < 40; i++)
          ChatMessage(
            id: 'long-message-$i',
            role: i.isEven ? 'user' : 'assistant',
            content: longBody,
            conversationId: 'conversation-1',
          ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: SettingsProvider(createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
            ChangeNotifierProvider.value(
              value: TtsProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(
              value: UserProvider(preferences: createBusinessTestPreferences()),
            ),
            ChangeNotifierProvider.value(value: AskUserInteractionService()),
            ChangeNotifierProvider.value(value: ToolApprovalService()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: const {},
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
              ),
            ),
          ),
        ),
      );

      // The tail of the list never entered layout, so its extents are still
      // estimates. A flat default (100px) makes the total extent — and with it a
      // bottom-pinned scroll offset — lurch every time one of them is measured.
      final tail = listController.extentForIndex(messages.length - 1);
      expect(tail.$2, isTrue, reason: 'tail item should still be estimated');
      expect(tail.$1, greaterThan(2000));

      scrollController.dispose();
      listController.dispose();
      processingFilesMessageId.dispose();
    },
  );

  testWidgets(
    'Estimated height respects accessibility font scaling',
    (tester) async {
      final listController = ListController();
      final body = List<String>.filled(
        120,
        '\u8FD9\u662F\u4E00\u6BB5\u7528\u4E8E\u6491\u9AD8\u6D88\u606F\u6C14\u6CE1\u7684\u957F\u6587\u672C，\u91CD\u590D\u51FA\u73B0\u4EE5\u4FBF\u4F30\u7B97\u9AD8\u5EA6。',
      ).join('\n');
      final messages = <ChatMessage>[
        for (var i = 0; i < 40; i++)
          ChatMessage(
            id: 'scaled-message-$i',
            role: 'assistant',
            content: body,
            conversationId: 'conversation-1',
          ),
      ];

      await _pumpEstimatorHarness(
        tester,
        messages,
        listController,
        textScale: 2.0,
      );
      final tail = listController.extentForIndex(39);

      // Items render at the system scale times the chat scale. Ignoring the
      // system half leaves the estimate at the unscaled ~2900px for this body,
      // while the real bubble is about four times that.
      expect(tail.$2, isTrue);
      expect(tail.$1, greaterThan(6000));

      listController.dispose();
    },
  );

  testWidgets(
    'Collapsed inline reasoning excluded from height estimate',
    (tester) async {
      final listController = ListController();
      final thinking = List<String>.filled(
        200,
        '\u8FD9\u662F\u4E00\u6BB5\u5F88\u957F\u7684\u601D\u8003\u5185\u5BB9。',
      ).join('\n');

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages(
          '<think>\n$thinking\n</think>\n\u7B80\u77ED\u7684\u6B63\u6587\u56DE\u7B54。',
        ),
        listController,
      );
      final tail = listController.extentForIndex(39);

      // Only the one visible line plus a collapsed card renders; counting the
      // 200 hidden lines would inflate the scroll range by orders of magnitude.
      expect(tail.$2, isTrue);
      expect(tail.$1, lessThan(400));

      listController.dispose();
    },
  );

  testWidgets(
    'Expanded reasoning body included in height estimate',
    (tester) async {
      final listController = ListController();
      final thinking = List<String>.filled(
        200,
        '\u8FD9\u662F\u4E00\u6BB5\u5F88\u957F\u7684\u601D\u8003\u5185\u5BB9。',
      ).join('\n');

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages(
          '<think>\n$thinking\n</think>\n\u7B80\u77ED\u7684\u6B63\u6587\u56DE\u7B54。',
        ),
        listController,
        collapseThinking: false,
      );
      final tail = listController.extentForIndex(39);

      // With auto-collapse off the whole block is on screen, so skipping it
      // would under-estimate by thousands of pixels.
      expect(tail.$2, isTrue);
      expect(tail.$1, greaterThan(4000));

      listController.dispose();
    },
  );

  testWidgets(
    'Literal think tag in user message counted toward height estimate',
    (tester) async {
      final listController = ListController();
      final thinking = List<String>.filled(
        200,
        '\u8FD9\u662F\u4E00\u6BB5\u5F88\u957F\u7684\u601D\u8003\u5185\u5BB9。',
      ).join('\n');

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages(
          '<think>\n$thinking\n</think>\n\u7B80\u77ED\u7684\u6B63\u6587\u56DE\u7B54。',
          role: 'user',
        ),
        listController,
      );
      final tail = listController.extentForIndex(39);

      // A user message renders its text verbatim — there is no thinking card.
      expect(tail.$2, isTrue);
      expect(tail.$1, greaterThan(4000));

      listController.dispose();
    },
  );

  testWidgets(
    'Estimated height ignores Markdown link targets',
    (tester) async {
      final listController = ListController();
      final target = 'https://example.com/${'a' * 4000}';

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages('[x]($target)'),
        listController,
      );
      final tail = listController.extentForIndex(39);

      // The link renders as the single character `x`; counting the hidden target
      // would invent hundreds of lines of scroll range.
      expect(tail.$2, isTrue);
      expect(tail.$1, lessThan(200));

      listController.dispose();
    },
  );

  testWidgets(
    'Long unwrapped code line is not estimated as wrapped',
    (tester) async {
      final listController = ListController();
      final codeLine = 'x' * 4000;

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages('```json\n$codeLine\n```'),
        listController,
      );
      final tail = listController.extentForIndex(39);

      // Code blocks scroll horizontally instead of wrapping, so one long line
      // stays one line.
      expect(tail.$2, isTrue);
      expect(tail.$1, lessThan(300));

      listController.dispose();
    },
  );

  testWidgets(
    'Wrapped code blocks contribute wrapped-line height',
    (tester) async {
      final listController = ListController();
      final codeLine = 'x' * 4000;

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages('```json\n$codeLine\n```'),
        listController,
        wrapCodeBlocks: true,
      );
      final tail = listController.extentForIndex(39);

      // Desktop (and mobile with the wrap setting on) renders the same line as
      // dozens of rows; the horizontal-scroll case above estimates it at under
      // 300px, so treating every renderer as scrolling under-estimates badly.
      expect(tail.$2, isTrue);
      expect(tail.$1, greaterThan(900));

      listController.dispose();
    },
  );

  testWidgets(
    'Expanded standalone reasoning included in height estimate',
    (tester) async {
      final listController = ListController();
      final reasoningText = List.filled(
        200,
        '\u8FD9\u662F\u4E00\u6BB5\u5F88\u957F\u7684\u601D\u8003\u5185\u5BB9。',
      ).join('\n');

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages('\u7B80\u77ED\u7684\u6B63\u6587\u56DE\u7B54。'),
        listController,
        reasoning: {
          for (var i = 0; i < 40; i++)
            'estimator-message-$i': stream_ctrl.ReasoningData()
              ..text = reasoningText
              ..expanded = true,
        },
      );
      final tail = listController.extentForIndex(39);

      // Reasoning lives outside message.content; ignoring it estimates a
      // reasoning-heavy message an order of magnitude too short.
      expect(tail.$2, isTrue);
      expect(tail.$1, greaterThan(3000));

      listController.dispose();
    },
  );

  testWidgets(
    'Collapsed standalone reasoning uses fixed card height',
    (tester) async {
      final listController = ListController();
      final reasoningText = List.filled(
        200,
        '\u8FD9\u662F\u4E00\u6BB5\u5F88\u957F\u7684\u601D\u8003\u5185\u5BB9。',
      ).join('\n');

      await _pumpEstimatorHarness(
        tester,
        _estimatorMessages('\u7B80\u77ED\u7684\u6B63\u6587\u56DE\u7B54。'),
        listController,
        reasoning: {
          for (var i = 0; i < 40; i++)
            'estimator-message-$i': stream_ctrl.ReasoningData()
              ..text = reasoningText
              ..expanded = false,
        },
      );
      final tail = listController.extentForIndex(39);

      expect(tail.$2, isTrue);
      expect(tail.$1, lessThan(400));

      listController.dispose();
    },
  );

  testWidgets(
    'Prepending taller messages preserves visible scroll position',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      final target = find.byKey(const ValueKey<String>('window-message-0'));
      expect(target, findsOneWidget);
      final topBeforePrepend = tester.getTopLeft(target).dy;

      state.prependMessages();
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforePrepend, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Sliding equal-size window backward preserves visible scroll position',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      final target = find.byKey(const ValueKey<String>('window-message-0'));
      expect(target, findsOneWidget);
      final topBeforeShift = tester.getTopLeft(target).dy;

      state.shiftWindowEarlier();
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforeShift, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Editing visible message preserves reading anchor',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      state.listController.jumpToItem(
        index: 15,
        scrollController: state.scrollController,
        alignment: 0.2,
      );
      await tester.pumpAndSettle();

      final target = find.byKey(const ValueKey<String>('window-message-15'));
      expect(target, findsOneWidget);
      final topBeforeEdit = tester.getTopLeft(target).dy;

      state.editMessageAboveAnchor();
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforeEdit, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Deleting messages above viewport preserves visible position',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      state.listController.jumpToItem(
        index: 15,
        scrollController: state.scrollController,
        alignment: 0.2,
      );
      await tester.pumpAndSettle();

      final target = find.byKey(const ValueKey<String>('window-message-15'));
      expect(target, findsOneWidget);
      final topBeforeDelete = tester.getTopLeft(target).dy;

      // A deletion in the middle of the window is neither a prefix nor a
      // suffix of the old slot list; without an explicit removal diff the list
      // would drop every measured height and drift while re-measuring.
      state.deleteMessage('window-message-5');
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforeDelete, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Deleting messages below viewport preserves visible content',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      state.listController.jumpToItem(
        index: 15,
        scrollController: state.scrollController,
        alignment: 0.2,
      );
      await tester.pumpAndSettle();

      final target = find.byKey(const ValueKey<String>('window-message-15'));
      expect(target, findsOneWidget);
      final topBeforeDelete = tester.getTopLeft(target).dy;

      state.deleteMessage('window-message-25');
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforeDelete, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Deleting messages preserves position with expanded long reasoning card',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(
        _PrependingMessageListHarness(
          key: key,
          initialReasoning: {
            // A tall expanded reasoning card whose height the extent estimator
            // can only approximate; the anchor restore must not inherit that
            // estimation error.
            'window-message-13': stream_ctrl.ReasoningData()
              ..text = List.filled(
                120,
                '\u601D\u8003\u5185\u5BB9\u884C，\u8DB3\u591F\u957F\u4EE5\u6491\u51FA\u5F88\u9AD8\u7684\u601D\u8003\u5361\u7247。',
              ).join('\n')
              ..expanded = true
              ..startAt = DateTime(2026, 1, 1)
              ..finishedAt = DateTime(2026, 1, 1, 0, 0, 5),
          },
        ),
      );

      final state = key.currentState!;
      state.listController.jumpToItem(
        index: 15,
        scrollController: state.scrollController,
        alignment: 0.2,
      );
      await tester.pumpAndSettle();

      final target = find.byKey(const ValueKey<String>('window-message-15'));
      expect(target, findsOneWidget);
      final topBeforeDelete = tester.getTopLeft(target).dy;

      state.deleteMessage('window-message-5');
      await tester.pumpAndSettle();

      expect(target, findsOneWidget);
      expect(
        tester.getTopLeft(target).dy,
        moreOrLessEquals(topBeforeDelete, epsilon: 1),
      );
    },
  );

  testWidgets(
    'Delete animation fades and collapses message while joining neighbors',
    (tester) async {
      final key = GlobalKey<_PrependingMessageListHarnessState>();
      await tester.pumpWidget(_PrependingMessageListHarness(key: key));

      final state = key.currentState!;
      state.listController.jumpToItem(
        index: 10,
        scrollController: state.scrollController,
        alignment: 0.2,
      );
      await tester.pumpAndSettle();

      final removing = find.byKey(const ValueKey<String>('window-message-10'));
      final below = find.byKey(const ValueKey<String>('window-message-11'));
      final removingHeight = tester.getSize(removing).height;
      final belowTopBefore = tester.getTopLeft(below).dy;

      state.markRemoving('window-message-10');
      await tester.pump();
      await tester.pump(ChatLayoutConstants.slotRemovalAnimationDuration);

      // The animated slot has collapsed to zero height and the message below
      // has spliced up into its place; the actual data removal afterwards is
      // then invisible.
      expect(tester.getSize(removing).height, lessThan(1));
      expect(
        tester.getTopLeft(below).dy,
        moreOrLessEquals(belowTopBefore - removingHeight, epsilon: 1.5),
      );

      state.deleteMessage('window-message-10');
      await tester.pumpAndSettle();
      expect(removing, findsNothing);
    },
  );
}

class _PrependingMessageListHarness extends StatefulWidget {
  const _PrependingMessageListHarness({
    super.key,
    this.initialReasoning = const <String, stream_ctrl.ReasoningData>{},
    this.showFooter = false,
    this.hasMoreAfter = false,
  });

  final Map<String, stream_ctrl.ReasoningData> initialReasoning;
  final bool showFooter;
  final bool hasMoreAfter;

  @override
  State<_PrependingMessageListHarness> createState() =>
      _PrependingMessageListHarnessState();
}

class _PrependingMessageListHarnessState
    extends State<_PrependingMessageListHarness> {
  final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
  final listController = ListController();
  final processingFilesMessageId = ValueNotifier<String?>(null);
  final removingSlotIds = <String>{};
  late List<ChatMessage> messages = <ChatMessage>[
    for (var index = 0; index < 30; index++)
      ChatMessage(
        id: 'window-message-$index',
        role: index.isEven ? 'user' : 'assistant',
        content: List<String>.filled(
          1 + index % 5,
          'variable height line $index',
        ).join('\n'),
        conversationId: 'conversation-1',
      ),
  ];

  void prependMessages() {
    setState(() {
      messages = <ChatMessage>[
        for (var index = 0; index < 5; index++)
          ChatMessage(
            id: 'prepended-message-$index',
            role: index.isEven ? 'user' : 'assistant',
            content: List<String>.filled(
              6 - index,
              'prepended variable height line $index',
            ).join('\n'),
            conversationId: 'conversation-1',
          ),
        ...messages,
      ];
    });
  }

  void replaceMessages(List<ChatMessage> next) {
    setState(() => messages = next);
  }

  void editMessageAboveAnchor() {
    setState(() {
      messages = [
        for (final message in messages)
          if (message.id == 'window-message-12')
            ChatMessage(
              id: 'window-message-12-v2',
              role: message.role,
              content: List<String>.filled(
                30,
                'edited message became substantially taller',
              ).join('\n'),
              conversationId: message.conversationId,
              groupId: 'window-message-12',
              version: 1,
            )
          else
            message,
      ];
    });
  }

  void shiftWindowEarlier() {
    setState(() {
      messages = <ChatMessage>[
        for (var index = 0; index < 5; index++)
          ChatMessage(
            id: 'earlier-message-$index',
            role: index.isEven ? 'user' : 'assistant',
            content: 'earlier message $index',
            conversationId: 'conversation-1',
          ),
        ...messages.take(messages.length - 5),
      ];
    });
  }

  void deleteMessage(String id) {
    setState(() {
      messages = [
        for (final message in messages)
          if (message.id != id) message,
      ];
    });
  }

  void markRemoving(String slotId) {
    setState(() => removingSlotIds.add(slotId));
  }

  @override
  void dispose() {
    scrollController.dispose();
    listController.dispose();
    processingFilesMessageId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(),
          body: MessageListView(
            scrollController: scrollController,
            listController: listController,
            messages: messages,
            byGroup: const {},
            versionSelections: const {},
            reasoning: widget.initialReasoning,
            reasoningSegments: const {},
            contentSplits: const {},
            toolParts: const {},
            translations: const {},
            selecting: false,
            selectedItems: const {},
            dividerPadding: EdgeInsets.zero,
            processingFilesMessageId: processingFilesMessageId,
            removingSlotIds: removingSlotIds,
            hasMoreAfter: widget.hasMoreAfter,
            footer: widget.showFooter
                ? const Center(
                    child: Text(
                      'Conversation prompt',
                      key: ValueKey('conversation-footer'),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpEstimatorHarness(
  WidgetTester tester,
  List<ChatMessage> messages,
  ListController listController, {
  double textScale = 1.0,
  bool collapseThinking = true,
  bool wrapCodeBlocks = false,
  Map<String, stream_ctrl.ReasoningData> reasoning =
      const <String, stream_ctrl.ReasoningData>{},
}) async {
  final scrollController = ScrollController();
  final processingFilesMessageId = ValueNotifier<String?>(null);
  addTearDown(scrollController.dispose);
  addTearDown(processingFilesMessageId.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: SettingsProvider(createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider.value(
          value: AssistantProvider(
            preferences: createBusinessTestPreferences(),
          ),
        ),
        ChangeNotifierProvider.value(
          value: TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider.value(
          value: UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider.value(value: AskUserInteractionService()),
        ChangeNotifierProvider.value(value: ToolApprovalService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: MessageListView(
                scrollController: scrollController,
                listController: listController,
                messages: messages,
                byGroup: const {},
                versionSelections: const {},
                reasoning: reasoning,
                reasoningSegments: const {},
                contentSplits: const {},
                toolParts: const {},
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: processingFilesMessageId,
                collapseThinking: collapseThinking,
                wrapCodeBlocks: wrapCodeBlocks,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

List<ChatMessage> _estimatorMessages(
  String content, {
  String role = 'assistant',
}) {
  return <ChatMessage>[
    for (var i = 0; i < 40; i++)
      ChatMessage(
        id: 'estimator-message-$i',
        role: role,
        content: content,
        conversationId: 'conversation-1',
      ),
  ];
}
