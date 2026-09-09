import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction date and time pickers support opt-in ranges and scrolling', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('class TransactionDateSelection'));
    expect(source, contains("label: 'Single date'"));
    expect(source, contains("label: 'Use range'"));
    expect(source, contains("'Select transaction date'"));
    expect(source, contains('thumbVisibility: true'));
    expect(source, contains('pickTransactionTimeSelection'));
    expect(source, contains("label: 'Single time'"));
    expect(source, contains("'Select transaction time range'"));
    expect(source, contains('timeRangeEnabled'));
    expect(source, contains('dateRangeEnabled'));
    expect(source, contains('endOn: hasEffectiveRange ? selectedEndDate : null'));
  });

  test('new transaction amount uses a focus-aware placeholder instead of a real zero', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final amount = TextEditingController();'));
    expect(source, isNot(contains("final amount = TextEditingController(text: '0');")));
    expect(source, contains('final amountFocus = FocusNode();'));
    expect(source, contains("hintText: _amountHasFocus ? null : '0'"));
    expect(source, contains('_dismissAmountFocus();'));
  });
}
