import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android settings expose battery optimization exemption for reliable background notifications', () {
    final app = File('lib/main.dart').readAsStringSync();
    final service = File('lib/android_background_permission_service.dart').readAsStringSync();
    final activity = File('android/app/src/main/kotlin/com/koinly/siam/MainActivity.kt').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(app, contains("const SectionHeader('Permissions')"));
    expect(app, contains("title: 'Ignore Battery Optimization'"));
    expect(app, contains("'Permission granted'"));
    expect(app, contains('AndroidBackgroundPermissionService.openBatteryOptimizationSettings()'));
    expect(service, contains("MethodChannel('com.koinly.siam/background_permissions')"));
    expect(service, isNot(contains('requestIgnoreBatteryOptimizations')));
    expect(activity, contains('Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'));
    expect(activity, contains('PowerManager'));
    expect(manifest, isNot(contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
  });

  test('notification feature toggles request notification permission on Android', () {
    final app = File('lib/main.dart').readAsStringSync();
    final reminders = File('lib/reminder_service.dart').readAsStringSync();

    expect(reminders, contains('static Future<void> requestNotificationPermission()'));
    expect(app, contains('await ReminderService.requestNotificationPermission();'));
  });
}
