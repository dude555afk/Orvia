import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';

class DebugConversationSeed {
  const DebugConversationSeed({
    required this.conversation,
    required this.messages,
    required this.totalContentBytes,
  });

  final Conversation conversation;
  final List<ChatMessage> messages;
  final int totalContentBytes;
}

class DebugConversationFactory {
  DebugConversationFactory._();

  static const int oversizedConversationBytes = 30 * 1024 * 1024;
  static const int manyMessagesCount = 1024;
  static const int dailyMixedMarkdownMessagesCount = 3000;
  static const int longReasoningMessagesCount = 128;

  static DebugConversationSeed createOversizedConversation({
    required String title,
    required String? assistantId,
    required String chunkText,
    int targetBytes = oversizedConversationBytes,
  }) {
    if (targetBytes <= 0) {
      throw ArgumentError.value(targetBytes, 'targetBytes');
    }
    if (chunkText.isEmpty) {
      throw ArgumentError.value(chunkText, 'chunkText');
    }

    final conversation = Conversation(title: title, assistantId: assistantId);
    final messages = <ChatMessage>[];
    var totalBytes = 0;
    var index = 0;
    const uuid = Uuid();

    while (totalBytes < targetBytes) {
      final role = index.isEven ? 'user' : 'assistant';
      final messageId = uuid.v4();
      final content = _buildOversizedContent(
        chunkText: chunkText,
        index: index,
        role: role,
      );
      totalBytes += utf8.encode(content).length;
      messages.add(
        ChatMessage(
          id: messageId,
          role: role,
          content: content,
          conversationId: conversation.id,
          groupId: messageId,
        ),
      );
      index++;
    }

    conversation.messageIds
      ..clear()
      ..addAll(messages.map((message) => message.id));
    conversation.updatedAt = DateTime.now();

    return DebugConversationSeed(
      conversation: conversation,
      messages: messages,
      totalContentBytes: totalBytes,
    );
  }

  static DebugConversationSeed createManyMessagesConversation({
    required String title,
    required String? assistantId,
    required String Function(int index, String role) contentBuilder,
    int messageCount = manyMessagesCount,
  }) {
    if (messageCount <= 0) {
      throw ArgumentError.value(messageCount, 'messageCount');
    }

    final conversation = Conversation(title: title, assistantId: assistantId);
    final messages = <ChatMessage>[];
    var totalBytes = 0;
    const uuid = Uuid();

    for (var index = 0; index < messageCount; index++) {
      final role = index.isEven ? 'user' : 'assistant';
      final messageId = uuid.v4();
      final content = contentBuilder(index, role);
      totalBytes += utf8.encode(content).length;
      messages.add(
        ChatMessage(
          id: messageId,
          role: role,
          content: content,
          conversationId: conversation.id,
          groupId: messageId,
        ),
      );
    }

    conversation.messageIds
      ..clear()
      ..addAll(messages.map((message) => message.id));
    conversation.updatedAt = DateTime.now();

    return DebugConversationSeed(
      conversation: conversation,
      messages: messages,
      totalContentBytes: totalBytes,
    );
  }

