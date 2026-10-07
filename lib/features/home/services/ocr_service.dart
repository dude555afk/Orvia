import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/retry_policy.dart';

/// OCR \u7F13\u5B58\u6761\u76EE
class OcrCacheEntry {
  OcrCacheEntry({required this.text});
  final String text;
}

/// Per-prepare OCR state that is not bounded by the process LRU.
///
/// Each concurrent conversation prepare owns its own session so snapshots cannot
/// overwrite each other.
class OcrPrepareSession {
  final Map<String, String> hashesByPath = <String, String>{};
  final Map<String, String> artifactTextsByHash = <String, String>{};
  final Map<String, Map<String, String>> artifactsByRevision =
      <String, Map<String, String>>{};
  final Set<String> loadedRevisionIds = <String>{};

  int get artifactSize => artifactTextsByHash.length;
}

/// OCR Image\u5904\u7406\u670D\u52A1
///
/// \u529F\u80FD：
/// - \u8FD0\u884C OCR \u8BC6\u522BImage\u5185\u5BB9
/// - \u7BA1\u7406 OCR \u7F13\u5B58（\u5185\u5B58 LRU → \u8BF7\u6C42\u7EA7 artifact \u5FEB\u7167 → SQLite → OCR \u6A21\u578B）
/// - \u5305\u88C5 OCR \u7ED3\u679C\u4E3A XML \u683C\u5F0F
class OcrService {
  OcrService({
    this.maxCacheEntries = 48,
    this.resolveContentHashes,
    this.loadArtifacts,
    this.persistArtifact,
    this.ocrExecutor,
    this.onError,
  });

  static const String artifactKind = 'image_ocr_v1';
  static const String memoryKeyPrefix = 'image_ocr_v1:';
  static const String defaultOcrUserPrompt =
      'Please perform OCR on the attached image(s) and return only the extracted text and visual descriptions.';

  /// LRU \u7F13\u5B58\u6700\u5927\u6761\u76EE\u6570
  final int maxCacheEntries;

  /// Resolve image path/data-URL → content SHA-256.
  final Future<Map<String, String>> Function(List<String> imagePaths)?
  resolveContentHashes;

  /// Batch-load persisted OCR items by revision ID.
  final Future<Map<String, Map<String, String>>> Function(
    List<String> revisionIds,
  )?
  loadArtifacts;

  /// Persist OCR items for a revision (merged upsert). Failures must not throw
  /// to callers that already have OCR text for the current request.
  final Future<void> Function(String revisionId, Map<String, String> items)?
  persistArtifact;

  /// Optional OCR backend override (tests). When null, uses ChatApiService.
  final Future<String?> Function(List<String> imagePaths)? ocrExecutor;

  /// Reports OCR model request failures without interrupting the chat request.
  void Function(Object error)? onError;

  /// OCR \u7F13\u5B58 (memoryKey -> cached OCR text)
  final Map<String, OcrCacheEntry> _cache = <String, OcrCacheEntry>{};

  /// LRU \u987A\u5E8F\u5217\u8868 (\u6700\u65E7\u7684\u5728\u524D)
  final List<String> _cacheOrder = <String>[];

  /// \u83B7\u53D6\u7F13\u5B58\u6761\u76EE\u6570\u91CF（\u7528\u4E8E\u6D4B\u8BD5/\u8C03\u8BD5）
  int get cacheSize => _cache.length;

  /// \u6E05\u9664\u7F13\u5B58
  void clearCache() {
    _cache.clear();
    _cacheOrder.clear();
  }

  static String memoryKeyForContentHash(String contentHash) {
    return '$memoryKeyPrefix$contentHash';
  }

