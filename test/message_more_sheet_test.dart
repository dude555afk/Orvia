import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/features/chat/widgets/message_more_sheet.dart';
import 'package:orvia/l10n/app_localizations.dart';

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
    'Multi-version message menu shows Delete all versions',
    (tester) async {
      await _openMoreSheet(tester, canDeleteAllVersions: true);

      expect(find.text('Select Messages'), findsOneWidget);
      expect(find.text('Create Branch'), findsOneWidget);
      expect(find.text('Delete This Version'), findsOneWidget);
      expect(find.text('Delete All Versions'), findsOneWidget);
    },
  );

  testWidgets(
    'Single-version message menu hides Delete all versions',
    (tester) async {
      await _openMoreSheet(tester, canDeleteAllVersions: false);

      expect(find.text('Select Messages'), findsOneWidget);
      expect(find.text('Delete This Version'), findsOneWidget);
      expect(find.text('Delete All Versions'), findsNothing);
    },
  );

  testWidgets(
    'Temporary chat menu hides Create branch',
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
