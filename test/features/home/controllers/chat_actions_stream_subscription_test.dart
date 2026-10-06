import 'dart:async' as async;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';

void main() {
  group('ChatActions.resolveStreamErrorContent', () {
    test(
      '\u96F6\u6B63\u6587\u5931\u8D25\u65F6\u628A\u9519\u8BEF\u4FE1\u606F\u5199\u5165\u52A9\u624B\u6D88\u606F',
      () {
        expect(
          ChatActions.resolveStreamErrorContent(
            partialContent: '',
            errorText: 'Connection failed',
          ),
          'Connection failed',
        );
      },
    );

    test(
      '\u5DF2\u6709\u90E8\u5206\u56DE\u590D\u65F6\u4FDD\u7559\u56DE\u590D\u6B63\u6587',
      () {
        expect(
          ChatActions.resolveStreamErrorContent(
            partialContent: 'Partial response',
            errorText: 'Connection failed',
          ),
          'Partial response',
        );
      },
    );
  });

  group('ChatActions.listenSequentiallyToStream', () {
    test(
      'backpressure bounds a slow consumer and resumes without losing order',
      () async {
        final source = async.StreamController<int>(sync: true);
        final release = async.Completer<void>();
        final done = async.Completer<void>();
        final seen = <int>[];
        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: source.stream,
          onData: (value) async {
            seen.add(value);
            if (value == 0) await release.future;
          },
          onError: (e, s) async => done.completeError(e, s),
          onDone: () async => done.complete(),
        );
        for (var i = 0; i < 1000; i++) {
          source.add(i);
        }
        expect(source.isPaused, true);
        expect(seen, [0]);
        release.complete();
        await source.close();
        await done.future;
        expect(seen, List.generate(1000, (i) => i));
        await subscription.cancel();
      },
    );

    test(
      'a busy burst yields an event-loop turn before draining completely',
      () async {
        final source = async.StreamController<int>(sync: true);
        final done = async.Completer<void>();
        final timer = async.Completer<int>();
        var processed = 0;
        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: source.stream,
          onData: (value) async {
            final work = Stopwatch()..start();
            while (work.elapsedMicroseconds < 250) {}
            processed++;
          },
          onError: (e, s) async => done.completeError(e, s),
          onDone: () async => done.complete(),
        );
        async.Timer.run(() => timer.complete(processed));
        for (var i = 0; i < 256; i++) {
          source.add(i);
        }
        final processedBeforeTimer = await timer.future;
        expect(processedBeforeTimer, lessThan(256));
        await source.close();
        await done.future;
        expect(processed, 256);
        await subscription.cancel();
      },
    );

    test(
      '\u6B63\u5E38\u6D41\u6309\u987A\u5E8F\u5904\u7406 chunk \u5E76\u8C03\u7528 done',
      () async {
        final controller = async.StreamController<int>();
        final done = async.Completer<void>();
        final seen = <int>[];

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            seen.add(value);
          },
          onError: (error, stackTrace) async {
            fail('unexpected stream error: $error');
          },
          onDone: () async {
            done.complete();
          },
        );
        addTearDown(subscription.cancel);

        controller
          ..add(1)
          ..add(2);
        await controller.close();
        await done.future.timeout(const Duration(seconds: 1));

        expect(seen, const [1, 2]);
      },
    );

    test('\u7A7A\u6D41\u76F4\u63A5\u8C03\u7528 done', () async {
      final controller = async.StreamController<int>();
      final done = async.Completer<void>();

      final subscription = ChatActions.listenSequentiallyToStream<int>(
        stream: controller.stream,
        onData: (_) async {
          fail('empty stream should not process data');
        },
        onError: (error, stackTrace) async {
          fail('unexpected stream error: $error');
        },
        onDone: () async {
          done.complete();
        },
      );
      addTearDown(subscription.cancel);

      await controller.close();
      await done.future.timeout(const Duration(seconds: 1));

      expect(done.isCompleted, isTrue);
    });

    test(
      'chunk \u5904\u7406\u5F02\u6B65\u5931\u8D25\u65F6\u8FDB\u5165 error \u6536\u5C3E\u4E14\u4E0D\u518D\u8C03\u7528 done',
      () async {
        final controller = async.StreamController<int>();
        final errorSeen = async.Completer<Object>();
        var doneCalled = false;

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            if (value == 2) {
              throw StateError('chunk failed');
            }
          },
          onError: (error, stackTrace) async {
            errorSeen.complete(error);
          },
          onDone: () async {
            doneCalled = true;
          },
        );
        addTearDown(subscription.cancel);

        controller
          ..add(1)
          ..add(2)
          ..add(3);
        await controller.close();

        final error = await errorSeen.future.timeout(
          const Duration(seconds: 1),
        );
        expect(error, isA<StateError>());
        await Future<void>.delayed(Duration.zero);
        expect(doneCalled, isFalse);
      },
    );

    test(
      'done \u6536\u5C3E\u5F02\u6B65\u5931\u8D25\u65F6\u8FDB\u5165 error \u6536\u5C3E',
      () async {
        final controller = async.StreamController<int>();
        final errorSeen = async.Completer<Object>();

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (_) async {},
          onError: (error, stackTrace) async {
            errorSeen.complete(error);
          },
          onDone: () async {
            throw StateError('done failed');
          },
        );
        addTearDown(subscription.cancel);

        await controller.close();

        final error = await errorSeen.future.timeout(
          const Duration(seconds: 1),
        );
        expect(error, isA<StateError>());
      },
    );

    test(
      'error handler secondary failure is reported without escaping drain',
      () async {
        final controller = async.StreamController<int>();
        final reported = async.Completer<FlutterErrorDetails>();
        final previousHandler = FlutterError.onError;
        FlutterError.onError = (details) => reported.complete(details);
        addTearDown(() {
          FlutterError.onError = previousHandler;
        });

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (_) async => throw StateError('primary'),
          onError: (_, _) async => throw StateError('secondary'),
          onDone: () async {},
        );
        addTearDown(subscription.cancel);

        controller.add(1);
        await controller.close();
        final details = await reported.future.timeout(
          const Duration(seconds: 1),
        );
        expect(details.exception, isA<StateError>());
        expect(details.exception.toString(), contains('secondary'));
      },
    );

    test(
      '\u5F02\u6B65 handler \u672A\u5B8C\u6210\u524D\u4E0D\u4F1A\u5E76\u53D1\u5904\u7406\u540E\u7EED chunk',
      () async {
        final controller = async.StreamController<int>();
        final firstStarted = async.Completer<void>();
        final allowFirstToFinish = async.Completer<void>();
        final done = async.Completer<void>();
        final started = <int>[];

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            started.add(value);
            if (value == 1) {
              firstStarted.complete();
              await allowFirstToFinish.future;
            }
          },
          onError: (error, stackTrace) async {
            fail('unexpected stream error: $error');
          },
          onDone: () async {
            done.complete();
          },
        );
        addTearDown(subscription.cancel);

        controller
          ..add(1)
          ..add(2);
        await firstStarted.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);
        expect(started, const [1]);

        allowFirstToFinish.complete();
        await controller.close();
        await done.future.timeout(const Duration(seconds: 1));

        expect(started, const [1, 2]);
      },
    );

    test(
      '\u5F02\u6B65 handler \u672A\u5B8C\u6210\u65F6\u7F51\u7EDC\u8BA2\u9605\u4FDD\u6301\u8BFB\u53D6\u5E76\u5728\u672C\u5730\u6392\u961F',
      () async {
        final controller = async.StreamController<int>(sync: true);
        addTearDown(controller.close);
        final firstStarted = async.Completer<void>();
        final allowFirstToFinish = async.Completer<void>();
        final done = async.Completer<void>();
        final seen = <int>[];

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            seen.add(value);
            if (value == 1) {
              firstStarted.complete();
              await allowFirstToFinish.future;
            }
          },
          onError: (error, stackTrace) async {
            fail('unexpected stream error: $error');
          },
          onDone: () async => done.complete(),
        );
        addTearDown(subscription.cancel);

        controller.add(1);
        await firstStarted.future.timeout(const Duration(seconds: 1));
        expect(controller.isPaused, isFalse);
        controller
          ..add(2)
          ..add(3);
        expect(controller.isPaused, isFalse);
        expect(seen, const [1]);

        allowFirstToFinish.complete();
        await controller.close();
        await done.future.timeout(const Duration(seconds: 1));
        expect(seen, const [1, 2, 3]);
      },
    );

    test(
      'cancel waits for in-flight chunk and drops queued late chunks',
      () async {
        final controller = async.StreamController<int>(sync: true);
        final firstStarted = async.Completer<void>();
        final releaseFirst = async.Completer<void>();
        final seen = <int>[];
        var doneCalled = false;

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            seen.add(value);
            if (value == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
          onError: (error, stackTrace) async {
            fail('unexpected stream error: $error');
          },
          onDone: () async {
            doneCalled = true;
          },
        );

        controller
          ..add(1)
          ..add(2)
          ..add(3);
        await firstStarted.future.timeout(const Duration(seconds: 1));
        var cancelCompleted = false;
        final cancelled = subscription.cancel().then((_) {
          cancelCompleted = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(cancelCompleted, isFalse);

        releaseFirst.complete();
        await cancelled.timeout(const Duration(seconds: 1));
        await controller.close();

        expect(seen, const [1]);
        expect(doneCalled, isFalse);
      },
    );

    test(
      'error terminal drops chunks already queued behind the error',
      () async {
        final controller = async.StreamController<int>(sync: true);
        addTearDown(controller.close);
        final firstStarted = async.Completer<void>();
        final releaseFirst = async.Completer<void>();
        final errorSeen = async.Completer<Object>();
        final seen = <int>[];

        final subscription = ChatActions.listenSequentiallyToStream<int>(
          stream: controller.stream,
          onData: (value) async {
            seen.add(value);
            if (value == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
          onError: (error, stackTrace) async => errorSeen.complete(error),
          onDone: () async => fail('error stream must not complete normally'),
        );
        addTearDown(subscription.cancel);

        controller.add(1);
        await firstStarted.future.timeout(const Duration(seconds: 1));
        controller
          ..addError(StateError('terminal'))
          ..add(2);
        releaseFirst.complete();

        expect(
          await errorSeen.future.timeout(const Duration(seconds: 1)),
          isA<StateError>(),
        );
        expect(seen, const [1]);
      },
    );
  });
}