  /// \u6784\u5EFA\u53D1\u7ED9 OCR \u6A21\u578B\u7684\u6D88\u606F。\u63D0\u793A\u8BCD\u4E3A\u7A7A\u65F6\u4E0D\u9644\u52A0 system，\u4EE5\u517C\u5BB9 GLM-OCR \u7B49\u4E13\u7528\u63A5\u53E3。
  static List<Map<String, dynamic>> buildOcrRequestMessages(String prompt) {
    final trimmed = prompt.trim();
    return <Map<String, dynamic>>[
      if (trimmed.isNotEmpty) {'role': 'system', 'content': trimmed},
      {'role': 'user', 'content': defaultOcrUserPrompt},
    ];
  }

  /// \u8FD0\u884C OCR \u8BC6\u522BImage\u5185\u5BB9
  ///
  /// [imagePaths] Image\u8DEF\u5F84\u5217\u8868
  /// [context] BuildContext \u7528\u4E8E\u83B7\u53D6 SettingsProvider
  /// [requestId] conversation send id; Stop cancels this OCR request too
  ///
  /// \u8FD4\u56DE\u8BC6\u522B\u7684\u6587\u672C\u5185\u5BB9，\u5931\u8D25\u65F6\u8FD4\u56DE null
  Future<String?> runOcrForImages(
    List<String> imagePaths,
    BuildContext context, {
    String? requestId,
  }) async {
    if (imagePaths.isEmpty) return null;
    if (ocrExecutor != null) {
      try {
        final out = (await ocrExecutor!(imagePaths))?.trim();
        return (out == null || out.isEmpty) ? null : out;
      } catch (e) {
        if (isUserCancelError(e)) rethrow;
        onError?.call(e);
        return null;
      }
    }

    final settings = context.read<SettingsProvider>();
    final prov = settings.ocrModelProvider;
    final model = settings.ocrModelId;
    if (prov == null || model == null) return null;

    final cfg = settings.getProviderConfig(prov);

    final messages = buildOcrRequestMessages(settings.ocrPrompt);

    String out = '';
    try {
      final result = await ChatApiService.generateMessage(
        conversationId: requestId,
        config: cfg,
        modelId: model,
        messages: messages,
        userImagePaths: imagePaths,
        reasoning: settings.ocrGenerationReasoningFor(null),
        ocrActive: true,
        requestId: requestId,
      );
      out = result.text;
    } catch (e) {
      if (isUserCancelError(e)) rethrow;
      onError?.call(e);
      return null;
    }
    out = out.trim();
    if (out.isEmpty) {
      onError?.call('empty_response');
      return null;
    }
    return out;
  }

  /// \u7F13\u5B58 OCR \u6587\u672C\u7ED3\u679C（\u6309\u5185\u5BB9\u54C8\u5E0C）
  void cacheOcrText(String contentHash, String text) {
    final hash = contentHash.trim();
    if (hash.isEmpty) return;
    final key = memoryKeyForContentHash(hash);

    _cache[key] = OcrCacheEntry(text: text);
    _cacheOrder.remove(key);
    _cacheOrder.add(key);

    // LRU \u6DD8\u6C70：\u79FB\u9664\u6700\u65E7\u7684\u6761\u76EE
    while (_cacheOrder.length > maxCacheEntries) {
      final oldest = _cacheOrder.removeAt(0);
      _cache.remove(oldest);
    }
  }

  /// \u83B7\u53D6\u7F13\u5B58\u7684 OCR \u6587\u672C
  ///
  /// \u8FD4\u56DE\u7F13\u5B58\u7684\u6587\u672C，\u4E0D\u5B58\u5728\u65F6\u8FD4\u56DE null
  /// \u8BBF\u95EE\u65F6\u4F1A\u66F4\u65B0 LRU \u987A\u5E8F
  String? getCachedOcrText(String contentHash) {
    final hash = contentHash.trim();
    if (hash.isEmpty) return null;
    final key = memoryKeyForContentHash(hash);

    final entry = _cache[key];
    if (entry != null) {
      // bump to most-recent
      _cacheOrder.remove(key);
      _cacheOrder.add(key);
      return entry.text;
    }
    return null;
  }

