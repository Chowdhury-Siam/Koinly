import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const updateGithubOwner = 'Chowdhury-Siam';
const updateGithubRepo = 'Koinly';
const updateGithubApiBase = 'https://api.github.com';
const updateGithubWebBase = 'https://github.com';
const updateRepositorySlug = '$updateGithubOwner/$updateGithubRepo';
const updateManifestAssetName = 'koinly-update.json';
const updateManifestUrl = '$updateGithubWebBase/$updateRepositorySlug/releases/latest/download/$updateManifestAssetName';
const includePrereleaseUpdates = bool.fromEnvironment(
  'KOINLY_INCLUDE_PRERELEASE_UPDATES',
  defaultValue: false,
);

enum UpdateCheckOutcome {
  upToDate,
  updateAvailable,
  noReleaseAvailable,
  networkError,
  rateLimited,
  malformedData,
  httpError,
}

enum UpdateAssetKind { arm64, arm32, x64, universal, windowsInstaller }

extension UpdateAssetKindLabel on UpdateAssetKind {
  String get label {
    switch (this) {
      case UpdateAssetKind.arm64:
        return 'ARM64';
      case UpdateAssetKind.arm32:
        return 'ARM32';
      case UpdateAssetKind.x64:
        return 'x86_64';
      case UpdateAssetKind.universal:
        return 'Universal';
      case UpdateAssetKind.windowsInstaller:
        return 'Windows installer';
    }
  }
}

@immutable
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch, {this.preRelease = const []});

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  bool get isPrerelease => preRelease.isNotEmpty;

  static SemanticVersion? tryParse(String value) {
    var raw = value.trim();
    if (raw.startsWith('v') || raw.startsWith('V')) raw = raw.substring(1);
    raw = raw.split('+').first;
    final dashIndex = raw.indexOf('-');
    final parts = dashIndex < 0 ? [raw] : [raw.substring(0, dashIndex), raw.substring(dashIndex + 1)];
    final numeric = parts.first.split('.');
    if (numeric.isEmpty || numeric.length > 3) return null;
    final major = int.tryParse(numeric[0]);
    final minor = numeric.length > 1 ? int.tryParse(numeric[1]) : 0;
    final patch = numeric.length > 2 ? int.tryParse(numeric[2]) : 0;
    if (major == null || minor == null || patch == null) return null;
    return SemanticVersion(
      major,
      minor,
      patch,
      preRelease: parts.length > 1 ? parts[1].split('.').where((e) => e.trim().isNotEmpty).toList() : const [],
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final main = [major.compareTo(other.major), minor.compareTo(other.minor), patch.compareTo(other.patch)].firstWhere((value) => value != 0, orElse: () => 0);
    if (main != 0) return main;
    if (!isPrerelease && other.isPrerelease) return 1;
    if (isPrerelease && !other.isPrerelease) return -1;
    final count = math.max(preRelease.length, other.preRelease.length);
    for (var i = 0; i < count; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;
      final left = preRelease[i];
      final right = other.preRelease[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null && leftNumber != rightNumber) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null && rightNumber == null) return -1;
      if (leftNumber == null && rightNumber != null) return 1;
      final text = left.compareTo(right);
      if (text != 0) return text;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}';
}

@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.browserDownloadUrl,
    this.contentType = '',
  });

  final int id;
  final String name;
  final int sizeBytes;
  final String browserDownloadUrl;
  final String contentType;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        id: (json['id'] as num? ?? 0).toInt(),
        name: json['name'] as String? ?? '',
        sizeBytes: (json['size'] as num? ?? 0).toInt(),
        browserDownloadUrl: json['browser_download_url'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
      );
}

@immutable
class GithubRelease {
  const GithubRelease({
    required this.id,
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.draft,
    required this.prerelease,
    required this.publishedAt,
    required this.assets,
  });

