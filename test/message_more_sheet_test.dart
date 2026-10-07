import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/chat/widgets/message_more_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

ChatMessage _message() {
  return ChatMessage(
    id: 'message-1',
    role: 'assistant',
    content: 'hello',
    conversationId: 'conversation-1',
  );
}

Future<void> _openMoreSheet(
  WidgetTester tester, {
  required bool canDeleteAllVersions,
  bool canCreateBranch = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showMessageMoreSheet(
                  context,
                  _message(),
                  canDeleteAllVersions: canDeleteAllVersions,
                  canCreateBranch: canCreateBranch,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '\u591A\u7248\u672C\u6D88\u606F\u83DC\u5355\u663E\u793A\u5220\u9664\u5168\u90E8\u7248\u672C',
    (tester) async {
      await _openMoreSheet(tester, canDeleteAllVersions: true);

      expect(find.text('Select Messages'), findsOneWidget);
      expect(find.text('Create Branch'), findsOneWidget);
      expect(find.text('Delete This Version'), findsOneWidget);
      expect(find.text('Delete All Versions'), findsOneWidget);
    },
  );

  testWidgets(
    '\u5355\u7248\u672C\u6D88\u606F\u83DC\u5355\u4E0D\u663E\u793A\u5220\u9664\u5168\u90E8\u7248\u672C',
    (tester) async {
      await _openMoreSheet(tester, canDeleteAllVersions: false);

      expect(find.text('Select Messages'), findsOneWidget);
      expect(find.text('Delete This Version'), findsOneWidget);
      expect(find.text('Delete All Versions'), findsNothing);
    },
  );

  testWidgets(
    '\u4E34\u65F6\u4F1A\u8BDD\u6D88\u606F\u83DC\u5355\u4E0D\u663E\u793A\u521B\u5EFA\u5206\u652F',
    (tester) async {
      await _openMoreSheet(
        tester,
        canDeleteAllVersions: false,
        canCreateBranch: false,
      );

      expect(find.text('Create Branch'), findsNothing);
    },
  );
}
