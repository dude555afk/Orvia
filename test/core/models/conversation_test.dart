import 'package:flutter_test/flutter_test.dart';

import 'package:orvia/core/models/conversation.dart';

void main() {
  group('Conversation chat suggestions compatibility', () {
    test('fromJson defaults missing suggestions to empty list', () {
      final conversation = Conversation.fromJson({
        'id': 'conversation-1',
        'title': 'Chat',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
        'messageIds': <String>[],
      });

      expect(conversation.chatSuggestions, isEmpty);
    });

    test('toJson includes chat suggestions', () {
      final conversation = Conversation(
        id: 'conversation-2',
        title: 'Chat',
        chatSuggestions: const ['\u7EE7\u7EED', '\u4E3E\u4F8B'],
      );

      expect(conversation.toJson()['chatSuggestions'], [
        '\u7EE7\u7EED',
        '\u4E3E\u4F8B',
      ]);
    });
  });

  group('Conversation extras', () {
    test('defaults to an empty map and round-trips', () {
      final conversation = Conversation(
        id: 'conversation-3',
        title: 'Chat',
        extras: const {'workspace.id': 'ws-1'},
      );
      expect(Conversation(id: 'empty', title: 'Chat').extras, isEmpty);
      final decoded = Conversation.fromJson(conversation.toJson());
      expect(decoded.extras['workspace.id'], 'ws-1');
    });

    test('fromJson tolerates missing and malformed extras', () {
      final missing = Conversation.fromJson({
        'id': 'conversation-4',
        'title': 'Chat',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
        'messageIds': <String>[],
      });
      expect(missing.extras, isEmpty);
      expect(Conversation.decodeExtras('{}'), isEmpty);
      expect(Conversation.decodeExtras('not-json'), isEmpty);
    });
  });
}
