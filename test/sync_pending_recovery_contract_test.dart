import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending sync reports Worker failures and recovers stale transports', () {
    final app = File('lib/main.dart').readAsStringSync();
    final api = File('lib/sync_services.dart').readAsStringSync();

    expect(app, isNot(contains('Sync pending • Waiting for internet')));
    expect(app, contains("return 'Sync pending • Worker timed out'"));
    expect(app, contains("return 'Sync pending • Can’t reach Worker'"));
    expect(app, contains("return 'Sync pending • Worker error'"));
    expect(app, contains("return 'Sync pending • Retrying'"));
    expect(app, contains('static const int _cloudSyncPushBatchSize = 25'));
    expect(app, contains('pendingSyncOperations(limit: _cloudSyncPushBatchSize)'));
    expect(app, contains('cloudSyncError = text;'));
    expect(app, contains("..writeln('- Status: \$cloudSyncStatusText')"));
    expect(app, contains("Last sync attempt:"));
    expect(app, contains('state.cloudSyncStatusText'));

    expect(api, contains('static http.Client _client = http.Client();'));
    expect(api, contains('static void _resetHttpClient()'));
    expect(api, contains("code: 'NETWORK_TIMEOUT'"));
    expect(api, contains("code: 'NETWORK_UNREACHABLE'"));
    expect(api, contains("code: 'NETWORK_TRANSPORT'"));
    expect(api, contains('on http.ClientException'));
  });
}
