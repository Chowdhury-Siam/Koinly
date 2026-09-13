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
    expect(app, isNot(contains('Self-hosted multi-device sync')));
    expect(app, isNot(contains('Enter the HTTPS URL from your own Cloudflare Worker deployment.')));
    expect(app, isNot(contains('Login merges your cloud copy with finance data already on this device. Local-only records are preserved.')));
    expect(app, isNot(contains('Only the first account can be created on a new self-hosted Worker. After that, sign in with that account on your other devices.')));
    expect(app, isNot(contains('Changing the Worker signs out this device because each self-hosted deployment has separate accounts and tokens.')));
    expect(app, isNot(contains("label: Text('Default')")));
    expect(app, isNot(contains('Use default service')));
    expect(app, isNot(contains('_useCustomCloudSync')));
    expect(sync, isNot(contains('KOINLY_SYNC_API_BASE_URL')));
    expect(build, isNot(contains('KOINLY_SYNC_API_BASE_URL')));
    expect(worker, isNot(contains("'invite-key'")));
    expect(File('.github/workflows/deploy-owner-sync-worker.yml').existsSync(), isFalse);
  });

  test('preference reload cannot erase a current self-hosted session', () {
    final app = File('lib/main.dart').readAsStringSync();

    expect(app, contains("final hadLegacyCustomSyncFlag = syncPrefs.containsKey('useCustomCloudSync');"));
    expect(app, contains('if (hadLegacyCustomSyncFlag && !legacyUsedSelfHostedSync && (syncAccessToken.isNotEmpty || syncRefreshToken.isNotEmpty))'));
    expect(app, isNot(contains('if (!legacyUsedSelfHostedSync && (syncAccessToken.isNotEmpty || syncRefreshToken.isNotEmpty))')));
  });
}
