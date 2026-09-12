import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile media is capped at 50 MB and synchronized in database chunks', () {
    final media = File('lib/profile/profile_media.dart').readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();
    final api = File('lib/sync_services.dart').readAsStringSync();
    final schema = File('cloud/worker/schema.sql').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();
    final profileUi = File('lib/profile/profile_ui.dart').readAsStringSync();

    expect(media, contains('50 * 1024 * 1024'));
    expect(media, contains('Profile media must be 50 MB or smaller.'));
    expect(app, contains('profileMediaCloudUploadPending'));
    expect(app, contains('const chunkSize = 10 * 1024 * 1024'));
    expect(worker, contains('const profileMediaChunkBytes = 10 * 1024 * 1024'));
    expect(worker, contains('Math.ceil(profileMediaChunkBytes / 3) * 4'));
    expect(app, contains('await _setCloudSyncPending(true);'));
    expect(app, contains("error.code == 'HTTP_404'"));
    expect(app, contains('_pullProfileMediaFromCloud'));
    expect(api, contains("'/v1/profile-media/begin'"));
    expect(api, contains("'/v1/profile-media/chunk'"));
    expect(api, contains("'/v1/profile-media/complete'"));
    expect(schema, contains('CREATE TABLE IF NOT EXISTS profile_media'));
    expect(schema, contains('CREATE TABLE IF NOT EXISTS profile_media_chunks'));
    expect(schema, contains('size_bytes <= 52428800'));
    expect(worker, contains("url.pathname === '/v1/profile-media/complete'"));
    expect(worker, contains('context.waitUntil(notifySyncHub(env, auth))'));
    expect(worker, contains('profileMediaSyncAvailable: true'));
    expect(profileUi, contains('syncCloudChangesIfIdle(force: true)'));
    expect(api, contains(r"?? 'HTTP_${response.statusCode}'"));
  });
}
