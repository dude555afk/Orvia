import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Versioned transfer container shared by Flutter Orvia and the native app.
///
/// This class only validates and packages byte entries. It deliberately does
/// not read a live database or import into either application's database.
final class NativeTransferArchive {
  NativeTransferArchive._();

  static const formatId = 'orvia.native-transfer';
  static const formatVersion = 1;
  static const manifestPath = 'manifest.json';

  // The first implementation is intentionally bounded because ZIP encoding
  // currently buffers its input and output. A future streaming writer can
  // raise these limits without changing the archive format.
  static const maxArchiveBytes = 64 * 1024 * 1024;
  static const maxTotalEntryBytes = 128 * 1024 * 1024;
  static const maxSingleEntryBytes = 32 * 1024 * 1024;
  static const maxEntries = 10000;

  static Uint8List encode({
    required String sourceAppVersion,
    required int sourceSchemaVersion,
    required DateTime exportedAt,
    required Map<String, int> entityCounts,
    required List<String> unsupportedRecords,
    required Map<String, List<int>> entries,
  }) {
    _validateMetadata(
      sourceAppVersion: sourceAppVersion,
      sourceSchemaVersion: sourceSchemaVersion,
      entityCounts: entityCounts,
      unsupportedRecords: unsupportedRecords,
    );
    if (entries.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'must not be empty');
    }
    if (entries.length > maxEntries) {
      throw StateError('native_transfer_entry_count_limit');
    }

    var totalBytes = 0;
    final payloads = <String, Uint8List>{};
    final descriptors = <String, Object>{};
    for (final entry in entries.entries) {
      _validateEntryPath(entry.key);
      if (entry.key == manifestPath) {
        throw ArgumentError.value(entry.key, 'entries', 'manifest is reserved');
      }
      if (payloads.containsKey(entry.key)) {
        throw ArgumentError.value(entry.key, 'entries', 'duplicate path');
      }
      final bytes = Uint8List.fromList(entry.value);
      _validateEntrySize(entry.key, bytes.length);
      totalBytes += bytes.length;
      if (totalBytes > maxTotalEntryBytes) {
        throw StateError('native_transfer_total_size_limit');
      }
      payloads[entry.key] = bytes;
      descriptors[entry.key] = <String, Object>{
        'sha256': sha256.convert(bytes).toString(),
        'sizeBytes': bytes.length,
      };
    }

    final manifest = <String, Object>{
      'format': formatId,
      'version': formatVersion,
      'sourceAppVersion': sourceAppVersion.trim(),
      'sourceSchemaVersion': sourceSchemaVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'entityCounts': entityCounts,
      'unsupportedRecords': unsupportedRecords,
      'entries': descriptors,
    };
    final archive = Archive();
    for (final entry in payloads.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    _validateEntrySize(manifestPath, manifestBytes.length);
    if (totalBytes + manifestBytes.length > maxTotalEntryBytes) {
      throw StateError('native_transfer_total_size_limit');
    }
    archive.addFile(
      ArchiveFile(manifestPath, manifestBytes.length, manifestBytes),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded.length > maxArchiveBytes) {
      throw StateError('native_transfer_archive_size_limit');
    }
    return Uint8List.fromList(encoded);
  }

  static NativeTransferArchiveContents decode(List<int> zipBytes) {
    if (zipBytes.isEmpty || zipBytes.length > maxArchiveBytes) {
      throw StateError('native_transfer_archive_size_limit');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (_) {
      throw const FormatException('native_transfer_archive_invalid');
    }
    if (archive.files.isEmpty || archive.files.length > maxEntries + 1) {
      throw const FormatException('native_transfer_entry_count_invalid');
    }

    final files = <String, Uint8List>{};
    var totalBytes = 0;
    for (final file in archive.files) {
      // Transfer archives contain flat files only. Directory entries, links,
      // and special ZIP entries are unnecessary and fail closed.
      if (!file.isFile) {
        throw const FormatException('native_transfer_entry_type_invalid');
      }
      _validateEntryPath(file.name);
      if (files.containsKey(file.name)) {
        throw const FormatException('native_transfer_duplicate_entry');
      }
      _validateEntrySize(file.name, file.size);
      totalBytes += file.size;
      if (totalBytes > maxTotalEntryBytes) {
        throw StateError('native_transfer_total_size_limit');
      }
      final content = file.content;
      if (content is! List<int> || content.length != file.size) {
        throw const FormatException('native_transfer_entry_content_invalid');
      }
      files[file.name] = Uint8List.fromList(content);
    }

    final manifestBytes = files.remove(manifestPath);
    if (manifestBytes == null) {
      throw const FormatException('native_transfer_manifest_missing');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(manifestBytes));
    } catch (_) {
      throw const FormatException('native_transfer_manifest_invalid');
    }
    if (decoded is! Map) {
      throw const FormatException('native_transfer_manifest_invalid');
    }
    final manifest = Map<String, Object?>.from(decoded);
    _validateManifest(manifest, files);
    return NativeTransferArchiveContents(
      manifest: Map<String, Object?>.unmodifiable(manifest),
      entries: Map<String, Uint8List>.unmodifiable(files),
    );
  }

