import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orvia/core/models/assistant.dart';
import 'package:orvia/core/models/chat_message.dart';
import 'package:orvia/core/models/message_part.dart';
import 'package:orvia/core/models/conversation.dart';
import 'package:orvia/core/providers/settings_provider.dart';
import 'package:orvia/core/services/api/providers/claude/claude_container.dart';
import 'package:orvia/core/services/api/providers/claude/claude_history.dart';
import 'package:orvia/core/services/chat/chat_service.dart';
import 'package:orvia/core/services/api/providers/google/gemini_thought_signature.dart';
import 'package:orvia/core/utils/multimodal_input_utils.dart';
import 'package:orvia/features/home/services/message_builder_service.dart';
import 'package:orvia/features/home/services/ocr_service.dart';

import '../../../support/business_test_harness.dart';

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService extends ChatService {
  _FakeChatService(
    this._toolEventsByMessageId, {
    this.persistedMessages = const [],
  });

  final Map<String, List<Map<String, dynamic>>> _toolEventsByMessageId;
  final List<ChatMessage> persistedMessages;

  @override
  List<Map<String, dynamic>> getToolEvents(String assistantMessageId) {
    return List<Map<String, dynamic>>.of(
      _toolEventsByMessageId[assistantMessageId] ?? const [],
    );
  }

  @override
  List<ChatMessage> getMessages(String conversationId) {
    return persistedMessages
        .where((message) => message.conversationId == conversationId)
        .toList();
  }
}

ChatMessage _message({
  required String id,
  required String role,
  required String content,
  String? reasoningText,
  String? groupId,
  int version = 0,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: content,
    conversationId: 'conversation-1',
    reasoningText: reasoningText,
    groupId: groupId,
    version: version,
  );
}

