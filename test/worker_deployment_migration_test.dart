import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koinly/app_config.dart';
import 'package:koinly/worker_deployment.dart';

const _config = WorkerDeploymentConfig(
  workerName: 'test-worker',
  cloudflareAccountId: '0123456789abcdef0123456789abcdef',
  cloudflareApiToken: 'test-token',
  tursoDatabaseUrl: 'libsql://test.turso.io',
  tursoAuthToken: 'test-token',
  jwtSecret: 'test-secret-with-at-least-32-characters',
  adminUsername: 'test-admin',
  adminPasswordHash: r'pbkdf2$100000$test-salt$test-hash',
);

// Exercise the public deployment API and inspect its serialized multipart upload.
// All endpoints and assets are mocked; no Cloudflare/Turso account is contacted.
class _DeploymentServer {
  _DeploymentServer({
    this.exists = true,
    this.settings = const {},
    this.versionTag,
    this.detailTag,
    this.expectedTag,
    this.rejectAll = false,
    this.unrelatedError = false,
  });

  final bool exists;
  final Map<String, Object?> settings;
  final String? versionTag;
  final String? detailTag;
  final String? expectedTag;
  final bool rejectAll;
  final bool unrelatedError;
  final uploads = <Map<String, dynamic>>[];
  final calls = <String>[];
  late final client = MockClient(_handle);

  http.Response _json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path == '/v2/pipeline') {
      final body = jsonDecode(request.body) as Map;
      return _json({'results': [
        for (final statement in body['requests'] as List)
          if (statement['type'] == 'execute')
            {'type': 'ok', 'response': {'type': 'execute', 'result': {'cols': [], 'rows': []}}},
      ]});
    }
    if (path.endsWith('/workers/subdomain')) {
      return _json({'success': true, 'result': {'subdomain': 'test-account'}});
    }
    if (path.endsWith('/settings')) {
      return _json({'success': exists, 'result': settings}, exists ? 200 : 404);
    }
    if (path.endsWith('/versions')) {
      if (versionTag != null) {
        return _json({'success': true, 'result': [{'id': 'latest', 'migration_tag': versionTag}]});
      }
      if (detailTag != null) {
        return _json({'success': true, 'result': [{'id': 'latest'}]});
      }
      return _json({'success': false}, 403);
    }
    if (path.endsWith('/versions/latest')) {
      return _json({'success': true, 'result': {'resources': {'script': {'migration_tag': detailTag}}}});
    }
    if (request.method == 'PUT' && path.endsWith('/scripts/test-worker')) {
      final metadata = jsonDecode(request.body.split('\r\n\r\n')[1].split('\r\n--')[0]) as Map<String, dynamic>;
      uploads.add(metadata);
      final migrations = metadata['migrations'];
      if (migrations is Map && migrations.containsKey('old_tag') && !migrations.containsKey('new_tag')) {
        return _json({'success': false, 'errors': [
          {'message': 'migration must include a new_tag because old_tag is set'},
        ]}, 400);
      }
      if (unrelatedError) {
        return _json({'success': false, 'errors': [{'message': 'Authentication error'}]}, 403);
      }
      if (expectedTag != null && (uploads.length == 1 || rejectAll)) {
        return _json({'success': false, 'errors': [
          {'message': 'migration tag mismatch: expected tag "$expectedTag"'},
        ]}, 400);
      }
      return _json({'success': true, 'result': {}});
    }
    if (path.endsWith('/subdomain') || path.endsWith('/schedules')) {
      return _json({'success': true});
    }
    if (path == '/health') {
      return _json({
        'ok': true, 'service': 'koinly-sync', 'databaseReachable': true,
        'schemaReady': true, 'registrationMode': 'first-user',
        'telegramBackupAvailable': true, 'googleDriveBackupAvailable': true,
        'analyticsUploadAvailable': true, 'realtimeSyncAvailable': true,
        'profileMediaSyncAvailable': true,
        'workerVersion': uploads.isEmpty ? '1.0.1' : appVersion,
      });
    }
    throw StateError('Unexpected deployment request: ${request.method} $path');
  }

  Future<WorkerDeploymentResult> deploy() =>
      WorkerDeploymentService(client: client).deploy(_config, onProgress: (_) {});
}

