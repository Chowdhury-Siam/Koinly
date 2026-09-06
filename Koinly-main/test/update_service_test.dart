import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koinly/update_service.dart';

void main() {
  test('uses the Koinly GitHub repository for update checks', () {
    expect(updateRepositorySlug, 'Chowdhury-Siam/Koinly');
  });

  group('SemanticVersion', () {
    test('compares semantic versions numerically', () {
      expect(SemanticVersion.tryParse('1.4.10')!.compareTo(SemanticVersion.tryParse('1.4.8')!), greaterThan(0));
      expect(SemanticVersion.tryParse('1.10.0')!.compareTo(SemanticVersion.tryParse('1.4.10')!), greaterThan(0));
      expect(SemanticVersion.tryParse('2.0.0')!.compareTo(SemanticVersion.tryParse('1.10.0')!), greaterThan(0));
    });

    test('stable releases sort above prereleases with same version', () {
      expect(SemanticVersion.tryParse('1.5.0')!.compareTo(SemanticVersion.tryParse('1.5.0-beta.1')!), greaterThan(0));
    });
  });

  group('GithubUpdateService', () {
    test('stable checks use GitHub latest release endpoint', () async {
      final service = GithubUpdateService(client: _latestClient(_release('v1.5.0')));
      final result = await service.check(installedVersion: '1.0.0', includePrereleases: false);
      expect(result.outcome, UpdateCheckOutcome.updateAvailable);
      expect(result.release!.displayVersion, '1.5.0');
    });

    test('prerelease checks follow GitHub release order instead of sorting old tags numerically', () async {
      final service = GithubUpdateService(client: _client([
        _release('v1.0.79-beta.1', prerelease: true),
        _release('v1.0.1035'),
      ]));
      final result = await service.check(installedVersion: '1.0.78', includePrereleases: true);
      expect(result.outcome, UpdateCheckOutcome.updateAvailable);
      expect(result.release!.tagName, 'v1.0.79-beta.1');
    });

    test('GitHub latest 1.0.77 wins over the older 1.0.1035 release', () async {
      final service = GithubUpdateService(client: MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(jsonEncode(_release('v1.0.77')), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response(
          jsonEncode([_release('v1.0.77'), _release('v1.0.1035')]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));
      final result = await service.check(installedVersion: '1.0.76');
      expect(result.outcome, UpdateCheckOutcome.updateAvailable);
      expect(result.release!.displayVersion, '1.0.77');
    });

    test('treats missing releases as no release available', () async {
      final service = GithubUpdateService(client: MockClient((request) async => http.Response('Not found', 404)));
      final result = await service.check(installedVersion: '1.0.0');
      expect(result.outcome, UpdateCheckOutcome.noReleaseAvailable);
    });

    test('detects newer stable release', () async {
      final service = GithubUpdateService(client: _latestClient(_release('v1.5.0')));
      final result = await service.check(installedVersion: '1.4.10');
      expect(result.outcome, UpdateCheckOutcome.updateAvailable);
    });

    test('reports up to date when installed version is current', () async {
      final service = GithubUpdateService(client: _latestClient(_release('v1.5.0')));
      final result = await service.check(installedVersion: '1.5.0');
      expect(result.outcome, UpdateCheckOutcome.upToDate);
    });
  });

  group('ReleaseAssetMatcher', () {
    final release = GithubRelease.fromJson(_release('v1.5.0', assets: [
      _asset('Koinly-v1.5.0-arm64.apk', 39900000),
      _asset('Koinly-v1.5.0-armeabi-v7a.apk', 32100000),
      _asset('Koinly-v1.5.0-x86_64.apk', 42600000),
      _asset('Koinly-v1.5.0-universal.apk', 111000000),
      _asset('Koinly-v1.5.0.aab', 50000000),
      _asset('Koinly-v1.5.0-Setup.exe', 21000000),
      _asset('KoinlyTool.exe', 1000),
    ]));

    test('matches ARM64 asset', () {
      expect(ReleaseAssetMatcher.androidApks(release)[UpdateAssetKind.arm64]!.name, contains('arm64'));
    });

    test('matches ARM32 asset', () {
      expect(ReleaseAssetMatcher.androidApks(release)[UpdateAssetKind.arm32]!.name, contains('armeabi'));
    });

    test('matches x86_64 asset', () {
      expect(ReleaseAssetMatcher.androidApks(release)[UpdateAssetKind.x64]!.name, contains('x86_64'));
    });

    test('matches Universal asset', () {
      expect(ReleaseAssetMatcher.androidApks(release)[UpdateAssetKind.universal]!.name, contains('universal'));
    });

    test('selects Windows installer before unrelated executables', () {
      expect(ReleaseAssetMatcher.preferredWindowsInstaller(release)!.name, contains('Setup'));
    });
  });

  test('changelog parser handles headings, bullets, numbered lists, paragraphs, and links', () {
    final blocks = ChangelogParser.parse('''
## Changes

- Fixed sync
* Added updater
1. First item

Read [release notes](https://example.com).
''');
    expect(blocks.map((block) => block.type), containsAll([ChangelogBlockType.heading, ChangelogBlockType.bullet, ChangelogBlockType.numbered, ChangelogBlockType.paragraph]));
    expect(blocks.last.segments.any((segment) => segment.url == 'https://example.com'), isTrue);
  });

  test('download progress calculates percentage and speed', () {
    final start = DateTime(2026, 1, 1);
    final progress = DownloadProgressSnapshot(
      receivedBytes: 50,
      totalBytes: 100,
      startedAt: start,
      now: start.add(const Duration(seconds: 2)),
    );
    expect(progress.percent, 50);
    expect(progress.speedBytesPerSecond, 25);
  });

  test('partial-download cleanup removes only .part files', () async {
    final dir = await Directory.systemTemp.createTemp('koinly_update_test_');
    try {
      final partial = File('${dir.path}${Platform.pathSeparator}update.apk.part');
      final apk = File('${dir.path}${Platform.pathSeparator}update.apk');
      await partial.writeAsString('partial');
      await apk.writeAsString('apk');
      await UpdateDownloadStore.cleanupPartialFiles(directory: dir);
      expect(await partial.exists(), isFalse);
      expect(await apk.exists(), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

MockClient _client(List<Map<String, dynamic>> releases) {
  return MockClient((request) async {
    expect(request.url.path.endsWith('/releases'), isTrue);
    return http.Response(jsonEncode(releases), 200, headers: {'content-type': 'application/json'});
  });
}

MockClient _latestClient(Map<String, dynamic> release) {
  return MockClient((request) async {
    expect(request.url.path.endsWith('/releases/latest'), isTrue);
    return http.Response(jsonEncode(release), 200, headers: {'content-type': 'application/json'});
  });
}

Map<String, dynamic> _release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  List<Map<String, dynamic>> assets = const [],
}) {
  return {
    'id': tag.hashCode,
    'tag_name': tag,
    'name': 'Koinly $tag',
    'body': '## What is new\n- Update details',
    'html_url': 'https://github.com/$updateRepositorySlug/releases/tag/$tag',
    'draft': draft,
    'prerelease': prerelease,
    'published_at': '2026-08-22T00:00:00Z',
    'assets': assets,
  };
}

Map<String, dynamic> _asset(String name, int size) {
  return {
    'id': name.hashCode,
    'name': name,
    'size': size,
    'browser_download_url': 'https://github.com/$updateRepositorySlug/releases/download/v1.5.0/$name',
    'content_type': name.endsWith('.apk') ? 'application/vnd.android.package-archive' : 'application/octet-stream',
  };
}
