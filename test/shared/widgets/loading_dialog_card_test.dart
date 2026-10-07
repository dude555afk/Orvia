import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orvia/shared/widgets/loading_dialog_card.dart';

void main() {
  group('LoadingDialogCard', () {
    testWidgets('renders activity indicator without label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LoadingDialogCard())),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders optional label text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingDialogCard(label: '\u6B63\u5728\u52A0\u8F7D'),
          ),
        ),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('\u6B63\u5728\u52A0\u8F7D'), findsOneWidget);
    });
  });
}
