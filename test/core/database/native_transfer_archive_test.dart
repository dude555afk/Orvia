import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/database/native_transfer_archive.dart';

void main() {
  group('NativeTransferArchive', () {
    Uint8List buildArchive({
      required Map<String, List<int>> entries,
      required Map<String, Object?> manifest,
    }) {
      final archive = Archive();
      for (final entry in entries.entries) {
        archive.addFile(
          ArchiveFile(
            entry.key,
            entry.value.length,
            Uint8List.fromList(entry.value),
          ),
        );
      }
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(
        ArchiveFile(
          NativeTransferArchive.manifestPath,
          manifestBytes.length,
          manifestBytes,
        ),
      );
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('round-trips payloads with manifest hashes and counts', () {
      final payload = utf8.encode('conversation payload');
      final zip = NativeTransferArchive.encode(
        sourceAppVersion: '1.3.18+98',
        sourceSchemaVersion: 3,
        exportedAt: DateTime.utc(2026, 11, 1, 12),
        entityCounts: const {'conversations': 1, 'assistants': 2},
        unsupportedRecords: const <String>[],
        entries: {'conversations/chat_01.json': payload},
      );

      final result = NativeTransferArchive.decode(zip);

      expect(result.entries.keys, contains('conversations/chat_01.json'));
      expect(
        utf8.decode(result.entries['conversations/chat_01.json']!),
        'conversation payload',
      );
      expect(result.manifest['format'], NativeTransferArchive.formatId);
      expect(result.manifest['version'], NativeTransferArchive.formatVersion);
      expect(result.manifest['entityCounts'], {'conversations': 1, 'assistants': 2});
    });

    test('rejects traversal and absolute archive paths on export', () {
      for (final path in [
        '../outside.json',
        'conversations/../../outside.json',
        '/tmp/outside.json',
        r'..\outside.json',
        r'C:\outside.json',
      ]) {
        expect(
          () => NativeTransferArchive.encode(
            sourceAppVersion: '1.0.0',
            sourceSchemaVersion: 3,
            exportedAt: DateTime.utc(2026),
            entityCounts: const {},
            unsupportedRecords: const [],
            entries: {path: const [1, 2, 3]},
          ),
          throwsFormatException,
          reason: path,
        );
      }
    });

    test('rejects path traversal from a hostile imported ZIP', () {
      final payload = utf8.encode('bad');
      final zip = buildArchive(
        entries: {'../outside.json': payload},
        manifest: {
          'format': NativeTransferArchive.formatId,
          'version': NativeTransferArchive.formatVersion,
          'sourceAppVersion': '1.0.0',
          'sourceSchemaVersion': 3,
          'exportedAt': DateTime.utc(2026).toIso8601String(),
          'entityCounts': <String, int>{},
          'unsupportedRecords': <String>[],
          'entries': <String, Object?>{},
        },
      );

      expect(
        () => NativeTransferArchive.decode(zip),
        throwsFormatException,
      );
    });

    test('rejects payload hash or size tampering', () {
      final payload = utf8.encode('original');
      final zip = buildArchive(
        entries: {'conversations/chat_01.json': payload},
        manifest: {
          'format': NativeTransferArchive.formatId,
          'version': NativeTransferArchive.formatVersion,
          'sourceAppVersion': '1.0.0',
          'sourceSchemaVersion': 3,
          'exportedAt': DateTime.utc(2026).toIso8601String(),
          'entityCounts': <String, int>{},
          'unsupportedRecords': <String>[],
          'entries': {
            'conversations/chat_01.json': {
              'sha256': '0' * 64,
              'sizeBytes': payload.length,
            },
          },
        },
      );

      expect(
        () => NativeTransferArchive.decode(zip),
        throwsFormatException,
      );
    });

    test('rejects unrecognized format versions', () {
      final payload = utf8.encode('conversation');
      final zip = buildArchive(
        entries: {'conversations/chat_01.json': payload},
        manifest: {
          'format': NativeTransferArchive.formatId,
          'version': 999,
          'sourceAppVersion': '1.0.0',
          'sourceSchemaVersion': 3,
          'exportedAt': DateTime.utc(2026).toIso8601String(),
          'entityCounts': <String, int>{},
          'unsupportedRecords': <String>[],
          'entries': <String, Object?>{
            'conversations/chat_01.json': {
              'sha256': '0' * 64,
              'sizeBytes': payload.length,
            },
          },
        },
      );

      expect(
        () => NativeTransferArchive.decode(zip),
        throwsFormatException,
      );
    });

    test('rejects empty entries and unsafe asset names', () {
      expect(
        () => NativeTransferArchive.encode(
          sourceAppVersion: '1.0.0',
          sourceSchemaVersion: 3,
          exportedAt: DateTime.utc(2026),
          entityCounts: const {},
          unsupportedRecords: const [],
          entries: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeTransferArchive.encode(
          sourceAppVersion: '1.0.0',
          sourceSchemaVersion: 3,
          exportedAt: DateTime.utc(2026),
          entityCounts: const {},
          unsupportedRecords: const [],
          entries: {'assets/not-a-sha256': const [1]},
        ),
        throwsFormatException,
      );
    });
  });
}
