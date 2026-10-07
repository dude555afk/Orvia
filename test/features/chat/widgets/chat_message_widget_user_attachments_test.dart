import "../../../support/business_test_harness.dart";
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/models/message_part.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/providers/user_provider.dart';
import 'package:orvia/features/chat/widgets/chat_message_widget.dart';
import 'package:orvia/utils/safe_resize_image.dart';
import 'package:orvia/l10n/app_localizations.dart';
import 'package:orvia/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            UserProvider(preferences: createBusinessTestPreferences()),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppSnackBarOverlay(child: child!),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSnackBarManager().dismissAll();
  });

  tearDown(() {
    AppSnackBarManager().dismissAll();
  });

  testWidgets(
    '\u7528\u6237\u6D88\u606F\u9644\u4EF6\u663E\u793A\u5728\u6587\u672C\u6C14\u6CE1\u4E0A\u65B9\u4E14\u4E0D\u5728\u6C14\u6CE1\u5185\u90E8',
    (tester) async {
      const messageId = 'user-with-attachments';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-user-attachments',
              parts: const [
                TextPart('\u8BF7\u770B\u8FD9\u4E2A'),
                ImagePart(uri: 'missing-user-image.png'),
                FilePart(
                  uri: '/tmp/spec.pdf',
                  name: 'spec.pdf',
                  mime: 'application/pdf',
                ),
              ],
            ),
          ),
        ),
      );

      final bubbleFinder = find.byKey(
        const ValueKey('user-message-text-bubble:$messageId'),
      );
      final attachmentsFinder = find.byKey(
        const ValueKey('user-message-attachments:$messageId'),
      );

      expect(bubbleFinder, findsOneWidget);
      expect(attachmentsFinder, findsOneWidget);
      expect(
        find.descendant(
          of: bubbleFinder,
          matching: find.text('\u8BF7\u770B\u8FD9\u4E2A'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bubbleFinder, matching: find.text('spec.pdf')),
        findsNothing,
      );
      expect(
        find.descendant(of: bubbleFinder, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: attachmentsFinder, matching: find.text('spec.pdf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: attachmentsFinder, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: attachmentsFinder, matching: find.byType(InkWell)),
        findsNothing,
      );

      final attachmentsRect = tester.getRect(attachmentsFinder);
      final bubbleRect = tester.getRect(bubbleFinder);
      expect(attachmentsRect.bottom, lessThanOrEqualTo(bubbleRect.top));
    },
  );

  testWidgets(
    'TextPart \u4E2D\u7684\u5B57\u9762\u91CF\u9644\u4EF6\u6807\u8BB0\u6309\u7EAF\u6587\u672C\u663E\u793A\u4E14\u4E0D\u751F\u6210\u9644\u4EF6',
    (tester) async {
      const messageId = 'user-literal-markers';
      const literal =
          '\u8BF7\u770B\u8FD9\u4E2A\n[image:missing-user-image.png]\n[file:/tmp/spec.pdf|spec.pdf|application/pdf]';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-literal-markers',
              parts: const [TextPart(literal)],
            ),
          ),
        ),
      );

      expect(
        find.byKey(ValueKey('user-message-attachments:$messageId')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('user-message-text-bubble:$messageId')),
        findsOneWidget,
      );
      expect(
        find.textContaining('[image:missing-user-image.png]'),
        findsOneWidget,
      );
      expect(
        find.textContaining('[file:/tmp/spec.pdf|spec.pdf|application/pdf]'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unavailable ImagePart \u663E\u793A\u5360\u4F4D\u800C\u4E0D\u662F\u53EF\u67E5\u770B\u56FE\u7247',
    (tester) async {
      const messageId = 'user-unavailable-image';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-unavailable-image',
              parts: const [
                TextPart('\u56FE\u6302\u4E86'),
                ImagePart(uri: '/tmp/gone.png', unavailable: true),
              ],
            ),
          ),
        ),
      );

      final attachmentsFinder = find.byKey(
        const ValueKey('user-message-attachments:$messageId'),
      );
      expect(attachmentsFinder, findsOneWidget);
      expect(
        find.descendant(of: attachmentsFinder, matching: find.byType(Image)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'MalformedPart \u663E\u793A\u9644\u4EF6\u4E0D\u53EF\u7528\u5360\u4F4D',
    (tester) async {
      const messageId = 'user-malformed-attachments';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-malformed-attachments',
              parts: const [
                TextPart('\u9644\u4EF6\u635F\u574F'),
                MalformedPart(
                  rawKind: 'image',
                  rawPayload: '{',
                  parseError: 'invalid image payload JSON',
                ),
                MalformedPart(
                  rawKind: 'file',
                  rawPayload: '{}',
                  parseError: 'file payload requires non-empty uri',
                ),
              ],
            ),
          ),
        ),
      );

      final attachmentsFinder = find.byKey(
        const ValueKey('user-message-attachments:$messageId'),
      );
      expect(attachmentsFinder, findsOneWidget);
      expect(
        find.descendant(
          of: attachmentsFinder,
          matching: find.text('Attachment unavailable'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-message-attachment:$messageId:1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-message-attachment:$messageId:2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FilePart \u5728 ImagePart \u4E4B\u524D\u65F6\u4FDD\u6301 parts \u5E8F\u53F7\u987A\u5E8F',
    (tester) async {
      const messageId = 'user-file-before-image';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-file-before-image',
              parts: const [
                TextPart('\u987A\u5E8F'),
                FilePart(
                  uri: '/tmp/first.pdf',
                  name: 'first.pdf',
                  mime: 'application/pdf',
                ),
                ImagePart(uri: 'https://example.com/second.png'),
              ],
            ),
          ),
        ),
      );

      final fileFinder = find.byKey(
        const ValueKey('user-message-attachment:$messageId:1'),
      );
      final imageFinder = find.byKey(
        const ValueKey('user-message-attachment:$messageId:2'),
      );
      expect(fileFinder, findsOneWidget);
      expect(imageFinder, findsOneWidget);
      expect(
        tester.getRect(fileFinder).left,
        lessThan(tester.getRect(imageFinder).left),
      );
      expect(
        find.descendant(of: fileFinder, matching: find.text('first.pdf')),
        findsOneWidget,
      );

      final image = tester.widget<Image>(
        find.descendant(of: imageFinder, matching: find.byType(Image)),
      );
      final provider = image.image;
      final network = provider is NetworkImage
          ? provider
          : provider is SafeResizeImage &&
                provider.imageProvider is NetworkImage
          ? provider.imageProvider as NetworkImage
          : null;
      expect(network, isA<NetworkImage>());
      expect(network!.url, 'https://example.com/second.png');
    },
  );

  testWidgets(
    'http ImagePart \u4F7F\u7528 Image.network \u800C\u4E0D\u662F Image.file',
    (tester) async {
      const messageId = 'user-http-image';

      await tester.pumpWidget(
        _harness(
          ChatMessageWidget(
            showUserAvatar: false,
            message: ChatMessage(
              id: messageId,
              role: 'user',
              conversationId: 'conversation-http-image',
              parts: const [
                TextPart('\u8FDC\u7A0B\u56FE'),
                ImagePart(uri: 'https://cdn.example.com/a.png'),
              ],
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      final inner = provider is SafeResizeImage
          ? provider.imageProvider
          : provider;
      expect(inner, isA<NetworkImage>());
      expect(inner, isNot(isA<FileImage>()));
    },
  );

  testWidgets('tapping https FilePart launches external URL', (tester) async {
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    String? launchedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          if (call.method == 'launch') {
            launchedUrl = (call.arguments as Map)['url'] as String?;
            return true;
          }
          return false;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, null);
    });

    const messageId = 'user-https-file';
    await tester.pumpWidget(
      _harness(
        ChatMessageWidget(
          showUserAvatar: false,
          message: ChatMessage(
            id: messageId,
            role: 'user',
            conversationId: 'conversation-https-file',
            parts: const [
              TextPart('\u8FDC\u7A0B\u6587\u4EF6'),
              FilePart(
                uri: 'https://example.com/doc.pdf',
                name: 'doc.pdf',
                mime: 'application/pdf',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('user-message-attachment:$messageId:1')),
    );
    await tester.pumpAndSettle();

    expect(launchedUrl, 'https://example.com/doc.pdf');
    expect(find.textContaining('File not found'), findsNothing);
    expect(find.textContaining('\u6587\u4EF6\u4E0D\u5B58\u5728'), findsNothing);
  });

  testWidgets('tapping data: FilePart shows unsupported snackbar', (
    tester,
  ) async {
    const messageId = 'user-data-file';
    await tester.pumpWidget(
      _harness(
        ChatMessageWidget(
          showUserAvatar: false,
          message: ChatMessage(
            id: messageId,
            role: 'user',
            conversationId: 'conversation-data-file',
            parts: const [
              TextPart('data\u6587\u4EF6'),
              FilePart(
                uri: 'data:application/pdf;base64,AAAA',
                name: 'inline.pdf',
                mime: 'application/pdf',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('user-message-attachment:$messageId:1')),
    );
    await tester.pump(); // show snackbar without waiting for auto-dismiss timer

    expect(
      find.textContaining('Cannot open file: unsupported data URI'),
      findsOneWidget,
    );
    expect(find.textContaining('File not found'), findsNothing);
    expect(find.textContaining('\u6587\u4EF6\u4E0D\u5B58\u5728'), findsNothing);

    // Drain snackbar auto-dismiss timer so the test binding stays clean.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('user attachment thumbs decode with cover and no upscaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _harness(
        ChatMessageWidget(
          showUserAvatar: false,
          message: ChatMessage(
            id: 'user-cover-thumb',
            role: 'user',
            conversationId: 'conversation-cover-thumb',
            parts: const [
              TextPart('\u56FE'),
              ImagePart(uri: 'https://example.com/wide.png'),
            ],
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(image.image, isA<SafeResizeImage>());
    final resized = image.image as SafeResizeImage;
    expect(resized.fit, SafeResizeFit.cover);
    expect(resized.allowUpscaling, isFalse);
    expect(resized.width, 336);
    expect(resized.height, 336);
    expect(
      resized.width * resized.height,
      lessThanOrEqualTo(kToolImageMaxDecodePixels),
    );
  });
}
