import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category breakdown uses the full fl_chart pie with edge badges', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('class _CategoryBreakdownCardState');
    final end = source.indexOf('class CategoryTransactionScreen', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final breakdownSource = source.substring(start, end);

    expect(breakdownSource, contains('PieChart('));
    expect(breakdownSource, contains('centerSpaceRadius: 0'));
    expect(breakdownSource, contains('titlePositionPercentageOffset: .60'));
    expect(breakdownSource, contains('badgeWidget: _PieCategoryBadge('));
    expect(breakdownSource, contains('badgePositionPercentageOffset: badgeOffset'));
    expect(breakdownSource, contains('radius: selected ? selectedRadius : normalRadius'));
    expect(breakdownSource, contains('pieTouchData: PieTouchData('));
    expect(breakdownSource, contains("title: showPercent ? '\${percentage.round()}%' : ''"));

    expect(breakdownSource, isNot(contains('centerSpaceRadius: chartSize * .285')));
    expect(breakdownSource, isNot(contains('_DonutBadgePositioned')));
    expect(breakdownSource, isNot(contains('_DonutPercentBadge')));
    expect(breakdownSource, isNot(contains('buildPackedBadgeCenters()')));
    expect(breakdownSource, isNot(contains('draggingBadgeIndex')));
  });
}
