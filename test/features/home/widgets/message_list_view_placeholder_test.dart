import "../../../support/business_test_harness.dart";

import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/providers/assistant_provider.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/providers/tts_provider.dart';
import 'package:orvia/core/providers/user_provider.dart';
import 'package:orvia/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:orvia/features/home/services/ask_user_interaction_service.dart';
import 'package:orvia/features/home/services/tool_approval_service.dart';
import 'package:orvia/features/home/widgets/message_list_view.dart';
import 'package:orvia/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    '\u51B7\u52A0\u8F7D\u7A7A\u7A97\u53E3\u663E\u793A\u6C14\u6CE1\u9AA8\u67B6\u5360\u4F4D',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
                isLoadingWindow: true,
              ),
            ),
          ),
        );

        expect(find.byKey(MessageListView.windowSkeletonKey), findsOneWidget);
        expect(find.byType(SuperListView), findsOneWidget);

        // The skeleton pulses; it must survive further frames.
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(MessageListView.windowSkeletonKey), findsOneWidget);
      } finally {
        scrollController.dispose();
        listController.dispose();
        processingFilesMessageId.dispose();
      }
    },
  );

  testWidgets(
    '\u7A7A\u7A97\u53E3\u975E\u52A0\u8F7D\u6001\u4FDD\u6301\u7A7A\u767D（\u65E0\u5360\u4F4D）',
    (tester) async {
      final scrollController = ScrollController();
      final listController = ListController();
      final processingFilesMessageId = ValueNotifier<String?>(null);

      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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

        expect(find.byKey(MessageListView.windowSkeletonKey), findsNothing);
        expect(find.byType(SuperListView), findsOneWidget);
      } finally {
        scrollController.dispose();
        listController.dispose();
        processingFilesMessageId.dispose();
      }
    },
  );

  testWidgets(
    '\u7A97\u53E3\u8F7D\u5165\u5B8C\u6210\u540E\u9AA8\u67B6\u5207\u6362\u4E3A\u6D88\u606F\u5185\u5BB9',
    (tester) async {
      final key = GlobalKey<_PlaceholderHarnessState>();
      await tester.pumpWidget(_PlaceholderHarness(key: key));
      final state = key.currentState!;

      expect(find.byKey(MessageListView.windowSkeletonKey), findsOneWidget);

      state.finishLoad();
      await tester.pump();

      expect(find.byKey(MessageListView.windowSkeletonKey), findsNothing);
      expect(find.text('loaded message content'), findsOneWidget);
    },
  );

  testWidgets(
    '\u5FEB\u8DEF\u5F84\u547D\u4E2D\u5DF2\u6709\u6D88\u606F\u65F6\u4E0D\u663E\u793A\u9AA8\u67B6',
    (tester) async {
      final key = GlobalKey<_PlaceholderHarnessState>();
      await tester.pumpWidget(
        _PlaceholderHarness(
          key: key,
          initialLoading: false,
          withMessages: true,
        ),
      );

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.byKey(MessageListView.windowSkeletonKey), findsNothing);
      }
      expect(find.text('loaded message content'), findsOneWidget);
    },
  );
}

class _PlaceholderHarness extends StatefulWidget {
  const _PlaceholderHarness({
    super.key,
    this.initialLoading = true,
    this.withMessages = false,
  });

  final bool initialLoading;
  final bool withMessages;

  @override
  State<_PlaceholderHarness> createState() => _PlaceholderHarnessState();
}

class _PlaceholderHarnessState extends State<_PlaceholderHarness> {
  final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
  final listController = ListController();
  final processingFilesMessageId = ValueNotifier<String?>(null);

  late bool isLoading = widget.initialLoading;
  late List<ChatMessage> messages = widget.withMessages
      ? _buildMessages()
      : const <ChatMessage>[];

  static List<ChatMessage> _buildMessages() {
    return <ChatMessage>[
      ChatMessage(
        id: 'history-message-0',
        role: 'assistant',
        content: 'loaded message content',
        conversationId: 'conversation-1',
      ),
    ];
  }

  void finishLoad() {
    setState(() {
      isLoading = false;
      messages = _buildMessages();
    });
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
            isLoadingWindow: isLoading,
          ),
        ),
      ),
    );
  }
}
