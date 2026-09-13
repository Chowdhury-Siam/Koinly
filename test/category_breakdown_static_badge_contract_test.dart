import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category breakdown percentage bubbles are static and not draggable', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('class _CategoryBreakdownCardState');
    final end = source.indexOf('class _DonutBadgePositioned', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final breakdownSource = source.substring(start, end);

    expect(breakdownSource, contains('buildPackedBadgeCenters()'));
    expect(breakdownSource, contains('firstRect.overlaps(secondRect)'));
    expect(breakdownSource, contains('onTap: ()'));
    expect(breakdownSource, contains('center: center'));
    expect(breakdownSource, isNot(contains('centerOverride:')));
    expect(breakdownSource, contains('clipBehavior: Clip.hardEdge'));

    expect(breakdownSource, isNot(contains('_badgeCenterFractions')));
    expect(breakdownSource, isNot(contains('draggingBadgeIndex')));
    expect(breakdownSource, isNot(contains('moveBadge(')));
    expect(breakdownSource, isNot(contains('onPanStart:')));
    expect(breakdownSource, isNot(contains('onPanUpdate:')));
    expect(breakdownSource, isNot(contains('onPanEnd:')));
    expect(breakdownSource, isNot(contains('onPanCancel:')));
    expect(breakdownSource, isNot(contains('SystemMouseCursors.grab')));
  });
}
