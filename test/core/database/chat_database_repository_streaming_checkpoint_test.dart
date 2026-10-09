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
      'Single transaction persists full message snapshot and tool events in order',
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
      'Checkpoint persists interleaved part order rather than flattening',
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
      'Italic paragraphs across adjacent data records reach checkpoint and API history exactly',
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
      'Late streaming checkpoint cannot revive finalized message',
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
      'Checkpoint does not insert a nonexistent message',
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
      'Cold start cleans unregistered flags and orphan tracking metadata atomically',
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
      'Tool part content and ordinals survive text-only checkpoint',
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
      'Changed tool events trigger full rebuild',
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
      'message_rows omit shadow content and reasoning_text columns',
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
      'No write path creates a tool_result part',
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
      'Parts remain readable and FTS-searchable after crash recovery',
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
      'Tool card survives checkpoint between ServerToolStart and ServerToolEnd in place',
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
      'Unmatched tool cards retain position when toolEvents are fewer than ToolCallPart',
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
      'Extra toolEvents insert after last tool card rather than at end of text',
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
      'Unmatched nonempty toolEvent ID does not overwrite another tool card',
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
      'ID-bearing event is not consumed by earlier ID-less tool card',
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
      'ID-bearing events merge by position if all tool cards lack IDs',
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
      'Checkpoint merges citation items with same ID instead of keeping only last',
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
      'Empty toolEvent arguments do not overwrite stored checkpoint code',
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
      'Ordinary tool items are not merged as search citations',
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
