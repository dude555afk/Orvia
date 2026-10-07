import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/controllers/file_processing_indicator_controller.dart';

void main() {
  const showDelay = Duration(milliseconds: 220);
  const minVisible = Duration(milliseconds: 320);

  FileProcessingIndicatorController newController() =>
      FileProcessingIndicatorController(
        showDelay: showDelay,
        minVisible: minVisible,
      );

  test(
    '\u89E3\u6790\u5FEB\u4E8E\u5EF6\u8FDF\u65F6\u89E3\u6790\u6761\u6839\u672C\u4E0D\u51FA\u73B0',
    () {
      fakeAsync((async) {
        final controller = newController();
        final seen = <String?>[];
        controller.messageId.addListener(
          () => seen.add(controller.messageId.value),
        );

        controller.start('a1');
        async.elapse(const Duration(milliseconds: 100));
        controller.finish('a1');
        async.elapse(const Duration(seconds: 1));

        expect(seen, isEmpty);
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );

  test(
    '\u89E3\u6790\u8D85\u8FC7\u5EF6\u8FDF\u540E\u51FA\u73B0，\u5E76\u81F3\u5C11\u505C\u7559\u6700\u77ED\u5C55\u793A\u65F6\u95F4',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay);
        expect(controller.messageId.value, 'a1');

        controller.finish('a1');
        // Still inside the hold: hiding now would be a flash.
        expect(controller.messageId.value, 'a1');

        async.elapse(minVisible);
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );

  test(
    '\u5C55\u793A\u65F6\u95F4\u5DF2\u8FC7\u540E\u7ED3\u675F\u4F1A\u7ACB\u5373\u9690\u85CF',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay + minVisible + const Duration(milliseconds: 10));
        expect(controller.messageId.value, 'a1');

        controller.finish('a1');
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );

  test(
    '\u5BF9\u8BDD A \u7ED3\u675F\u4E0D\u4F1A\u53D6\u6D88\u5BF9\u8BDD B \u5F85\u663E\u793A\u7684\u89E3\u6790\u6761',
    () {
      fakeAsync((async) {
        final controller = newController();

        // B raises the indicator while A is still generating.
        controller.start('b1');
        async.elapse(const Duration(milliseconds: 100));

        // A finishes in the background.
        controller.finish('a1');

        async.elapse(showDelay);
        expect(
          controller.messageId.value,
          'b1',
          reason:
              'A \u7684\u7EC8\u6B62\u4E0D\u5E94\u53D6\u6D88 B \u7684\u5F85\u663E\u793A\u8BA1\u65F6\u5668',
        );
        controller.dispose();
      });
    },
  );

  test(
    '\u5BF9\u8BDD A \u7ED3\u675F\u4E0D\u4F1A\u9690\u85CF\u5BF9\u8BDD B \u5DF2\u663E\u793A\u7684\u89E3\u6790\u6761',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('b1');
        async.elapse(showDelay + minVisible);
        expect(controller.messageId.value, 'b1');

        controller.finish('a1');
        async.elapse(const Duration(seconds: 1));

        expect(controller.messageId.value, 'b1');
        controller.dispose();
      });
    },
  );

  test(
    '\u65B0\u7684\u89E3\u6790\u7ACB\u5373\u4ECE\u4E0A\u4E00\u6761\u624B\u91CC\u63A5\u7BA1',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay);
        expect(controller.messageId.value, 'a1');

        controller.start('b1');
        expect(
          controller.messageId.value,
          isNull,
          reason:
              '\u65E7\u7684\u90A3\u6761\u5E94\u7ACB\u523B\u8BA9\u51FA，\u800C\u4E0D\u662F\u7EE7\u7EED\u6302\u5728\u4E0A\u4E00\u6761\u56DE\u590D\u4E0A',
        );

        async.elapse(showDelay);
        expect(controller.messageId.value, 'b1');
        controller.dispose();
      });
    },
  );

  test(
    'null \u4F1A\u6E05\u6389\u5F53\u524D\u6301\u6709\u8005，\u4E0D\u7BA1\u5B83\u662F\u8C01',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay + minVisible);
        expect(controller.messageId.value, 'a1');

        // \u4F20 null \u7684\u6E05\u7406\u4E0D\u505A\u5F52\u5C5E\u5224\u65AD，\u4EFB\u4F55\u6301\u6709\u8005\u90FD\u4F1A\u88AB\u6E05\u6389。
        controller.finish(null);
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );

  test(
    'null \u6E05\u7406\u4ECD\u7136\u9075\u5B88\u6700\u77ED\u5C55\u793A\u65F6\u95F4',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay);
        controller.finish(null);
        expect(controller.messageId.value, 'a1');

        async.elapse(minVisible);
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );

  test(
    'reset \u5FFD\u7565\u6700\u77ED\u5C55\u793A\u65F6\u95F4\u7ACB\u523B\u6E05\u7A7A',
    () {
      fakeAsync((async) {
        final controller = newController();

        controller.start('a1');
        async.elapse(showDelay);
        expect(controller.messageId.value, 'a1');

        controller.reset();
        expect(controller.messageId.value, isNull);
        expect(controller.owner, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(controller.messageId.value, isNull);
        controller.dispose();
      });
    },
  );
}
