import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic updates use native Android WorkManager when Koinly is closed', () {
    final app = File('lib/main.dart').readAsStringSync();
    final background = File('lib/update_background_service.dart').readAsStringSync();
    final nativeWorker = File('android/app/src/main/kotlin/com/koinly/siam/UpdateCheckWorker.kt').readAsStringSync();
    final activity = File('android/app/src/main/kotlin/com/koinly/siam/MainActivity.kt').readAsStringSync();
    final reminders = File('lib/reminder_service.dart').readAsStringSync();

    expect(app, contains('await UpdateBackgroundService.initialize();'));
    expect(app, contains('await UpdateBackgroundService.setEnabled(enabled);'));
    expect(background, contains("MethodChannel('com.koinly.siam/update_background')"));
    expect(background, contains("cancelByUniqueName(_legacyBackgroundUpdateUniqueName)"));
    expect(background, contains("invokeMethod<void>('sync', {'enabled': enabled})"));
    expect(nativeWorker, contains('PeriodicWorkRequestBuilder<UpdateCheckWorker>(15, TimeUnit.MINUTES)'));
    expect(nativeWorker, contains('.setRequiredNetworkType(NetworkType.CONNECTED)'));
    expect(nativeWorker, contains('ExistingPeriodicWorkPolicy.UPDATE'));
    expect(nativeWorker, contains('.getPackageInfo(applicationContext.packageName, 0)'));
    expect(nativeWorker, contains('https://api.github.com/repos/Chowdhury-Siam/Koinly/releases/latest'));
    expect(nativeWorker, contains('Koinly ${release.version} is available'));
    expect(nativeWorker, contains('lastNotifiedUpdateVersion'));
    expect(activity, contains('NativeUpdateCheckScheduler.sync(this)'));
    expect(activity, contains('updateBackgroundChannel'));
    expect(reminders, contains("'koinly_app_updates'"));
    expect(reminders, contains("'Koinly updates'"));
  });

  test('home wave and empty-state icon motion are contextual and reduce-motion aware', () {
    final app = File('lib/main.dart').readAsStringSync();
    final lottie = File('assets/lottie/empty_state.json').readAsStringSync();

    expect(app, contains('class _DecorativeSparkline extends StatefulWidget'));
    expect(app, contains('_controller.repeat();'));
    expect(app, contains('MediaQuery.of(context).disableAnimations'));
    expect(app, contains('class _AnimatedEmptyStateIcon extends StatefulWidget'));
    expect(app, contains('_AnimatedEmptyStateIcon(icon: icon, color: color)'));
    expect(app, contains("Lottie.asset('assets/lottie/empty_state.json'"));
    expect(lottie, isNot(contains('Wallet')));
  });

  test('semantic feedback is a compact safe-area top overlay', () {
    final app = File('lib/main.dart').readAsStringSync();
    expect(app, contains('class _KoinlyTopFeedbackBanner extends StatefulWidget'));
    expect(app, contains('media.padding.top +'));
    expect(app, contains('constraints: const BoxConstraints(minHeight: 68, maxHeight: 94)'));
    expect(app, contains('ContentType.success'));
    expect(app, isNot(contains('final materialBanner = MaterialBanner(')));
    expect(app, isNot(contains('inMaterialBanner: true')));
  });
}
