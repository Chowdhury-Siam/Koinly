import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app_config.dart';
import 'reminder_service.dart';
import 'update_service.dart';

const _backgroundUpdateUniqueName = 'koinly-periodic-update-check';
const _backgroundUpdateTaskName = 'koinlyUpdateCheck';
const _automaticUpdatePreferenceKey = 'automaticUpdatePopupEnabled';
const _lastNotifiedUpdateVersionKey = 'lastNotifiedUpdateVersion';

@pragma('vm:entry-point')
void koinlyBackgroundUpdateDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName != _backgroundUpdateTaskName) return true;
    return UpdateBackgroundService.runBackgroundCheck();
  });
}

class UpdateBackgroundService {
  const UpdateBackgroundService._();

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(koinlyBackgroundUpdateDispatcher);
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_automaticUpdatePreferenceKey) ?? true;
    await setEnabled(enabled);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_backgroundUpdateUniqueName);
      await ReminderService.cancelUpdateAvailableNotification();
      return;
    }
    await Workmanager().registerPeriodicTask(
      _backgroundUpdateUniqueName,
      _backgroundUpdateTaskName,
      frequency: const Duration(hours: 6),
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'koinly-updates',
    );
  }

  static Future<bool> runBackgroundCheck() async {
    if (!Platform.isAndroid) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_automaticUpdatePreferenceKey) ?? true)) return true;
      final result = await GithubUpdateService().check(installedVersion: appVersion);
      if (result.hasUpdate && result.release != null) {
        await notifyReleaseIfNeeded(result.release!);
      }
      return result.outcome != UpdateCheckOutcome.networkError &&
          result.outcome != UpdateCheckOutcome.httpError;
    } catch (_) {
      return false;
    }
  }

  static Future<void> notifyReleaseIfNeeded(GithubRelease release) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_automaticUpdatePreferenceKey) ?? true)) return;
    if (prefs.getString(_lastNotifiedUpdateVersionKey) == release.displayVersion) return;

    await ReminderService.showUpdateAvailableNotification(
      version: release.displayVersion,
      releaseName: release.name,
    );
    await prefs.setString(_lastNotifiedUpdateVersionKey, release.displayVersion);
  }
}
