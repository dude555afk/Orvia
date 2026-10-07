import 'package:orvia/utils/orvia_file_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrviaFileUri encode/decode roundtrip', () {
    test('handles spaces, #, %, and Unicode filenames', () {
      const cases = <String>[
        'hello world.png',
        'hash#tag.png',
        'percent%20done.png',
        '\u5199\u771F_😀.png',
        'nested/dir/file name (1).png',
      ];

      for (final name in cases) {
        final abs = '/data/app/upload/$name';
        final uri = OrviaFileUri.encodeFromAbsolute(abs, root: '/data/app');
        expect(uri, isNotNull, reason: name);
        expect(OrviaFileUri.isOrviaFileUri(uri!), isTrue);

        final segments = OrviaFileUri.decodeToSegments(uri);
        expect(segments, isNotNull, reason: name);
        expect(segments!.first, 'upload');
        expect(segments.skip(1).join('/'), name);

        final again = OrviaFileUri.encodeFromAbsolute(
          OrviaFileUri.resolveToAbsolute(uri, root: '/data/app')!,
          root: '/data/app',
        );
        expect(again, uri);
      }
    });
  });

  group('OrviaFileUri.decodeToSegments rejects invalid URIs', () {
    test(
      'rejects path traversal, unknown managed root, host, query/fragment',
      () {
        const invalid = <String>[
          'orvia-file:///../secret',
          'orvia-file:///unknown/a.png',
          'orvia-file://host/upload/a.png',
          'orvia-file:///upload/a.png?x=1',
          'orvia-file:///upload/a.png#frag',
          'orvia-file:///upload//a.png',
          'orvia-file:///upload/',
          'orvia-file:///upload',
          'orvia-file:///',
          'orvia-file:',
          'file:///upload/a.png',
        ];

        for (final uri in invalid) {
          expect(OrviaFileUri.decodeToSegments(uri), isNull, reason: uri);
        }
      },
    );

    test('rejects empty path segments and dot segments', () {
      expect(
        OrviaFileUri.decodeToSegments('orvia-file:///images/a//b.png'),
        isNull,
      );
      expect(
        OrviaFileUri.decodeToSegments('orvia-file:///images/./a.png'),
        isNull,
      );
      expect(
        OrviaFileUri.decodeToSegments('orvia-file:///images/foo/../a.png'),
        isNull,
      );
    });

    test('returns null for malformed percent encoding', () {
      for (final uri in const [
        'orvia-file:///upload/%ZZ.pdf',
        'orvia-file:///upload/%.pdf',
        'orvia-file:///upload/%FF.pdf',
      ]) {
        expect(OrviaFileUri.decodeToSegments(uri), isNull, reason: uri);
      }
    });
  });

  group('OrviaFileUri.resolveToAbsolute', () {
    test('joins under POSIX root without existence checks', () {
      final abs = OrviaFileUri.resolveToAbsolute(
        'orvia-file:///upload/nested/a.png',
        root: '/var/mobile/Documents',
      );
      expect(abs, '/var/mobile/Documents/upload/nested/a.png');
    });

    test('joins under Windows-style root', () {
      final abs = OrviaFileUri.resolveToAbsolute(
        'orvia-file:///images/photo.png',
        root: r'C:\Users\me\AppData\Local\Orvia',
      );
      expect(abs, r'C:\Users\me\AppData\Local\Orvia\images\photo.png');
    });

    test('returns null for invalid URI', () {
      expect(
        OrviaFileUri.resolveToAbsolute(
          'orvia-file:///unknown/a.png',
          root: '/tmp/root',
        ),
        isNull,
      );
    });
  });

  group('OrviaFileUri.tryEncodeLegacyAbsolutePath', () {
    test('encodes iOS Documents style paths even when file is missing', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/upload/x.png',
        ),
        'orvia-file:///upload/x.png',
      );
    });

    test('encodes Windows AppData orvia style paths case-insensitively', () {
      for (final folder in ['orvia', 'Orvia', 'ORVIA']) {
        expect(
          OrviaFileUri.tryEncodeLegacyAbsolutePath(
            'C:/Users/me/AppData/Local/$folder/images/Pic.PNG',
            allowGenericFallback: false,
          ),
          'orvia-file:///images/Pic.PNG',
          reason: folder,
        );
      }
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Roaming/orvia/avatars/a.png',
          allowGenericFallback: false,
        ),
        'orvia-file:///avatars/a.png',
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          r'C:\Users\old-user\AppData\Roaming\com.psyche\orvia\upload\legacy.pdf',
          allowGenericFallback: false,
        ),
        'orvia-file:///upload/legacy.pdf',
      );
      // Bare .../Orvia/images without AppData must not match.
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/Projects/Orvia/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Suffix / prefix folder names must not match.
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Local/OrviaNotes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
    });

    test(
      'encodes Android package-private app_flutter and files style paths',
      () {
        expect(
          OrviaFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/com.dude555afk.orvia/app_flutter/fonts/a.ttf',
            allowGenericFallback: false,
          ),
          'orvia-file:///fonts/a.ttf',
        );
        expect(
          OrviaFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/com.dude555afk.orvia/files/upload/doc.pdf',
            allowGenericFallback: false,
          ),
          'orvia-file:///upload/doc.pdf',
        );
        // Non-orvia package must not be claimed without generic fallback.
        expect(
          OrviaFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/com.example/app_flutter/fonts/a.ttf',
            allowGenericFallback: false,
          ),
          isNull,
        );
      },
    );

    test('rejects lookalike bundles, fake UUIDs, and nested archives', () {
      // Ordinary paths / substring Orvia.
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Documents/images/report.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Projects/Orvia/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Similar-but-not-whitelist bundles/packages.
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Containers/com.other.orvia.notes/Data/Documents/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Application Support/com.other.orvia.notes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/data/user/0/com.other.orvia.notes/app_flutter/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Local/OrviaNotes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Fake / short UUID under real iOS root.
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Containers/Data/Application/ABC/Documents/upload/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Nested archives: prefixing a valid sandbox path must not claim it.
      for (final nested in const [
        '/tmp/archive/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/x.png',
        '/tmp/archive/Users/alice/Library/Developer/CoreSimulator/Devices/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/data/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/sim.png',
        '/tmp/archive/Users/alice/Library/Application Support/com.dude555afk.orvia/images/a.png',
        '/tmp/archive/Users/alice/Library/Containers/com.dude555afk.orvia/Data/Documents/upload/x.png',
        '/tmp/archive/C:/Users/me/AppData/Local/Orvia/images/Pic.PNG',
        '/tmp/archive/data/user/0/com.dude555afk.orvia/app_flutter/fonts/a.ttf',
      ]) {
        expect(
          OrviaFileUri.tryEncodeLegacyAbsolutePath(
            nested,
            allowGenericFallback: false,
          ),
          isNull,
          reason: nested,
        );
      }
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/tmp/playground/app_flutter/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '//server/share/images/a.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
    });

    test('encodes iOS Simulator CoreSimulator UUID Documents paths', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Developer/CoreSimulator/Devices/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/data/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/sim.png',
          allowGenericFallback: false,
        ),
        'orvia-file:///images/sim.png',
      );
    });

    test('encodes iOS file: URI via portable slash path', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          'file:///var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/pic.png',
          allowGenericFallback: false,
        ),
        'orvia-file:///images/pic.png',
      );
    });

    test('normalizes Windows managed root Images casing under AppData', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          r'C:\Users\me\AppData\Local\Orvia\Images\x.png',
          allowGenericFallback: false,
        ),
        'orvia-file:///images/x.png',
      );
    });

    test('encodes macOS Application Support orvia bundle paths', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Application Support/com.dude555afk.orvia/images/a.png',
          allowGenericFallback: false,
        ),
        'orvia-file:///images/a.png',
      );
    });

    test('uses generic managed-subdir fallback', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/some/random/place/images/nested/file.png',
        ),
        'orvia-file:///images/nested/file.png',
      );
    });

    test('rejects POSIX backslash filenames instead of splitting path', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          r'/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/a\b.png',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          r'/some/random/place/images/a\b.png',
        ),
        isNull,
      );
    });

    test('returns null when managed root/filename requirements fail', () {
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/cache/x.png',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/upload',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/upload/',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.tryEncodeLegacyAbsolutePath('/tmp/only-file.png'),
        isNull,
      );
    });
  });

  group('OrviaFileUri.isOrviaFileUri', () {
    test('is a cheap prefix check', () {
      expect(
        OrviaFileUri.isOrviaFileUri('orvia-file:///upload/a.png'),
        isTrue,
      );
      expect(OrviaFileUri.isOrviaFileUri('orvia-file:anything'), isTrue);
      expect(OrviaFileUri.isOrviaFileUri('file:///upload/a.png'), isFalse);
      expect(
        OrviaFileUri.isOrviaFileUri('Orvia-file:///upload/a.png'),
        isFalse,
      );
      expect(OrviaFileUri.isOrviaFileUri(''), isFalse);
    });
  });

  group('OrviaFileUri.encodeFromAbsolute', () {
    test('encodes only paths under root/<managed>/', () {
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/data/app/upload/a.png',
          root: '/data/app',
        ),
        'orvia-file:///upload/a.png',
      );
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/data/app/images/nested/b.png',
          root: '/data/app',
        ),
        'orvia-file:///images/nested/b.png',
      );
    });

    test('returns null for external or unmanaged paths', () {
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/other/place/upload/a.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/data/app/cache/a.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.encodeFromAbsolute('/data/app/upload', root: '/data/app'),
        isNull,
      );
    });

    test('encodes Windows-style absolute paths under root', () {
      expect(
        OrviaFileUri.encodeFromAbsolute(
          r'C:\Users\me\AppData\Local\Orvia\upload\a.png',
          root: r'C:\Users\me\AppData\Local\Orvia',
        ),
        'orvia-file:///upload/a.png',
      );
    });

    test('rejects backslash in filename segments', () {
      expect(
        OrviaFileUri.encodeFromAbsolute(
          r'/data/app/upload/a\b.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        OrviaFileUri.decodeToSegments('orvia-file:///upload/a%5Cb.png'),
        isNull,
      );
    });
    test('percent-encodes special characters in filenames', () {
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/data/app/upload/report final.pdf',
          root: '/data/app',
        ),
        'orvia-file:///upload/report%20final.pdf',
      );
      expect(
        OrviaFileUri.encodeFromAbsolute(
          '/data/app/upload/a#b.png',
          root: '/data/app',
        ),
        'orvia-file:///upload/a%23b.png',
      );
    });
  });
}
