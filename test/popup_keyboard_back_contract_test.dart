import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared keyboard back guard consumes back while the IME is visible', () {
    final app = File('lib/main.dart').readAsStringSync();
    final guardStart = app.indexOf('class _KeyboardDismissOnBack extends StatelessWidget');
    final pageStart = app.indexOf('class PageScaffold extends StatelessWidget');

    expect(guardStart, greaterThanOrEqualTo(0));
    expect(pageStart, greaterThan(guardStart));

    final guard = app.substring(guardStart, pageStart);
    expect(guard, contains('MediaQuery.viewInsetsOf(context).bottom > 0'));
    expect(guard, contains('return PopScope<Object?>('));
    expect(guard, contains('canPop: !keyboardVisible'));
    expect(guard, contains('onPopInvokedWithResult: (didPop, result)'));
    expect(guard, contains('if (didPop || !keyboardVisible) return;'));
    expect(guard, contains('FocusManager.instance.primaryFocus?.unfocus();'));
  });

  test('all standard pages and center popups use the keyboard back guard', () {
    final app = File('lib/main.dart').readAsStringSync();

    final pageStart = app.indexOf('class PageScaffold extends StatelessWidget');
    final atmosphereStart = app.indexOf('class KoinlyAtmosphere extends StatelessWidget');
    expect(pageStart, greaterThanOrEqualTo(0));
    expect(atmosphereStart, greaterThan(pageStart));
    final pageScaffold = app.substring(pageStart, atmosphereStart);
    expect(pageScaffold, contains('return _KeyboardDismissOnBack('));
    expect(pageScaffold, contains('child: Scaffold('));

    final frameStart = app.indexOf('class _KoinlyPopupFrame extends StatelessWidget');
    final contentStart = app.indexOf('class KoinlyPopupContent extends StatelessWidget');
    expect(frameStart, greaterThanOrEqualTo(0));
    expect(contentStart, greaterThan(frameStart));
    final frame = app.substring(frameStart, contentStart);
    expect(frame, contains('return _KeyboardDismissOnBack('));

    // Currency setup contains text inputs during first-run onboarding, which
    // uses its own Scaffold rather than PageScaffold. Guard that route too.
    final onboardingStart = app.indexOf('class OnboardingScreen extends StatefulWidget');
    final onboardingFrameStart = app.indexOf('class OnboardingPageFrame extends StatelessWidget');
    expect(onboardingStart, greaterThanOrEqualTo(0));
    expect(onboardingFrameStart, greaterThan(onboardingStart));
    final onboarding = app.substring(onboardingStart, onboardingFrameStart);
    expect(onboarding, contains('return _KeyboardDismissOnBack('));
    expect(onboarding, contains('CurrencySetupPane(state: state)'));
  });

  test('transaction editor still uses the guarded center-popup route', () {
    final app = File('lib/main.dart').readAsStringSync();
    final editorStart = app.indexOf('Future<void> showTransactionEditor(');
    final stateStart = app.indexOf('class TransactionEditor extends StatefulWidget', editorStart);

    expect(editorStart, greaterThanOrEqualTo(0));
    expect(stateStart, greaterThan(editorStart));

    final editorLauncher = app.substring(editorStart, stateStart);
    expect(editorLauncher, contains('showKoinlyPopup<void>('));
    expect(editorLauncher, contains('child: TransactionEditor('));
  });
}
