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

  test('Android release keeps the dedicated uncropped Koinly splash resources', () {
    final baseStyles = File('android/app/src/main/res/values/styles.xml').readAsStringSync();
    final android12Styles = File('android/app/src/main/res/values-v31/styles.xml').readAsStringSync();
    final launchBackground = File('android/app/src/main/res/drawable/launch_background.xml').readAsStringSync();
    final workflow = File('.github/workflows/build-android-apks.yml').readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();

    expect(File('android/app/src/main/res/drawable-nodpi/koinly_splash_icon.png').existsSync(), isTrue);
    expect(File('assets/icons/koinly_mark.png').existsSync(), isTrue);
    expect(app, contains("Image.asset('assets/icons/koinly_mark.png'"));
    expect(app, contains('width: 88'));
    expect(app, contains('height: 104'));
    expect(baseStyles, contains('@drawable/launch_background'));
    expect(android12Styles, contains('android:windowSplashScreenAnimatedIcon'));
    expect(android12Styles, contains('@drawable/koinly_splash_icon'));
    expect(launchBackground, contains('@drawable/koinly_splash_icon'));
    expect(workflow, contains('cp -a android \"\$ANDROID_SOURCE\"'));
    expect(workflow, contains('rm -rf android'));
    expect(workflow, contains('cp -a \"\$ANDROID_SOURCE\" android'));
    expect(workflow, contains("grep -q '@drawable/koinly_splash_icon'"));
  });

  test('Account and sync keeps restore and upload actions side by side', () {
    final app = File('lib/main.dart').readAsStringSync();
    final restoreIndex = app.indexOf("label: const Text('Restore cloud copy')");
    final uploadIndex = app.indexOf('label: Text(uploadButtonLabel)');
    final recoveryIndex = app.indexOf("label: const Text('Recovery key')");

    expect(restoreIndex, greaterThan(0));
    expect(uploadIndex, greaterThan(restoreIndex));
    expect(recoveryIndex, greaterThan(uploadIndex));
    final actionBlock = app.substring(restoreIndex - 900, recoveryIndex + 250);
    expect(actionBlock, contains('Row('));
    expect(actionBlock, contains('const SizedBox(width: 10)'));
  });
}
