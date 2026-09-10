import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account sync is self-hosted only', () {
    final app = File('lib/main.dart').readAsStringSync();
    final sync = File('lib/sync_services.dart').readAsStringSync();
    final build = File('.github/workflows/build-android-apks.yml').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();

    expect(app, contains("Text('Self-hosted Sync Worker'"));
    expect(app, contains("label: const Text('Validate and use Worker')"));
    expect(app, isNot(contains("label: Text('Default')")));
    expect(app, isNot(contains('Use default service')));
    expect(app, isNot(contains('_useCustomCloudSync')));
    expect(sync, isNot(contains('KOINLY_SYNC_API_BASE_URL')));
    expect(build, isNot(contains('KOINLY_SYNC_API_BASE_URL')));
    expect(worker, isNot(contains("'invite-key'")));
    expect(File('.github/workflows/deploy-owner-sync-worker.yml').existsSync(), isFalse);
  });
}