class _MemoryCredentials extends WorkerDeploymentCredentialStore {
  WorkerDeploymentProfile profile = WorkerDeploymentProfile(
    workerName: _config.workerName, cloudflareAccountId: _config.cloudflareAccountId,
    cloudflareApiToken: _config.cloudflareApiToken, tursoDatabaseUrl: _config.tursoDatabaseUrl,
    tursoAuthToken: _config.tursoAuthToken, jwtSecret: _config.jwtSecret,
    adminUsername: _config.adminUsername, adminPasswordHash: _config.adminPasswordHash,
    workerUrl: 'https://test-worker.test-account.workers.dev', workerVersion: '1.0.1',
  );
  @override
  Future<WorkerDeploymentProfile?> read() async => profile;
  @override
  Future<void> write(WorkerDeploymentProfile value) async { profile = value; }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    rootBundle.evict('assets/worker/koinly_sync_worker.js');
    rootBundle.evict('cloud/worker/schema.sql');
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
      final asset = switch (path) {
        'assets/worker/koinly_sync_worker.js' => '//${List.filled(10001, 'x').join()}',
        'cloud/worker/schema.sql' => 'CREATE TABLE IF NOT EXISTS users (id TEXT);',
        _ => throw StateError('Unexpected asset $path'),
      };
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(asset)));
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    rootBundle.evict('assets/worker/koinly_sync_worker.js');
    rootBundle.evict('cloud/worker/schema.sql');
  });

  for (final source in ['version list', 'version detail', 'settings fallback']) {
    test('code-only redeploy preserves the tag from $source', () async {
      final server = _DeploymentServer(
        versionTag: source == 'version list' ? 'existing-v7' : null,
        detailTag: source == 'version detail' ? 'existing-v7' : null,
        settings: source == 'settings fallback' ? {'migrations': {'new_tag': 'existing-v7'}} : {},
      );
      addTearDown(server.client.close);
      await server.deploy();
      expect(server.uploads.single['migrations'], {'old_tag': 'existing-v7', 'new_tag': 'existing-v7'});
      expect(server.uploads.single['bindings'], contains(equals({
        'type': 'durable_object_namespace', 'name': 'SYNC_HUB', 'class_name': 'SyncHub',
      })));
    });
  }

  test('new Worker still creates SyncHub with the initial migration', () async {
    final server = _DeploymentServer(exists: false);
    addTearDown(server.client.close);
    await server.deploy();
    expect(server.uploads.single['migrations'], {
      'new_tag': 'v1-realtime-sync-hub', 'new_sqlite_classes': ['SyncHub'],
    });
  });

  for (final knownTag in [null, 'stale-v1']) {
    test('retry preserves authoritative tag when inspected tag is $knownTag', () async {
      final server = _DeploymentServer(versionTag: knownTag, expectedTag: 'actual-v9');
      addTearDown(server.client.close);
      await server.deploy();
      expect(server.uploads, hasLength(2));
      expect(server.uploads.last['migrations'], {'old_tag': 'actual-v9', 'new_tag': 'actual-v9'});
    });
  }

  test('declarative exports are preserved without migrations', () async {
    final server = _DeploymentServer(settings: {'exports': {'SyncHub': {'type': 'durable-object', 'storage': 'sqlite'}}});
    addTearDown(server.client.close);
    await server.deploy();
    expect(server.uploads.single['exports'], server.settings['exports']);
    expect(server.uploads.single.containsKey('migrations'), isFalse);
  });

  test('migration recovery retries only once', () async {
    final server = _DeploymentServer(versionTag: 'stale-v1', expectedTag: 'actual-v9', rejectAll: true);
    addTearDown(server.client.close);
    await expectLater(server.deploy(), throwsA(isA<WorkerDeploymentException>()));
    expect(server.uploads, hasLength(2));
    expect(server.calls.any((call) => call.endsWith('/schedules')), isFalse);
  });

  test('unrelated upload errors are surfaced without migration retries', () async {
    final server = _DeploymentServer(versionTag: 'existing-v7', unrelatedError: true);
    addTearDown(server.client.close);
    await expectLater(server.deploy(), throwsA(isA<WorkerDeploymentException>()));
    expect(server.uploads, hasLength(1));
  });

  test('automatic update completes and refreshes saved version', () async {
    final server = _DeploymentServer(detailTag: 'existing-v7');
    final credentials = _MemoryCredentials();
    final updater = WorkerAutoUpdateService(client: server.client, credentialStore: credentials);
    addTearDown(updater.close);
    final result = await updater.checkAndUpdate(activeWorkerUrl: credentials.profile.workerUrl);
    expect(result.outcome, WorkerAutoUpdateOutcome.updated);
    expect(credentials.profile.workerVersion, appVersion);
    expect(server.uploads.single['migrations'], {'old_tag': 'existing-v7', 'new_tag': 'existing-v7'});
  });
}
