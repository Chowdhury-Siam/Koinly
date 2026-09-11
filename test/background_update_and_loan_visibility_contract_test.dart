import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed-app update polling uses the Android periodic minimum', () {
    final background = File('lib/update_background_service.dart').readAsStringSync();

    expect(background, contains('Duration(minutes: 15)'));
    expect(background, contains('frequency: _backgroundUpdateFrequency'));
    expect(background, contains('NetworkType.connected'));
    expect(background, isNot(contains('requiresBatteryNotLow: true')));
  });

  test('loan preferences can hide linked movements only from Transaction list', () {
    final app = File('lib/main.dart').readAsStringSync();
    final controller = File('lib/loans/loan_controller_part.dart').readAsStringSync();
    final sheet = File('lib/loans/loan_sheets.dart').readAsStringSync();

    expect(app, contains('bool loanTransactionsVisibleInTransactionList = true;'));
    expect(app, contains('List<MoneyTransaction> transactionListTransactions()'));
    expect(app, contains('visible.where((tx) => !tx.isLoanTransaction).toList()'));
    expect(app, contains('final txs = state.transactionListTransactions();'));
    expect(controller, contains('showTransactionsInTransactionList'));
    expect(sheet, contains('Show loan transactions in Transaction'));
  });
}
