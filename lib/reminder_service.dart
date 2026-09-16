import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'android_background_permission_service.dart';
import 'app_config.dart';

class LoanDueReminder {
  const LoanDueReminder({
    required this.id,
    required this.personName,
    required this.dueDate,
    required this.amountText,
    required this.toCollect,
  });

  final String id;
  final String personName;
  final DateTime dueDate;
  final String amountText;
  final bool toCollect;
}

class ReminderService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> ensureInitialized({bool requestPermission = true}) async {
    if (!kSupportsLocalNotifications) return;
    await _configureLocalTimeZone();
    if (!_initialized) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _notifications.initialize(settings);
      _initialized = true;
    }
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (requestPermission) await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> _configureLocalTimeZone() async {
    tzdata.initializeTimeZones();
    final deviceTimeZoneId = await AndroidBackgroundPermissionService.deviceTimeZoneId();
    if (deviceTimeZoneId != null) {
      try {
        tz.setLocalLocation(tz.getLocation(deviceTimeZoneId));
        return;
      } on tz.LocationNotFoundException {
        // Some OEMs return fixed-offset IDs instead of an IANA zone. Fall
        // through to an offset match so reminders still use local wall time.
      }
    }

    final now = DateTime.now();
    final nowUtcMillis = now.toUtc().millisecondsSinceEpoch;
    final offsetMillis = now.timeZoneOffset.inMilliseconds;
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.timeZone(nowUtcMillis).offset == offsetMillis) {
        tz.setLocalLocation(location);
        return;
      }
    }
  }

  static Future<void> requestNotificationPermission() async {
    if (!kSupportsLocalNotifications) return;
    await ensureInitialized(requestPermission: false);
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<bool> requestExactAlarmPermission() async {
    if (!kSupportsLocalNotifications) return true;
    await ensureInitialized(requestPermission: false);
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await androidPlugin?.requestExactAlarmsPermission() ?? true;
    } on PlatformException {
      return false;
    }
  }

  static bool _isExactAlarmPermissionError(PlatformException error) =>
      error.code == 'exact_alarms_not_permitted';

  static Future<void> _zonedScheduleWithExactFallback({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    Future<void> schedule(AndroidScheduleMode mode) => _notifications.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          details,
          payload: payload,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );

    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (error) {
      if (!_isExactAlarmPermissionError(error)) rethrow;
      // Android 12+ can deny exact-alarm special access. Do not drop the
      // reminder in that case: keep a best-effort inexact alarm scheduled.
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static Future<void> scheduleDaily(TimeOfDay time) async {
    if (!kSupportsLocalNotifications) return;
    await ensureInitialized(requestPermission: false);
    await cancel();
    final scheduled = _next(time);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_expense_reminder',
        'Daily expense reminder',
        channelDescription: 'Reminder to add daily expenses.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _zonedScheduleWithExactFallback(
      id: 501,
      title: 'Koinly',
      body: "Don’t forget to record your expenses",
      scheduledDate: scheduled,
      details: details,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _next(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var date = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (date.isBefore(now)) date = date.add(const Duration(days: 1));
    return date;
  }

  static Future<void> cancel() async {
    if (!kSupportsLocalNotifications) return;
    await _notifications.cancel(501);
  }

  static int _stableLoanNotificationId(String id) {
    final bytes = sha256.convert(utf8.encode(id)).bytes;
    final value = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return 100000 + (value & 0x3FFFFFFF);
  }

  static Future<void> scheduleLoanDueReminders(List<LoanDueReminder> reminders) async {
    if (!kSupportsLocalNotifications) return;
    await ensureInitialized(requestPermission: false);
    await cancelLoanDueReminders();
    final now = tz.TZDateTime.now(tz.local);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'loan_due_reminder',
        'Loan due reminders',
        channelDescription: 'Reminders for upcoming lending and borrowing due dates.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    for (final reminder in reminders.take(25)) {
      var scheduled = tz.TZDateTime(
        tz.local,
        reminder.dueDate.year,
        reminder.dueDate.month,
        reminder.dueDate.day - 1,
        10,
      );
      if (!scheduled.isAfter(now)) {
        scheduled = tz.TZDateTime(tz.local, reminder.dueDate.year, reminder.dueDate.month, reminder.dueDate.day, 10);
      }
      if (!scheduled.isAfter(now)) continue;
      await _zonedScheduleWithExactFallback(
        id: _stableLoanNotificationId(reminder.id),
        title: reminder.toCollect ? 'Payment due from ${reminder.personName}' : 'Payment due to ${reminder.personName}',
        body: reminder.toCollect
            ? '${reminder.amountText} is still expected.'
            : '${reminder.amountText} is still due.',
        scheduledDate: scheduled,
        details: details,
        payload: 'loan:${reminder.id}',
      );
    }
  }

  static Future<void> cancelLoanDueReminders() async {
    if (!kSupportsLocalNotifications) return;
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending.where((item) => item.payload?.startsWith('loan:') == true)) {
      await _notifications.cancel(request.id);
    }
  }

  static Future<void> showUpdateAvailableNotification({
    required String version,
    String? releaseName,
  }) async {
    if (!kSupportsLocalNotifications) return;
    await ensureInitialized(requestPermission: false);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'koinly_app_updates',
        'Koinly updates',
        channelDescription: 'Notifications when a newer Koinly release is available.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final name = releaseName?.trim() ?? '';
    await _notifications.show(
      902,
      'Koinly $version is available',
      name.isEmpty ? 'A new update is ready. Open Koinly to review what changed.' : '$name is ready. Open Koinly to review what changed.',
      details,
      payload: 'update:$version',
    );
  }

  static Future<void> cancelUpdateAvailableNotification() async {
    if (!kSupportsLocalNotifications) return;
    await _notifications.cancel(902);
  }
}
