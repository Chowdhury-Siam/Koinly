import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic update pop-up can be disabled without disabling manual checks', () {
    final app = File('lib/main.dart').readAsStringSync();

    expect(app, contains('bool automaticUpdatePopupEnabled = true;'));
    expect(app, contains("prefs.getBool('automaticUpdatePopupEnabled', true)"));
    expect(app, contains('setAutomaticUpdatePopupEnabled(bool enabled)'));
    expect(app, contains("title: const Text('Automatic update pop-ups'"));
    expect(app, contains('!state.automaticUpdatePopupEnabled'));
    expect(app, contains('checkForUpdates(manual: true)'));
  });

  test('Android uses a dedicated padded native splash icon', () {
    final baseStyles = File('android/app/src/main/res/values/styles.xml').readAsStringSync();
    final android12Styles = File('android/app/src/main/res/values-v31/styles.xml').readAsStringSync();
    final launchBackground = File('android/app/src/main/res/drawable/launch_background.xml').readAsStringSync();

    expect(File('android/app/src/main/res/drawable-nodpi/koinly_splash_icon.png').existsSync(), isTrue);
    expect(baseStyles, contains('@drawable/launch_background'));
    expect(android12Styles, contains('android:windowSplashScreenAnimatedIcon'));
    expect(android12Styles, contains('@drawable/koinly_splash_icon'));
    expect(launchBackground, contains('@drawable/koinly_splash_icon'));
  });
}
