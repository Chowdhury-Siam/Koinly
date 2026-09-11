import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic update preference controls Android background notification checks', () {
    final app = File('lib/main.dart').readAsStringSync();
    final background = File('lib/update_background_service.dart').readAsStringSync();
    final reminders = File('lib/reminder_service.dart').readAsStringSync();

    expect(app, contains('await UpdateBackgroundService.initialize();'));
    expect(app, contains('await UpdateBackgroundService.setEnabled(enabled);'));
    expect(background, contains('Workmanager().registerPeriodicTask('));
    expect(background, contains('NetworkType.connected'));
    expect(background, contains('ExistingPeriodicWorkPolicy.update'));
    expect(background, contains("prefs.getBool(_automaticUpdatePreferenceKey) ?? true"));
    expect(background, contains('_lastNotifiedUpdateVersionKey'));
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

  test('semantic Awesome Snackbar feedback is presented from the top', () {
    final app = File('lib/main.dart').readAsStringSync();
    expect(app, contains('final materialBanner = MaterialBanner('));
    expect(app, contains('inMaterialBanner: true'));
    expect(app, contains('messenger.showMaterialBanner(materialBanner)'));
  });
}
