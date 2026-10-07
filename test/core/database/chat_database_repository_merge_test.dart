import 'dart:io';

import 'package:orvia/core/database/chat_database_repository.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/models/conversation.dart';
import 'package:orvia/core/models/message_part.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('ChatDatabaseRepository merge snapshot', () {
    late Directory directory;
    late ChatDatabaseRepository live;
    late ChatDatabaseRepository source;
    late File sourceFile;
    var sourceClosed = false;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('orvia_merge_test_');
      live = ChatDatabaseRepository.open(
        file: File('${directory.path}/live.sqlite'),
      );
      sourceFile = File('${directory.path}/source.sqlite');
      source = ChatDatabaseRepository.open(file: sourceFile);
      sourceClosed = false;
      await live.ensureReady();
      await source.ensureReady();
    });

    tearDown(() async {
      await live.close();
      if (!sourceClosed) await source.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    Future<void> putConversation(
      ChatDatabaseRepository repository, {
      required String conversationId,
      required String title,
      required String messageId,
      required String content,
      String? chatModelProvider,
      String? chatModelId,
    }) {
      // Fixed instants: the fingerprint truncates timestamps to whole seconds,
      // so two DateTime.now() writes straddling a second boundary would stop
      // identical conversations from deduplicating.
      final anchor = DateTime.utc(2026, 8, 7, 12);
      return repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: conversationId,
            title: title,
            createdAt: anchor,
            updatedAt: anchor,
            messageIds: [messageId],
            mcpServerIds: const ['server'],
            versionSelections: {messageId: 0},
            chatModelProvider: chatModelProvider,
            chatModelId: chatModelId,
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: messageId,
              role: 'assistant',
              content: content,
              conversationId: conversationId,
              timestamp: anchor,
            ),
            messageOrder: 0,
          ),
        ],
        toolEventsByMessageId: {
          messageId: [
            {'id': 'tool', 'content': content},
          ],
        },
        geminiSignaturesByMessageId: {messageId: 'sig-$content'},
      );
    }

    /// Two messages whose text, reasoning and tool payloads differ. Both carry
    /// the same thought signature on purpose: a swapped-body variant must then
    /// differ only in which revision owns which part, leaving part grouping as
    /// the sole thing the fingerprint can tell them apart by.
    Future<void> putTwoMessageConversation(
      ChatDatabaseRepository repository, {
      required String conversationId,
      required String firstMessageId,
      required String secondMessageId,
      required String firstBody,
      required String secondBody,
    }) {
      final anchor = DateTime.utc(2026, 8, 7, 12);
      ChatMessage message(String id, String body, int index) => ChatMessage(
        id: id,
        role: 'assistant',
        content: '$body content',
        reasoningText: '$body reasoning',
        conversationId: conversationId,
        timestamp: anchor.add(Duration(minutes: index)),
      );
      return repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: conversationId,
            title: 'Two messages',
            createdAt: anchor,
            updatedAt: anchor,
            messageIds: [firstMessageId, secondMessageId],
            mcpServerIds: const ['server'],
            versionSelections: {firstMessageId: 0, secondMessageId: 0},
          ),
        ],
        messages: [
          (message: message(firstMessageId, firstBody, 0), messageOrder: 0),
          (message: message(secondMessageId, secondBody, 1), messageOrder: 1),
        ],
        toolEventsByMessageId: {
          firstMessageId: [
            {'id': 'tool', 'content': '$firstBody tool'},
          ],
          secondMessageId: [
            {'id': 'tool', 'content': '$secondBody tool'},
          ],
        },
        geminiSignaturesByMessageId: {
          firstMessageId: 'sig-shared',
          secondMessageId: 'sig-shared',
        },
      );
    }

    Future<void> putConversationWithAttachments(
      ChatDatabaseRepository repository, {
      required String conversationId,
      required String messageId,
      required String content,
      required List<MessagePart> parts,
    }) {
      final anchor = DateTime.utc(2026, 8, 7, 12);
      return repository.putMigrationBatch(
        conversations: [
          Conversation(
            id: conversationId,
            title: 'Attachments',
            createdAt: anchor,
            updatedAt: anchor,
            messageIds: [messageId],
            mcpServerIds: const ['server'],
            versionSelections: {messageId: 0},
          ),
        ],
        messages: [
          (
            message: ChatMessage(
              id: messageId,
              role: 'user',
              content: content,
              conversationId: conversationId,
              timestamp: anchor,
              parts: parts,
            ),
            messageOrder: 0,
          ),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );
    }

    Future<void> putSparseConversation({
      required String conversationId,
      required String messagePrefix,
    }) async {
      final anchor = DateTime.utc(2026, 8, 7, 12);
      final messages = [
        for (var index = 0; index < 3; index++)
          ChatMessage(
            id: '$messagePrefix-${String.fromCharCode(97 + index)}',
            role: index.isEven ? 'user' : 'assistant',
            content: String.fromCharCode(97 + index),
            conversationId: conversationId,
            timestamp: anchor.add(Duration(minutes: index)),
          ),
      ];
      await source.putMigrationBatch(
        conversations: [
          Conversation(
            id: conversationId,
            title: 'Sparse',
            createdAt: anchor,
            updatedAt: anchor,
            messageIds: messages.map((message) => message.id).toList(),
            versionSelections: {for (final message in messages) message.id: 0},
          ),
        ],
        messages: [
          for (var index = 0; index < messages.length; index++)
            (message: messages[index], messageOrder: index),
        ],
        toolEventsByMessageId: const {},
        geminiSignaturesByMessageId: const {},
      );
      await source.deleteMessage(messages[1].id);
    }

    Future<void> reopenLive() async {
      await live.close();
      live = ChatDatabaseRepository.open(
        file: File('${directory.path}/live.sqlite'),
      );
      await live.ensureReady();
    }

    test(
      '\u65E0\u51B2\u7A81 conversation \u539F ID \u5BFC\u5165\u4E14 order/\u5173\u8054\u6570\u636E\u5B8C\u6574',
      () async {
        await putConversation(
          source,
          conversationId: 'source-conversation',
          title: 'Source',
          messageId: 'source-message',
          content: 'answer',
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.importedConversations, 1);
        expect(report.remappedConversations, 0);
        final conversation = await live.getConversation('source-conversation');
        expect(conversation?.messageIds, const ['source-message']);
        expect(
          (await live.getMessagesRange(
            'source-conversation',
            start: 0,
            limit: 10,
          )).single.content,
          'answer',
        );
        expect(await live.getToolEvents('source-message'), const [
          {'id': 'tool', 'content': 'answer'},
        ]);
        expect(
          await live.getGeminiThoughtSignature('source-message'),
          'sig-answer',
        );
      },
    );

    test(
      '\u4F1A\u8BDD\u7EA7\u6A21\u578B\u9501\u5B9A\u968F\u5408\u5E76\u5BFC\u5165\u4E00\u5E76\u643A\u5E26',
      () async {
        await putConversation(
          source,
          conversationId: 'pinned-conversation',
          title: 'Pinned',
          messageId: 'pinned-message',
          content: 'answer',
          chatModelProvider: 'OpenAI',
          chatModelId: 'gpt-5',
        );
        await source.close();
        sourceClosed = true;

        await live.mergeBackupSnapshot(sourceFile);

        final conversation = await live.getConversation('pinned-conversation');
        expect(conversation?.chatModelProvider, 'OpenAI');
        expect(conversation?.chatModelId, 'gpt-5');
      },
    );

    test(
      '\u76F8\u540C ID \u4E0E\u5185\u5BB9\u6309 hash \u53BB\u91CD，\u91CD\u590D\u5BFC\u5165\u4FDD\u6301\u5E42\u7B49',
      () async {
        for (final repository in [live, source]) {
          await putConversation(
            repository,
            conversationId: 'same-conversation',
            title: 'Same',
            messageId: 'same-message',
            content: 'same',
          );
        }
        await source.close();
        sourceClosed = true;

        final first = await live.mergeBackupSnapshot(sourceFile);
        final second = await live.mergeBackupSnapshot(sourceFile);

        expect(first.deduplicatedConversations, 1);
        expect(second.deduplicatedConversations, 1);
        expect(await live.getAllConversations(), hasLength(1));
      },
    );

    test(
      '\u4EC5 sender_id \u4E0D\u540C\u4E0D\u4F1A\u88AB\u8BEF\u5224\u4E3A\u91CD\u590D',
      () async {
        for (final repository in [live, source]) {
          await putConversation(
            repository,
            conversationId: 'sender-conv',
            title: 'Same body',
            messageId: 'sender-msg',
            content: 'same body',
          );
        }
        await source.close();
        sourceClosed = true;
        final raw = sqlite.sqlite3.open(sourceFile.path);
        try {
          raw.execute(
            "UPDATE message_rows SET sender_id = 'assistant-b' "
            "WHERE id = 'sender-msg';",
          );
        } finally {
          raw.close();
        }

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.deduplicatedConversations, 0);
        expect(report.importedConversations, 1);
        final remappedId = report.remappedConversationIds['sender-conv'];
        expect(remappedId, isNotNull);
        // The imported copy keeps the snapshot's authoring identity.
        final liveRaw = sqlite.sqlite3.open('${directory.path}/live.sqlite');
        try {
          final row = liveRaw.select(
            'SELECT sender_id FROM message_rows WHERE conversation_id = ?;',
            [remappedId],
          ).single;
          expect(row['sender_id'], 'assistant-b');
        } finally {
          liveRaw.close();
        }
      },
    );

    test(
      '\u4EC5\u6D88\u606F extras_json \u4E0D\u540C\u4E0D\u4F1A\u88AB\u8BEF\u5224\u4E3A\u91CD\u590D',
      () async {
        for (final repository in [live, source]) {
          await putConversation(
            repository,
            conversationId: 'extras-conv',
            title: 'Same body',
            messageId: 'extras-msg',
            content: 'same body',
          );
        }
        await source.close();
        sourceClosed = true;
        final raw = sqlite.sqlite3.open(sourceFile.path);
        try {
          raw.execute('UPDATE message_rows SET extras_json = ? WHERE id = ?;', [
            '{"game":"card-1"}',
            'extras-msg',
          ]);
        } finally {
          raw.close();
        }

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.deduplicatedConversations, 0);
        expect(report.importedConversations, 1);
        expect(report.remappedConversationIds['extras-conv'], isNotNull);
      },
    );

    test(
      '\u591A\u6D88\u606F\u4F1A\u8BDD parts \u6309 revision \u5206\u7EC4\u540E\u6307\u7EB9\u4E00\u81F4，\u91CD\u590D\u5BFC\u5165\u53BB\u91CD',
      () async {
        for (final repository in [live, source]) {
          await putTwoMessageConversation(
            repository,
            conversationId: 'multi',
            firstMessageId: 'multi-a',
            secondMessageId: 'multi-b',
            firstBody: 'alpha',
            secondBody: 'beta',
          );
        }
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.deduplicatedConversations, 1);
        expect(await live.getAllConversations(), hasLength(1));
      },
    );

    test(
      '\u591A\u6D88\u606F\u4F1A\u8BDD\u6B63\u6587\u4E92\u6362\u540E\u6307\u7EB9\u4E0D\u540C，\u4E0D\u4F1A\u88AB\u8BEF\u5224\u4E3A\u91CD\u590D',
      () async {
        // Both sides hold the same multiset of text/reasoning/tool payloads, the
        // same signature and the same per-position timestamps, and differ only in
        // which message owns which payload. A fingerprint that pooled parts per
        // conversation instead of per revision would hash these equal and
        // silently drop the imported conversation as a duplicate.
        await putTwoMessageConversation(
          live,
          conversationId: 'swap',
          firstMessageId: 'swap-a',
          secondMessageId: 'swap-b',
          firstBody: 'alpha',
          secondBody: 'beta',
        );
        await putTwoMessageConversation(
          source,
          conversationId: 'swap',
          firstMessageId: 'swap-a',
          secondMessageId: 'swap-b',
          firstBody: 'beta',
          secondBody: 'alpha',
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.deduplicatedConversations, 0);
        expect(report.importedConversations, 1);
        final remappedId = report.remappedConversationIds['swap'];
        expect(remappedId, isNotNull);
        expect(await live.getAllConversations(), hasLength(2));

        expect(
          (await live.getMessagesRange(
            'swap',
            start: 0,
            limit: 10,
          )).map((message) => message.content).toList(),
          const ['alpha content', 'beta content'],
        );
        final imported = await live.getMessagesRange(
          remappedId!,
          start: 0,
          limit: 10,
        );
        expect(imported.map((message) => message.content).toList(), const [
          'beta content',
          'alpha content',
        ]);
        expect(
          imported.map((message) => message.reasoningText).toList(),
          const ['beta reasoning', 'alpha reasoning'],
        );
        expect(await live.getToolEvents(imported.first.id), const [
          {'id': 'tool', 'content': 'beta tool'},
        ]);
      },
    );

    test(
      '\u6B63\u6587\u76F8\u540C\u4F46\u9644\u4EF6\u4E0D\u540C\u4E0D\u4F1A\u88AB\u8BEF\u5224\u4E3A\u91CD\u590D',
      () async {
        await putConversationWithAttachments(
          live,
          conversationId: 'attach',
          messageId: 'attach-msg',
          content: 'same body',
          parts: const [
            ImagePart(
              uri: 'orvia-file:///upload/a.png',
              mime: 'image/png',
              assetId: 'asset-a',
            ),
          ],
        );
        await putConversationWithAttachments(
          source,
          conversationId: 'attach',
          messageId: 'attach-msg',
          content: 'same body',
          parts: const [
            ImagePart(
              uri: 'orvia-file:///upload/b.png',
              mime: 'image/png',
              assetId: 'asset-b',
            ),
          ],
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        expect(report.deduplicatedConversations, 0);
        expect(report.importedConversations, 1);
        expect(await live.getAllConversations(), hasLength(2));
      },
    );

    test(
      '\u4EC5 unavailable \u4E0D\u540C\u4ECD\u6309\u9644\u4EF6\u8EAB\u4EFD\u53BB\u91CD',
      () async {
        await putConversationWithAttachments(
          live,
          conversationId: 'avail',
          messageId: 'avail-msg',
          content: 'same body',
          parts: const [
            ImagePart(
              uri: 'orvia-file:///upload/a.png',
              mime: 'image/png',
              assetId: 'asset-a',
              unavailable: false,
            ),
          ],
        );
        await putConversationWithAttachments(
          source,
          conversationId: 'avail',
          messageId: 'avail-msg',
          content: 'same body',
          parts: const [
            ImagePart(
              uri: 'orvia-file:///upload/a.png',
              mime: 'image/png',
              assetId: 'asset-a',
              unavailable: true,
            ),
          ],
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        expect(report.deduplicatedConversations, 1);
        expect(report.importedConversations, 0);
        expect(await live.getAllConversations(), hasLength(1));
      },
    );

    test(
      '\u9644\u4EF6 ordinal \u987A\u5E8F\u4E0D\u540C\u4EA7\u751F\u4E0D\u540C\u6307\u7EB9',
      () async {
        await putConversationWithAttachments(
          live,
          conversationId: 'order',
          messageId: 'order-msg',
          content: 'same body',
          parts: const [
            ImagePart(uri: 'orvia-file:///upload/a.png', mime: 'image/png'),
            ImagePart(uri: 'orvia-file:///upload/b.png', mime: 'image/png'),
          ],
        );
        await putConversationWithAttachments(
          source,
          conversationId: 'order',
          messageId: 'order-msg',
          content: 'same body',
          parts: const [
            ImagePart(uri: 'orvia-file:///upload/b.png', mime: 'image/png'),
            ImagePart(uri: 'orvia-file:///upload/a.png', mime: 'image/png'),
          ],
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        expect(report.deduplicatedConversations, 0);
        expect(report.importedConversations, 1);
        expect(await live.getAllConversations(), hasLength(2));
      },
    );

    test(
      '\u540C conversation ID \u5F02\u5185\u5BB9\u65F6\u6574\u4F1A\u8BDD remap \u5E76\u53EF\u91CD\u590D\u53BB\u91CD',
      () async {
        await putConversation(
          live,
          conversationId: 'collision',
          title: 'Local',
          messageId: 'local-message',
          content: 'local',
        );
        await putConversation(
          source,
          conversationId: 'collision',
          title: 'Imported',
          messageId: 'imported-message',
          content: 'imported',
        );
        await source.close();
        sourceClosed = true;

        final first = await live.mergeBackupSnapshot(sourceFile);
        final remappedId = first.remappedConversationIds['collision'];
        expect(remappedId, isNotNull);
        final remapped = await live.getConversation(remappedId!);
        expect(remapped?.title, 'Imported');
        expect(remapped?.messageIds.single, startsWith('merge-'));
        expect(remapped?.versionSelections.keys.single, startsWith('merge-'));
        expect(await live.getToolEvents(remapped!.messageIds.single), const [
          {'id': 'tool', 'content': 'imported'},
        ]);

        final second = await live.mergeBackupSnapshot(sourceFile);
        expect(second.importedConversations, 0);
        expect(second.deduplicatedConversations, 1);
        expect(await live.getAllConversations(), hasLength(2));
      },
    );

    test(
      'conversation ID \u53EF\u7528\u4F46 message ID \u51B2\u7A81\u65F6\u6574\u4F1A\u8BDD remap',
      () async {
        await putConversation(
          live,
          conversationId: 'local-conversation',
          title: 'Local',
          messageId: 'shared-message',
          content: 'local',
        );
        await putConversation(
          source,
          conversationId: 'source-conversation',
          title: 'Imported',
          messageId: 'shared-message',
          content: 'imported',
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        final remappedId =
            report.remappedConversationIds['source-conversation'];

        expect(remappedId, isNotNull);
        expect(await live.getConversation('source-conversation'), isNull);
        final remapped = await live.getConversation(remappedId!);
        expect(remapped?.messageIds.single, startsWith('merge-'));
        expect(
          (await live.getMessagesRange(
            remappedId,
            start: 0,
            limit: 1,
          )).single.content,
          'imported',
        );
      },
    );

    test(
      '\u8FC1\u79FB\u6279\u5199\u5165\u540E\u5DE5\u5177\u4E8B\u4EF6\u4E0E\u7B7E\u540D\u7269\u5316\u8FDB parts/artifacts \u53EF\u8BFB',
      () async {
        await putConversation(
          live,
          conversationId: 'materialized',
          title: 'Materialized',
          messageId: 'materialized-message',
          content: 'answer',
        );

        await reopenLive();

        expect(await live.getToolEvents('materialized-message'), const [
          {'id': 'tool', 'content': 'answer'},
        ]);
        expect(
          await live.getGeminiThoughtSignature('materialized-message'),
          'sig-answer',
        );
      },
    );

    test(
      'merge \u62F7\u8D1D parts/artifacts，\u65E0 legacy \u8868\u65F6\u4ECD\u53EF\u8BFB',
      () async {
        await putConversation(
          source,
          conversationId: 'artifact-conversation',
          title: 'Artifacts',
          messageId: 'artifact-message',
          content: 'answer',
        );
        await source.upsertImageOcrArtifactItems(
          revisionId: 'artifact-message',
          items: const {'hash-1': 'ocr text'},
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        expect(report.importedConversations, 1);

        await reopenLive();

        expect(await live.getToolEvents('artifact-message'), const [
          {'id': 'tool', 'content': 'answer'},
        ]);
        expect(
          await live.getGeminiThoughtSignature('artifact-message'),
          'sig-answer',
        );
        expect(await live.getImageOcrArtifacts(const ['artifact-message']), {
          'artifact-message': {'hash-1': 'ocr text'},
        });
      },
    );

    test(
      'remap \u65F6 group_id \u4E3A null \u7684 v0 \u4E0E\u540E\u7EED\u7248\u672C\u4ECD\u5C5E\u540C\u4E00\u7248\u672C\u7EC4',
      () async {
        await putConversation(
          live,
          conversationId: 'versioned',
          title: 'Local',
          messageId: 'local-message',
          content: 'local',
        );

        // \u751F\u4EA7\u5F62\u6001：v0 \u4E0D\u663E\u5F0F\u4F20 id，\u56E0\u6B64 group_id \u843D\u5E93\u4E3A NULL。
        final v0 = ChatMessage(
          role: 'assistant',
          content: 'v0',
          conversationId: 'versioned',
        );
        await source.putMigrationBatch(
          conversations: [
            Conversation(
              id: 'versioned',
              title: 'Imported',
              messageIds: [v0.id],
            ),
          ],
          messages: [(message: v0, messageOrder: 0)],
          toolEventsByMessageId: const {},
          geminiSignaturesByMessageId: const {},
        );
        final appended = await source.appendMessageVersion(
          messageId: v0.id,
          content: 'v1',
        );
        expect(appended, isNotNull);
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        final remappedId = report.remappedConversationIds['versioned'];
        expect(remappedId, isNotNull);

        final projections = await live.getSelectedMessageProjections(
          remappedId!,
        );
        expect(projections, hasLength(1));
        expect(projections.single.content, 'v1');
        expect(
          await live.getMaxMessageVersionForGroup(
            remappedId,
            projections.single.groupId!,
          ),
          1,
        );

        final second = await live.mergeBackupSnapshot(sourceFile);
        expect(second.importedConversations, 0);
        expect(second.deduplicatedConversations, 1);
        expect(await live.getAllConversations(), hasLength(2));
      },
    );

    test(
      '\u5220\u9664\u4E2D\u95F4\u6D88\u606F\u540E\u7684\u7A00\u758F order \u53EF\u5BFC\u5165、\u7A33\u5B9A\u53BB\u91CD\u5E76\u4FDD\u7559\u6C34\u4F4D',
      () async {
        await putSparseConversation(
          conversationId: 'sparse',
          messagePrefix: 'sparse',
        );
        await source.close();
        sourceClosed = true;

        final first = await live.mergeBackupSnapshot(sourceFile);

        expect(first.importedConversations, 1);
        expect(first.skippedConversations, 0);
        expect((await live.getConversation('sparse'))?.messageIds, const [
          'sparse-a',
          'sparse-c',
        ]);
        expect(await live.getMessageIndex('sparse', 'sparse-a'), 0);
        expect(await live.getMessageIndex('sparse', 'sparse-c'), 2);
        expect(
          (await live.getConversation('sparse'))?.lastMemoryExtractedOrder,
          2,
        );

        final second = await live.mergeBackupSnapshot(sourceFile);
        expect(second.importedConversations, 0);
        expect(second.deduplicatedConversations, 1);
        expect(second.skippedConversations, 0);
      },
    );

    test(
      '\u7A00\u758F order \u5728 conversation ID \u51B2\u7A81\u65F6\u53EF\u6574\u4F1A\u8BDD remap',
      () async {
        await putConversation(
          live,
          conversationId: 'sparse-remap',
          title: 'Local',
          messageId: 'local-message',
          content: 'local',
        );
        await putSparseConversation(
          conversationId: 'sparse-remap',
          messagePrefix: 'remap',
        );
        await source.close();
        sourceClosed = true;

        final report = await live.mergeBackupSnapshot(sourceFile);
        final remappedId = report.remappedConversationIds['sparse-remap'];

        expect(remappedId, isNotNull);
        expect(report.skippedConversations, 0);
        final imported = await live.getConversation(remappedId!);
        expect(imported?.messageIds, hasLength(2));
        expect(
          await live.getMessageIndex(remappedId, imported!.messageIds[0]),
          0,
        );
        expect(
          await live.getMessageIndex(remappedId, imported.messageIds[1]),
          2,
        );
        expect(imported.lastMemoryExtractedOrder, 2);
      },
    );

    test(
      '\u975E\u6CD5 order \u4EC5\u8DF3\u8FC7\u6240\u5C5E\u4F1A\u8BDD\u5E76\u8BA1\u6570',
      () async {
        await putConversation(
          source,
          conversationId: 'valid',
          title: 'Valid',
          messageId: 'valid-message',
          content: 'valid',
        );
        await putTwoMessageConversation(
          source,
          conversationId: 'invalid',
          firstMessageId: 'invalid-a',
          secondMessageId: 'invalid-b',
          firstBody: 'a',
          secondBody: 'b',
        );
        await source.close();
        sourceClosed = true;
        final raw = sqlite.sqlite3.open(sourceFile.path);
        try {
          raw.execute('PRAGMA ignore_check_constraints = ON;');
          raw.execute(
            'UPDATE message_rows SET message_order = -1 '
            "WHERE id = 'invalid-b';",
          );
        } finally {
          raw.close();
        }

        final report = await live.mergeBackupSnapshot(sourceFile);

        expect(report.importedConversations, 1);
        expect(report.skippedConversations, 1);
        expect(await live.getConversation('valid'), isNotNull);
        expect(await live.getConversation('invalid'), isNull);
        expect(await live.getAllConversations(), hasLength(1));
      },
    );
  });
}
