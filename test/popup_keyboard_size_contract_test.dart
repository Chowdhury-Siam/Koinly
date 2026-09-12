import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening the keyboard does not shrink shared center popups', () {
    final app = File('lib/main.dart').readAsStringSync();
    final frameStart = app.indexOf('class _KoinlyPopupFrame extends StatelessWidget');
    final contentStart = app.indexOf('class KoinlyPopupContent extends StatelessWidget');

    expect(frameStart, greaterThanOrEqualTo(0));
    expect(contentStart, greaterThan(frameStart));

    final frame = app.substring(frameStart, contentStart);
    expect(frame, contains('final keyboardVisible = media.viewInsets.bottom > 0;'));
    expect(frame, contains('media.size.height - media.padding.top - media.padding.bottom - (verticalInset * 2)'));
    expect(frame, isNot(contains('media.size.height - media.padding.top - media.padding.bottom - media.viewInsets.bottom')));
    expect(frame, contains('padding: EdgeInsets.fromLTRB(horizontalInset, verticalInset, horizontalInset, verticalInset)'));
    expect(frame, isNot(contains('verticalInset + media.viewInsets.bottom')));
    expect(frame, contains('alignment: keyboardVisible ? Alignment.topCenter : Alignment.center'));
  });

  test('popup body only scales for the actual safe viewport', () {
    final app = File('lib/main.dart').readAsStringSync();
    final contentStart = app.indexOf('class KoinlyPopupContent extends StatelessWidget');
    final onboardingStart = app.indexOf('// -----------------------------------------------------------------------------\n// Onboarding', contentStart);

    expect(contentStart, greaterThanOrEqualTo(0));
    expect(onboardingStart, greaterThan(contentStart));

    final content = app.substring(contentStart, onboardingStart);
    expect(content, contains('fit: BoxFit.scaleDown'));
    expect(content, isNot(contains('viewInsets')));
  });
}
