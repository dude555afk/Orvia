import 'package:orvia/core/models/environment_state.dart';

class MirrorCandidate {
  const MirrorCandidate({
    required this.base,
    required this.probe,
    this.official = false,
  });

  final Uri base;
  final Uri probe;
  final bool official;
}

class MirrorCatalog {
  static const String defaultAlpineBranch = 'latest-stable';

  static Uri officialBase(MirrorCategory category, {String arch = 'arm64'}) {
    return candidates(category, arch: arch).firstWhere((c) => c.official).base;
  }

  static List<MirrorCandidate> candidates(
    MirrorCategory category, {
    String arch = 'arm64',
  }) {
    switch (category) {
      case MirrorCategory.apt:
        return arch == 'amd64' ? _aptAmd64 : _aptArm64;
      case MirrorCategory.apk:
        return _apk;
      case MirrorCategory.pip:
        return _pip;
      case MirrorCategory.npm:
        return _npm;
    }
  }

  static final List<MirrorCandidate> _aptArm64 = [
    _apt('http://ports.ubuntu.com/ubuntu-ports', official: true),
  ];

  static final List<MirrorCandidate> _aptAmd64 = [
    _apt('http://archive.ubuntu.com/ubuntu', official: true),
  ];

  static final List<MirrorCandidate> _apk = [
    _entry(
      'https://dl-cdn.alpinelinux.org/alpine',
      'last-updated',
      official: true,
    ),
  ];

  static final List<MirrorCandidate> _pip = [
    _entry('https://pypi.org/simple', 'pip/', official: true),
  ];

  static final List<MirrorCandidate> _npm = [
    _entry('https://registry.npmjs.org', '-/ping', official: true),
  ];

  static MirrorCandidate _apt(String base, {bool official = false}) {
    return _entry(base, 'dists/noble/Release', official: official);
  }

  static MirrorCandidate _entry(
    String base,
    String probePath, {
    bool official = false,
  }) {
    final baseUri = Uri.parse(base.endsWith('/') ? base : '$base/');
    return MirrorCandidate(
      base: Uri.parse(_trimSlash(base)),
      probe: baseUri.resolve(probePath),
      official: official,
    );
  }

  static String _trimSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
