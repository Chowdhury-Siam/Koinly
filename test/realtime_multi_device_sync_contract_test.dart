import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground multi-device sync uses realtime worker notifications with fallback polling', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final serviceSource = File('lib/sync_services.dart').readAsStringSync();
    final workerSource = File('cloud/worker/src/index.ts').readAsStringSync();
    final wranglerSource = File('cloud/worker/wrangler.self-hosted.toml').readAsStringSync();

    expect(mainSource, contains('Duration(milliseconds: 120)'));
    expect(mainSource, contains('Duration(seconds: 20)'));
    expect(mainSource, contains('_startCloudLiveConnection'));
    expect(mainSource, contains("decoded['type'] != 'sync-change'"));
    expect(mainSource, contains('syncCloudChangesIfIdle(force: true)'));
    expect(serviceSource, contains("/v1/sync/live"));
    expect(serviceSource, contains("httpUri.scheme == 'https' ? 'wss' : 'ws'"));
    expect(workerSource, contains('export class SyncHub'));
    expect(workerSource, contains("url.pathname === '/v1/sync/live'"));
    expect(workerSource, contains("type: 'sync-change'"));
    expect(wranglerSource, contains('name = "SYNC_HUB"'));
    expect(wranglerSource, contains('new_sqlite_classes = ["SyncHub"]'));
  });
}
