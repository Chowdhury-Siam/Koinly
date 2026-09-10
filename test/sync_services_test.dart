import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/sync_services.dart';

void main() {
  test('self-hosted sync endpoint accepts only an HTTPS origin', () {
    expect(
      CloudSyncService.validateApiBaseUrl(' https://my-sync.example.com/ '),
      'https://my-sync.example.com',
    );
    expect(() => CloudSyncService.validateApiBaseUrl('http://my-sync.example.com'), throwsStateError);
    expect(() => CloudSyncService.validateApiBaseUrl('https://my-sync.example.com/v1'), throwsStateError);
  });

  test('sync endpoint resolution never falls back to a compiled service', () {
    expect(CloudSyncService.resolveApiBaseUrl(), isEmpty);
    expect(
      CloudSyncService.resolveApiBaseUrl(' https://owner-sync.example.workers.dev/ '),
      'https://owner-sync.example.workers.dev',
    );
  });
}
