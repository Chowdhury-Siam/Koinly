import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/sync_services.dart';

void main() {
  test('custom sync endpoint accepts only an HTTPS origin', () {
    expect(
      CloudSyncService.validateApiBaseUrl(' https://my-sync.example.com/ '),
      'https://my-sync.example.com',
    );
    expect(() => CloudSyncService.validateApiBaseUrl('http://my-sync.example.com'), throwsStateError);
    expect(() => CloudSyncService.validateApiBaseUrl('https://my-sync.example.com/v1'), throwsStateError);
  });

  test('self-hosted registration payload omits an empty registration key', () {
    final payload = KoinlySyncApi.buildRegistrationPayload(
      email: 'owner@example.com',
      password: 'correct horse battery staple',
      registrationKey: '   ',
      deviceId: 'device-1',
      deviceName: 'Owner phone',
      platform: 'android',
    );

    expect(payload.containsKey('registrationKey'), isFalse);
  });

  test('default-service registration payload keeps a supplied registration key', () {
    final payload = KoinlySyncApi.buildRegistrationPayload(
      email: 'user@example.com',
      password: 'correct horse battery staple',
      registrationKey: '  KLY1-TEST-KEY  ',
      deviceId: 'device-2',
      deviceName: 'User phone',
      platform: 'android',
    );

    expect(payload['registrationKey'], 'KLY1-TEST-KEY');
  });
}