  final int id;
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  SemanticVersion? get semanticVersion => SemanticVersion.tryParse(tagName);
  String get displayVersion => semanticVersion?.toString() ?? tagName.replaceFirst(RegExp('^[vV]'), '');

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    return GithubRelease(
      id: (json['id'] as num? ?? 0).toInt(),
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      draft: json['draft'] as bool? ?? false,
      prerelease: json['prerelease'] as bool? ?? false,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: rawAssets is List ? rawAssets.whereType<Map>().map((asset) => ReleaseAsset.fromJson(Map<String, dynamic>.from(asset))).toList() : const [],
    );
  }
}

@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.outcome,
    this.release,
    this.installedVersion,
    this.latestVersion,
    this.message = '',
  });

  final UpdateCheckOutcome outcome;
  final GithubRelease? release;
  final SemanticVersion? installedVersion;
  final SemanticVersion? latestVersion;
  final String message;

  bool get hasUpdate => outcome == UpdateCheckOutcome.updateAvailable && release != null;
}

class GithubUpdateService {
  GithubUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<UpdateCheckResult> check({
    required String installedVersion,
    bool includePrereleases = includePrereleaseUpdates,
  }) async {
    final installed = SemanticVersion.tryParse(installedVersion);
    if (!includePrereleases) {
      final manifestRelease = await _fetchStableReleaseManifest();
      if (manifestRelease != null) {
        return _resultForRelease(manifestRelease, installed: installed);
      }
    }

    final releasePath = includePrereleases ? 'releases' : 'releases/latest';
    final uri = Uri.parse('$updateGithubApiBase/repos/$updateRepositorySlug/$releasePath');
    http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Koinly-Updater'})
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.networkError, installedVersion: installed, message: 'GitHub update check timed out.');
    } on SocketException {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.networkError, installedVersion: installed, message: 'No internet connection. Please try again later.');
    } catch (_) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.networkError, installedVersion: installed, message: 'Could not check for updates. Please try again.');
    }

    if (response.statusCode == 404) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.noReleaseAvailable, installedVersion: installed, message: 'No GitHub release is available yet.');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.rateLimited, installedVersion: installed, message: 'GitHub API rate limit reached. Please try again later.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.httpError, installedVersion: installed, message: 'GitHub returned HTTP ${response.statusCode}.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.malformedData, installedVersion: installed, message: 'GitHub returned malformed release data.');
    }
    final Iterable<Map> rawReleases;
    if (includePrereleases) {
      if (decoded is! List) {
        return UpdateCheckResult(outcome: UpdateCheckOutcome.malformedData, installedVersion: installed, message: 'GitHub release data was not a list.');
      }
      rawReleases = decoded.whereType<Map>();
    } else {
      if (decoded is! Map) {
        return UpdateCheckResult(outcome: UpdateCheckOutcome.malformedData, installedVersion: installed, message: 'GitHub latest-release data was not an object.');
      }
      rawReleases = [decoded];
    }

    final releases = rawReleases.map((release) => GithubRelease.fromJson(Map<String, dynamic>.from(release))).where((release) {
      if (release.draft) return false;
      if (!includePrereleases && release.prerelease) return false;
      return release.semanticVersion != null;
    }).toList();

    if (releases.isEmpty) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.noReleaseAvailable, installedVersion: installed, message: 'No stable release is available yet.');
    }

    final latest = releases.first;
    return _resultForRelease(latest, installed: installed);
  }

  Future<GithubRelease?> _fetchStableReleaseManifest() async {
    http.Response response;
    try {
      response = await _client
          .get(Uri.parse(updateManifestUrl), headers: const {'Accept': 'application/json', 'User-Agent': 'Koinly-Updater'})
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final release = GithubRelease.fromJson(Map<String, dynamic>.from(decoded));
    if (release.draft || release.prerelease || release.semanticVersion == null) return null;
    return release;
  }

  UpdateCheckResult _resultForRelease(GithubRelease latest, {required SemanticVersion? installed}) {
    final latestVersion = latest.semanticVersion;
    if (installed == null || latestVersion == null) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.malformedData, release: latest, installedVersion: installed, latestVersion: latestVersion, message: 'Could not compare app versions.');
    }

    if (latestVersion.compareTo(installed) > 0) {
      return UpdateCheckResult(outcome: UpdateCheckOutcome.updateAvailable, release: latest, installedVersion: installed, latestVersion: latestVersion, message: 'Update ${latest.displayVersion} is available.');
    }

    return UpdateCheckResult(outcome: UpdateCheckOutcome.upToDate, release: latest, installedVersion: installed, latestVersion: latestVersion, message: 'You are up to date.');
  }

  void close() => _client.close();
}

