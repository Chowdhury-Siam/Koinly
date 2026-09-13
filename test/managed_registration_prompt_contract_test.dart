import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Worker-managed registration uses admin-panel prompt instead of persistent sync error', () {
    final app = File('lib/main.dart').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();

    expect(app, contains("state.cloudSyncErrorCode == 'REGISTRATION_MANAGED'"));
    expect(app, contains('Registration is managed by the Worker administrator at /profile.'));
    expect(app, contains('Do you wish to create an account from the admin panel?'));
    expect(app, contains("child: const Text('No')"));
    expect(app, contains("child: const Text('Yes')"));
    expect(app, contains("Uri.parse('\$baseUrl/profile')"));
    expect(app, contains('state.clearCloudSyncTransientError();'));
    expect(app, contains("cloudSyncError = managedRegistration ? null : cleaned;"));

    expect(worker, contains("'REGISTRATION_MANAGED'"));
    expect(worker, contains("return json({ error: message, ...(code ? { code } : {}) }, statusCode);"));
  });
}
