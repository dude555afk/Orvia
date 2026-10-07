import "../../../support/business_test_harness.dart";
import 'package:orvia/core/models/chat_input_data.dart';
import 'package:orvia/core/models/model_spec.dart';
import 'package:orvia/core/models/reasoning_request.dart';
import 'package:orvia/features/home/utils/model_display_helper.dart';
import 'package:orvia/core/providers/assistant_provider.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/features/home/widgets/chat_input_bar.dart';
import 'package:orvia/icons/lucide_adapter.dart';
import 'package:orvia/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<ChatInputSubmissionResult> Function(ChatInputData input)
    onSend,
    SettingsProvider? settingsProvider,
    AssistantProvider? assistantProvider,
    ChatInputBarController? mediaController,
    bool loading = false,
    bool hasQueuedInput = false,
    String? queuedPreviewText,
    VoidCallback? onCancelQueuedInput,
    String? conversationId,
    String? sendButtonTooltip,
    ThemeData? theme,
    bool backgroundImageActive = false,
    double inputBackgroundOpacityLight = 0.8236,
    double inputBackgroundOpacityDark = 0.7396,
    bool supportsReasoning = false,
    ReasoningRequest? reasoning,
    bool reasoningActive = false,
  }) {
    final settings =
        settingsProvider ?? SettingsProvider(createBusinessTestPreferences());
    final assistants =
        assistantProvider ??
        AssistantProvider(preferences: createBusinessTestPreferences());
    // In the app, HomePage resolves the chat model (conversation override ->
    // assistant -> global default) and passes it down; mirror that here.
    final chatModel = resolveChatModel(
      settings,
      assistant: assistants.currentAssistant,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: assistants),
      ],
      child: MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: theme?.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatInputBar(
            chatModelProviderKey: chatModel.providerKey,
            chatModelId: chatModel.modelId,
            controller: controller,
            focusNode: focusNode,
            mediaController: mediaController,
            onSend: onSend,
            loading: loading,
            hasQueuedInput: hasQueuedInput,
            queuedPreviewText: queuedPreviewText,
            onCancelQueuedInput: onCancelQueuedInput,
            conversationId: conversationId,
            sendButtonTooltip: sendButtonTooltip,
            backgroundImageActive: backgroundImageActive,
            inputBackgroundOpacityLight: inputBackgroundOpacityLight,
            inputBackgroundOpacityDark: inputBackgroundOpacityDark,
            supportsReasoning: supportsReasoning,
            reasoning: reasoning,
            reasoningActive: reasoningActive,
          ),
        ),
      ),
    );
  }

  testWidgets(
    '\u63D0\u4EA4\u7ED3\u679C queued \u65F6\u4F1A\u6E05\u7A7A\u8F93\u5165',
    (tester) async {
      final controller = TextEditingController(text: 'queued message');
      final focusNode = FocusNode();
      ChatInputData? submitted;

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (input) async {
            submitted = input;
            return ChatInputSubmissionResult.queued;
          },
        ),
      );

      await tapSendButton(tester);

      expect(submitted?.text, 'queued message');
      expect(controller.text, isEmpty);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u63D0\u4EA4\u7ED3\u679C rejected \u65F6\u4FDD\u7559\u8F93\u5165\u5185\u5BB9',
    (tester) async {
      final controller = TextEditingController(text: 'keep me');
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      await tapSendButton(tester);

      expect(controller.text, 'keep me');

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u53D1\u9001\u6309\u94AE\u53EF\u663E\u793A\u7F16\u8F91\u6001\u4FDD\u5B58\u5E76\u53D1\u9001\u63D0\u793A',
    (tester) async {
      final controller = TextEditingController(text: 'edited message');
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          sendButtonTooltip: 'Save & Send',
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(find.byTooltip('Save & Send'), findsOneWidget);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u6709\u6392\u961F\u9879\u65F6\u663E\u793A\u72B6\u6001\u5E76\u5141\u8BB8\u53D6\u6D88',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      var cancelled = false;
      const preview =
          '\u7B2C\u4E00\u884C\n\u7B2C\u4E8C\u884C\n\u7B2C\u4E09\u884C\n\u7B2C\u56DB\u884C';

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          hasQueuedInput: true,
          queuedPreviewText: preview,
          onCancelQueuedInput: () {
            cancelled = true;
          },
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.readOnly, isTrue);
      expect(find.text('Queued to send'), findsOneWidget);
      expect(find.text('Cancel Queue'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);

      final previewText = tester.widget<Text>(find.text(preview));
      expect(previewText.maxLines, 3);
      expect(previewText.overflow, TextOverflow.ellipsis);

      await tester.tap(find.text('Cancel Queue'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u7ED8\u56FE\u6A21\u5F0F\u80F6\u56CA\u53EF\u5173\u95ED\u5E76\u4F20\u9012\u804A\u5929\u63A5\u53E3\u8DEF\u7531',
    (tester) async {
      final controller = TextEditingController(text: 'draw a cat');
      final focusNode = FocusNode();
      final mediaController = ChatInputBarController();
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.setProviderConfig(
        'OpenAITest',
        ProviderConfig(
          id: 'OpenAITest',
          enabled: true,
          name: 'OpenAITest',
          apiKey: 'test-key',
          baseUrl: 'https://example.com/v1',
          providerType: ProviderKind.openai,
        ),
      );
      await settings.setCurrentModel('OpenAITest', 'gpt-image-2');
      ChatInputData? submitted;

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          mediaController: mediaController,
          settingsProvider: settings,
          onSend: (input) async {
            submitted = input;
            return ChatInputSubmissionResult.rejected;
          },
        ),
      );

      expect(find.text('Image mode'), findsOneWidget);

      await tester.tap(find.byIcon(Lucide.X));
      await tester.pumpAndSettle();

      expect(find.text('Image mode'), findsNothing);
      expect(mediaController.allowImagesApiRouting, isFalse);

      await tapSendButton(tester);

      expect(submitted?.text, 'draw a cat');
      expect(submitted?.allowImagesApiRouting, isFalse);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u7ED8\u56FE\u6A21\u5F0F\u5173\u95ED\u540E\u5207\u6362\u5BF9\u8BDD\u4F1A\u91CD\u65B0\u663E\u793A',
    (tester) async {
      final controller = TextEditingController(text: 'draw a cat');
      final focusNode = FocusNode();
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.setProviderConfig(
        'OpenAITest',
        ProviderConfig(
          id: 'OpenAITest',
          enabled: true,
          name: 'OpenAITest',
          apiKey: 'test-key',
          baseUrl: 'https://example.com/v1',
          providerType: ProviderKind.openai,
        ),
      );
      await settings.setCurrentModel('OpenAITest', 'gpt-image-2');

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          settingsProvider: settings,
          conversationId: 'conversation-a',
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(find.text('Image mode'), findsOneWidget);

      await tester.tap(find.byIcon(Lucide.X));
      await tester.pumpAndSettle();

      expect(find.text('Image mode'), findsNothing);

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          settingsProvider: settings,
          conversationId: 'conversation-b',
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Image mode'), findsOneWidget);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u975E\u7ED8\u56FE\u6A21\u578B\u4FDD\u6301\u9ED8\u8BA4\u8DEF\u7531\u8BB8\u53EF',
    (tester) async {
      final controller = TextEditingController(text: 'hello');
      final focusNode = FocusNode();
      ChatInputData? submitted;

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (input) async {
            submitted = input;
            return ChatInputSubmissionResult.rejected;
          },
        ),
      );

      expect(find.text('Image mode'), findsNothing);

      await tapSendButton(tester);

      expect(submitted?.allowImagesApiRouting, isTrue);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u5728\u4EAE\u8272\u4E3B\u9898\u4E0B\u6709\u7A33\u5B9A\u5E95\u8272',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          theme: ThemeData.light(),
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final decoration = _mainInputDecoration(tester);
      expect(decoration.color?.a, greaterThanOrEqualTo(0.70));

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u5728\u6697\u8272\u4E3B\u9898\u4E0B\u4E0D\u662F\u7EAF\u900F\u660E\u6BDB\u73BB\u7483',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          theme: ThemeData.dark(),
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final decoration = _mainInputDecoration(tester);
      expect(decoration.color?.a, greaterThanOrEqualTo(0.60));

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u5728\u80CC\u666F\u56FE\u6A21\u5F0F\u4E0B\u964D\u4F4E\u7EAF\u8272\u8986\u76D6',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          theme: ThemeData.light(),
          backgroundImageActive: true,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final decoration = _mainInputDecoration(tester);
      expect(decoration.color?.a, inExclusiveRange(0.35, 0.70));

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u80CC\u666F\u900F\u660E\u5EA6\u6309\u5F53\u524D\u4E3B\u9898\u9009\u62E9\u5B9E\u9645 alpha',
    (tester) async {
      final lightController = TextEditingController();
      final lightFocusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: lightController,
          focusNode: lightFocusNode,
          theme: ThemeData.light(),
          inputBackgroundOpacityLight: 0.35,
          inputBackgroundOpacityDark: 0.75,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final light = _mainInputDecoration(tester).color;
      expect(light?.a, closeTo(0.35, 0.0001));

      await tester.pumpWidget(const SizedBox.shrink());

      lightController.dispose();
      lightFocusNode.dispose();

      final darkController = TextEditingController();
      final darkFocusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: darkController,
          focusNode: darkFocusNode,
          theme: ThemeData.dark(),
          inputBackgroundOpacityLight: 0.35,
          inputBackgroundOpacityDark: 0.75,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final dark = _mainInputDecoration(tester).color;
      expect(dark?.a, closeTo(0.75, 0.0001));

      darkController.dispose();
      darkFocusNode.dispose();
    },
  );

  testWidgets(
    '\u80CC\u666F\u56FE\u6A21\u5F0F\u540C\u6837\u9075\u5FAA\u8F93\u5165\u6846\u80CC\u666F\u900F\u660E\u5EA6\u8BBE\u7F6E',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          theme: ThemeData.dark(),
          backgroundImageActive: true,
          inputBackgroundOpacityDark: 0.7396,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      final decoration = _mainInputDecoration(tester);
      expect(decoration.color?.a, closeTo(0.545, 0.0001));

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u56FE\u7247\u548C\u6587\u4EF6\u9884\u89C8\u663E\u793A\u5728\u4E3B\u8F93\u5165\u6846\u5185\u90E8\u9876\u90E8',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final mediaController = ChatInputBarController();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          mediaController: mediaController,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      mediaController
        ..addFiles(const [
          DocumentAttachment(
            path: '/tmp/draft.pdf',
            fileName: 'draft.pdf',
            mime: 'application/pdf',
          ),
        ])
        ..addImages(['missing-draft-image.png']);
      await tester.pump();

      final surfaceFinder = _mainInputSurfaceFinder();
      expect(surfaceFinder, findsOneWidget);
      expect(
        find.descendant(of: surfaceFinder, matching: find.text('draft.pdf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: surfaceFinder, matching: find.byType(Image)),
        findsOneWidget,
      );
      final imagePreviewsFinder = find.byKey(
        const ValueKey('chat-input-image-previews'),
      );
      final documentPreviewsFinder = find.byKey(
        const ValueKey('chat-input-document-previews'),
      );
      expect(imagePreviewsFinder, findsOneWidget);
      expect(documentPreviewsFinder, findsOneWidget);

      final imagePreviewsRect = tester.getRect(imagePreviewsFinder);
      final documentPreviewsRect = tester.getRect(documentPreviewsFinder);
      expect(
        imagePreviewsRect.right,
        lessThanOrEqualTo(documentPreviewsRect.left),
      );

      final imageRect = tester.getRect(find.byType(Image));
      final removeButtonRect = tester.getRect(
        find.byKey(const ValueKey('chat-input-image-remove:0')),
      );
      expect(imageRect.contains(removeButtonRect.topLeft), isTrue);
      expect(imageRect.contains(removeButtonRect.bottomRight), isTrue);
      expect(removeButtonRect.width, lessThan(22));
      expect(removeButtonRect.height, lessThan(22));
      expect(
        find.descendant(
          of: imagePreviewsFinder,
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: documentPreviewsFinder,
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u5916\u5C42\u5E95\u90E8\u7559\u767D\u53EA\u4E0B\u79FB\u4E00\u70B9',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding == const EdgeInsets.fromLTRB(12, 4, 12, 8),
        ),
        findsOneWidget,
      );

      controller.dispose();
      focusNode.dispose();
    },
  );

  testWidgets('reasoning button hides level badge by default', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
        supportsReasoning: true,
        reasoning: const ReasoningRequest(ReasoningLevel.low),
        reasoningActive: true,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Reasoning Strength'), findsOneWidget);
    expect(find.text('low'), findsNothing);
  });

  testWidgets('reasoning button shows level badge when enabled', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setShowReasoningLevelBadge(true);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        settingsProvider: settings,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
        supportsReasoning: true,
        reasoning: const ReasoningRequest(ReasoningLevel.low),
        reasoningActive: true,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Reasoning Strength'), findsOneWidget);
    expect(find.text('low'), findsOneWidget);
  });
}

Future<void> tapSendButton(WidgetTester tester) async {
  await tester.tap(find.byIcon(Lucide.ArrowUp));
  await tester.pumpAndSettle();
}

Finder _mainInputSurfaceFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).borderRadius ==
            BorderRadius.circular(20),
  );
}

BoxDecoration _mainInputDecoration(WidgetTester tester) {
  final candidates = tester
      .widgetList<Container>(_mainInputSurfaceFinder())
      .map((widget) => widget.decoration)
      .whereType<BoxDecoration>()
      .toList();

  expect(candidates, hasLength(1));
  return candidates.single;
}
