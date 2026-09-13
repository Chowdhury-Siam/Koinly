import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysis cash flow chart uses the LineChartSample1 visual treatment', () {
    final app = File('lib/main.dart').readAsStringSync();

    expect(app, contains('curveSmoothness: .35'));
    expect(app, contains('barWidth: 8'));
    expect(app, contains('Color(0xFF2C274C)'));
    expect(app, contains('Color(0xFF46426C)'));
    expect(app, contains('Color(0xFF4E4965)'));
    expect(app, contains('gridData: const FlGridData(show: false)'));
    expect(app, contains('duration: const Duration(milliseconds: 250)'));
    expect(app, contains('curve: Curves.easeInOut'));
    expect(app, contains('Color(0xFF75729E)'));
    expect(app, contains('Color(0xFF72719B)'));

    // The replacement keeps the live Koinly series rather than hard-coded
    // demonstration points from the upstream sample.
    expect(app, contains('spots: incomeSpots'));
    expect(app, contains('spots: expenseSpots'));
    expect(app, isNot(contains('FlSpot(1, 1),\n      FlSpot(3, 1.5)')));
  });
}
