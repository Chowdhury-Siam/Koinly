import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release workflow builds Linux and macOS desktop packages', () {
    final workflow =
        File('.github/workflows/build-android-apks.yml').readAsStringSync();

    expect(workflow, contains('build-linux:'));
    expect(workflow, contains('ubuntu-22.04-arm'));
    expect(workflow, contains('flutter build linux --release'));
    expect(
      workflow,
      contains(r'linuxdeploy-${{ matrix.appimage_arch }}.AppImage'),
    );
    expect(
      workflow,
      contains(
        r'Koinly-v${KOINLY_APP_VERSION_NAME}-linux-${{ matrix.arch }}.tar.gz',
      ),
    );

    expect(workflow, contains('build-macos:'));
    expect(workflow, contains('macos-15-intel'));
    expect(workflow, contains('runner: macos-15'));
    expect(workflow, contains('flutter build macos --release'));
    expect(
      workflow,
      contains(
        r'Koinly-v${KOINLY_APP_VERSION_NAME}-macos-${{ matrix.arch }}.dmg',
      ),
    );
    expect(workflow, contains('xcrun notarytool submit'));

    expect(workflow, contains('pattern: koinly-linux-*'));
    expect(workflow, contains('pattern: koinly-macos-*'));
  });

  test('desktop platform metadata stays versioned and documented', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final config = File('lib/app_config.dart').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, contains('version: 1.0.1104+148'));
    expect(config, contains("defaultValue: '1.0.1104'"));
    expect(readme, contains('Android, Windows, Linux, and macOS'));
    expect(File('tools/linux/koinly.desktop').existsSync(), isTrue);
  });
}
