import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category spending rows reserve one shared amount column width', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final displayedCategoryEntries = topCategories.take(4).toList();'));
    expect(source, contains('final categoryAmountWidth = displayedCategoryEntries.fold<double>'));
    expect(source, contains('width: categoryAmountWidth'));
    expect(source, contains('textAlign: TextAlign.end'));
  });
}
