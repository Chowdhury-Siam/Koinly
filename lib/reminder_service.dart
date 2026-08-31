import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  static Future<void> ensureInitialized() async {
    if (!kSupportsLocalNotifications) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> scheduleDaily(TimeOfDay time) async {
    if (!kSupportsLocalNotifications) return;
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
    await _notifications.zonedSchedule(
      501,
      'Koinly',
      "Don’t forget to record your expenses",
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
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
      await _notifications.zonedSchedule(
        _stableLoanNotificationId(reminder.id),
        reminder.toCollect ? 'Payment due from ${reminder.personName}' : 'Payment due to ${reminder.personName}',
        reminder.toCollect
            ? '${reminder.amountText} is still expected.'
            : '${reminder.amountText} is still due.',
        scheduled,
        details,
        payload: 'loan:${reminder.id}',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
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
}
