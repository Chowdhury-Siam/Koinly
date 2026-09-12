import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release workflow builds Linux and universal macOS desktop packages', () {
    final workflow =
        File('.github/workflows/build-android-apks.yml').readAsStringSync();

    expect(workflow, contains('build-linux:'));
    expect(workflow, contains('ubuntu-22.04-arm'));
    expect(workflow, contains("if: matrix.arch == 'arm64'"));
    expect(workflow, contains('git clone --depth 1 --branch 3.47.4'));
    expect(workflow, contains('flutter build linux --release'));
    expect(workflow, contains('imagemagick'));
    expect(workflow, contains('-resize 512x512!'));
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
    expect(workflow, contains('runs-on: macos-15'));
    expect(workflow, isNot(contains('runs-on: macos-15-intel')));
    expect(workflow, contains('Restore pinned Flutter SDK cache'));
    expect(workflow, contains('Set up pinned Flutter on Apple Silicon'));
    expect(workflow, contains('--filter=blob:none --single-branch --depth 1'));
    expect(workflow, contains('Restore macOS dependency and incremental build caches'));
    expect(workflow, contains('build/macos'));
    expect(workflow, contains('FLUTTER_MACOS_ARM64_ONLY: "false"'));
    expect(workflow, contains('flutter build macos --release'));
    expect(workflow, contains('lipo -archs'));
    expect(workflow, contains('macos-universal.dmg'));
    expect(workflow, contains('macos-universal.zip'));
    expect(workflow, contains('xcrun notarytool submit'));

    expect(workflow, contains('pattern: koinly-linux-*'));
    expect(workflow, contains('pattern: koinly-macos-*'));
  });


  test('release package jobs never build in fork repositories', () {
    final workflow =
        File('.github/workflows/build-android-apks.yml').readAsStringSync();

    expect(
      workflow,
      isNot(
        contains(
          "github.event_name == 'workflow_dispatch' || github.repository == 'Chowdhury-Siam/Koinly'",
        ),
      ),
    );
    expect(
      RegExp(
        r"^    if: github\.repository == 'Chowdhury-Siam/Koinly'\s*$",
        multiLine: true,
      ).allMatches(workflow).length,
      4,
    );
  });

  test('desktop platform metadata stays versioned and documented', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final config = File('lib/app_config.dart').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, contains('version: 1.0.1118+162'));
    expect(config, contains("defaultValue: '1.0.1118'"));
    expect(readme, contains('Android, Windows, Linux, and macOS'));
    expect(readme, contains('universal macOS package'));
    expect(File('tools/linux/koinly.desktop').existsSync(), isTrue);
  });
}