  static DebugConversationSeed createLongReasoningConversation({
    required String title,
    required String? assistantId,
    int messageCount = longReasoningMessagesCount,
  }) {
    if (messageCount <= 0) {
      throw ArgumentError.value(messageCount, 'messageCount');
    }

    final conversation = Conversation(title: title, assistantId: assistantId);
    final messages = <ChatMessage>[];
    var totalBytes = 0;
    const uuid = Uuid();
    final baseTime = DateTime.now();

    for (var index = 0; index < messageCount; index++) {
      final role = index.isEven ? 'user' : 'assistant';
      final messageId = uuid.v4();
      final timestamp = baseTime.add(Duration(seconds: index));
      final content = role == 'user'
          ? _buildReasoningUserContent(index)
          : _buildReasoningAssistantContent(index);
      final reasoningText = role == 'assistant'
          ? _buildReasoningText(index)
          : null;
      final reasoningStartAt = reasoningText == null
          ? null
          : timestamp.subtract(const Duration(seconds: 18));
      final reasoningFinishedAt = reasoningText == null
          ? null
          : timestamp.subtract(const Duration(seconds: 2));
      final reasoningSegmentsJson = reasoningText == null
          ? null
          : _buildReasoningSegmentsJson(
              reasoningText: reasoningText,
              startAt: reasoningStartAt!,
              finishedAt: reasoningFinishedAt!,
              expanded: index < messageCount - 16,
            );

      totalBytes += utf8.encode(content).length;
      if (reasoningText != null) {
        totalBytes += utf8.encode(reasoningText).length;
      }
      messages.add(
        ChatMessage(
          id: messageId,
          role: role,
          content: content,
          timestamp: timestamp,
          conversationId: conversation.id,
          groupId: messageId,
          reasoningText: reasoningText,
          reasoningStartAt: reasoningStartAt,
          reasoningFinishedAt: reasoningFinishedAt,
          reasoningSegmentsJson: reasoningSegmentsJson,
        ),
      );
    }

    conversation.messageIds
      ..clear()
      ..addAll(messages.map((message) => message.id));
    conversation.updatedAt = DateTime.now();

    return DebugConversationSeed(
      conversation: conversation,
      messages: messages,
      totalContentBytes: totalBytes,
    );
  }

  static DebugConversationSeed createDailyMixedMarkdownConversation({
    required String title,
    required String? assistantId,
    int messageCount = dailyMixedMarkdownMessagesCount,
  }) {
    if (messageCount <= 0) {
      throw ArgumentError.value(messageCount, 'messageCount');
    }

    return createManyMessagesConversation(
      title: title,
      assistantId: assistantId,
      messageCount: messageCount,
      contentBuilder: (index, role) => role == 'user'
          ? _buildDailyUserMarkdownContent(index)
          : _buildDailyAssistantMarkdownContent(index),
    );
  }

  static String _buildOversizedContent({
    required String chunkText,
    required int index,
    required String role,
  }) {
    final buffer = StringBuffer()
      ..writeln('debug-message-index: $index')
      ..writeln('debug-message-role: $role');
    for (var block = 0; block < 128; block++) {
      buffer
        ..write(chunkText)
        ..write(' index=')
        ..write(index)
        ..write(' block=')
        ..write(block)
        ..write('\n');
    }
    return buffer.toString();
  }

  static String _buildReasoningUserContent(int index) {
    final turn = (index ~/ 2) + 1;
    return [
      'Debug long reasoning prompt #$turn.',
      'Please answer with a visible final answer after extended thinking.',
      'Keep enough detail to exercise long conversation history replay.',
    ].join('\n');
  }

  static String _buildDailyUserMarkdownContent(int index) {
    final turn = (index ~/ 2) + 1;
    switch (turn % 6) {
      case 0:
        return [
          "Round $turn: help me organize today's tasks, prioritizing work and personal items.",
          '',
          '- [ ] Reply to product review feedback',
          '- [ ] Confirm the travel budget before 8 PM',
          '- [ ] Reduce the meeting notes to 3 conclusions',
        ].join('\n');
      case 1:
        return [
          'Can you review this Markdown note from my daily work?',
          '',
          '## Context $turn',
          '',
          '| Item | Status | Owner |',
          '| --- | --- | --- |',
          '| API retry | blocked | me |',
          '| UI copy | ready | design |',
        ].join('\n');
      case 2:
        return [
          'Explain why this code occasionally submits twice:',
          '',
          '```dart',
          'if (isSending) return;',
          'isSending = true;',
          'await submitMessage(input);',
          'isSending = false;',
          '```',
        ].join('\n');
      case 3:
        return [
          'Summarize this shopping comparison in Chinese:',
          '',
          '1. Keyboard: quiet switches, compact layout.',
          '2. Monitor light: needs USB-C power.',
          '3. SSD enclosure: check heat during long copies.',
          '',
          '> I want a practical answer, not a long review.',
        ].join('\n');
      case 4:
        return [
          "Today's workout log:",
          '',
          '- Run for 32 minutes',
          '- 4 sets of squats',
          '- Only 6 hours of sleep',
          '',
          'Give me a **not overly aggressive** plan for tomorrow.',
        ].join('\n');
      default:
        return [
          'Draft a short reply for this message:',
          '',
          '```text',
          'Thanks for the update. Could we move the sync to Thursday?',
          'I need one more day to finish the migration checks.',
          '```',
        ].join('\n');
    }
  }

