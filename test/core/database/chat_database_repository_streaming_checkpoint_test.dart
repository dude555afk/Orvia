import 'dart:convert';
import 'dart:io';

import 'package:orvia/core/database/chat_database_repository.dart';
import 'package:orvia/core/database/generation_run.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/models/conversation.dart';
import 'package:orvia/core/models/message_part.dart';
import 'package:orvia/core/services/api/providers/openai/chat_completions_decoder.dart';
import 'package:orvia/core/services/api/stream/sse_decode_loop.dart';
import 'package:orvia/core/services/api/stream/sse_framing.dart';
import 'package:orvia/core/services/api/stream/stream_chunk.dart';
import 'package:orvia/core/services/api/stream/stream_chunk_handler.dart';
import 'package:orvia/core/services/chat/chat_service.dart';
import 'package:orvia/features/home/services/message_builder_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChatDatabaseRepository streaming checkpoint', () {
    late Directory directory;
    late ChatDatabaseRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'orvia_streaming_checkpoint_test_',
      );
      repository = ChatDatabaseRepository.open(
        file: File('${directory.path}/chat.sqlite'),
      );
      await repository.ensureReady();
      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: 'conversation',
            title: 'Conversation',
            messageIds: const ['first', 'streaming'],
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: 'first',
              role: 'user',
              content: 'question',
              conversationId: 'conversation',
            ),
            messageOrder: 0,
          ),
          (
            message: ChatMessage(
              id: 'streaming',
              role: 'assistant',
              content: '',
              conversationId: 'conversation',
              isStreaming: true,
            ),
            messageOrder: 1,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );
    });

    tearDown(() async {
      await repository.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'checkpoints preserve unchanged parts and remove only a truncated tail',
      () async {
        final snapshot = ChatMessage(
          id: 'streaming',
          role: 'assistant',
          conversationId: 'conversation',
          isStreaming: true,
          parts: const [
            ReasoningPart('plan'),
            TextPart('before'),
            TextPart('tail'),
          ],
        );
        await repository.updateStreamingCheckpoint(snapshot, const []);
        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          final before = raw.select(
            "SELECT part_id, updated_at FROM message_part_rows WHERE revision_id = 'streaming' ORDER BY ordinal",
          );
          await repository.updateStreamingCheckpoint(
            snapshot.copyWith(
              parts: const [
                ReasoningPart('plan'),
                TextPart('before'),
                TextPart('tail more'),
              ],
            ),
            const [],
          );
          final after = raw.select(
            "SELECT part_id, updated_at FROM message_part_rows WHERE revision_id = 'streaming' ORDER BY ordinal",
          );
          expect(
            after.map((r) => r['part_id']),
            before.map((r) => r['part_id']),
          );
          expect(
            after.take(2).map((r) => r['updated_at']),
            before.take(2).map((r) => r['updated_at']),
          );
          await repository.updateStreamingCheckpoint(
            snapshot.copyWith(
              parts: const [ReasoningPart('plan'), TextPart('before')],
              isStreaming: false,
            ),
            const [],
          );
          final finalRows = raw.select(
            "SELECT part_id, payload FROM message_part_rows WHERE revision_id = 'streaming' ORDER BY ordinal",
          );
          expect(
            finalRows.map((r) => r['part_id']),
            before.take(2).map((r) => r['part_id']),
          );
          expect(finalRows.map((r) => r['payload']), ['plan', 'before']);
        } finally {
          raw.close();
        }
      },
    );

    test(
      '\u4E00\u6B21\u4E8B\u52A1\u5199\u5165\u5B8C\u6574\u6D88\u606F\u5FEB\u7167\u548C tool events \u4E14\u4E0D\u6539\u53D8\u987A\u5E8F',
      () async {
        final snapshot = ChatMessage(
          id: 'streaming',
          role: 'assistant',
          content: 'partial answer',
          conversationId: 'conversation',
          isStreaming: true,
          totalTokens: 12,
          reasoningText: 'thinking',
        );

        await repository.updateStreamingCheckpoint(snapshot, const [
          {
            'id': 'tool-1',
            'name': 'search',
            'arguments': {'q': 'orvia'},
            'content': 'result',
          },
        ]);

        final messages = await repository.getMessagesByIds(const [
          'first',
          'streaming',
        ]);
        expect(messages.map((message) => message.id), const [
          'first',
          'streaming',
        ]);
        expect(messages.last.content, 'partial answer');
        expect(messages.last.totalTokens, 12);
        expect(messages.last.reasoningText, 'thinking');
        expect(await repository.getToolEvents('streaming'), const [
          {
            'id': 'tool-1',
            'name': 'search',
            'arguments': {'q': 'orvia'},
            'content': 'result',
          },
        ]);

        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          final parts = raw.select(
            "SELECT kind FROM message_part_rows WHERE revision_id = "
            "'streaming' ORDER BY ordinal;",
          );
          expect(parts.map((row) => row['kind']), const [
            'reasoning',
            'text',
            'tool_call',
          ]);
          expect(
            raw
                .select(
                  "SELECT COUNT(*) AS c FROM message_part_rows "
                  "WHERE kind = 'tool_result';",
                )
                .single['c'],
            0,
          );
        } finally {
          raw.close();
        }

        final authoritative = await repository.getMessage('streaming');
        expect(authoritative?.content, 'partial answer');
        expect(authoritative?.reasoningText, 'thinking');
      },
    );

    test(
      'checkpoint \u6309 parts \u4EA4\u9519\u987A\u5E8F\u843D\u5E93\u800C\u4E0D\u662F\u62CD\u5E73',
      () async {
        const toolEvents = [
          {'id': 'tool-1', 'name': 'search', 'content': 'result'},
        ];
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ReasoningPart('thinking'),
              TextPart('before '),
              ToolCallPart(
                '{"id":"tool-1","name":"search","content":"result"}',
              ),
              TextPart('after'),
            ],
          ),
          toolEvents,
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind).toList(), [
          'reasoning',
          'text',
          'tool_call',
          'text',
        ]);
        expect(persisted.content, 'before after');
        expect(await repository.getToolEvents('streaming'), toolEvents);
      },
    );

    test(
      '\u76F8\u90BB data \u8BB0\u5F55\u4E2D\u7684\u659C\u4F53\u6BB5\u843D\u9010\u5B57\u8FDB\u5165 checkpoint \u548C API \u5386\u53F2',
      () async {
        const fragments = <String>[
          '*\u88AB\u7A9D\u88F9\u4F4F，\u5979\u53CD\u800C\u7B11\u5F97\u66F4',
          '\u751C*\n\n*\u61D2\u61D2\u5730、',
          '\u9ECF\u7CCA\u7CCA\u5730*\n\n\u5BF9',
          '……\u540E\u9762\u7684\u5185\u5BB9\u4ECD\u7136\u4FDD\u7559。',
        ];
        String frame(String text) =>
            'data: ${jsonEncode(<String, dynamic>{
              'choices': <Map<String, dynamic>>[
                <String, dynamic>{
                  'delta': <String, dynamic>{'content': text},
                  'finish_reason': null,
                },
              ],
            })}';
        final wire =
            '${frame(fragments[0])}\n\n'
            '${frame(fragments[1])}\n'
            '${frame(fragments[2])}\n\n'
            '${frame(fragments[3])}\n\n'
            'data: [DONE]\n\n';
        final chunks = await decodeSseEvents(
          parseSseEventStrings(
            Stream<String>.value(wire),
            recoverAdjacentJsonDataRecords: true,
          ),
          ChatCompletionsStreamDecoder(),
        ).toList();
        final result = StreamChunkHandler.collect(chunks);

        final snapshot = ChatMessage(
          id: 'streaming',
          role: 'assistant',
          conversationId: 'conversation',
          isStreaming: true,
          parts: result.parts,
        );
        await repository.updateStreamingCheckpoint(snapshot, const []);
        await repository.updateStreamingCheckpoint(
          snapshot.copyWith(isStreaming: false),
          const [],
        );

        // Force a cold database read before rebuilding the next API request.
        await repository.close();
        repository = ChatDatabaseRepository.open(
          file: File('${directory.path}/chat.sqlite'),
        );
        await repository.ensureReady();

        final expected = fragments.join();
        final persisted = await repository.getMessage('streaming');
        expect(persisted!.content, expected);
        expect(
          persisted.parts.whereType<TextPart>().map((part) => part.text).join(),
          expected,
        );

        final history = await repository.getMessagesByIds(const [
          'first',
          'streaming',
        ]);
        final apiMessages =
            MessageBuilderService(
              chatService: ChatService(),
              contextProvider: _FakeBuildContext(),
            ).buildApiMessages(
              messages: history,
              versionSelections: const {},
              currentConversation: Conversation(title: 'Conversation'),
            );
        expect(apiMessages.last['role'], 'assistant');
        expect(apiMessages.last['content'], expected);
      },
    );

    test(
      '\u5DF2 finalize \u7684\u6D88\u606F\u4E0D\u4F1A\u88AB\u8FDF\u5230\u7684\u6D41\u5F0F checkpoint \u590D\u6D3B',
      () async {
        // Terminal write commits the finalized (non-streaming) content.
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'final answer',
            conversationId: 'conversation',
            isStreaming: false,
          ),
          const [],
        );

        // A late flush replays a stale streaming snapshot for the same revision.
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'stale partial',
            conversationId: 'conversation',
            isStreaming: true,
          ),
          const [],
        );

        final message = await repository.getMessage('streaming');
        expect(message?.content, 'final answer');
        expect(message?.isStreaming, isFalse);

        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          expect(
            raw
                .select(
                  "SELECT is_streaming FROM message_rows WHERE id = 'streaming';",
                )
                .single['is_streaming'],
            0,
          );
        } finally {
          raw.close();
        }
      },
    );

    test(
      '\u4E0D\u5B58\u5728\u7684\u6D88\u606F\u4E0D\u4F1A\u88AB checkpoint \u610F\u5916\u63D2\u5165',
      () async {
        await expectLater(
          repository.updateStreamingCheckpoint(
            ChatMessage(
              id: 'missing',
              role: 'assistant',
              content: 'orphan',
              conversationId: 'conversation',
              isStreaming: true,
            ),
            const [],
          ),
          throwsA(anything),
        );

        expect(await repository.getMessagesByIds(const ['missing']), isEmpty);
      },
    );

    test(
      'cold start \u4E00\u6B21\u4E8B\u52A1\u6E05\u7406\u672A\u767B\u8BB0 flag \u548C\u5B64\u513F tracking metadata',
      () async {
        final createdAt = DateTime.now().toUtc();
        await repository.createGenerationRun(
          id: 'abandoned-run',
          conversationId: 'conversation',
          targetRevisionId: 'streaming',
          createdAt: createdAt,
        );
        await repository.transitionGenerationRun(
          id: 'abandoned-run',
          expectedState: GenerationRunState.preparing,
          expectedStateRevision: 0,
          nextState: GenerationRunState.requesting,
          updatedAt: createdAt.add(const Duration(milliseconds: 1)),
        );
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'preserved partial',
            conversationId: 'conversation',
            isStreaming: true,
          ),
          const [],
          generationRunId: 'abandoned-run',
          checkpointSeq: 1,
        );

        expect(await repository.resetStaleStreamingState(), 1);

        final message = await repository.getMessage('streaming');
        expect(message?.isStreaming, isFalse);
        expect(message?.content, 'preserved partial');
        final run = await repository.getGenerationRun('abandoned-run');
        expect(run?.state, GenerationRunState.interrupted);
        expect(run?.stateRevision, 2);
        expect(run?.checkpointSeq, 1);
        expect(run?.errorCode, 'app_restart');
        expect(await repository.getActiveStreamingIds(), isEmpty);
      },
    );

    test('active generation projection comes only from run rows', () async {
      final createdAt = DateTime.now().toUtc();
      await repository.createGenerationRun(
        id: 'first-run',
        conversationId: 'conversation',
        targetRevisionId: 'first',
        createdAt: createdAt,
      );
      await repository.createGenerationRun(
        id: 'streaming-run',
        conversationId: 'conversation',
        targetRevisionId: 'streaming',
        createdAt: createdAt,
      );

      expect(
        await repository.getActiveStreamingIds(),
        containsAll(['first', 'streaming']),
      );
      final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
      try {
        expect(
          raw.select(
            "SELECT value FROM chat_storage_meta_rows "
            "WHERE key = 'active_streaming_ids';",
          ),
          isEmpty,
        );
      } finally {
        raw.close();
      }
    });

    test(
      'tool parts \u5185\u5BB9\u4E0E ordinal \u5728\u4EC5\u6B63\u6587\u53D8\u5316\u7684 checkpoint \u540E\u4FDD\u6301\u7B49\u4EF7',
      () async {
        const toolEvents = [
          {
            'id': 'tool-1',
            'name': 'search',
            'arguments': {'q': 'orvia'},
            'content': 'result',
          },
        ];
        ChatMessage snapshot(String content) => ChatMessage(
          id: 'streaming',
          role: 'assistant',
          content: content,
          conversationId: 'conversation',
          isStreaming: true,
          reasoningText: 'thinking',
        );

        await repository.updateStreamingCheckpoint(
          snapshot('draft one'),
          toolEvents,
        );
        List<Map<String, Object?>> toolPartRows() {
          final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
          try {
            return raw
                .select(
                  "SELECT kind, payload, ordinal, updated_at FROM "
                  "message_part_rows WHERE revision_id = 'streaming' AND "
                  "kind = 'tool_call' ORDER BY ordinal;",
                )
                .map(
                  (row) => <String, Object?>{
                    'kind': row['kind'],
                    'payload': row['payload'],
                    'ordinal': row['ordinal'],
                    'updated_at': row['updated_at'],
                  },
                )
                .toList();
          } finally {
            raw.close();
          }
        }

        final before = toolPartRows();
        expect(before.map((row) => row['kind']), const ['tool_call']);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await repository.updateStreamingCheckpoint(
          snapshot('draft two is longer'),
          toolEvents,
        );

        // Full rewrite is fine as long as tool payloads and ordinals stay
        // equivalent. The old contiguous-tool fast path is gone.
        expect(
          toolPartRows().map(
            (row) => (row['kind'], row['payload'], row['ordinal']),
          ),
          before.map((row) => (row['kind'], row['payload'], row['ordinal'])),
        );
        final persisted = await repository.getMessage('streaming');
        expect(persisted?.content, 'draft two is longer');
        expect(persisted?.reasoningText, 'thinking');
        expect(await repository.getToolEvents('streaming'), toolEvents);
      },
    );

    test(
      'tool events \u53D8\u5316\u65F6\u56DE\u9000\u5168\u91CF\u91CD\u5EFA',
      () async {
        ChatMessage snapshot(String content) => ChatMessage(
          id: 'streaming',
          role: 'assistant',
          content: content,
          conversationId: 'conversation',
          isStreaming: true,
        );

        await repository.updateStreamingCheckpoint(snapshot('draft'), const [
          {'id': 'tool-1', 'content': 'first'},
        ]);
        int firstToolUpdatedAt() {
          final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
          try {
            return raw
                    .select(
                      "SELECT updated_at FROM message_part_rows WHERE "
                      "revision_id = 'streaming' AND kind = 'tool_call' "
                      "ORDER BY ordinal LIMIT 1;",
                    )
                    .single['updated_at']
                as int;
          } finally {
            raw.close();
          }
        }

        final before = firstToolUpdatedAt();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await repository.updateStreamingCheckpoint(
          snapshot('draft two'),
          const [
            {'id': 'tool-1', 'content': 'first'},
            {'id': 'tool-2', 'content': 'second'},
          ],
        );

        expect(firstToolUpdatedAt(), isNot(before));
        expect(await repository.getToolEvents('streaming'), const [
          {'id': 'tool-1', 'content': 'first'},
          {'id': 'tool-2', 'content': 'second'},
        ]);
        expect(
          (await repository.getMessage('streaming'))?.content,
          'draft two',
        );
      },
    );

    test(
      'message_rows \u4E0D\u518D\u5305\u542B content / reasoning_text \u5F71\u5B50\u5217',
      () async {
        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          final columns = raw
              .select('PRAGMA table_info(message_rows);')
              .map((row) => row['name'] as String)
              .toSet();
          expect(columns.contains('content'), isFalse);
          expect(columns.contains('reasoning_text'), isFalse);
        } finally {
          raw.close();
        }
      },
    );

    test(
      '\u4EFB\u4F55\u5199\u5165\u8DEF\u5F84\u90FD\u4E0D\u4F1A\u4EA7\u751F tool_result part',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'with tools',
            conversationId: 'conversation',
            isStreaming: true,
            reasoningText: 'think',
          ),
          const [
            {
              'id': 'tool-1',
              'name': 'search',
              'arguments': {'q': 'x'},
              'content': 'result body',
            },
          ],
        );
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'final with tools',
            conversationId: 'conversation',
            isStreaming: false,
            reasoningText: 'think',
          ),
          const [
            {
              'id': 'tool-1',
              'name': 'search',
              'arguments': {'q': 'x'},
              'content': 'result body',
            },
          ],
        );
        await repository.updateMessageFields(
          'streaming',
          content: 'edited with tools',
        );

        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          expect(
            raw
                .select(
                  "SELECT COUNT(*) AS c FROM message_part_rows "
                  "WHERE kind = 'tool_result';",
                )
                .single['c'],
            0,
          );
          expect(
            raw
                .select(
                  "SELECT kind FROM message_part_rows "
                  "WHERE revision_id = 'streaming' ORDER BY ordinal;",
                )
                .map((row) => row['kind']),
            const ['reasoning', 'text', 'tool_call'],
          );
        } finally {
          raw.close();
        }
      },
    );

    test(
      '\u5D29\u6E83\u6062\u590D\u540E parts \u53EF\u8BFB\u4E14 FTS \u53EF\u641C\u7D22',
      () async {
        final createdAt = DateTime.now().toUtc();
        await repository.createGenerationRun(
          id: 'crashed-run',
          conversationId: 'conversation',
          targetRevisionId: 'streaming',
          createdAt: createdAt,
        );
        await repository.transitionGenerationRun(
          id: 'crashed-run',
          expectedState: GenerationRunState.preparing,
          expectedStateRevision: 0,
          nextState: GenerationRunState.requesting,
          updatedAt: createdAt.add(const Duration(milliseconds: 1)),
        );
        final requesting = await repository.getGenerationRun('crashed-run');
        await repository.transitionGenerationRun(
          id: 'crashed-run',
          expectedState: GenerationRunState.requesting,
          expectedStateRevision: requesting!.stateRevision,
          nextState: GenerationRunState.streaming,
          updatedAt: createdAt.add(const Duration(milliseconds: 2)),
        );
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            content: 'interrupted crash-recovery-token partial',
            conversationId: 'conversation',
            isStreaming: true,
            reasoningText: 'interrupted reasoning trail',
          ),
          const [],
          generationRunId: 'crashed-run',
          checkpointSeq: 1,
        );

        // Simulate process kill: message still streaming with checkpointed parts.
        final midCrash = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          expect(
            midCrash
                .select(
                  "SELECT is_streaming FROM message_rows WHERE id = 'streaming';",
                )
                .single['is_streaming'],
            1,
          );
          expect(
            midCrash
                .select(
                  "SELECT payload FROM message_part_rows "
                  "WHERE revision_id = 'streaming' AND kind = 'text';",
                )
                .single['payload'],
            'interrupted crash-recovery-token partial',
          );
        } finally {
          midCrash.close();
        }

        expect(await repository.resetStaleStreamingState(), 1);

        final message = await repository.getMessage('streaming');
        expect(message?.isStreaming, isFalse);
        expect(message?.content, 'interrupted crash-recovery-token partial');
        expect(message?.reasoningText, 'interrupted reasoning trail');
        final run = await repository.getGenerationRun('crashed-run');
        expect(run?.state, GenerationRunState.interrupted);

        expect(
          (await repository.searchConversationMatches(
            tokens: const ['crash-recovery-token'],
          )).single.messageId,
          'streaming',
        );

        await repository.close();
        final raw = sqlite.sqlite3.open('${directory.path}/chat.sqlite');
        try {
          raw.execute(
            "INSERT INTO message_search_fts(message_search_fts) "
            "VALUES('integrity-check');",
          );
        } finally {
          raw.close();
        }
        // Re-open so tearDown can close a live repository handle.
        repository = ChatDatabaseRepository.open(
          file: File('${directory.path}/chat.sqlite'),
        );
        await repository.ensureReady();
      },
    );

    test('reasoning finishing mid-stream keeps earlier tool parts', () async {
      // Gemini pattern: reasoning streams first and stops updating once tool
      // calls begin. The reasoning part must not be treated as "gone" just
      // because the checkpoint message still carries the pre-allocated
      // reasoningStartAt timestamp with null text.
      await repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: 'conv-gemini',
            title: 'Gemini',
            messageIds: const ['assistant-1'],
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: 'assistant-1',
              conversationId: 'conv-gemini',
              role: 'assistant',
              content: '',
              isStreaming: true,
            ),
            messageOrder: 0,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );

      // Checkpoint 1: reasoning actively streaming.
      await repository.updateStreamingCheckpoint(
        ChatMessage(
          id: 'assistant-1',
          conversationId: 'conv-gemini',
          role: 'assistant',
          content: '',
          isStreaming: true,
          reasoningText: 'let me think',
          reasoningStartAt: DateTime.utc(2026, 7, 28, 10),
        ),
        const [],
      );

      // Checkpoint 2: reasoning done, tool call arrives.
      await repository.updateStreamingCheckpoint(
        ChatMessage(
          id: 'assistant-1',
          conversationId: 'conv-gemini',
          role: 'assistant',
          content: '',
          isStreaming: true,
          reasoningText: 'let me think',
          reasoningStartAt: DateTime.utc(2026, 7, 28, 10),
          reasoningFinishedAt: DateTime.utc(2026, 7, 28, 10, 0, 3),
        ),
        const [
          {'id': 'call-1', 'name': 'search', 'arguments': '{"q":"x"}'},
        ],
      );

      // Checkpoint 3 (the Gemini regression): reasoning text null but the
      // pre-allocated reasoningStartAt timestamp still set; tool result in.
      await repository.updateStreamingCheckpoint(
        ChatMessage(
          id: 'assistant-1',
          conversationId: 'conv-gemini',
          role: 'assistant',
          content: '',
          isStreaming: true,
          reasoningText: null,
          reasoningStartAt: DateTime.utc(2026, 7, 28, 10),
          reasoningFinishedAt: DateTime.utc(2026, 7, 28, 10, 0, 3),
        ),
        const [
          {'id': 'call-1', 'name': 'search', 'arguments': '{"q":"x"}'},
          {'id': 'call-1', 'name': 'search', 'content': 'result payload'},
        ],
      );

      expect(await repository.getToolEvents('assistant-1'), hasLength(2));
      final message = await repository.getMessage('assistant-1');
      expect(message?.reasoningText, 'let me think');
    });

    test(
      'ServerToolStart \u5230 checkpoint \u518D\u5230 ServerToolEnd \u5DE5\u5177\u5361\u4E0D\u4E22\u4E14\u4F4D\u7F6E\u4E0D\u53D8',
      () async {
        final handler = StreamChunkHandler();
        handler.handle(
          const ServerToolStart(id: 'srv_1', toolName: 'search_web'),
        );
        handler.handle(
          const TextDelta(id: 't', text: '\u6211\u67E5\u4E00\u4E0B'),
        );

        ChatMessage snapshot() => ChatMessage(
          id: 'streaming',
          role: 'assistant',
          conversationId: 'conversation',
          isStreaming: true,
          parts: handler.parts,
        );

        await repository.updateStreamingCheckpoint(snapshot(), const []);
        var persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind), [
          'tool_call',
          'text',
        ]);
        expect(
          jsonDecode((persisted.parts[0] as ToolCallPart).payloadJson)['id'],
          'srv_1',
        );
        expect(
          jsonDecode(
            (persisted.parts[0] as ToolCallPart).payloadJson,
          )['server'],
          isTrue,
        );
        expect(
          (persisted.parts[1] as TextPart).text,
          '\u6211\u67E5\u4E00\u4E0B',
        );

        handler.handle(
          const ServerToolEnd(id: 'srv_1', output: {'items': <Object>[]}),
        );
        handler.handle(const TextDelta(id: 't', text: '\u7ED3\u679C\u662F X'));
        await repository.updateStreamingCheckpoint(snapshot(), const [
          {
            'id': 'srv_1',
            'name': 'search_web',
            'content': {'items': <Object>[]},
            'server': true,
          },
        ]);

        persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind), [
          'tool_call',
          'text',
        ]);
        final payload = jsonDecode(
          (persisted.parts[0] as ToolCallPart).payloadJson,
        );
        expect(payload['id'], 'srv_1');
        expect(payload['server'], isTrue);
        expect(
          (persisted.parts[1] as TextPart).text,
          '\u6211\u67E5\u4E00\u4E0B\u7ED3\u679C\u662F X',
        );
      },
    );

    test(
      'toolEvents \u5C11\u4E8E ToolCallPart \u65F6\u672A\u5339\u914D\u7684\u5DE5\u5177\u5361\u4FDD\u7559\u539F\u4F4D',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              TextPart('\u6211\u67E5\u4E00\u4E0B'),
              ToolCallPart('{"id":"local_1","name":"lookup","arguments":{}}'),
              ToolCallPart('{"id":"srv_1","name":"search_web","server":true}'),
              TextPart('\u7ED3\u679C\u662F X'),
            ],
          ),
          const [
            {'id': 'local_1', 'name': 'lookup', 'content': 'local result'},
          ],
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind), [
          'text',
          'tool_call',
          'tool_call',
          'text',
        ]);
        expect(
          jsonDecode((persisted.parts[1] as ToolCallPart).payloadJson)['id'],
          'local_1',
        );
        expect(
          jsonDecode((persisted.parts[2] as ToolCallPart).payloadJson)['id'],
          'srv_1',
        );
        expect(
          jsonDecode(
            (persisted.parts[2] as ToolCallPart).payloadJson,
          )['server'],
          isTrue,
        );
        expect(
          (persisted.parts[0] as TextPart).text,
          '\u6211\u67E5\u4E00\u4E0B',
        );
        expect((persisted.parts[3] as TextPart).text, '\u7ED3\u679C\u662F X');
      },
    );

    test(
      '\u591A\u4F59 toolEvents \u63D2\u5728\u6700\u540E\u4E00\u4E2A\u5DE5\u5177\u5361\u4E4B\u540E\u800C\u4E0D\u662F\u5168\u6587\u672B\u5C3E',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              TextPart('\u6211\u67E5\u4E00\u4E0B'),
              ToolCallPart('{"id":"local_1","name":"lookup"}'),
              TextPart('\u7ED3\u679C\u662F X'),
            ],
          ),
          const [
            {'id': 'local_1', 'name': 'lookup', 'content': 'local result'},
            {'id': 'extra_1', 'name': 'search_web', 'content': 'extra'},
          ],
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind), [
          'text',
          'tool_call',
          'tool_call',
          'text',
        ]);
        expect(
          jsonDecode((persisted.parts[1] as ToolCallPart).payloadJson)['id'],
          'local_1',
        );
        expect(
          jsonDecode((persisted.parts[2] as ToolCallPart).payloadJson)['id'],
          'extra_1',
        );
        expect((persisted.parts[3] as TextPart).text, '\u7ED3\u679C\u662F X');
      },
    );

    test(
      '\u672A\u5339\u914D\u7684\u975E\u7A7A toolEvent ID \u4E0D\u4F1A\u6539\u5199\u53E6\u4E00\u5F20\u5DE5\u5177\u5361',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart(
                '{"id":"A","name":"lookup","arguments":{"q":"one"}}',
              ),
            ],
          ),
          const [
            {
              'id': 'C',
              'name': 'search_web',
              'arguments': {'q': 'two'},
              'content': 'hits',
            },
          ],
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts.map((part) => part.kind), [
          'tool_call',
          'tool_call',
        ]);
        expect(
          jsonDecode((persisted.parts[0] as ToolCallPart).payloadJson)['id'],
          'A',
        );
        expect(
          jsonDecode((persisted.parts[0] as ToolCallPart).payloadJson)['name'],
          'lookup',
        );
        expect(
          jsonDecode((persisted.parts[1] as ToolCallPart).payloadJson)['id'],
          'C',
        );
      },
    );

    test(
      '\u6709 ID \u7684\u4E8B\u4EF6\u4E0D\u4F1A\u88AB\u524D\u9762\u7684\u65E0 ID \u5DE5\u5177\u5361\u62A2\u8D70',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart('{"name":"lookup","arguments":{"q":"legacy"}}'),
              ToolCallPart(
                '{"id":"C","name":"lookup_web","arguments":{"q":"keep"}}',
              ),
            ],
          ),
          const [
            {
              'id': 'C',
              'name': 'lookup_web',
              'arguments': {'q': 'keep'},
              'content': 'hits',
            },
          ],
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts, hasLength(2));
        expect(
          jsonDecode((persisted.parts[0] as ToolCallPart).payloadJson)['id'],
          isNot(equals('C')),
        );
        expect(
          jsonDecode((persisted.parts[0] as ToolCallPart).payloadJson)['name'],
          'lookup',
        );
        expect(
          jsonDecode((persisted.parts[1] as ToolCallPart).payloadJson)['id'],
          'C',
        );
        expect(
          jsonDecode(
            (persisted.parts[1] as ToolCallPart).payloadJson,
          )['content'],
          'hits',
        );
      },
    );

    test(
      '\u53EA\u6709\u65E0 ID \u5DE5\u5177\u5361\u65F6\u4ECD\u5141\u8BB8\u6309\u4F4D\u7F6E\u5408\u5E76\u6709 ID \u7684\u4E8B\u4EF6',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart('{"name":"lookup","arguments":{"q":"legacy"}}'),
            ],
          ),
          const [
            {
              'id': 'C',
              'name': 'lookup_web',
              'arguments': {'q': 'two'},
              'content': 'hits',
            },
          ],
        );

        final persisted = await repository.getMessage('streaming');
        expect(persisted!.parts, hasLength(1));
        final payload = jsonDecode(
          (persisted.parts.single as ToolCallPart).payloadJson,
        );
        expect(payload['id'], 'C');
        expect(payload['content'], 'hits');
        expect(payload['arguments'], {'q': 'two'});
      },
    );

    test(
      'checkpoint \u5408\u5E76\u540C id \u5F15\u7528 items \u800C\u4E0D\u662F\u53EA\u7559\u6700\u540E\u4E00\u6761',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart(
                '{"id":"round-0:search-1","name":"builtin_search","server":true,"content":{"items":[{"url":"https://a.example","title":"A"},{"url":"https://b.example","title":"B"}]}}',
              ),
            ],
          ),
          const [
            {
              'id': 'round-0:search-1',
              'name': 'builtin_search',
              'content': {
                'items': [
                  {'url': 'https://b.example', 'title': 'B'},
                ],
              },
            },
          ],
        );

        final events = await repository.getToolEvents('streaming');
        expect(events, hasLength(1));
        expect(events.single['content'], isA<String>());
        expect(jsonDecode(events.single['content'] as String)['items'], [
          {'url': 'https://a.example', 'title': 'A'},
          {'url': 'https://b.example', 'title': 'B'},
        ]);
      },
    );

    test(
      '\u7A7A toolEvent arguments \u4E0D\u4F1A\u8986\u76D6 checkpoint \u91CC\u5DF2\u6709\u7684\u4EE3\u7801',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart(
                '{"id":"code_1","name":"code_execution","arguments":{"language":"python","code":"print(1)"},"server":true}',
              ),
            ],
          ),
          const [
            {
              'id': 'code_1',
              'name': 'code_execution',
              'arguments': <String, dynamic>{},
              'content': null,
              'server': true,
            },
          ],
        );

        final persisted = await repository.getMessage('streaming');
        final payload = jsonDecode(
          (persisted!.parts.single as ToolCallPart).payloadJson,
        );
        expect(payload['id'], 'code_1');
        expect(payload['arguments'], {
          'language': 'python',
          'code': 'print(1)',
        });
        expect(payload['server'], isTrue);
      },
    );

    test(
      '\u666E\u901A\u5DE5\u5177\u7684 items \u4E0D\u88AB\u5F53\u6210\u641C\u7D22\u5F15\u7528\u5408\u5E76',
      () async {
        await repository.updateStreamingCheckpoint(
          ChatMessage(
            id: 'streaming',
            role: 'assistant',
            conversationId: 'conversation',
            isStreaming: true,
            parts: const [
              ToolCallPart(
                '{"id":"lookup_1","name":"lookup","content":{"items":[{"id":1}]}}',
              ),
            ],
          ),
          const [
            {
              'id': 'lookup_1',
              'name': 'lookup',
              'content': {
                'items': [
                  {'id': 2},
                ],
              },
            },
          ],
        );

        final events = await repository.getToolEvents('streaming');
        expect(events, hasLength(1));
        expect(events.single['content'], {
          'items': [
            {'id': 2},
          ],
        });
      },
    );
  });
}
