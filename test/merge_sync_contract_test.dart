import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account sync never calls destructive replace-all from the Flutter client', () {
    final source = File('lib/main.dart').readAsStringSync();
    final syncApiSource = File('lib/sync_services.dart').readAsStringSync();
    expect(source, isNot(contains('api.replaceAll(')));
    expect(syncApiSource, isNot(contains('/v1/sync/replace')));
    expect(source, contains('performMultiDeviceSync(pushLocalChanges: true, pullFullCloudCopy: true)'));
    expect(source, contains('Backup merged with local data'));
  });

  test('Android automatic backup uses persisted Storage Access Framework access', () {
    final dartSource = File('lib/android_saf_backup_store.dart').readAsStringSync();
    final androidSource = File('android/app/src/main/kotlin/com/koinly/siam/MainActivity.kt').readAsStringSync();

    expect(dartSource, contains('com.koinly.siam/backup_storage'));
    expect(androidSource, contains('Intent.ACTION_OPEN_DOCUMENT_TREE'));
    expect(androidSource, contains('takePersistableUriPermission'));
    expect(androidSource, contains('DocumentsContract.createDocument'));
  });
}