void main() {
  test(
    'inlineLocalImages leaves view_image error text and snapshots to the provider',
    () async {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final dir = await Directory.systemTemp.createTemp('image_error_history_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/private.png');
      await file.writeAsBytes([1, 2, 3]);
      final error = jsonEncode({
        'error': 'path_error',
        'message': '/invalid/![](${file.path})',
      });
      final snapshot = '![](${file.path})';
      final messages = <Map<String, dynamic>>[
        {'role': 'tool', 'name': 'view_image', 'content': error},
        {'role': 'tool', 'name': 'view_image', 'content': snapshot},
        {'role': 'user', 'content': snapshot},
      ];
      await service.inlineLocalImages(messages);
      expect(messages[0]['content'], error);
      expect(messages[1]['content'], snapshot);
      expect(messages[2]['content'], contains('data:image/png;base64,AQID'));
    },
  );

  test(
    'collapseVersions \u6309\u771F\u5B9E\u7248\u672C\u53F7\u9009\u62E9\u6D88\u606F',
    () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );

      final collapsed = service.collapseVersions(
        [
          _message(
            id: 'v1',
            role: 'assistant',
            content: 'selected',
            groupId: 'answer',
            version: 1,
          ),
          _message(
            id: 'v2',
            role: 'assistant',
            content: 'not selected',
            groupId: 'answer',
            version: 2,
          ),
        ],
        const {'answer': 1},
      );

      expect(collapsed.single.id, 'v1');
    },
  );

  group('MessageBuilderService.parseInputFromMessage', () {
    test('reads image/file parts without marker strings', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final message = ChatMessage(
        role: 'user',
        conversationId: 'c1',
        parts: const [
          TextPart('media'),
          ImagePart(uri: 'C:/tmp/photo.png', mime: 'image/png'),
          FilePart(uri: 'C:/tmp/clip.mp4', name: 'clip.mp4', mime: 'video/mp4'),
        ],
      );
      final input = service.parseInputFromMessage(message);
      expect(input.text, 'media');
      expect(input.imagePaths, contains('C:/tmp/photo.png'));
      expect(input.imagePaths, contains('C:/tmp/clip.mp4'));
      expect(input.documents.single.fileName, 'clip.mp4');
    });

    test(
      'skips unavailable parts for API media and keeps mime on documents',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService(const {}),
          contextProvider: _FakeBuildContext(),
        );
        final input = service.parseInputFromMessage(
          ChatMessage(
            role: 'user',
            conversationId: 'c1',
            parts: const [
              TextPart('media'),
              ImagePart(
                uri: '/tmp/missing.png',
                mime: 'image/png',
                unavailable: true,
              ),
              ImagePart(uri: '/tmp/ok.png', mime: 'image/png'),
              FilePart(
                uri: '/tmp/gone.wav',
                name: 'gone.wav',
                mime: 'audio/wav',
                unavailable: true,
              ),
              FilePart(
                uri: '/tmp/keep.wav',
                name: 'keep.wav',
                mime: 'audio/wav',
              ),
            ],
          ),
        );
        expect(input.imagePaths, ['/tmp/ok.png', '/tmp/keep.wav']);
        expect(input.documents.single.fileName, 'keep.wav');
        expect(input.documents.single.mime, 'audio/wav');
      },
    );

    test('TextPart-only content does not decode legacy attachment markers', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final message = ChatMessage(
        role: 'user',
        conversationId: 'c1',
        parts: const [
          TextPart(
            'see [image:/tmp/a.png] and [file:/tmp/a.pdf|a.pdf|application/pdf]',
          ),
        ],
      );
      final input = service.parseInputFromMessage(message);
      expect(
        input.text,
        'see [image:/tmp/a.png] and [file:/tmp/a.pdf|a.pdf|application/pdf]',
      );
      expect(input.imagePaths, isEmpty);
      expect(input.documents, isEmpty);
    });
  });

  group('MessageBuilderService.parseInputFromApiMap', () {
    test('uses content text and internal media paths only', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final input = service.parseInputFromApiMap({
        'role': 'user',
        'content': 'caption [image:/tmp/ignored.png]',
        MessageBuilderService.internalMediaPathsKey: [
          '/tmp/real.png',
          '/tmp/clip.mp3',
        ],
      });
      expect(input.text, 'caption [image:/tmp/ignored.png]');
      expect(input.imagePaths, ['/tmp/real.png', '/tmp/clip.mp3']);
      expect(input.documents.single.fileName, 'clip.mp3');
      expect(input.documents.single.mime.startsWith('audio/'), isTrue);
    });

    test('reads structured map media refs and preserves mime', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final input = service.parseInputFromApiMap({
        'role': 'user',
        'content': 'caption',
        MessageBuilderService.internalMediaPathsKey: [
          encodeInternalMediaRef(uri: '/tmp/real.png', mime: 'image/png'),
          encodeInternalMediaRef(uri: '/tmp/voice.bin', mime: 'audio/wav'),
        ],
      });
      expect(input.imagePaths, ['/tmp/real.png', '/tmp/voice.bin']);
      expect(input.documents.single.fileName, 'voice.bin');
      expect(input.documents.single.mime, 'audio/wav');
    });
  });

  group('MessageBuilderService.parseInputFromMessage media files', () {
    test(
      'image/png FilePart enters imagePaths when includeMediaFilePathsAsImages',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService(const {}),
          contextProvider: _FakeBuildContext(),
        );
        final input = service.parseInputFromMessage(
          ChatMessage(
            role: 'user',
            conversationId: 'c1',
            parts: const [
              TextPart('caption'),
              FilePart(
                uri: '/tmp/photo.png',
                name: 'photo.png',
                mime: 'image/png',
              ),
            ],
          ),
        );
        expect(input.imagePaths, contains('/tmp/photo.png'));
        expect(input.documents.single.fileName, 'photo.png');
        expect(input.documents.single.mime, 'image/png');
      },
    );

    test(
      '\u9ED8\u8BA4\u5C06\u89C6\u9891\u548C\u97F3\u9891 FilePart \u7EB3\u5165\u5A92\u4F53\u8DEF\u5F84\u4F9B API \u4F7F\u7528',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService(const {}),
          contextProvider: _FakeBuildContext(),
        );

        final input = service.parseInputFromMessage(
          ChatMessage(
            role: 'user',
            conversationId: 'c1',
            parts: const [
              TextPart('media'),
              FilePart(
                uri: 'C:/tmp/clip.mp4',
                name: 'clip.mp4',
                mime: 'video/mp4',
              ),
              FilePart(
                uri: 'C:/tmp/audio.wav',
                name: 'audio.wav',
                mime: 'audio/wav',
              ),
            ],
          ),
        );

        expect(input.text, 'media');
        expect(input.imagePaths, ['C:/tmp/clip.mp4', 'C:/tmp/audio.wav']);
        expect(input.documents.map((document) => document.fileName), [
          'clip.mp4',
          'audio.wav',
        ]);
      },
    );

    test(
      '\u7F16\u8F91\u6062\u590D\u8349\u7A3F\u65F6\u4E0D\u628A\u89C6\u9891\u548C\u97F3\u9891 FilePart \u4F2A\u88C5\u6210\u56FE\u7247',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService(const {}),
          contextProvider: _FakeBuildContext(),
        );

        final input = service.parseInputFromMessage(
          ChatMessage(
            role: 'user',
            conversationId: 'c1',
            parts: const [
              TextPart('media'),
              ImagePart(uri: 'C:/tmp/photo.png', mime: 'image/png'),
              FilePart(
                uri: 'C:/tmp/clip.mp4',
                name: 'clip.mp4',
                mime: 'video/mp4',
              ),
              FilePart(
                uri: 'C:/tmp/audio.wav',
                name: 'audio.wav',
                mime: 'audio/wav',
              ),
            ],
          ),
          includeMediaFilePathsAsImages: false,
        );

        expect(input.text, 'media');
        expect(input.imagePaths, ['C:/tmp/photo.png']);
        expect(input.documents.map((document) => document.fileName), [
          'clip.mp4',
          'audio.wav',
        ]);
      },
    );
  });

  group('MessageBuilderService.buildApiMessages media paths', () {
    test('pure-attachment user message emits structured media paths', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final apiMessages = service.buildApiMessages(
        messages: [
          ChatMessage(
            id: 'u1',
            role: 'user',
            conversationId: 'c1',
            parts: const [ImagePart(uri: '/tmp/only.png', mime: 'image/png')],
          ),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      expect(apiMessages, hasLength(1));
      expect(apiMessages.single['content'], '');
      expect(
        apiMessages.single[MessageBuilderService.internalRevisionIdKey],
        'u1',
      );
      expect(apiMessages.single[MessageBuilderService.internalMediaPathsKey], [
        encodeInternalMediaRef(uri: '/tmp/only.png', mime: 'image/png'),
      ]);
    });

    test('assistant ImagePart gets media paths too', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final apiMessages = service.buildApiMessages(
        messages: [
          _message(id: 'u1', role: 'user', content: 'hi'),
          ChatMessage(
            id: 'a1',
            role: 'assistant',
            conversationId: 'c1',
            parts: const [
              TextPart('see image'),
              ImagePart(uri: '/tmp/assistant.png', mime: 'image/png'),
            ],
          ),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      final assistant = apiMessages.lastWhere(
        (message) => message['role'] == 'assistant',
      );
      expect(assistant[MessageBuilderService.internalMediaPathsKey], [
        encodeInternalMediaRef(uri: '/tmp/assistant.png', mime: 'image/png'),
      ]);
    });

    test('unavailable parts are omitted from media paths', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final apiMessages = service.buildApiMessages(
        messages: [
          ChatMessage(
            id: 'u1',
            role: 'user',
            conversationId: 'c1',
            parts: const [
              TextPart('mixed'),
              ImagePart(
                uri: '/tmp/missing.png',
                mime: 'image/png',
                unavailable: true,
              ),
              ImagePart(uri: '/tmp/ok.png', mime: 'image/png'),
              FilePart(
                uri: '/tmp/gone.mp3',
                name: 'gone.mp3',
                mime: 'audio/mpeg',
                unavailable: true,
              ),
            ],
          ),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      expect(apiMessages.single[MessageBuilderService.internalMediaPathsKey], [
        encodeInternalMediaRef(uri: '/tmp/ok.png', mime: 'image/png'),
      ]);
    });

    test('pure PDF FilePart-only user message appears in buildApiMessages', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final apiMessages = service.buildApiMessages(
        messages: [
          ChatMessage(
            id: 'u-pdf',
            role: 'user',
            conversationId: 'c1',
            parts: const [
              FilePart(
                uri: '/tmp/spec.pdf',
                name: 'spec.pdf',
                mime: 'application/pdf',
              ),
            ],
          ),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      expect(apiMessages, hasLength(1));
      expect(apiMessages.single['role'], 'user');
      expect(apiMessages.single['content'], '');
      expect(
        apiMessages.single[MessageBuilderService.internalRevisionIdKey],
        'u-pdf',
      );
      // PDF is a document, not a media-path attachment.
      expect(
        apiMessages.single.containsKey(
          MessageBuilderService.internalMediaPathsKey,
        ),
        isFalse,
      );
    });

    test(
      'octet-stream video FilePart emits inferred video mime in media refs',
      () {
        final refs = MessageBuilderService.mediaRefsFromParts(
          ChatMessage(
            role: 'user',
            conversationId: 'c1',
            parts: const [
              FilePart(
                uri: '/tmp/clip.mp4',
                name: 'clip.mp4',
                mime: 'application/octet-stream',
              ),
            ],
          ),
        );
        expect(refs, hasLength(1));
        expect(refs.single['uri'], '/tmp/clip.mp4');
        expect(refs.single['mime'], 'video/mp4');
      },
    );

    test('audio FilePart is detectable without processUserMessagesForApi', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService(const {}),
        contextProvider: _FakeBuildContext(),
      );
      final apiMessages = service.buildApiMessages(
        messages: [
          ChatMessage(
            id: 'u1',
            role: 'user',
            conversationId: 'c1',
            parts: const [
              FilePart(
                uri: '/tmp/voice.bin',
                name: 'voice.bin',
                mime: 'audio/wav',
              ),
            ],
          ),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      final refs = parseInternalMediaRefs(
        apiMessages.single[MessageBuilderService.internalMediaPathsKey],
      );
      expect(refs, isNotEmpty);
      expect(
        refs.any(
          (ref) => isAudioMime(
            (ref.mime != null && ref.mime!.isNotEmpty)
                ? ref.mime!
                : inferMediaMimeFromSource(ref.uri),
          ),
        ),
        isTrue,
      );
      expect(refs.single.mime, 'audio/wav');
    });
  });

  group('MessageBuilderService.buildApiMessages', () {
    test(
      '\u6709\u5DE5\u5177\u8C03\u7528\u65F6\u4F1A\u628A reasoning_content \u56DE\u586B\u5230 assistant tool \u6D88\u606F',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'get_weather',
                'arguments': {'location': 'Hangzhou', 'date': '2026-04-25'},
                'content': 'Cloudy 7~13°C',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(
              id: 'u1',
              role: 'user',
              content:
                  '\u676D\u5DDE\u660E\u5929\u5929\u6C14\u600E\u4E48\u6837？',
            ),
            _message(
              id: 'a1',
              role: 'assistant',
              content: '\u660E\u5929\u591A\u4E91，7 \u5230 13 \u5EA6。',
              reasoningText:
                  '\u5148\u5224\u65AD\u65E5\u671F，\u518D\u67E5\u8BE2\u5929\u6C14。',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final assistantToolMessage = apiMessages.firstWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] is List,
        );
        final finalAssistantMessage = apiMessages.lastWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] == null,
        );

        expect(assistantToolMessage['content'], '\n\n');
        expect(
          assistantToolMessage['reasoning_content'],
          '\u5148\u5224\u65AD\u65E5\u671F，\u518D\u67E5\u8BE2\u5929\u6C14。',
        );
        expect(
          finalAssistantMessage['reasoning_content'],
          '\u5148\u5224\u65AD\u65E5\u671F，\u518D\u67E5\u8BE2\u5929\u6C14。',
        );
      },
    );

    test(
      'a stored Claude turn rides on the tool message, the container on both',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'srvtoolu_1',
                'name': 'web_fetch',
                'arguments': {'url': 'https://example.com'},
                'content': '{}',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
          providerArtifactLookup: (message, kind) => switch (kind) {
            claudeTurnArtifactKind => '[[{"type":"text","text":"hi"}]]',
            claudeContainerArtifactKind => '{"id":"container_1"}',
            _ => null,
          },
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: '\u770B\u770B'),
            _message(id: 'a1', role: 'assistant', content: 'hi'),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final toolMessage = apiMessages.firstWhere(
          (message) => message['tool_calls'] is List,
        );
        final finalMessage = apiMessages.last;
        expect(
          toolMessage[multimodalInternalClaudeTurnKey],
          '[[{"type":"text","text":"hi"}]]',
        );
        expect(
          toolMessage[multimodalInternalClaudeContainerKey],
          '{"id":"container_1"}',
        );
        expect(finalMessage[multimodalInternalClaudeTurnKey], isNull);
        expect(
          finalMessage[multimodalInternalClaudeContainerKey],
          '{"id":"container_1"}',
        );
      },
    );

    test('a stored Gemini signature rides on the final assistant message', () {
      final service = MessageBuilderService(
        chatService: _FakeChatService({}),
        contextProvider: _FakeBuildContext(),
        providerArtifactLookup: (message, kind) =>
            kind == geminiThoughtSignatureArtifactKind && message.id == 'a1'
            ? 'sig-stored'
            : null,
      );

      final apiMessages = service.buildApiMessages(
        messages: [
          _message(id: 'u1', role: 'user', content: '\u4F60\u597D'),
          _message(id: 'a1', role: 'assistant', content: '\u4F60\u597D\u5440'),
          _message(id: 'u2', role: 'user', content: '\u518D\u89C1'),
        ],
        versionSelections: const {},
        currentConversation: Conversation(title: 'test'),
      );

      expect(
        apiMessages.map((m) => m[multimodalInternalGeminiThoughtSignatureKey]),
        [null, 'sig-stored', null],
      );
    });

    test(
      'a turn that ran code and said nothing still carries its container',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'srvtoolu_1',
                'name': 'code_execution',
                'arguments': {'code': 'print(1)'},
                'content': '{"stdout":"1\\n"}',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
          providerArtifactLookup: (message, kind) =>
              kind == claudeContainerArtifactKind
              ? '{"id":"container_1"}'
              : null,
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: '\u8DD1\u4E00\u4E0B'),
            _message(id: 'a1', role: 'assistant', content: ''),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        expect(apiMessages.last['role'], 'tool');
        final toolMessage = apiMessages.firstWhere(
          (message) => message['tool_calls'] is List,
        );
        expect(
          toolMessage[multimodalInternalClaudeContainerKey],
          '{"id":"container_1"}',
        );
      },
    );

    test(
      'reasoningText \u4E3A\u7A7A\u65F6\u4E0D\u4F1A\u4F2A\u9020 reasoning_content',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'get_date',
                'arguments': <String, dynamic>{},
                'content': '2026-04-24',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(
              id: 'u1',
              role: 'user',
              content: '\u4ECA\u5929\u51E0\u53F7？',
            ),
            _message(
              id: 'a1',
              role: 'assistant',
              content: '\u4ECA\u5929\u662F 2026-04-24。',
              reasoningText: '',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final assistantToolMessage = apiMessages.firstWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] is List,
        );
        final finalAssistantMessage = apiMessages.lastWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] == null,
        );

        expect(assistantToolMessage.containsKey('reasoning_content'), isFalse);
        expect(finalAssistantMessage.containsKey('reasoning_content'), isFalse);
      },
    );

    test(
      'reasoning_details \u53EA\u6302\u5728\u6700\u7EC8 assistant \u6D88\u606F，\u4E0D\u91CD\u590D\u5230 tool call \u6D88\u606F',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'get_weather',
                'arguments': {'location': 'Hangzhou'},
                'content': 'Cloudy 7~13°C',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        const reasoningDetails = [
          {
            'type': 'reasoning.text',
            'text': 'final round thinking',
            'signature': 'sig-final',
          },
        ];
        final apiMessages = service.buildApiMessages(
          messages: [
            _message(
              id: 'u1',
              role: 'user',
              content:
                  '\u676D\u5DDE\u660E\u5929\u5929\u6C14\u600E\u4E48\u6837？',
            ),
            ChatMessage(
              id: 'a1',
              role: 'assistant',
              content: '\u660E\u5929\u591A\u4E91，7 \u5230 13 \u5EA6。',
              conversationId: 'conversation-1',
              reasoningSegmentsJson:
                  '{"v":2,"segments":[],"reasoningDetails":[{"type":"reasoning.text","text":"final round thinking","signature":"sig-final"}]}',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final assistantToolMessage = apiMessages.firstWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] is List,
        );
        final finalAssistantMessage = apiMessages.lastWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] == null,
        );

        // Replaying the same reasoning on both assistant messages makes
        // OpenRouter/Anthropic reject the history; only the final message may
        // carry it.
        expect(assistantToolMessage.containsKey('reasoning_details'), isFalse);
        expect(finalAssistantMessage['reasoning_details'], reasoningDetails);
      },
    );

    test(
      '\u6062\u590D\u5DE5\u5177\u56DE\u7B54\u7EED\u5199\u65F6\u53EA\u53D1\u9001 tool call \u548C tool result',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'ask_user_input_v0',
                'arguments': {
                  'questions': [
                    {
                      'id': 'scope',
                      'question': '\u9009\u54EA\u4E2A\u8303\u56F4？',
                      'type': 'single',
                      'options': ['\u6700\u5C0F', '\u5B8C\u6574'],
                    },
                  ],
                },
                'content':
                    '{"type":"ask_user_answer","answers":{"scope":{"type":"single","value":"\u5B8C\u6574","custom":false,"skipped":false}}}',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: '\u5F00\u59CB\u5427'),
            _message(id: 'a1', role: 'assistant', content: ''),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        expect(
          apiMessages.where(
            (message) =>
                message['role'] == 'assistant' && message['tool_calls'] == null,
          ),
          isEmpty,
        );
        expect(
          apiMessages.where(
            (message) =>
                message['role'] == 'assistant' && message['tool_calls'] is List,
          ),
          hasLength(1),
        );
        expect(
          apiMessages.where((message) => message['role'] == 'tool'),
          hasLength(1),
        );
      },
    );

    test(
      '\u4F20\u5165\u6D88\u606F\u7F3A\u5C11 reasoningText \u65F6\u4F1A\u4ECE\u5DF2\u6301\u4E45\u5316\u6D88\u606F\u515C\u5E95\u56DE\u586B',
      () {
        final persistedAssistant = _message(
          id: 'a1',
          role: 'assistant',
          content:
              '\u73B0\u5728\u662F\u5317\u4EAC\u65F6\u95F4\u4E0B\u5348\u4E09\u70B9。',
          reasoningText:
              '\u5148\u8C03\u7528\u65F6\u95F4\u5DE5\u5177，\u518D\u6574\u7406\u6210\u4E2D\u6587\u65F6\u95F4。',
        );
        final service = MessageBuilderService(
          chatService: _FakeChatService(
            {
              'a1': [
                {
                  'id': 'call_1',
                  'name': 'get-current-time',
                  'arguments': {'timeZone': 'Asia/Shanghai'},
                  'content': 'Friday, 2026-04-24 15:25:41',
                },
              ],
            },
            persistedMessages: [
              _message(
                id: 'u1',
                role: 'user',
                content: '\u73B0\u5728\u51E0\u70B9\u4E86',
              ),
              persistedAssistant,
            ],
          ),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(
              id: 'u1',
              role: 'user',
              content: '\u73B0\u5728\u51E0\u70B9\u4E86',
            ),
            _message(
              id: 'a1',
              role: 'assistant',
              content:
                  '\u73B0\u5728\u662F\u5317\u4EAC\u65F6\u95F4\u4E0B\u5348\u4E09\u70B9。',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final assistantToolMessage = apiMessages.firstWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] is List,
        );
        final finalAssistantMessage = apiMessages.lastWhere(
          (message) =>
              message['role'] == 'assistant' && message['tool_calls'] == null,
        );

        expect(
          assistantToolMessage['reasoning_content'],
          '\u5148\u8C03\u7528\u65F6\u95F4\u5DE5\u5177，\u518D\u6574\u7406\u6210\u4E2D\u6587\u65F6\u95F4。',
        );
        expect(
          finalAssistantMessage['reasoning_content'],
          '\u5148\u8C03\u7528\u65F6\u95F4\u5DE5\u5177，\u518D\u6574\u7406\u6210\u4E2D\u6587\u65F6\u95F4。',
        );
      },
    );

    test(
      '\u5173\u95ED OpenAI \u5DE5\u5177\u6D88\u606F\u91CD\u5EFA\u65F6\u4E0D\u989D\u5916\u6CE8\u5165 assistant tool \u6D88\u606F',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'get_weather',
                'arguments': {'location': 'Hangzhou'},
                'content': 'Cloudy',
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(
              id: 'u1',
              role: 'user',
              content: '\u5E2E\u6211\u67E5\u5929\u6C14',
            ),
            _message(
              id: 'a1',
              role: 'assistant',
              content: '\u660E\u5929\u591A\u4E91。',
              reasoningText:
                  '\u5148\u67E5\u65E5\u671F，\u518D\u67E5\u5929\u6C14。',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: false,
        );

        expect(
          apiMessages.where((message) => message['tool_calls'] is List),
          isEmpty,
        );
      },
    );

    test(
      '\u5DE5\u5177\u5386\u53F2\u4F1A\u4FDD\u7559 provider \u5143\u6570\u636E\u4F9B Claude \u548C Gemini \u91CD\u653E',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'lookup',
                'arguments': {'query': 'Orvia'},
                'content': '{"result":"ok"}',
                'metadata': {
                  'anthropic': {
                    'assistant_blocks': [
                      {
                        'type': 'thinking',
                        'thinking': '\u9700\u8981\u67E5\u8BE2\u8D44\u6599。',
                        'signature': 'sig-claude',
                      },
                      {
                        'type': 'tool_use',
                        'id': 'call_1',
                        'name': 'lookup',
                        'input': {'query': 'Orvia'},
                      },
                    ],
                  },
                  'google': {
                    'part': {
                      'functionCall': {
                        'name': 'lookup',
                        'args': {'query': 'Orvia'},
                      },
                      'thoughtSignature': 'sig-gemini',
                    },
                  },
                },
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: '\u67E5 Orvia'),
            _message(
              id: 'a1',
              role: 'assistant',
              content: '\u67E5\u5230\u4E86。',
            ),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final assistantToolMessage = apiMessages.firstWhere(
          (message) => message['tool_calls'] is List,
        );
        final toolMessage = apiMessages.firstWhere(
          (message) => message['role'] == 'tool',
        );
        final toolCall =
            (assistantToolMessage['tool_calls'] as List).single
                as Map<String, dynamic>;

        expect(
          toolCall['metadata']['anthropic']['assistant_blocks'],
          isNotEmpty,
        );
        expect(
          toolCall['metadata']['google']['part']['thoughtSignature'],
          'sig-gemini',
        );
        expect(
          toolMessage['metadata']['google']['part']['thoughtSignature'],
          'sig-gemini',
        );
      },
    );

    test(
      '\u5DE5\u5177\u5386\u53F2\u4F1A\u4FDD\u7559 OpenAI \u517C\u5BB9 Gemini \u7684 extra_content',
      () {
        const extraContent = <String, dynamic>{
          'google': <String, dynamic>{'thought_signature': 'sig-create-memory'},
        };
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_mem',
                'name': 'create_memory',
                'arguments': {'content': 'note'},
                'content': '{"ok":true}',
                'metadata': {
                  'google': {'extra_content': extraContent},
                },
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: 'remember this'),
            _message(id: 'a1', role: 'assistant', content: 'saved'),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        final toolCall =
            (apiMessages.firstWhere(
                          (message) => message['tool_calls'] is List,
                        )['tool_calls']
                        as List)
                    .single
                as Map<String, dynamic>;

        expect(toolCall['metadata']['google']['extra_content'], extraContent);
      },
    );

    test(
      '\u672A\u5B8C\u6210\u7684\u5DE5\u5177\u5360\u4F4D\u4E8B\u4EF6\u4E0D\u4F1A\u88AB\u91CD\u5EFA\u4E3A API tool call',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({
            'a1': [
              {
                'id': 'call_1',
                'name': 'create_memory',
                'arguments': {'content': 'test'},
                'content': null,
                'metadata': {
                  'anthropic': {
                    'assistant_blocks': [
                      {
                        'type': 'tool_use',
                        'id': 'call_1',
                        'name': 'create_memory',
                        'input': {'content': 'test'},
                      },
                    ],
                  },
                },
              },
            ],
          }),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: '\u8BB0\u4E00\u4E0B'),
            _message(
              id: 'a1',
              role: 'assistant',
              content: '\u7A0D\u540E\u7EE7\u7EED。',
            ),
            _message(id: 'u2', role: 'user', content: 'ok'),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
          includeToolMessages: true,
        );

        expect(
          apiMessages.where((message) => message['tool_calls'] is List),
          isEmpty,
        );
        expect(
          apiMessages.where((message) => message['role'] == 'tool'),
          isEmpty,
        );
        expect(apiMessages.map((message) => message['content']).toList(), [
          '\u8BB0\u4E00\u4E0B',
          '\u7A0D\u540E\u7EE7\u7EED。',
          'ok',
        ]);
      },
    );

    test(
      'user \u6D88\u606F\u4F1A\u9644\u5E26\u5185\u90E8 revision id，strip \u540E\u4E0D\u518D\u51FA\u73B0',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = service.buildApiMessages(
          messages: [
            _message(id: 'u1', role: 'user', content: 'hello'),
            _message(id: 'a1', role: 'assistant', content: 'hi'),
          ],
          versionSelections: const {},
          currentConversation: Conversation(title: 'test'),
        );

        expect(apiMessages.first['role'], 'user');
        expect(
          apiMessages.first[MessageBuilderService.internalRevisionIdKey],
          'u1',
        );
        expect(
          apiMessages.last.containsKey(
            MessageBuilderService.internalRevisionIdKey,
          ),
          isFalse,
        );

        service.stripInternalRevisionIds(apiMessages);
        expect(
          apiMessages.any(
            (message) => message.containsKey(multimodalInternalRevisionIdKey),
          ),
          isFalse,
        );
      },
    );

    test(
      'WorldBook \u6CE8\u5165\u540E\u7684\u6700\u7EC8\u88C1\u526A\u4F1A\u9650\u5236\u53D1\u9001\u6D88\u606F\u6570',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );
        // prepareApiMessages injects WorldBook against the full history, then
        // applies a single context trim before OCR — only when the assistant
        // opts into limitContextMessages (default is unlimited, D-30).
        final apiMessages = <Map<String, dynamic>>[
          {'role': 'system', 'content': 'system'},
          for (var index = 0; index < 6; index++)
            {
              'role': index.isEven ? 'user' : 'assistant',
              'content': 'message-$index',
            },
          {'role': 'user', 'content': 'worldbook-top'},
          {'role': 'user', 'content': 'worldbook-bottom'},
        ];

        service.applyContextLimit(
          apiMessages,
          const Assistant(
            id: 'assistant-1',
            name: 'test',
            contextMessageSize: 4,
            limitContextMessages: true,
          ),
        );
        expect(apiMessages.length, 5); // system + 4
        expect(apiMessages.first['role'], 'system');
        // Images in dropped history are never OCR'd because OCR runs after this trim.
        expect(
          apiMessages.any(
            (m) => (m['content'] ?? '').toString() == 'message-0',
          ),
          isFalse,
        );
      },
    );

    test(
      '\u4E0A\u4E0B\u6587\u88C1\u526A\u4F1A\u4E22\u6389\u5386\u53F2\u56FE\u7247\u6D88\u606F\u5E76\u4FDD\u7559\u5185\u90E8 revision id',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );

        final apiMessages = <Map<String, dynamic>>[
          for (var index = 0; index < 6; index++)
            if (index.isEven)
              {
                'role': 'user',
                'content': 'u$index',
                MessageBuilderService.internalMediaPathsKey: [
                  '/img-$index.png',
                ],
                MessageBuilderService.internalRevisionIdKey: 'u$index',
              }
            else
              {'role': 'assistant', 'content': 'a$index'},
        ];

        service.applyContextLimit(
          apiMessages,
          const Assistant(
            id: 'assistant-1',
            name: 'test',
            contextMessageSize: 2,
            limitContextMessages: true,
          ),
        );

        expect(apiMessages, hasLength(2));
        final retainedMediaPaths = apiMessages
            .expand(
              (message) =>
                  (message[MessageBuilderService.internalMediaPathsKey]
                      as List?) ??
                  const [],
            )
            .map((path) => path.toString())
            .toList();
        expect(retainedMediaPaths, isNot(contains('/img-0.png')));
        expect(retainedMediaPaths, isNot(contains('/img-2.png')));
        expect(retainedMediaPaths, contains('/img-4.png'));

        final retainedUser = apiMessages.firstWhere(
          (message) => message['role'] == 'user',
        );
        expect(
          retainedUser[MessageBuilderService.internalRevisionIdKey],
          isNotNull,
        );
        expect(retainedUser[MessageBuilderService.internalMediaPathsKey], [
          '/img-4.png',
        ]);
        expect(
          (retainedUser['content'] ?? '').toString(),
          isNot(contains('[image:')),
        );
      },
    );

    test(
      '\u65E0\u9650\u5236\u4E0A\u4E0B\u6587\u4E0D\u4F1A\u88C1\u6389\u4E00\u5343\u6761\u4EE5\u4E0A\u7684\u6D88\u606F',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );
        final apiMessages = <Map<String, dynamic>>[
          for (var index = 0; index < 1507; index++)
            {
              'role': index.isEven ? 'user' : 'assistant',
              'content': 'message-$index',
            },
        ];

        service.applyContextLimit(
          apiMessages,
          const Assistant(
            id: 'assistant-1',
            name: 'test',
            limitContextMessages: false,
          ),
        );

        expect(apiMessages, hasLength(1507));
        expect(apiMessages.first['content'], 'message-0');
        expect(apiMessages.last['content'], 'message-1506');
      },
    );

    test(
      '\u4E0A\u4E0B\u6587\u88C1\u526A\u4E0D\u4F1A\u4FDD\u7559\u7F3A\u5C11 tool result \u7684 assistant tool call',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );
        final apiMessages = <Map<String, dynamic>>[
          {'role': 'user', 'content': 'before'},
          {
            'role': 'assistant',
            'content': '\n\n',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'create_memory', 'arguments': '{}'},
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call_1',
            'name': 'create_memory',
            'content': 'ok',
          },
          {'role': 'assistant', 'content': 'done'},
          {'role': 'user', 'content': 'next'},
        ];

        service.applyContextLimit(
          apiMessages,
          const Assistant(
            id: 'assistant-1',
            name: 'test',
            contextMessageSize: 3,
            limitContextMessages: true,
          ),
        );

        expect(
          apiMessages.where((message) => message['tool_calls'] is List),
          isEmpty,
        );
        expect(
          apiMessages.where((message) => message['role'] == 'tool'),
          isEmpty,
        );
        expect(apiMessages.map((message) => message['content']).toList(), [
          'done',
          'next',
        ]);
      },
    );

    test(
      '\u4E0A\u4E0B\u6587\u88C1\u526A\u4F1A\u4FDD\u7559\u5B8C\u6574\u7684 assistant tool call \u4E0E tool result',
      () {
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );
        final apiMessages = <Map<String, dynamic>>[
          {'role': 'user', 'content': 'before'},
          {
            'role': 'assistant',
            'content': '\n\n',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'create_memory', 'arguments': '{}'},
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call_1',
            'name': 'create_memory',
            'content': 'ok',
          },
          {'role': 'assistant', 'content': 'done'},
          {'role': 'user', 'content': 'next'},
        ];

        service.applyContextLimit(
          apiMessages,
          const Assistant(
            id: 'assistant-1',
            name: 'test',
            contextMessageSize: 4,
            limitContextMessages: true,
          ),
        );

        expect(
          apiMessages.where((message) => message['tool_calls'] is List),
          hasLength(1),
        );
        expect(
          apiMessages.where((message) => message['role'] == 'tool'),
          hasLength(1),
        );
        expect(apiMessages.map((message) => message['role']).toList(), [
          'assistant',
          'tool',
          'assistant',
          'user',
        ]);
      },
    );
  });

  group('MessageBuilderService.hasPendingAttachmentWork', () {
    Future<SettingsProvider> newSettings() async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
      return settings;
    }

    Future<SettingsProvider> settingsWithOcr() async {
      final settings = await newSettings();
      await settings.setProviderConfig(
        'ocr-provider',
        ProviderConfig(
          id: 'ocr-provider',
          enabled: true,
          name: 'OCR',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          models: const ['ocr-model'],
          modelOverrides: const {
            'ocr-model': {
              'input': ['text', 'image'],
            },
          },
        ),
      );
      await settings.setOcrModel('ocr-provider', 'ocr-model');
      await settings.setOcrEnabled(true);
      return settings;
    }

    MessageBuilderService serviceWithOcr() => MessageBuilderService(
      chatService: _FakeChatService({}),
      contextProvider: _FakeBuildContext(),
      ocrHandler: (imagePaths, {revisionId, session, requestId}) async => 'ocr',
    );

    List<Map<String, dynamic>> apiMessagesFor(ChatMessage message) => [
      {
        'role': 'user',
        'content': message.content,
        MessageBuilderService.internalRevisionIdKey: message.id,
      },
    ];

    test(
      '\u7EAF\u6587\u672C\u6D88\u606F\u6CA1\u6709\u5F85\u89E3\u6790\u9644\u4EF6',
      () async {
        final settings = await settingsWithOcr();
        final user = ChatMessage(
          id: 'u1',
          role: 'user',
          conversationId: 'c1',
          parts: const [TextPart('just text')],
        );
        expect(
          serviceWithOcr().hasPendingAttachmentWork(
            apiMessagesFor(user),
            settings,
            sourceMessages: [user],
          ),
          isFalse,
        );
      },
    );

    test(
      '\u5173\u95ED OCR \u65F6\u7EAF\u56FE\u7247\u6D88\u606F\u6CA1\u6709\u5F85\u89E3\u6790\u9644\u4EF6',
      () async {
        final settings = await newSettings();
        final user = ChatMessage(
          id: 'u1',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('look'),
            ImagePart(uri: '/tmp/a.png', mime: 'image/png'),
          ],
        );
        expect(
          serviceWithOcr().hasPendingAttachmentWork(
            apiMessagesFor(user),
            settings,
            sourceMessages: [user],
          ),
          isFalse,
        );
      },
    );

    test(
      '\u5F00\u542F OCR \u65F6\u56FE\u7247\u6D88\u606F\u9700\u8981\u89E3\u6790',
      () async {
        final settings = await settingsWithOcr();
        final user = ChatMessage(
          id: 'u1',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('look'),
            ImagePart(uri: '/tmp/a.png', mime: 'image/png'),
          ],
        );
        expect(
          serviceWithOcr().hasPendingAttachmentWork(
            apiMessagesFor(user),
            settings,
            sourceMessages: [user],
          ),
          isTrue,
        );
      },
    );

    test(
      '\u6587\u6863\u9644\u4EF6\u65E0\u8BBA OCR \u5F00\u5173\u90FD\u9700\u8981\u89E3\u6790',
      () async {
        final settings = await newSettings();
        final user = ChatMessage(
          id: 'u1',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('read this'),
            FilePart(uri: '/tmp/a.pdf', name: 'a.pdf', mime: 'application/pdf'),
          ],
        );
        expect(
          serviceWithOcr().hasPendingAttachmentWork(
            apiMessagesFor(user),
            settings,
            sourceMessages: [user],
          ),
          isTrue,
        );
      },
    );

    test(
      '\u97F3\u89C6\u9891\u9644\u4EF6\u4E0D\u7B97\u5F85\u89E3\u6790\u6587\u6863',
      () async {
        final settings = await newSettings();
        final user = ChatMessage(
          id: 'u1',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('listen'),
            FilePart(
              uri: '/tmp/clip.mp3',
              name: 'clip.mp3',
              mime: 'audio/mpeg',
            ),
          ],
        );
        expect(
          serviceWithOcr().hasPendingAttachmentWork(
            apiMessagesFor(user),
            settings,
            sourceMessages: [user],
          ),
          isFalse,
        );
      },
    );

    test(
      '\u7F3A\u5C11 revision id \u7684 WorldBook lore \u4E0D\u7B97\u5F85\u89E3\u6790\u9644\u4EF6',
      () async {
        final settings = await settingsWithOcr();
        expect(
          serviceWithOcr().hasPendingAttachmentWork(const [
            {'role': 'user', 'content': 'lore [image:/tmp/lore.png]'},
          ], settings),
          isFalse,
        );
      },
    );
  });

  group('MessageBuilderService.processUserMessagesForApi', () {
    test(
      '\u4E0D\u5904\u7406\u7F3A\u5C11\u5185\u90E8 revision ID \u7684 WorldBook lore user \u6D88\u606F',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(createBusinessTestPreferences());
        await settings.loaded;

        final ocrCalls = <List<String>>[];
        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
          ocrHandler: (imagePaths, {revisionId, session, requestId}) async {
            ocrCalls.add(List<String>.of(imagePaths));
            return 'ocr-should-not-run';
          },
          ocrPrefetch: ({required revisionIds, required imagePaths}) async {
            ocrCalls.add(['prefetch', ...imagePaths]);
            return OcrPrepareSession();
          },
        );

        // Intentional negative: literal marker text in WorldBook lore must be
        // ignored when the message has no internal revision id.
        const loreContent =
            'lore with markers\n[image:/tmp/lore.png]\n[file:/tmp/lore.txt|lore.txt|text/plain]';
        final realUser = ChatMessage(
          id: 'u-real',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('real user'),
            ImagePart(uri: '/tmp/real.png', mime: 'image/png'),
          ],
        );
        final apiMessages = <Map<String, dynamic>>[
          {
            'role': 'user',
            'content': loreContent, // WorldBook injection: no revision id
          },
          {
            'role': 'user',
            'content': realUser.content,
            MessageBuilderService.internalRevisionIdKey: realUser.id,
          },
        ];

        await settings.setProviderConfig(
          'ocr-provider',
          ProviderConfig(
            id: 'ocr-provider',
            enabled: true,
            name: 'OCR',
            apiKey: 'key',
            baseUrl: 'https://example.test',
            models: const ['ocr-model'],
            modelOverrides: const {
              'ocr-model': {
                'input': ['text', 'image'],
              },
            },
          ),
        );
        await settings.setOcrModel('ocr-provider', 'ocr-model');
        await settings.setOcrEnabled(true);

        await service.processUserMessagesForApi(
          apiMessages,
          settings,
          const Assistant(id: 'a1', name: 'test'),
          sourceMessages: [realUser],
        );

        expect(apiMessages.first['content'], loreContent);
        expect(
          apiMessages.first.containsKey(
            MessageBuilderService.internalMediaPathsKey,
          ),
          isFalse,
        );
        expect(
          ocrCalls.expand((paths) => paths),
          isNot(contains('/tmp/lore.png')),
        );
        expect(ocrCalls.expand((paths) => paths), contains('/tmp/real.png'));
        expect(apiMessages.last['content'], isNot(contains('[image:')));
        expect(apiMessages.first['content'], contains('[image:/tmp/lore.png]'));
      },
    );

    test('writes structured media refs and keeps OCR filtering', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;

      final service = MessageBuilderService(
        chatService: _FakeChatService({}),
        contextProvider: _FakeBuildContext(),
        ocrHandler: (imagePaths, {revisionId, session, requestId}) async =>
            'ocr',
      );

      final realUser = ChatMessage(
        id: 'u-real',
        role: 'user',
        conversationId: 'c1',
        parts: const [
          TextPart('real user'),
          ImagePart(uri: '/tmp/real.png', mime: 'image/png'),
          FilePart(uri: '/tmp/clip.mp3', name: 'clip.mp3', mime: 'audio/mpeg'),
        ],
      );
      final apiMessages = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': realUser.content,
          MessageBuilderService.internalRevisionIdKey: realUser.id,
          MessageBuilderService.internalMediaPathsKey:
              MessageBuilderService.mediaRefsFromParts(realUser),
        },
      ];

      await settings.setProviderConfig(
        'ocr-provider',
        ProviderConfig(
          id: 'ocr-provider',
          enabled: true,
          name: 'OCR',
          apiKey: 'key',
          baseUrl: 'https://example.test',
          models: const ['ocr-model'],
          modelOverrides: const {
            'ocr-model': {
              'input': ['text', 'image'],
            },
          },
        ),
      );
      await settings.setOcrModel('ocr-provider', 'ocr-model');
      await settings.setOcrEnabled(true);

      await service.processUserMessagesForApi(
        apiMessages,
        settings,
        const Assistant(id: 'a1', name: 'test'),
        sourceMessages: [realUser],
      );

      final media =
          apiMessages.single[MessageBuilderService.internalMediaPathsKey]
              as List;
      // OCR active: image paths filtered out, audio kept as structured ref.
      expect(media, [
        encodeInternalMediaRef(uri: '/tmp/clip.mp3', mime: 'audio/mpeg'),
      ]);
      expect(apiMessages.single['content'], isNot(contains('[image:')));
    });

    test(
      'octet-stream mp4 FilePart stays video/mp4 in processUserMessagesForApi',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(createBusinessTestPreferences());
        await settings.loaded;

        final service = MessageBuilderService(
          chatService: _FakeChatService({}),
          contextProvider: _FakeBuildContext(),
        );

        final realUser = ChatMessage(
          id: 'u-video',
          role: 'user',
          conversationId: 'c1',
          parts: const [
            TextPart('clip please'),
            FilePart(
              uri: '/tmp/clip.mp4',
              name: 'clip.mp4',
              mime: 'application/octet-stream',
            ),
          ],
        );
        final apiMessages = <Map<String, dynamic>>[
          {
            'role': 'user',
            'content': realUser.content,
            MessageBuilderService.internalRevisionIdKey: realUser.id,
            // Seed with raw/stale mime so the rebuild path must re-resolve.
            MessageBuilderService.internalMediaPathsKey: [
              encodeInternalMediaRef(
                uri: '/tmp/clip.mp4',
                mime: 'application/octet-stream',
              ),
            ],
          },
        ];

        await service.processUserMessagesForApi(
          apiMessages,
          settings,
          const Assistant(id: 'a1', name: 'test'),
          sourceMessages: [realUser],
        );

        final media =
            apiMessages.single[MessageBuilderService.internalMediaPathsKey]
                as List;
        expect(media, [
          encodeInternalMediaRef(uri: '/tmp/clip.mp4', mime: 'video/mp4'),
        ]);
      },
    );
  });
}