class ReleaseAssetMatcher {
  const ReleaseAssetMatcher._();

  static Map<UpdateAssetKind, ReleaseAsset> androidApks(GithubRelease release) {
    final result = <UpdateAssetKind, ReleaseAsset>{};
    for (final asset in release.assets) {
      final name = asset.name.toLowerCase();
      if (!name.endsWith('.apk')) continue;
      if (_matchesAny(name, const ['universal', 'all-abi', 'all_arch', 'all-arch'])) {
        result.putIfAbsent(UpdateAssetKind.universal, () => asset);
      } else if (_matchesAny(name, const ['arm64-v8a', 'arm64', 'aarch64'])) {
        result.putIfAbsent(UpdateAssetKind.arm64, () => asset);
      } else if (_matchesAny(name, const ['armeabi-v7a', 'arm32', 'arm-v7a', 'armv7', 'android-arm'])) {
        result.putIfAbsent(UpdateAssetKind.arm32, () => asset);
      } else if (_matchesAny(name, const ['x86_64', 'x86-64', 'x64', 'amd64'])) {
        result.putIfAbsent(UpdateAssetKind.x64, () => asset);
      }
    }
    return result;
  }

  static ReleaseAsset? preferredWindowsInstaller(GithubRelease release) {
    final executableAssets = release.assets.where((asset) => asset.name.toLowerCase().endsWith('.exe')).toList();
    if (executableAssets.isEmpty) return null;
    executableAssets.sort((a, b) => _windowsInstallerRank(a.name).compareTo(_windowsInstallerRank(b.name)));
    final best = executableAssets.first;
    return _windowsInstallerRank(best.name) >= 50 ? null : best;
  }

  static bool isTrustedReleaseAssetUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.host != 'github.com') return false;
    return uri.path.toLowerCase().startsWith('/${updateGithubOwner.toLowerCase()}/${updateGithubRepo.toLowerCase()}/releases/download/');
  }

  static bool _matchesAny(String name, List<String> needles) => needles.any(name.contains);

  static int _windowsInstallerRank(String name) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.exe')) return 100;
    if (RegExp(r'(^|[-_\s])setup([-_\s.]|$)').hasMatch(lower)) return 0;
    if (lower.contains('installer')) return 1;
    if (lower.contains('install')) return 2;
    return 50;
  }
}

enum ChangelogBlockType { heading, bullet, numbered, paragraph }

@immutable
class MarkdownTextSegment {
  const MarkdownTextSegment(this.text, {this.url});
  final String text;
  final String? url;
}

@immutable
class ChangelogBlock {
  const ChangelogBlock({required this.type, required this.segments, this.level = 0, this.number});
  final ChangelogBlockType type;
  final List<MarkdownTextSegment> segments;
  final int level;
  final int? number;

  String get plainText => segments.map((segment) => segment.text).join();
}

class ChangelogParser {
  const ChangelogParser._();

  static List<ChangelogBlock> parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <ChangelogBlock>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(ChangelogBlock(type: ChangelogBlockType.paragraph, segments: _parseSegments(paragraph.join(' ').trim())));
      paragraph.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(ChangelogBlock(type: ChangelogBlockType.heading, level: heading.group(1)!.length, segments: _parseSegments(heading.group(2)!.trim())));
        continue;
      }

      final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        blocks.add(ChangelogBlock(type: ChangelogBlockType.bullet, segments: _parseSegments(bullet.group(1)!.trim())));
        continue;
      }

      final numbered = RegExp(r'^(\d+)[.)]\s+(.+)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        blocks.add(ChangelogBlock(type: ChangelogBlockType.numbered, number: int.tryParse(numbered.group(1)!), segments: _parseSegments(numbered.group(2)!.trim())));
        continue;
      }

      paragraph.add(trimmed);
    }
    flushParagraph();
    return blocks;
  }

  static List<MarkdownTextSegment> _parseSegments(String text) {
    final segments = <MarkdownTextSegment>[];
    final linkRegex = RegExp(r'\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)');
    var index = 0;
    for (final match in linkRegex.allMatches(text)) {
      if (match.start > index) segments.add(MarkdownTextSegment(text.substring(index, match.start)));
      segments.add(MarkdownTextSegment(match.group(1)!, url: match.group(2)!));
      index = match.end;
    }
    if (index < text.length) segments.add(MarkdownTextSegment(text.substring(index)));
    return segments;
  }
}

