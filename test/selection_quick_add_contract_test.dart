import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account and category pickers expose inline create actions', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains("addActionLabel: 'Add account'"));
    expect(source, contains("addActionLabel: 'Add category'"));
    expect(source, contains("return showKoinlyPopup<String>("));
    expect(source, contains('Navigator.pop(context, a.id)'));
    expect(source, contains('Navigator.pop(context, category.id)'));
    expect(source, contains('fixedType: categoryType'));
    expect(source, contains("'Nothing here yet. Add one to continue.'"));
  });

  test('cash-flow header exposes the net value beside the date control', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains("message: 'Net cash flow'"));
    expect(source, contains("Text(\n                        'Net',"));
    expect(source, contains('state.format(net)'));
    expect(source, contains("tooltip: 'Change date range'"));
  });
}
