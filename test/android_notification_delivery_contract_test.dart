import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android scheduled notifications declare the plugin receivers and exact-alarm access', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(
      manifest,
      contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'),
    );
    expect(
      manifest,
      contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'),
    );
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });

  test('reminders use the device time zone and exact scheduling with safe fallback', () {
    final reminders = File('lib/reminder_service.dart').readAsStringSync();
    final bridge = File('lib/android_background_permission_service.dart').readAsStringSync();
    final activity = File('android/app/src/main/kotlin/com/koinly/siam/MainActivity.kt').readAsStringSync();

    expect(bridge, contains("invokeMethod<String>('deviceTimeZoneId')"));
    expect(activity, contains('TimeZone.getDefault().id'));
    expect(reminders, contains('tz.setLocalLocation(tz.getLocation(deviceTimeZoneId))'));
    expect(reminders, contains('AndroidScheduleMode.exactAllowWhileIdle'));
    expect(reminders, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
    expect(reminders, contains("error.code == 'exact_alarms_not_permitted'"));
    expect(reminders, contains('requestExactAlarmsPermission()'));
  });

  test('saved daily reminder is recreated on launch and exact access is requested when enabled', () {
    final app = File('lib/main.dart').readAsStringSync();

    expect(app, contains('if (reminderEnabled && kSupportsLocalNotifications)'));
    expect(app, contains('await ReminderService.scheduleDaily(reminderTime);'));
    expect(app, contains('await ReminderService.requestExactAlarmPermission();'));
  });
}
