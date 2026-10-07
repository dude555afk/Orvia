import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/workspace_binding.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/external_mounts_provider.dart';
import '../../../utils/app_directories.dart';
import 'workspace_paths.dart';

enum OrviaLinkKind {
  workspaceFile,
  chatFile,
  externalFile,
  temporaryFile,
  chatAttachment,
  chatOutput,
  skillFile,
  terminal,
}

class OrviaLink {
  const OrviaLink({
    required this.kind,
    required this.relativePath,
    this.conversationId,
    this.mountId,
    this.terminalCommand,
  });

  final OrviaLinkKind kind;
  final String relativePath;
  final String? conversationId;
  final String? mountId;
  final String? terminalCommand;

  /// Absolute guest path for the referenced entry in its owning mount/session.
  String? guestPath({String? mountRoot}) {
    final root = switch (kind) {
      OrviaLinkKind.workspaceFile => WorkspacePaths.guestWorkspace,
      OrviaLinkKind.chatFile => WorkspacePaths.guestChat,
      OrviaLinkKind.chatAttachment => '${WorkspacePaths.guestChat}/attachments',
      OrviaLinkKind.chatOutput => '${WorkspacePaths.guestChat}/outputs',
      OrviaLinkKind.skillFile => WorkspacePaths.guestSkills,
      OrviaLinkKind.temporaryFile => WorkspacePaths.guestTmp,
      OrviaLinkKind.externalFile => mountRoot,
      OrviaLinkKind.terminal => null,
    };
    return root == null ? null : p.posix.join(root, relativePath);
  }

  static const String scheme = 'orvia';