  String? _lookupCachedText(String contentHash, OcrPrepareSession? session) {
    final sessionText = session?.artifactTextsByHash[contentHash]?.trim();
    if (sessionText != null && sessionText.isNotEmpty) return sessionText;
    final memoryText = getCachedOcrText(contentHash)?.trim();
    if (memoryText != null && memoryText.isNotEmpty) return memoryText;
    return null;
  }

  void _rememberRequestText(
    String contentHash,
    String text,
    OcrPrepareSession? session,
  ) {
    final hash = contentHash.trim();
    final trimmed = text.trim();
    if (hash.isEmpty || trimmed.isEmpty) return;
    if (session != null) {
      session.artifactTextsByHash[hash] = trimmed;
    }
    cacheOcrText(hash, trimmed);
  }

  /// Prefetch hashes + SQLite OCR for one prepare/send pass.
  ///
  /// Returns an isolated session owned by the caller. Concurrent prepares must
  /// not share this object.
  Future<OcrPrepareSession> prefetchPersistedOcr({
    required List<String> revisionIds,
    required List<String> imagePaths,
  }) async {
    final session = OcrPrepareSession();

    final paths = <String>[
      ...{
        for (final path in imagePaths)
          if (path.trim().isNotEmpty) path.trim(),
      },
    ];
    if (paths.isNotEmpty && resolveContentHashes != null) {
      try {
        session.hashesByPath.addAll(await resolveContentHashes!(paths));
      } catch (_) {}
    }

    final ids = revisionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    session.loadedRevisionIds.addAll(ids);

    if (ids.isEmpty || loadArtifacts == null) return session;

    Map<String, Map<String, String>> artifacts;
    try {
      artifacts = await loadArtifacts!(ids);
    } catch (_) {
      return session;
    }

    for (final entry in artifacts.entries) {
      final revisionItems = <String, String>{};
      for (final item in entry.value.entries) {
        final hash = item.key.trim();
        final text = item.value.trim();
        if (hash.isEmpty || text.isEmpty) continue;
        revisionItems[hash] = text;
        session.artifactTextsByHash[hash] = text;
        cacheOcrText(hash, text);
      }
      if (revisionItems.isNotEmpty) {
        session.artifactsByRevision[entry.key] = revisionItems;
      }
    }
    return session;
  }