  static void _validateManifest(
    Map<String, Object?> manifest,
    Map<String, Uint8List> files,
  ) {
    if (manifest['format'] != formatId ||
        manifest['version'] != formatVersion) {
      throw const FormatException('native_transfer_format_unsupported');
    }
    final appVersion = manifest['sourceAppVersion'];
    final schemaVersion = manifest['sourceSchemaVersion'];
    final exportedAt = manifest['exportedAt'];
    final counts = manifest['entityCounts'];
    final unsupported = manifest['unsupportedRecords'];
    final descriptors = manifest['entries'];
    if (appVersion is! String ||
        appVersion.trim().isEmpty ||
        appVersion.length > 64 ||
        schemaVersion is! int ||
        schemaVersion < 1 ||
        exportedAt is! String ||
        DateTime.tryParse(exportedAt) == null ||
        counts is! Map ||
        unsupported is! List ||
        unsupported.any(
          (item) => item is! String || item.trim().isEmpty || item.length > 512,
        ) ||
        descriptors is! Map ||
        descriptors.length > maxEntries) {
      throw const FormatException('native_transfer_manifest_invalid');
    }

    final entityCounts = <String, int>{};
    for (final entry in counts.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).length > 128 ||
          entry.value is! int ||
          (entry.value as int) < 0) {
        throw const FormatException('native_transfer_entity_counts_invalid');
      }
      entityCounts[entry.key as String] = entry.value as int;
    }

    final declaredPaths = <String>{};
    for (final entry in descriptors.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('native_transfer_entry_manifest_invalid');
      }
      final path = entry.key as String;
      _validateEntryPath(path);
      final descriptor = Map<String, Object?>.from(entry.value as Map);
      final expectedHash = descriptor['sha256'];
      final expectedSize = descriptor['sizeBytes'];
      if (expectedHash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash) ||
          expectedSize is! int ||
          expectedSize < 0 ||
          !declaredPaths.add(path)) {
        throw const FormatException('native_transfer_entry_manifest_invalid');
      }
      final actual = files[path];
      if (actual == null ||
          actual.length != expectedSize ||
          sha256.convert(actual).toString() != expectedHash) {
        throw const FormatException('native_transfer_entry_integrity_failed');
      }
    }
    if (declaredPaths.length != files.length ||
        !declaredPaths.containsAll(files.keys)) {
      throw const FormatException('native_transfer_entry_set_mismatch');
    }
  }

  static void _validateMetadata({
    required String sourceAppVersion,
    required int sourceSchemaVersion,
    required Map<String, int> entityCounts,
    required List<String> unsupportedRecords,
  }) {
    if (sourceAppVersion.trim().isEmpty || sourceAppVersion.length > 64) {
      throw ArgumentError.value(sourceAppVersion, 'sourceAppVersion');
    }
    if (sourceSchemaVersion < 1) {
      throw ArgumentError.value(sourceSchemaVersion, 'sourceSchemaVersion');
    }
    for (final entry in entityCounts.entries) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 128 ||
          entry.value < 0) {
        throw ArgumentError.value(entry, 'entityCounts');
      }
    }
    for (final item in unsupportedRecords) {
      if (item.trim().isEmpty || item.length > 512) {
        throw ArgumentError.value(item, 'unsupportedRecords');
      }
    }
  }

  static void _validateEntrySize(String path, int size) {
    if (size < 0 || size > maxSingleEntryBytes) {
      throw StateError('native_transfer_entry_size_limit:$path');
    }
  }

  static void _validateEntryPath(String path) {
    if (path.isEmpty ||
        path.length > 512 ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        path.contains('\\') ||
        path.contains(':') ||
        path.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw const FormatException('native_transfer_entry_path_invalid');
    }
    final segments = path.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('native_transfer_entry_path_invalid');
    }

    final allowed =
        path == 'assistants.json' ||
        path == 'providers.json' ||
        path == 'settings.json' ||
        RegExp(r'^conversations/[A-Za-z0-9_-]{1,128}\.json$').hasMatch(path) ||
        RegExp(r'^business-data/[a-z][a-z0-9_-]{0,63}\.json$').hasMatch(path) ||
        RegExp(r'^assets/[0-9a-f]{64}$').hasMatch(path);
    if (!allowed) {
      throw const FormatException('native_transfer_entry_path_unsupported');
    }
  }
}

final class NativeTransferArchiveContents {
  const NativeTransferArchiveContents({
    required this.manifest,
    required this.entries,
  });

  final Map<String, Object?> manifest;
  final Map<String, Uint8List> entries;
}
