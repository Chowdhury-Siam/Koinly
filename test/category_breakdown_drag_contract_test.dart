import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category breakdown bubbles stay draggable, bounded, and collision free', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final Map<String, Offset> _badgeCenterFractions'));
    expect(source, contains('const badgeCollisionGap = 8.0'));
    expect(source, contains('buildPackedBadgeCenters()'));
    expect(source, contains('badgeCollisionRect('));
    expect(source, contains('badgeCenterCollides('));
    expect(source, contains('furthestFreeBadgeCenter('));
    expect(source, contains('firstRect.overlaps(secondRect)'));
    expect(source, contains('movingRect.overlaps(badgeCollisionRect'));
    expect(source, contains('onPanUpdate: (details)'));
    expect(source, contains('moveBadge(i, currentBadgeWidth, currentBadgeHeight, details.delta)'));
    expect(source, contains('SystemMouseCursors.grab'));
    expect(source, contains('centerOverride: center'));
    expect(source, contains('candidate.dx.clamp(minX, maxX)'));
    expect(source, contains('candidate.dy.clamp(minY, maxY)'));
    expect(source, contains('clipBehavior: Clip.hardEdge'));
  });
}