  static String _buildDailyAssistantMarkdownContent(int index) {
    final turn = (index ~/ 2) + 1;
    switch (turn % 6) {
      case 0:
        return [
          'Sure. Rank them by impact:',
          '',
          '1. Handle product review feedback that blocks other people first.',
          '2. Set only a ceiling for the travel budget instead of turning it into a full itinerary.',
          '3. Keep conclusions, owners, and deadlines in the meeting notes.',
          '',
          '- [x] Set priorities',
          '- [ ] Wait for specific times',
        ].join('\n');
      case 1:
        return [
          'Here is the cleaned version:',
          '',
          '## Daily Status',
          '',
          '| Area | Next step | Risk |',
          '| --- | --- | --- |',
          '| API retry | Confirm idempotency key | duplicate writes |',
          '| UI copy | Ship current draft | low |',
        ].join('\n');
      case 2:
        return [
          'The issue usually occurs on the exception path: if `submitMessage` throws, `isSending` is not reset.',
          '',
          '```dart',
          'if (isSending) return;',
          'isSending = true;',
          'try {',
          '  await submitMessage(input);',
          '} finally {',
          '  isSending = false;',
          '}',
          '```',
        ].join('\n');
      case 3:
        return [
          'I would decide like this:',
          '',
          '- **Keyboard**: prioritize it if you type more than 4 hours a day.',
          '- **Monitor light**: buy it after confirming power and desk space.',
          '- **Drive enclosure**: upgrade only if you frequently copy large files.',
          '',
          '> Conclusion: buy the keyboard first and postpone the other two.',
        ].join('\n');
      case 4:
        return [
          "Tomorrow's plan should be conservative:",
          '',
          '- Easy run for 20 minutes or brisk walk for 35 minutes',
          '- Reduce lower-body strength work to 2 sets',
          '- Target 7.5 hours of sleep',
          '',
          'Prioritize recovery, not more volume.',
        ].join('\n');
      default:
        return [
          'You could reply:',
          '',
          '```text',
          'Thursday works for me. I will use the extra day to finish the',
          'migration checks and send a concise status before the sync.',
          '```',
          '',
          'This keeps the tone direct and accountable.',
        ].join('\n');
    }
  }

  static String _buildReasoningAssistantContent(int index) {
    final turn = (index ~/ 2) + 1;
    return [
      'Debug answer #$turn.',
      '',
      'Summary:',
      '- The requested scenario was analyzed against earlier turns.',
      '- The final answer stays short while the reasoning payload is stored separately.',
      '- This message intentionally keeps structured reasoning metadata.',
    ].join('\n');
  }

  static String _buildReasoningText(int index) {
    final turn = (index ~/ 2) + 1;
    final buffer = StringBuffer()
      ..writeln('Debug reasoning chain for assistant turn #$turn.')
      ..writeln('1. Inspect the recent user request and retained context.')
      ..writeln('2. Compare it with previous constraints and generated state.')
      ..writeln('3. Decide whether the final answer needs a concise response.');
    for (var step = 0; step < 12; step++) {
      buffer.writeln(
        'Reasoning detail $step for turn $turn: repeated diagnostic content '
        'keeps this block large enough to reproduce long-chat rendering and '
        'persistence behavior without calling a real provider.',
      );
    }
    return buffer.toString().trimRight();
  }

  static String _buildReasoningSegmentsJson({
    required String reasoningText,
    required DateTime startAt,
    required DateTime finishedAt,
    required bool expanded,
  }) {
    return jsonEncode({
      'v': 2,
      'segments': [
        {
          'text': reasoningText,
          'startAt': startAt.toIso8601String(),
          'finishedAt': finishedAt.toIso8601String(),
          'expanded': expanded,
          'toolStartIndex': 0,
        },
      ],
      'contentSplits': {
        'offsets': [0],
        'reasoningCounts': [1],
        'toolCounts': [0],
      },
    });
  }
}
