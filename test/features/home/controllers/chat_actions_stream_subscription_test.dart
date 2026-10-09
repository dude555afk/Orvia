import 'dart:async' as async;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:orvia/features/home/controllers/chat_actions.dart';

void main() {
  group('ChatActions.resolveStreamErrorContent', () {
    test(
      'On failure without body writes error text into assistant message',
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
      'Preserves partial assistant response on failure',
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
      'Processes chunks in order and calls done on normal stream',
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

    test('Calls done immediately on empty stream', () async {
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
      'Async chunk handling failure finalizes error without calling done',
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
      'Async done handler failure enters error finalization',
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
      'Does not process subsequent chunks concurrently with pending async handler',
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
      'Subscription keeps reading and locally queues chunks while handler is pending',
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
