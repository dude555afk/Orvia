import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  testWidgets(
    '\u6D88\u606F\u753B\u5E03\u94FA\u5230\u7CFB\u7EDF\u72B6\u6001\u680F\u540E\u65B9，\u5E95\u90E8\u8986\u76D6\u5C42\u8D34\u4F4F\u5E95\u90E8',
    (tester) async {
      const rootKey = Key('root');
      const contentKey = Key('content');
      const overlayKey = Key('overlay');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              key: rootKey,
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: ColoredBox(key: contentKey, color: Colors.blue),
                bottomOverlay: SizedBox(
                  key: overlayKey,
                  width: 200,
                  height: 50,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
      expect(tester.getBottomLeft(find.byKey(contentKey)).dy, 600);
      expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
    },
  );

  testWidgets(
    '\u5E95\u90E8\u8986\u76D6\u5C42\u6700\u9AD8\u53EA\u5230\u9876\u680F\u4E0B\u65B9，\u4E0D\u4F1A\u538B\u4F4F\u6807\u9898',
    (tester) async {
      const overlayKey = Key('overlay');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: ColoredBox(color: Colors.blue),
                bottomOverlay: SizedBox(
                  key: overlayKey,
                  width: 200,
                  height: 900,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 112);
      expect(tester.getBottomLeft(find.byKey(overlayKey)).dy, 600);
    },
  );

  testWidgets(
    '\u8F93\u5165\u6846\u5C42\u4F4D\u4E8E\u524D\u666F\u906E\u7F69\u4E0A\u65B9',
    (tester) async {
      var inputTaps = 0;
      var foregroundTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: const ColoredBox(color: Colors.blue),
                foreground: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => foregroundTaps++,
                ),
                bottomOverlay: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => inputTaps++,
                  child: const SizedBox(width: 400, height: 88),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(200, 560));
      await tester.pump();

      expect(inputTaps, 1);
      expect(foregroundTaps, 0);
    },
  );

  testWidgets(
    '\u5E95\u90E8\u8986\u76D6\u5C42\u540E\u65B9\u6709\u6E10\u53D8\u906E\u7F69\u9694\u5F00\u6D88\u606F\u5185\u5BB9',
    (tester) async {
      const fadeKey = Key('chat-input-overlay-bottom-fade');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: ColoredBox(color: Colors.blue),
                bottomOverlay: SizedBox(width: 200, height: 50),
              ),
            ),
          ),
        ),
      );

      final fadeFinder = find.byKey(fadeKey);
      expect(fadeFinder, findsOneWidget);
      expect(tester.getTopLeft(fadeFinder).dy, 420);
      expect(tester.getBottomLeft(fadeFinder).dy, 600);

      final decoration = tester.widget<DecoratedBox>(
        find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
      );
      final boxDecoration = decoration.decoration as BoxDecoration;
      final gradient = boxDecoration.gradient as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors[1].a, greaterThan(0.80));
      expect(gradient.colors.last.a, greaterThan(0.95));
    },
  );

  testWidgets(
    '\u9876\u90E8\u5BFC\u822A\u680F\u540E\u65B9\u6709\u6E10\u53D8\u906E\u7F69\u9694\u5F00\u6D88\u606F\u5185\u5BB9',
    (tester) async {
      const fadeKey = Key('chat-input-overlay-top-fade');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: ColoredBox(color: Colors.blue),
                bottomOverlay: SizedBox(width: 200, height: 50),
              ),
            ),
          ),
        ),
      );

      final fadeFinder = find.byKey(fadeKey);
      expect(fadeFinder, findsOneWidget);
      expect(tester.getTopLeft(fadeFinder).dy, 0);
      expect(tester.getBottomLeft(fadeFinder).dy, 116);

      final decoration = tester.widget<DecoratedBox>(
        find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
      );
      final boxDecoration = decoration.decoration as BoxDecoration;
      final gradient = boxDecoration.gradient as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.stops, const [0.0, 0.48, 0.78, 1.0]);
      expect(gradient.colors.first.a, 1);
      expect(gradient.colors[1].a, inInclusiveRange(0.98, 0.995));
      expect(gradient.colors[2].a, inInclusiveRange(0.85, 0.90));
      expect(gradient.colors.last.a, 0);
    },
  );

  testWidgets(
    '\u6EDA\u52A8\u4E2D\u7684\u6D88\u606F\u6301\u7EED\u7ED8\u5236\u5230\u7CFB\u7EDF\u72B6\u6001\u680F\u533A\u57DF',
    (tester) async {
      const firstMessageKey = Key('overflow-message');
      final scrollController = ScrollController(initialScrollOffset: 132);
      final listController = ListController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                content: SuperListView.builder(
                  controller: scrollController,
                  listController: listController,
                  padding: const EdgeInsets.only(top: 108),
                  itemCount: 12,
                  itemBuilder: (context, index) => ColoredBox(
                    key: index == 0 ? firstMessageKey : null,
                    color: index.isEven
                        ? const Color(0xFF0055FF)
                        : const Color(0xFF00CC66),
                    child: const SizedBox(height: 80),
                  ),
                ),
                bottomOverlay: const SizedBox(width: 200, height: 50),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final listFinder = find.byType(SuperListView);
      expect(tester.getTopLeft(listFinder).dy, 0);
      expect(tester.getTopLeft(find.byKey(firstMessageKey)).dy, -24);

      scrollController.dispose();
      listController.dispose();
    },
  );

  testWidgets(
    '\u80CC\u666F\u56FE\u6A21\u5F0F\u4E0B\u7528\u80CC\u666F\u8986\u76D6\u9876\u90E8\u4E14\u4E0D\u6E32\u67D3\u7EAF\u8272\u906E\u7F69',
    (tester) async {
      const bottomFadeKey = Key('chat-input-overlay-bottom-fade');
      const bottomBackgroundKey = Key('chat-input-overlay-bottom-background');
      const topFadeKey = Key('chat-input-overlay-top-fade');
      const topBackgroundKey = Key('chat-input-overlay-top-background');
      const backgroundKey = Key('background');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatInputOverlayLayout(
                topInset: 100,
                backgroundImageActive: true,
                topBackground: ColoredBox(
                  key: backgroundKey,
                  color: Colors.green,
                ),
                content: ColoredBox(color: Colors.blue),
                bottomOverlay: SizedBox(width: 200, height: 50),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(bottomFadeKey), findsNothing);
      expect(find.byKey(bottomBackgroundKey), findsOneWidget);
      expect(find.byKey(topFadeKey), findsNothing);
      expect(find.byKey(topBackgroundKey), findsOneWidget);
      expect(find.byKey(backgroundKey), findsNWidgets(2));

      final clipRect = tester.widget<ClipRect>(
        find.ancestor(
          of: find.byKey(topBackgroundKey),
          matching: find.byType(ClipRect),
        ),
      );
      final clip = clipRect.clipper!.getClip(const Size(400, 600));
      expect(clip.height, 116);

      final bottomClipRect = tester.widget<ClipRect>(
        find.ancestor(
          of: find.byKey(bottomBackgroundKey),
          matching: find.byType(ClipRect),
        ),
      );
      final bottomClip = bottomClipRect.clipper!.getClip(const Size(400, 600));
      expect(bottomClip.top, 420);
      expect(bottomClip.height, 180);
    },
  );

  testWidgets(
    '\u952E\u76D8\u5F39\u51FA\u65F6\u80CC\u666F\u4ECD\u6309\u952E\u76D8\u6536\u8D77\u65F6\u7684\u9AD8\u5EA6\u5E03\u5C40',
    (tester) async {
      const backgroundKey = Key('background');
      const contentKey = Key('content');

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Widget build() {
        return const MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: true,
            body: ChatInputOverlayLayout(
              topInset: 100,
              backgroundImageActive: true,
              topBackground: ColoredBox(
                key: backgroundKey,
                color: Colors.green,
              ),
              content: ColoredBox(key: contentKey, color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        );
      }

      await tester.pumpWidget(build());
      final closedContentHeight = tester.getSize(find.byKey(contentKey)).height;
      final closedBackgroundHeight = tester
          .getSize(find.byKey(backgroundKey).first)
          .height;
      expect(closedBackgroundHeight, closedContentHeight);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpWidget(build());

      // The body really did shrink around the keyboard...
      expect(
        tester.getSize(find.byKey(contentKey)).height,
        closedContentHeight - 300,
      );
      // ...but the artwork keeps its original box, so BoxFit.cover does not
      // re-crop and the background stays put.
      expect(
        tester.getSize(find.byKey(backgroundKey).first).height,
        closedBackgroundHeight,
      );
      expect(tester.getTopLeft(find.byKey(backgroundKey).first).dy, 0);
    },
  );
}
