import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic local backup UI stays concise and Android runs in background', () {
    final main = File('lib/main.dart').readAsStringSync();
    final safStore = File('lib/android_saf_backup_store.dart').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/koinly/siam/MainActivity.kt',
    ).readAsStringSync();
    final worker = File(
      'android/app/src/main/kotlin/com/koinly/siam/AutomaticBackupWorker.kt',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(
      main,
      isNot(contains(
        'Choose a parent location once. Koinly creates and uses ' +
            'Koinly/Backup there, with persistent Android folder access for scheduled backups.',
      )),
    );
    expect(
      main,
      isNot(contains(
        'When on, Koinly deletes previous automatic backups after a new one is saved, ' +
            'so only the latest automatic backup remains. Turn it off to keep backup history.',
      )),
    );
    expect(
      main,
      isNot(contains('Creates encrypted ' + '.koinlybackup files on this device.')),
    );
    expect(
      main,
      isNot(contains(
        'If Koinly is closed at the scheduled time, the missed backup is created ' +
            'the next time the app opens or resumes.',
      )),
    );

    expect(main, contains('_syncAndroidAutomaticBackupWorker'));
    expect(main, contains('refreshAutomaticBackupState'));
    expect(main, contains('autoBackupBackgroundError'));
    expect(safStore, contains("'syncAutomaticBackup'"));
    expect(activity, contains('"syncAutomaticBackup"'));
    expect(activity, contains('AutomaticBackupScheduler.sync(this)'));

    expect(worker, contains('class AutomaticBackupWorker'));
    expect(worker, contains('PeriodicWorkRequestBuilder<AutomaticBackupWorker>'));
    expect(worker, contains('koinly-native-automatic-local-backup'));
    expect(worker, contains('FlutterSharedPreferences'));
    expect(worker, contains('koinly_flutter.db'));
    expect(worker, contains('DocumentsContract'));
    expect(worker, contains('lastAutoBackupAt'));
    expect(worker, contains('autoBackupBackgroundError'));
    expect(worker, contains('koinly_auto_'));
    expect(worker, contains('YOUR_SECRET_PASSWORD'));
    expect(gradle, contains('androidx.work:work-runtime-ktx:2.10.2'));
  });
}
