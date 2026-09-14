import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Account & sync exposes in-app Worker deployment and auto-configures URL', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains("'Deploy Database'"));
    expect(main, contains('class WorkerDeploymentScreen extends StatefulWidget'));
    expect(main, contains('Navigator.push<String>'));
    expect(main, contains('text: workerUrl'));
    expect(main, contains('await _saveSyncEndpoint();'));
    expect(main, contains("title: 'Deploy Database'"));
    expect(main, contains("label: Text(_deploying ? 'Deploying…' : 'Deploy Worker')"));
  });

  test('in-app deployment provisions database, Worker, route, cron and health', () {
    final service = File('lib/worker_deployment.dart').readAsStringSync();

    expect(service, contains("'/v2/pipeline'"));
    expect(service, contains('SELECT 1 AS koinly_connection_test'));
    expect(service, contains("'baton': null"));
    expect(service, contains("'want_rows': true"));
    expect(service, isNot(contains("_tursoHttpBase(c.tursoDatabaseUrl)}/version")));
    expect(service, contains(r'workers/scripts/${Uri.encodeComponent(c.workerName)}'));
    expect(service, contains("'durable_object_namespace'"));
    expect(service, contains("'new_tag': 'v1-realtime-sync-hub'"));
    expect(service, contains("'new_sqlite_classes': ['SyncHub']"));
    expect(service, contains("/subdomain'"));
    expect(service, contains("/schedules'"));
    expect(service, contains("'cron': '*/5 * * * *'"));
    expect(service, contains("data['analyticsUploadAvailable'] == true"));
    expect(service, contains("data['profileMediaSyncAvailable'] == true"));
    expect(service, contains("data['workerVersion'] == appVersion"));
    expect(service, contains("'KOINLY_WORKER_VERSION'"));
    expect(service, contains('const maxAttempts = 24'));
    expect(service, contains('Worker health check $attempt/$maxAttempts'));
    expect(service, contains('_healthDiagnostic('));
    expect(service, contains("'TURSO_DATABASE_URL', 'text': _tursoHttpBase(c.tursoDatabaseUrl)"));
    expect(service, contains('Worker deployed successfully.'));
  });

  test('deployment credentials use secure storage for automatic Worker updates', () {
    final service = File('lib/worker_deployment.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(service, contains("'ADMIN_PASSWORD_HASH'"));
    expect(service, isNot(contains("'ADMIN_PASSWORD', 'text'")));
    expect(service, contains('_pbkdf2HmacSha256'));
    expect(service, contains(r'pbkdf2\$100000\$'));
    expect(service, contains('FlutterSecureStorage'));
    expect(service, contains('koinly_worker_auto_deployment_profile_v1'));
    expect(service, contains('WorkerAutoUpdateService'));
    expect(service, contains("decoded['workerVersion']"));
    expect(main, contains("title: const Text('Automatic Worker updates'"));
    expect(main, contains("label: const Text('Forget saved deployment credentials')"));
    expect(main, contains('checkForAutomaticWorkerUpdate()'));
    expect(main, contains('Automatic Worker update failed:'));
  });

  test('release builds embed a Worker bundle generated from current Worker source', () {
    final workflow = File('.github/workflows/build-android-apks.yml').readAsStringSync();
    final package = File('cloud/worker/package.json').readAsStringSync();
    final builder = File('cloud/worker/scripts/build-app-deploy-bundle.mjs').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(workflow, contains('prepare-worker-bundle:'));
    expect(workflow, contains('npm run bundle:app'));
    expect(workflow, contains('koinly-worker-deploy-bundle'));
    expect(workflow, contains('      - "cloud/worker/**"'));
    expect(package, contains('"bundle:app"'));
    expect(builder, contains('wrangler.self-hosted.toml'));
    expect(builder, contains('koinly_sync_worker.js'));
    expect(pubspec, contains('    - assets/worker/'));
    expect(pubspec, contains('    - cloud/worker/schema.sql'));
    expect(workflow, contains("'cloud/worker/wrangler.self-hosted.toml'"));
  });
}
