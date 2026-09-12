import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app_config.dart';
import 'reminder_service.dart';
import 'subscription_background_service.dart';
import 'update_service.dart';

const _backgroundUpdateUniqueName = 'koinly-periodic-update-check';
const _backgroundUpdateTaskName = 'koinlyUpdateCheck';
const _backgroundSubscriptionUniqueName = 'koinly-periodic-subscription-check';
const _backgroundSubscriptionTaskName = 'koinlySubscriptionCheck';
const _backgroundUpdateFrequency = Duration(minutes: 15);
const _automaticUpdatePreferenceKey = 'automaticUpdatePopupEnabled';
const _lastNotifiedUpdateVersionKey = 'lastNotifiedUpdateVersion';

@pragma('vm:entry-point')
void koinlyBackgroundUpdateDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName == _backgroundUpdateTaskName) {
      return UpdateBackgroundService.runBackgroundCheck();
    }
    if (taskName == _backgroundSubscriptionTaskName) {
      await SubscriptionBackgroundService.processDueNow();
      return true;
    }
    return true;
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
    await Workmanager().registerPeriodicTask(
      _backgroundSubscriptionUniqueName,
      _backgroundSubscriptionTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'koinly-subscriptions',
    );
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
      // Android WorkManager's minimum periodic interval is 15 minutes.
      // Keeping the updater at that floor means a release can be discovered
      // while Koinly is closed instead of waiting for the next foreground launch.
      frequency: _backgroundUpdateFrequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
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
