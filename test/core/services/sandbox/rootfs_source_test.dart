import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/services/sandbox/rootfs_source.dart';

void main() {
  const source = RootfsSource();

  test(
    'Ubuntu 24.04.3 stays the default while newer releases are available',
    () {
      expect(source.image.id, 'ubuntu-24.04.3');
      expect(RootfsCatalog.defaultForDistro('ubuntu').id, 'ubuntu-24.04.3');
      expect(RootfsCatalog.forDistro('ubuntu').map((image) => image.version), [
        '24.04.4',
        '24.04.3',
        '22.04.5',
      ]);
    },
  );

  test('catalog keeps ABI-specific verified images', () {
    for (final image in RootfsCatalog.images) {
      final imageSource = RootfsSource(image: image);
      for (final arch in ['armhf', 'arm64', 'amd64']) {
        expect(image.checksums[arch], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(imageSource.officialTarballUri(arch).scheme, 'https');
        expect(image.cacheName(arch), contains(image.id));
        expect(imageSource.officialTarballUri(arch).path, endsWith(image.format));
      }
      expect(imageSource.availableSources, const [
        RootfsDownloadSource.automatic,
        RootfsDownloadSource.official,
        RootfsDownloadSource.custom,
        RootfsDownloadSource.local,
      ]);
    }

    expect(RootfsSource.archiveFormat('LOCAL.TAR.XZ'), 'tar.xz');
    expect(RootfsSource.archiveFormat('image.iso'), isNull);
  });

  test('ABI map and pinned hashes match the official 24.04.3 manifest', () {
    expect(RootfsSource.archForAbi('arm64-v8a'), 'arm64');
    expect(RootfsSource.archForAbi('x86_64'), 'amd64');
    expect(RootfsSource.archForAbi('armeabi-v7a'), 'armhf');
    expect(RootfsSource.archForAbi('armhf'), 'armhf');
    expect(RootfsSource.archForAbi('armeabi'), isNull);
    expect(RootfsSource.archForAbi('x86'), isNull);
    expect(
      source.checksums['armhf'],
      '747909a2f81d816fc6252f076757fcf6bd75a55f848a1c049ee79c0e88c0b9a0',
    );
    expect(
      source.checksums['arm64'],
      '7b2dced6dd56ad5e4a813fa25c8de307b655fdabc6ea9213175a92c48dabb048',
    );
    expect(
      source.checksums['amd64'],
      '6bc2cde3930ad088b3bb46fa45279e96d25bc3810f209850ecbe4722711874f9',
    );
  });

  test('automatic and local defer while official resolves directly', () {
    expect(
      source.selectedUri(RootfsDownloadSource.automatic, '', 'arm64'),
      isNull,
    );
    expect(
      source.selectedUri(RootfsDownloadSource.local, '', 'arm64'),
      isNull,
    );
    expect(
      source.selectedUri(RootfsDownloadSource.official, '', 'arm64'),
      source.officialTarballUri('arm64'),
    );
  });

  test('custom directory follows ABI, full URLs preserve query parameters', () {
    expect(
      RootfsSource.customTarballUri(
        'https://mirror.test/release/',
        'armhf',
      ).toString(),
      'https://mirror.test/release/ubuntu-base-24.04.3-base-armhf.tar.gz',
    );
    expect(
      RootfsSource.customTarballUri(
        ' https://mirror.test/release/ ',
        'amd64',
      ).toString(),
      'https://mirror.test/release/ubuntu-base-24.04.3-base-amd64.tar.gz',
    );
    expect(
      RootfsSource.customTarballUri(
        'https://mirror.test/image.tar.gz?token=x%2Fy',
        'arm64',
      ).toString(),
      'https://mirror.test/image.tar.gz?token=x%2Fy',
    );
  });

  test('reject malformed, credential-bearing and non-HTTP custom sources', () {
    for (final url in [
      '',
      'file:///tmp/a.tar.gz',
      'ftp://mirror.test/',
      'https://user:pass@mirror.test/',
      'https://mirror.test/with space',
      'https://mirror.test/#part',
      'https://mirror.test/release?token=x',
    ]) {
      expect(
        () => RootfsSource.customTarballUri(url, 'arm64'),
        throwsFormatException,
        reason: url,
      );
    }
  });
}
