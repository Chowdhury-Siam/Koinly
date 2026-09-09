import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('elastic motion stays enabled without defeating accessibility reduced motion', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final foundation = File('lib/ui_foundation.dart').readAsStringSync();

    expect(mainSource, contains('disableAnimations: media.disableAnimations'));
    expect(mainSource, isNot(contains('disableAnimations: kLowEndFriendlyUi || media.disableAnimations')));
    expect(foundation, contains('class MotionInkWell'));
    expect(foundation, contains('class MotionTouchFeedback'));
    expect(foundation, contains('SpringSimulation'));
    expect(foundation, contains('extends BouncingScrollPhysics'));
    expect(mainSource, contains('MotionInkWell('));
    expect(mainSource, contains("label: const Text('Plan')"));
    expect(mainSource, contains('AppMotion.selectionHaptic(context)'));
  });
}