  /// \u83B7\u53D6Image\u7684 OCR \u6587\u672C（\u4F18\u5148\u4F7F\u7528\u7F13\u5B58）
  ///
  /// [imagePaths] Image\u8DEF\u5F84\u5217\u8868
  /// [context] BuildContext \u7528\u4E8E\u83B7\u53D6 SettingsProvider
  /// [revisionId] \u5E26\u56FE user \u6D88\u606F revision，\u7528\u4E8E SQLite \u6301\u4E45\u5316
  /// [session] optional per-prepare snapshot from [prefetchPersistedOcr]
  /// [requestId] conversation send id so chat Stop also cancels OCR backoff
  ///
  /// \u8FD4\u56DE\u5408\u5E76\u540E\u7684 OCR \u6587\u672C，\u5931\u8D25\u65F6\u8FD4\u56DE null
  Future<String?> getOcrTextForImages(
    List<String> imagePaths,
    BuildContext context, {
    String? revisionId,
    OcrPrepareSession? session,
    String? requestId,
  }) async {
    if (imagePaths.isEmpty) return null;

    // Test doubles inject ocrExecutor and skip SettingsProvider wiring.
    if (ocrExecutor == null) {
      final settings = context.read<SettingsProvider>();
      if (!(settings.ocrEnabled &&
          settings.ocrModelProvider != null &&
          settings.ocrModelId != null)) {
        return null;
      }
    }

    final paths = imagePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return null;

    final hashesByPath = <String, String>{};
    final unresolved = <String>[];
    for (final path in paths) {
      final cachedHash = session?.hashesByPath[path]?.trim();
      if (cachedHash != null && cachedHash.isNotEmpty) {
        hashesByPath[path] = cachedHash;
      } else if (!unresolved.contains(path)) {
        unresolved.add(path);
      }
    }
    if (unresolved.isNotEmpty && resolveContentHashes != null) {
      try {
        final resolved = await resolveContentHashes!(unresolved);
        for (final entry in resolved.entries) {
          final hash = entry.value.trim();
          if (hash.isEmpty) continue;
          hashesByPath[entry.key] = hash;
          session?.hashesByPath[entry.key] = hash;
        }
      } catch (_) {}
    }

    final normalizedRevisionId = revisionId?.trim();
    final hasRevision =
        normalizedRevisionId != null && normalizedRevisionId.isNotEmpty;

    // Only hit SQLite here when this revision was not part of the batch prefetch.
    if (hasRevision &&
        loadArtifacts != null &&
        (session == null ||
            !session.loadedRevisionIds.contains(normalizedRevisionId))) {
      try {
        final artifacts = await loadArtifacts!([normalizedRevisionId]);
        final items = artifacts[normalizedRevisionId] ?? const {};
        session?.loadedRevisionIds.add(normalizedRevisionId);
        if (items.isNotEmpty) {
          final revisionItems = <String, String>{
            for (final entry in items.entries)
              if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
                entry.key.trim(): entry.value.trim(),
          };
          if (revisionItems.isNotEmpty) {
            session?.artifactsByRevision[normalizedRevisionId] = {
              ...session.artifactsByRevision[normalizedRevisionId] ?? const {},
              ...revisionItems,
            };
            for (final entry in revisionItems.entries) {
              _rememberRequestText(entry.key, entry.value, session);
            }
          }
        }
      } catch (_) {}
    }

    final existingForRevision = hasRevision
        ? <String, String>{
            ...session?.artifactsByRevision[normalizedRevisionId] ?? const {},
          }
        : const <String, String>{};

    final combined = StringBuffer();
    final toPersist = <String, String>{};

    for (final path in paths) {
      final hash = hashesByPath[path]?.trim();
      if (hash != null && hash.isNotEmpty) {
        final cached = _lookupCachedText(hash, session);
        if (cached != null) {
          combined.writeln(cached);
          _rememberRequestText(hash, cached, session);
          if (hasRevision && !existingForRevision.containsKey(hash)) {
            toPersist[hash] = cached;
          }
          continue;
        }
      }

      if (!context.mounted) break;
      final text = await runOcrForImages([path], context, requestId: requestId);
      if (text != null && text.trim().isNotEmpty) {
        final t = text.trim();
        if (hash != null && hash.isNotEmpty) {
          _rememberRequestText(hash, t, session);
          if (hasRevision) {
            toPersist[hash] = t;
          }
        }
        combined.writeln(t);
      }
    }

    if (toPersist.isNotEmpty && hasRevision && persistArtifact != null) {
      try {
        await persistArtifact!(normalizedRevisionId, toPersist);
        if (session != null) {
          session.artifactsByRevision[normalizedRevisionId] = {
            ...session.artifactsByRevision[normalizedRevisionId] ?? const {},
            ...toPersist,
          };
        }
      } catch (_) {
        // Persistence failure must not block the current chat turn.
      }
    }

    final out = combined.toString().trim();
    return out.isEmpty ? null : out;
  }

  /// \u5305\u88C5 OCR \u6587\u672C\u4E3A XML \u683C\u5F0F
  ///
  /// [ocrText] OCR \u8BC6\u522B\u7684\u539F\u59CB\u6587\u672C
  ///
  /// \u8FD4\u56DE\u5305\u88C5\u540E\u7684 XML \u683C\u5F0F\u6587\u672C
  String wrapOcrBlock(String ocrText) {
    final buf = StringBuffer();
    buf.writeln(
      "The image_file_ocr tag contains a description of an image that the user uploaded to you, not the user's prompt.",
    );
    buf.writeln('<image_file_ocr>');
    buf.writeln(ocrText.trim());
    buf.writeln('</image_file_ocr>');
    buf.writeln();
    return buf.toString();
  }
}
