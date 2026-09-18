import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category spending rows reserve one shared amount column width', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final displayedCategoryEntries = topCategories.take(4).toList();'));
    expect(source, contains('final categoryAmountWidth = displayedCategoryEntries.fold<double>'));
    expect(source, contains('width: categoryAmountWidth'));
    expect(source, contains('textAlign: TextAlign.end'));

    // The card must not own horizontal padding around the interactive rows.
    // Otherwise ListTile's hover/focus ink is inset and looks like a floating
    // invisible field that stops short of the actual category row width.
    expect(source, contains('padding: const EdgeInsets.symmetric(vertical: 18)'));
    expect(source, contains('contentPadding: const EdgeInsets.symmetric(horizontal: 18)'));
  });
}