@immutable
class DownloadProgressSnapshot {
  const DownloadProgressSnapshot({
    required this.receivedBytes,
    required this.totalBytes,
    required this.startedAt,
    required this.now,
    this.status = 'Downloading',
  });

  final int receivedBytes;
  final int totalBytes;
  final DateTime startedAt;
  final DateTime now;
  final String status;

  double get fraction => totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1).toDouble();
  int get percent => (fraction * 100).round().clamp(0, 100);
  double get speedBytesPerSecond {
    final millis = math.max(1, now.difference(startedAt).inMilliseconds);
    return receivedBytes / (millis / 1000);
  }

  String get downloadedText => formatBytes(receivedBytes);
  String get totalText => totalBytes <= 0 ? 'Unknown size' : formatBytes(totalBytes);
  String get speedText => '${formatBytes(speedBytesPerSecond.round())}/s';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
}

class UpdateDownloadStore {
  const UpdateDownloadStore._();

  static Future<Directory> updatesDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'koinly_updates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String safeFileName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');

  static Future<File> androidApkFile({
    required GithubRelease release,
    required UpdateAssetKind kind,
    required ReleaseAsset asset,
  }) async {
    final dir = await updatesDirectory();
    final version = safeFileName(release.displayVersion);
    final name = safeFileName(asset.name.isEmpty ? 'Koinly-v$version-${kind.label}.apk' : asset.name);
    return File(p.join(dir.path, name));
  }


  static Future<File> windowsInstallerFile({
    required GithubRelease release,
    required ReleaseAsset asset,
  }) async {
    final dir = await updatesDirectory();
    final version = safeFileName(release.displayVersion);
    final assetName = safeFileName(asset.name.isEmpty ? 'Koinly-Setup.exe' : asset.name);
    final name = assetName.contains(version) ? assetName : 'Koinly-v$version-$assetName';
    return File(p.join(dir.path, name));
  }

  static Future<void> cleanupPartialFiles({Directory? directory}) async {
    final dir = directory ?? await updatesDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.part')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> cleanupStaleAndroidUpdates({
    required String keepVersion,
    Directory? directory,
  }) async {
    final dir = directory ?? await updatesDirectory();
    if (!await dir.exists()) return;
    final keep = safeFileName(keepVersion);
    await for (final entity in dir.list()) {
      if (entity is File && (entity.path.endsWith('.apk') || entity.path.endsWith('.part')) && !p.basename(entity.path).contains(keep)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> cleanupStaleWindowsUpdates({
    required String keepVersion,
    Directory? directory,
  }) async {
    final dir = directory ?? await updatesDirectory();
    if (!await dir.exists()) return;
    final keep = safeFileName(keepVersion);
    await for (final entity in dir.list()) {
      if (entity is File && (entity.path.toLowerCase().endsWith('.exe') || entity.path.endsWith('.part')) && !p.basename(entity.path).contains(keep)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

}

class WindowsUpdateInstaller {
  const WindowsUpdateInstaller._();

  static Future<bool> install(String path) async {
    if (!Platform.isWindows) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      await Process.start(
        file.path,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AndroidUpdateInstaller {
  static const MethodChannel _channel = MethodChannel('com.koinly.siam/updater');

  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<bool> installApk(String path) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('installApk', {'path': path}) ?? false;
  }
}
