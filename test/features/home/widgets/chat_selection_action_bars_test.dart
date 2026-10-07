import "../../../support/business_test_harness.dart";
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/widgets/chat_selection_delete_bar.dart';
import 'package:Kelivo/features/home/widgets/chat_selection_export_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpBar(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(createBusinessTestPreferences()),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(width: 420, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '\u5206\u4EAB\u5BFC\u51FA\u680F\u4E0D\u5C55\u793A\u5220\u9664\u64CD\u4F5C',
    (tester) async {
      await _pumpBar(
        tester,
        ChatSelectionExportBar(
          onExportMarkdown: () {},
          onExportTxt: () {},
          onExportImage: () {},
          showThinkingTools: false,
          showThinkingContent: false,
          onToggleThinkingTools: () {},
          onToggleThinkingContent: () {},
        ),
      );

      expect(find.text('TXT'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
      expect(find.text('Delete Selected'), findsNothing);
      expect(find.text('Delete This Version'), findsNothing);
      expect(find.text('Delete All Versions'), findsNothing);
    },
  );

  testWidgets(
    '\u5220\u9664\u680F\u5728\u5355\u7248\u672C\u9009\u62E9\u65F6\u53EA\u5C55\u793A\u666E\u901A\u5220\u9664',
    (tester) async {
      var currentVersionDeletes = 0;
      var allVersionDeletes = 0;

      await _pumpBar(
        tester,
        ChatSelectionDeleteBar(
          hasMultiVersionSelection: false,
          onDeleteCurrentVersions: () {
            currentVersionDeletes++;
          },
          onDeleteAllVersions: () {
            allVersionDeletes++;
          },
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Delete This Version'), findsNothing);
      expect(find.text('Delete All Versions'), findsNothing);
      expect(
        tester.getSize(find.byType(IosCardPress)).width,
        closeTo(396, 0.1),
      );
      expect(
        tester.widget<Text>(find.text('Delete')).style?.fontWeight,
        AppFontWeights.medium,
      );

      await tester.tap(find.text('Delete'));
      expect(currentVersionDeletes, 1);
      expect(allVersionDeletes, 0);
    },
  );

  testWidgets(
    '\u5220\u9664\u680F\u5728\u591A\u7248\u672C\u9009\u62E9\u65F6\u5C55\u793A\u672C\u7248\u672C\u548C\u5168\u90E8\u7248\u672C',
    (tester) async {
      var currentVersionDeletes = 0;
      var allVersionDeletes = 0;

      await _pumpBar(
        tester,
        ChatSelectionDeleteBar(
          hasMultiVersionSelection: true,
          onDeleteCurrentVersions: () {
            currentVersionDeletes++;
          },
          onDeleteAllVersions: () {
            allVersionDeletes++;
          },
        ),
      );

      expect(find.text('Delete This Version'), findsOneWidget);
      expect(find.text('Delete All Versions'), findsOneWidget);

      await tester.tap(find.text('Delete This Version'));
      await tester.tap(find.text('Delete All Versions'));

      expect(currentVersionDeletes, 1);
      expect(allVersionDeletes, 1);
    },
  );
}
