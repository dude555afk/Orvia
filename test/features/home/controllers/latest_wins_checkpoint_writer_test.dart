import 'dart:async';

import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/latest_wins_checkpoint_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LatestWinsCheckpointWriter', () {
    test(
      '\u5199\u5165\u4E2D\u53EA\u4FDD\u7559\u6700\u65B0 checkpoint',
      () async {
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final writes = <int>[];
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (value) async {
            writes.add(value);
            if (value == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
        );

        writer.add(() => 1);
        await firstStarted.future;
        writer
          ..add(() => 2)
          ..add(() => 3);

        releaseFirst.complete();
        await writer.barrier();

        expect(writes, const [1, 3]);
      },
    );

    test(
      '\u76F8\u90BB checkpoint \u8D77\u59CB\u65F6\u95F4\u81F3\u5C11\u95F4\u9694 250ms',
      () async {
        var now = DateTime(2026);
        final delays = <Duration>[];
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final writes = <int>[];
        final writer = LatestWinsCheckpointWriter<int>(
          now: () => now,
          delay: (duration) async {
            delays.add(duration);
            now = now.add(duration);
          },
          write: (value) async {
            writes.add(value);
            if (value == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
        );

        writer.add(() => 1);
        await firstStarted.future;
        writer.add(() => 2);
        releaseFirst.complete();
        await writer.barrier();

        expect(writes, const [1, 2]);
        expect(delays, const [Duration(milliseconds: 250)]);
      },
    );

    test(
      'final \u7B49\u5F85\u5728\u9014\u5199\u5E76\u4E22\u5F03\u5DF2\u88AB\u7EC8\u6001\u8986\u76D6\u7684 pending snapshot',
      () async {
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final events = <String>[];
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (value) async {
            events.add('checkpoint:$value');
            if (value == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
        );

        writer.add(() => 1);
        await firstStarted.future;
        writer.add(() => 2);
        final finalized = writer.finalize(() async {
          events.add('final');
          return 7;
        });

        await Future<void>.delayed(Duration.zero);
        expect(events, const ['checkpoint:1']);
        releaseFirst.complete();

        expect(await finalized, 7);
        expect(events, const ['checkpoint:1', 'final']);
        expect(() => writer.add(() => 3), throwsStateError);
      },
    );

    test(
      'checkpoint \u5931\u8D25\u53EF\u89C2\u5BDF\u4E14\u6210\u529F final \u53EF\u6062\u590D',
      () async {
        final errors = <Object>[];
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (_) async => throw StateError('write failed'),
          onError: (error, _) => errors.add(error),
        );
        var finalCalled = false;

        writer.add(() => 1);

        await writer.finalize(() async {
          finalCalled = true;
        });

        expect(finalCalled, isTrue);
        expect(errors, hasLength(1));
        expect(errors.single, isA<StateError>());
      },
    );

    test(
      '\u5931\u8D25\u7684 checkpoint \u4E0D\u4F1A\u6BD2\u5316\u540E\u7EED\u5199\u5165\u6216 barrier',
      () async {
        final errors = <Object>[];
        var attempt = 0;
        final writes = <int>[];
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (value) async {
            attempt++;
            // The first write fails (e.g. a transient DB busy); later writes
            // must still be attempted and must succeed.
            if (attempt == 1) throw StateError('transient busy');
            writes.add(value);
          },
          onError: (error, _) => errors.add(error),
        );

        writer.add(() => 1);
        await writer.barrier();
        expect(errors, hasLength(1));

        // A subsequent add must not throw and must be written.
        writer.add(() => 2);
        await writer.barrier();

        expect(writes, const [2]);
        expect(errors, hasLength(1));

        var finalCalled = false;
        await writer.finalize(() async => finalCalled = true);
        expect(finalCalled, isTrue);
      },
    );

    test(
      '\u6CA1\u6709 checkpoint \u65F6 final \u7ACB\u5373\u6267\u884C',
      () async {
        final writer = LatestWinsCheckpointWriter<int>(
          write: (_) async => fail('no checkpoint expected'),
        );

        final result = await writer.finalize(() async => 'done');

        expect(result, 'done');
      },
    );

    test(
      '100 token/s and 1 MiB burst never waits for checkpoint I/O',
      () async {
        final firstWriteStarted = Completer<void>();
        final releaseFirstWrite = Completer<void>();
        final allChunksConsumed = Completer<void>();
        final finalizationStarted = Completer<void>();
        final streamDone = Completer<void>();
        final writes = <int>[];
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (bytes) async {
            writes.add(bytes);
            if (writes.length == 1) {
              firstWriteStarted.complete();
              await releaseFirstWrite.future;
            }
          },
        );
        final controller = StreamController<String>(sync: true);
        const chunkBytes = 1024;
        const chunkCount = 1024;
        var consumed = 0;
        final subscription = ChatActions.listenSequentiallyToStream<String>(
          stream: controller.stream,
          onData: (chunk) async {
            consumed += chunk.length;
            writer.add(() => consumed);
            if (consumed == chunkBytes * chunkCount) {
              allChunksConsumed.complete();
            }
          },
          onError: (error, stackTrace) async => fail('$error'),
          onDone: () async {
            finalizationStarted.complete();
            await writer.finalize(() async => writes.add(consumed));
            streamDone.complete();
          },
        );
        addTearDown(subscription.cancel);

        final chunk = 'x' * chunkBytes;
        for (var index = 0; index < chunkCount; index++) {
          controller.add(chunk);
        }
        final closing = controller.close();

        await firstWriteStarted.future.timeout(const Duration(seconds: 1));
        await allChunksConsumed.future.timeout(const Duration(seconds: 1));
        expect(controller.isPaused, isFalse);
        expect(consumed, 1 << 20);
        expect(writes, hasLength(1));
        expect(streamDone.isCompleted, isFalse);

        // Stream delivery may yield before onDone. Wait until finalize has
        // dropped the pending checkpoint before releasing the in-flight write.
        await finalizationStarted.future.timeout(const Duration(seconds: 1));
        releaseFirstWrite.complete();
        await streamDone.future.timeout(const Duration(seconds: 1));
        await closing;
        expect(writes, hasLength(2));
        expect(writes.last, 1 << 20);
      },
    );

    test(
      '\u88AB\u8986\u76D6\u7684 pending builder \u4ECE\u672A\u6267\u884C',
      () async {
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final writes = <int>[];
        var first = 0;
        var second = 0;
        var third = 0;
        final writer = LatestWinsCheckpointWriter<int>(
          minimumInterval: Duration.zero,
          write: (value) async {
            writes.add(value);
            if (writes.length == 1) {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
        );

        writer.add(() {
          first++;
          return 1;
        });
        await firstStarted.future;
        writer
          ..add(() {
            second++;
            return 2;
          })
          ..add(() {
            third++;
            return 3;
          });
        releaseFirst.complete();
        await writer.barrier();

        expect(writes, const [1, 3]);
        expect(first, 1);
        expect(second, 0);
        expect(third, 1);
      },
    );
  });
}
