import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/retry_policy.dart';
import '../../../core/services/api/stream/stream_chunk.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../settings/widgets/language_select_sheet.dart';

/// Translation\u7ED3\u679C\u7C7B\u578B
enum TranslationResultType {
  /// Translation\u6210\u529F
  success,

  /// \u7528\u6237\u9009\u62E9\u6E05\u9664Translation
  cleared,

  /// \u7528\u6237\u53D6\u6D88\u9009\u62E9\u8BED\u8A00
  cancelled,

  /// \u672A\u914D\u7F6ETranslation\u6A21\u578B
  noModelConfigured,

  /// Translation\u51FA\u9519
  error,
}

/// Translation\u7ED3\u679C
class TranslationResult {
  TranslationResult({required this.type, this.errorMessage});

  final TranslationResultType type;
  final String? errorMessage;

  bool get isSuccess => type == TranslationResultType.success;
  bool get isCleared => type == TranslationResultType.cleared;
  bool get isCancelled => type == TranslationResultType.cancelled;
}

/// True when [runToken] is still the in-flight translation for this message.
@visibleForTesting
bool translationRunIsCurrent(Object runToken, Object? currentToken) =>
    identical(currentToken, runToken);

@visibleForTesting
String translationRequestId(String messageId) => 'translate-msg-$messageId';

/// Replaces any in-flight run so the old token no longer owns UI/DB writes.
@visibleForTesting
Object supersedeTranslationRun(Map<String, Object> runs, String messageId) {
  final token = Object();
  runs[messageId] = token;
  return token;
}

/// True when a failed translation should clear UI/DB and report an error.
@visibleForTesting
bool shouldApplyTranslationFailure({
  required Object runToken,
  required Object? currentToken,
  required Object error,
}) {
  if (!translationRunIsCurrent(runToken, currentToken)) return false;
  return !isUserCancelError(error);
}

/// \u6D88\u606FTranslation\u670D\u52A1
///
/// \u529F\u80FD：
/// - \u663E\u793A\u8BED\u8A00\u9009\u62E9\u5668
/// - \u8C03\u7528Translation API
/// - \u6D41\u5F0F\u66F4\u65B0Translation\u7ED3\u679C
/// - \u4FDD\u5B58Translation\u5230\u6570\u636E\u5E93
class TranslationService {
  TranslationService({required this.chatService, required this._getContext});

  final ChatService chatService;
  final BuildContext Function() _getContext;
  final Map<String, Object> _runs = <String, Object>{};

  /// Translation\u6D88\u606F
  ///
  /// [message] \u8981Translation\u7684\u6D88\u606F
  /// [onTranslationStarted] Translation\u5F00\u59CB\u56DE\u8C03（\u7528\u6237\u9009\u62E9\u8BED\u8A00\u540E、\u5F00\u59CB\u8BF7\u6C42\u524D\u8C03\u7528）
  /// [onTranslationUpdate] Translation\u66F4\u65B0\u56DE\u8C03（\u7528\u4E8E\u5B9E\u65F6\u66F4\u65B0 UI）
  /// [onTranslationCleared] Translation\u6E05\u9664\u56DE\u8C03
  ///
  /// \u8FD4\u56DETranslation\u7ED3\u679C
  Future<TranslationResult> translateMessage({
    required ChatMessage message,
    required void Function() onTranslationStarted,
    required void Function(String translation) onTranslationUpdate,
    required void Function() onTranslationCleared,
  }) async {
    // Resolve a fresh context per call to avoid holding on to a stale BuildContext.
    final context = _getContext();
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // \u663E\u793A\u8BED\u8A00\u9009\u62E9\u5668
    final language = await showLanguageSelector(context);
    if (language == null) {
      return TranslationResult(type: TranslationResultType.cancelled);
    }

    // \u68C0\u67E5\u662F\u5426\u9009\u62E9\u6E05\u9664Translation
    if (language.code == '__clear__') {
      final clearToken = supersedeTranslationRun(_runs, message.id);
      ChatApiService.cancelRequest(translationRequestId(message.id));
      onTranslationCleared();
      await chatService.updateMessage(message.id, translation: '');
      if (identical(_runs[message.id], clearToken)) {
        _runs.remove(message.id);
      }
      return TranslationResult(type: TranslationResultType.cleared);
    }

    // \u83B7\u53D6Translation\u6A21\u578B\u914D\u7F6E，\u56DE\u9000\u987A\u5E8F：Translation\u4E13\u7528 -> \u52A9\u624B\u6A21\u578B -> \u5168\u5C40\u9ED8\u8BA4
    final translateProvider =
        settings.translateModelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final translateModelId =
        settings.translateModelId ??
        assistant?.chatModelId ??
        settings.currentModelId;

    if (translateProvider == null || translateModelId == null) {
      return TranslationResult(type: TranslationResultType.noModelConfigured);
    }

    // \u7528\u6237\u5DF2\u9009\u62E9\u8BED\u8A00\u4E14\u6A21\u578B\u914D\u7F6E\u6709\u6548，\u901A\u77E5\u5F00\u59CBTranslation
    onTranslationStarted();

    // \u63D0\u53D6\u8981Translation\u7684\u6587\u672C\u5185\u5BB9
    String textToTranslate = message.content;
    final runToken = Object();
    _runs[message.id] = runToken;

    try {
      // \u6784\u5EFATranslation prompt
      String prompt = settings.translatePrompt
          .replaceAll('{source_text}', textToTranslate)
          .replaceAll('{target_lang}', language.displayName);

      // \u521B\u5EFATranslation\u8BF7\u6C42
      final provider = settings.getProviderConfig(translateProvider);

      final translationStream = ChatApiService.sendMessageStream(
        conversationId: message.conversationId,
        config: provider,
        modelId: translateModelId,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        reasoning: settings.translateGenerationReasoningFor(assistant),
        requestId: translationRequestId(message.id),
        parseMarkdownImageLinks: settings.sendMarkdownImageLinksAsImages,
      );

      final buffer = StringBuffer();

      await for (final chunk in translationStream) {
        if (!translationRunIsCurrent(runToken, _runs[message.id])) {
          return TranslationResult(type: TranslationResultType.cancelled);
        }
        if (chunk is! TextDelta || chunk.text.isEmpty) continue;
        buffer.write(chunk.text);
        // \u5B9E\u65F6\u66F4\u65B0Translation
        onTranslationUpdate(buffer.toString());
      }

      if (!translationRunIsCurrent(runToken, _runs[message.id])) {
        return TranslationResult(type: TranslationResultType.cancelled);
      }

      // \u4FDD\u5B58\u6700\u7EC8Translation\u7ED3\u679C
      await chatService.updateMessage(
        message.id,
        translation: buffer.toString(),
      );

      return TranslationResult(type: TranslationResultType.success);
    } catch (e) {
      if (!shouldApplyTranslationFailure(
        runToken: runToken,
        currentToken: _runs[message.id],
        error: e,
      )) {
        return TranslationResult(type: TranslationResultType.cancelled);
      }
      // \u51FA\u9519\u65F6\u6E05\u9664Translation
      onTranslationCleared();
      await chatService.updateMessage(message.id, translation: '');

      return TranslationResult(
        type: TranslationResultType.error,
        errorMessage: e.toString(),
      );
    } finally {
      if (identical(_runs[message.id], runToken)) {
        _runs.remove(message.id);
      }
    }
  }
}
