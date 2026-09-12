import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category breakdown bubbles stay draggable and bounded', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final Map<String, Offset> _badgeCenterFractions'));
    expect(source, contains('onPanUpdate: (details)'));
    expect(source, contains('moveBadge(i, currentBadgeWidth, currentBadgeHeight, details.delta)'));
    expect(source, contains('SystemMouseCursors.grab'));
    expect(source, contains('centerOverride: center'));
    expect(source, contains("candidate.dx.clamp(minX, maxX)"));
    expect(source, contains("candidate.dy.clamp(minY, maxY)"));
    expect(source, contains('clipBehavior: Clip.hardEdge'));
  });
}
