import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notifications use the dedicated monochrome Koinly status icon', () {
    final icon = File('android/app/src/main/res/drawable/ic_stat_koinly.xml').readAsStringSync();
    final reminders = File('lib/reminder_service.dart').readAsStringSync();
    final worker = File('android/app/src/main/kotlin/com/koinly/siam/UpdateCheckWorker.kt').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(icon, contains('android:fillColor="#FFFFFFFF"'));
    expect(icon, contains('android:pathData='));
    expect(reminders, contains("AndroidInitializationSettings('ic_stat_koinly')"));
    expect(RegExp("icon: 'ic_stat_koinly'").allMatches(reminders).length, greaterThanOrEqualTo(3));
    expect(worker, contains('.setSmallIcon(R.drawable.ic_stat_koinly)'));
    expect(worker, isNot(contains('android.R.drawable.stat_sys_download_done')));
    expect(manifest, contains('com.google.firebase.messaging.default_notification_icon'));
    expect(manifest, contains('@drawable/ic_stat_koinly'));
  });
}
