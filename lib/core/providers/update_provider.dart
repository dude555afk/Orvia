import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
  });

  String? bestDownloadUrl() {
    if (Platform.isIOS) {
      return downloads['ios'] ??
          downloads['iosAppStore'] ??
          downloads['universal'];
    }
    if (Platform.isAndroid) {
      return downloads['android'] ?? downloads['universal'];
    }
    if (Platform.isMacOS) {
      return downloads['macos'] ??
          downloads['mac'] ??
          downloads['darwin'] ??
          downloads['universal'];
    }
    if (Platform.isWindows) {
      return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    }
    if (Platform.isLinux) {
      return downloads['linux'] ?? downloads['universal'];
    }
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        released = DateTime.parse(releasedRaw);
      } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateProvider() {
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(_cleanupStaleUpdateApks());
    }
  }

  static const MethodChannel _androidUpdater = MethodChannel('app.updater');
  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;
  bool _downloading = false;
  bool get downloading => _downloading;
  bool _installing = false;
  bool get installing => _installing;
  double? _downloadProgress;
  double? get downloadProgress => _downloadProgress;

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      await _cleanupStaleUpdateApks();
      final resp = await http.get(
        Uri.parse(
          'https://api.github.com/repos/dude555afk/Orvia/releases/latest',
        ),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Orvia',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('GitHub HTTP ${resp.statusCode}');
      }
      final release =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rawTag = (release['tag_name'] ?? '').toString().trim();
      final version = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
      final downloads = <String, String>{};
      for (final asset in (release['assets'] as List? ?? const [])) {
        if (asset is! Map) continue;
        final name = (asset['name'] ?? '').toString();
        final url = (asset['browser_download_url'] ?? '').toString();
        if (url.isEmpty || !name.toLowerCase().endsWith('.apk')) continue;
        if (name.contains('arm64-v8a')) {
          downloads['androidArm64'] = url;
        } else if (name.contains('armeabi-v7a')) {
          downloads['androidArmv7'] = url;
        } else if (name.contains('x86_64')) {
          downloads['androidX64'] = url;
        } else {
          downloads['android'] = url;
        }
      }
      final info = UpdateInfo(
        app: 'Orvia',
        version: version,
        releasedAt: DateTime.tryParse(
          (release['published_at'] ?? '').toString(),
        ),
        notes: (release['body'] ?? '').toString(),
        downloads: downloads,
      );

      final pkg = await PackageInfo.fromPlatform();
      final hasNew = _isRemoteNewer(
        remoteVersion: info.version,
        currentVersion: pkg.version,
      );
      _available = hasNew ? info : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<void> downloadAndInstallAvailable() async {
    if (_downloading || _installing) return;
    final info = _available;
    if (info == null) throw StateError('No update is available');
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'In-app installation is only available on Android',
      );
    }

    _downloading = true;
    _downloadProgress = 0;
    _error = null;
    notifyListeners();

    File? apk;
    http.Client? client;
    try {
      final abi = await _androidUpdater.invokeMethod<String>('getPreferredAbi');
      final url =
          switch (abi) {
            'arm64-v8a' => info.downloads['androidArm64'],
            'armeabi-v7a' => info.downloads['androidArmv7'],
            'x86_64' => info.downloads['androidX64'],
            _ => null,
          } ??
          info.downloads['androidArm64'] ??
          info.downloads['android'] ??
          (info.downloads.isNotEmpty ? info.downloads.values.first : null);
      if (url == null || url.isEmpty) {
        throw StateError('No compatible Android APK is available');
      }

      await _cleanupStaleUpdateApks();
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/orvia_updates',
      );
      await dir.create(recursive: true);
      final name = Uri.parse(url).pathSegments.last;
      apk = File('${dir.path}/$name');

      client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Accept'] = 'application/octet-stream'
        ..headers['User-Agent'] = 'Orvia';
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('APK download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = apk.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            _downloadProgress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      _downloading = false;
      _downloadProgress = 1;
      _installing = true;
      notifyListeners();

      await _androidUpdater.invokeMethod<bool>('installApk', {
        'path': apk.path,
      });
    } catch (e) {
      _error = e.toString();
      if (apk != null) {
        try {
          if (await apk.exists()) await apk.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client?.close();
      _downloading = false;
      _installing = false;
      notifyListeners();
    }
  }

  Future<void> _cleanupStaleUpdateApks() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/orvia_updates',
      );
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.toLowerCase().endsWith('.apk')) {
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final parts = v.split('.');
      final nums = <int>[];
      for (int i = 0; i < 3; i++) {
        nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
      }
      return nums;
    }

    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }
}