  /// Percent-encodes each path segment with [Uri.encodeComponent].
  /// Builders and the model prompt share this rule; [tryParse] decodes
  /// per segment and also accepts raw UTF-8.
  static String encodePath(String relativePath) {
    final parts = relativePath.replaceAll(r'\', '/').split('/');
    final encoded = <String>[];
    for (final part in parts) {
      if (part.isEmpty) continue;
      encoded.add(Uri.encodeComponent(part));
    }
    return encoded.join('/');
  }

  static OrviaLink? tryParse(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return null;
    // Manual split: a case-insensitive regex `[^/?#]` does not match
    // non-ASCII (Dart ignoreCase + negated class), so model-emitted
    // `orvia://workspace/\u5458\u5DE5\u8868.csv` never parsed. Do not use [Uri]
    // either — it would normalize `%2e%2e` / `..` away.
    const scheme = 'orvia://';
    if (raw.length < scheme.length) return null;
    if (raw.substring(0, scheme.length).toLowerCase() != scheme) {
      return null;
    }
    final rest = raw.substring(scheme.length);
    final hash = rest.indexOf('#');
    final withoutFragment = hash < 0 ? rest : rest.substring(0, hash);
    final q = withoutFragment.indexOf('?');
    final query = q < 0 ? null : withoutFragment.substring(q);
    final authorityAndPath = q < 0
        ? withoutFragment
        : withoutFragment.substring(0, q);
    final slash = authorityAndPath.indexOf('/');
    final host =
        (slash < 0 ? authorityAndPath : authorityAndPath.substring(0, slash))
            .toLowerCase();
    final rawPath = slash < 0 ? null : authorityAndPath.substring(slash);
    if (host.isEmpty) return null;

    if (host == 'terminal') {
      var command = '';
      if (query != null && query.length > 1) {
        command = Uri.splitQueryString(query.substring(1))['cmd'] ?? '';
      }
      return OrviaLink(
        kind: OrviaLinkKind.terminal,
        relativePath: '',
        terminalCommand: command,
      );
    }

    final segments = _decodedRelativeSegments(rawPath);
    if (segments == null) return null;

    switch (host) {
      case 'session':
        return OrviaLink(
          kind: OrviaLinkKind.chatFile,
          relativePath: segments.join('/'),
        );
      case 'tmp':
        return OrviaLink(
          kind: OrviaLinkKind.temporaryFile,
          relativePath: segments.join('/'),
        );
      case 'mounts':
        if (segments.isEmpty) return null;
        return OrviaLink(
          kind: OrviaLinkKind.externalFile,
          mountId: segments.first,
          relativePath: segments.skip(1).join('/'),
        );
      case 'workspace':
        return OrviaLink(
          kind: OrviaLinkKind.workspaceFile,
          relativePath: segments.join('/'),
        );
      case 'chat':
        if (segments.isEmpty) return null;
        final folder = segments.first;
        final rest = segments.sublist(1);
        if (folder == 'attachments') {
          return OrviaLink(
            kind: OrviaLinkKind.chatAttachment,
            relativePath: rest.join('/'),
          );
        }
        if (folder == 'outputs') {
          return OrviaLink(
            kind: OrviaLinkKind.chatOutput,
            relativePath: rest.join('/'),
          );
        }
        if (rest.isEmpty) return null;
        // orvia://chat/<conversationId>/… — model-emitted or explicit id.
        if (!_isSafeSegment(folder)) return null;
        if (rest.first == 'attachments' || rest.first == 'outputs') {
          if (rest.length < 2) return null;
          return OrviaLink(
            kind: rest.first == 'attachments'
                ? OrviaLinkKind.chatAttachment
                : OrviaLinkKind.chatOutput,
            relativePath: rest.sublist(1).join('/'),
            conversationId: folder,
          );
        }
        return OrviaLink(
          kind: OrviaLinkKind.chatOutput,
          relativePath: rest.join('/'),
          conversationId: folder,
        );
      case 'skills':
        return OrviaLink(
          kind: OrviaLinkKind.skillFile,
          relativePath: segments.join('/'),
        );
      default:
        return null;
    }
  }

  /// Decodes path segments and rejects `..`, `.`, empties, separators, and
  /// absolute-host / drive paths. [rawPath] is the `/...` portion before
  /// query/fragment, not a normalized [Uri.path].
  static List<String>? _decodedRelativeSegments(String? rawPath) {
    if (rawPath == null || rawPath.isEmpty || rawPath == '/') return const [];
    if (!rawPath.startsWith('/')) return null;
    var path = rawPath.substring(1);
    if (path.startsWith('/') || path.startsWith(r'\')) return null;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(path)) return null;
    if (path.isEmpty) return null;

    final rawParts = path.split('/');
    final decoded = <String>[];
    for (final raw in rawParts) {
      if (raw.isEmpty) return null;
      final part = _decodePathSegment(raw);
      if (part == null || !_isSafeSegment(part)) return null;
      decoded.add(part);
    }
    return decoded;
  }

  /// Percent-decode one path segment. [Uri.decodeComponent] throws
  /// `ArgumentError: Illegal percent encoding` on any code unit > 127, so
  /// raw UTF-8 names (`\u5458\u5DE5\u8868.csv`) must be passed through. Mixed segments
  /// (`\u62A5\u544A%20\u7EC8\u7A3F.csv`) are normalized then decoded.
  static String? _decodePathSegment(String raw) {
    if (!raw.contains('%')) return raw;
    final normalized = StringBuffer();
    for (final rune in raw.runes) {
      if (rune > 127) {
        normalized.write(Uri.encodeComponent(String.fromCharCode(rune)));
      } else {
        normalized.writeCharCode(rune);
      }
    }
    try {
      return Uri.decodeComponent(normalized.toString());
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static bool _isSafeSegment(String part) {
    if (part.isEmpty || part == '.' || part == '..') return false;
    if (part.contains('/') || part.contains(r'\')) return false;
    if (part.contains('\x00')) return false;
    return true;
  }
}

enum FileLinkFailure { missing, mountUnavailable }

class FileLinkException implements Exception {
  const FileLinkException(this.reason);
  final FileLinkFailure reason;
}

class FileLinkResolver {
  FileLinkResolver({required this.workspaces, this.externalMounts});

  final WorkspaceProvider workspaces;
  final ExternalMountsProvider? externalMounts;

  Future<File?> resolveToHostFile(
    OrviaLink link, {
    required String conversationId,
    required WorkspaceBinding binding,
  }) async {
    try {
      final entry = await resolveToHostEntry(
        link,
        conversationId: conversationId,
        binding: binding,
      );
      return entry is File ? entry : null;
    } on FileLinkException {
      return null;
    }
  }

  Future<FileSystemEntity?> resolveToHostEntry(
    OrviaLink link, {
    required String conversationId,
    required WorkspaceBinding binding,
  }) async {
    if (link.kind == OrviaLinkKind.terminal) return null;
    if (!_isSafeRelativePath(link.relativePath)) return null;
    final sessionId = link.conversationId ?? conversationId;
    late final String root;
    switch (link.kind) {
      case OrviaLinkKind.workspaceFile:
        if (!binding.isBound) return null;
        await workspaces.loaded;
        final workspace = workspaces.byId(binding.workspaceId!);
        if (workspace == null) return null;
        root = await workspaces.hostRootFor(workspace);
      case OrviaLinkKind.chatAttachment:
        root = p.join(
          (await AppDirectories.sessionDir(sessionId)).path,
          'attachments',
        );
      case OrviaLinkKind.chatOutput:
        root = p.join(
          (await AppDirectories.sessionDir(sessionId)).path,
          'outputs',
        );
      case OrviaLinkKind.chatFile:
        root = (await AppDirectories.sessionDir(sessionId)).path;
      case OrviaLinkKind.skillFile:
        root = (await AppDirectories.getSkillsDirectory()).path;
      case OrviaLinkKind.temporaryFile:
        root = Directory.systemTemp.path;
      case OrviaLinkKind.externalFile:
        final provider = externalMounts;
        if (provider == null) {
          throw const FileLinkException(FileLinkFailure.mountUnavailable);
        }
        try {
          final mounts = await provider.resolveMounts();
          final mount = mounts
              .where((m) => m.externalId == link.mountId)
              .firstOrNull;
          if (mount == null) {
            throw const FileLinkException(FileLinkFailure.mountUnavailable);
          }
          root = mount.host;
        } catch (_) {
          throw const FileLinkException(FileLinkFailure.mountUnavailable);
        }
      case OrviaLinkKind.terminal:
        return null;
    }
    return _entryUnderRoot(root, link.relativePath);
  }

  static bool _isSafeRelativePath(String relativePath) {
    if (relativePath.isEmpty) return true;
    if (relativePath.startsWith('/') || relativePath.startsWith(r'\')) {
      return false;
    }
    if (RegExp(r'^[a-zA-Z]:').hasMatch(relativePath)) return false;
    return relativePath.split('/').every(OrviaLink._isSafeSegment);
  }

  static FileSystemEntity? _entryUnderRoot(String root, String relativePath) {
    try {
      final canonicalRoot = Directory(root).resolveSymbolicLinksSync();
      final joined = p.join(p.canonicalize(root), relativePath);
      final type = FileSystemEntity.typeSync(joined);
      if (type == FileSystemEntityType.notFound) {
        throw const FileLinkException(FileLinkFailure.missing);
      }
      final canonical = type == FileSystemEntityType.directory
          ? Directory(joined).resolveSymbolicLinksSync()
          : File(joined).resolveSymbolicLinksSync();
      if (!p.equals(canonicalRoot, canonical) &&
          !p.isWithin(canonicalRoot, canonical)) {
        return null;
      }
      if (type == FileSystemEntityType.file) return File(joined);
      if (type == FileSystemEntityType.directory) return Directory(joined);
      return null;
    } on FileSystemException {
      throw const FileLinkException(FileLinkFailure.missing);
    }
  }
}
