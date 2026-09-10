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
    expect(foundation, contains('class KoinlyDesktopScrollPhysics extends BouncingScrollPhysics'));
    expect(foundation, contains('class _DesktopElasticScrollFeedback extends StatefulWidget'));
    expect(foundation, contains('onPointerSignal: _onPointerSignal'));
    expect(foundation, contains('onPointerDown: _pointerDown'));
    expect(foundation, contains('onEnter: (_) => _hover(true)'));
    expect(
      foundation,
      isNot(contains('if (kIsDesktopApp) return const RangeMaintainingScrollPhysics(parent: ClampingScrollPhysics())')),
    );
    expect(mainSource, contains('MotionInkWell('));
    expect(mainSource, contains("label: const Text('Plan')"));
    expect(mainSource, contains('AppMotion.selectionHaptic(context)'));
  });
}
