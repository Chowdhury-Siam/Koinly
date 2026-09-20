import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction screen exposes persistent re-sorting for existing data', () {
    final models = File('lib/models.dart').readAsStringSync();
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      models,
      contains(
        'enum TransactionSortMode { dateNewest, dateOldest, categoryAsc, categoryDesc, amountHigh, amountLow, titleAsc, titleDesc }',
      ),
    );
    expect(source, contains("'transactionSortMode',"));
    expect(source, contains('TransactionSortMode.values'));
    expect(source, contains("await prefs.setEnum('transactionSortMode', mode);"));
    expect(source, contains("'transactionSortMode': enumName(transactionSortMode)"));
    expect(source, contains("key: const ValueKey('transaction-sort-button')"));
    expect(source, contains("'Sort transactions'"));
    expect(source, contains("'Newest first'"));
    expect(source, contains("'Oldest first'"));
    expect(source, contains("'Category A–Z'"));
    expect(source, contains("'Category Z–A'"));
    expect(source, contains("'Amount high–low'"));
    expect(source, contains("'Amount low–high'"));
    expect(source, contains("'Title A–Z'"));
    expect(source, contains("'Title Z–A'"));
    expect(source, contains('_sortTransactionList(result);'));
    expect(source, contains('List<MoneyTransaction>.of(visible)'));
    expect(source, contains('respectLoanVisibility: false'));
  });
}
