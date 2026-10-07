import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/widgets/chat_suggestion_bubbles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders suggestion bubbles and reports taps', (tester) async {
    final tapped = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatSuggestionBubbles(
            suggestions: const ['\u7EE7\u7EED', '\u4E3E\u4F8B', '\u603B\u7ED3'],
            onTap: tapped.add,
          ),
        ),
      ),
    );

    expect(find.text('\u7EE7\u7EED'), findsOneWidget);
    expect(find.text('\u4E3E\u4F8B'), findsOneWidget);
    expect(find.text('\u603B\u7ED3'), findsOneWidget);

    await tester.tap(find.text('\u4E3E\u4F8B'));
    await tester.pump();

    expect(tapped, ['\u4E3E\u4F8B']);
  });
}
