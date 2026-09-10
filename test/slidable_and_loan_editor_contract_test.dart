import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slidable rows use grouped rounded actions and atomic tab stage', () {
    final app = File('lib/main.dart').readAsStringSync();
    final loans = File('lib/loans/loan_screens.dart').readAsStringSync();

    expect(app, contains('SlidableAutoCloseBehavior('));
    expect(app, contains("groupTag: 'transactions'"));
    expect(app, contains("groupTag: 'planned-purchases'"));
    expect(loans, contains("groupTag: 'loans'"));
    expect(app, contains('class _KoinlySlidableAction extends StatelessWidget'));
    expect(app, contains('motion: const BehindMotion()'));
    expect(loans, contains('motion: const BehindMotion()'));

    final switcherIndex = app.indexOf('child: AnimatedSwitcher(');
    final keyedStageIndex = app.indexOf('key: ValueKey<int>(tabIndex)', switcherIndex);
    final pageIndex = app.indexOf('Positioned.fill(child: pages[tabIndex])', keyedStageIndex);
    final planIndex = app.indexOf('if (planButton != null)', keyedStageIndex);
    final dockIndex = app.indexOf('child: _FloatingDockNavigation(', keyedStageIndex);
    expect(switcherIndex, greaterThanOrEqualTo(0));
    expect(keyedStageIndex, greaterThan(switcherIndex));
    expect(pageIndex, greaterThan(keyedStageIndex));
    expect(planIndex, greaterThan(pageIndex));
    expect(dockIndex, greaterThan(planIndex));
  });

  test('loan editor no longer exposes Plan or Account movement controls', () {
    final file = File('lib/loans/loan_sheets.dart').readAsStringSync();
    final start = file.indexOf('class _LoanEditorSheetState');
    final end = file.indexOf('Future<void> showLoanPaymentSheet', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final editor = file.substring(start, end);

    expect(editor, isNot(contains("SectionHeader('Plan')")));
    expect(editor, isNot(contains('Monthly installments (optional)')));
    expect(editor, isNot(contains("SectionHeader('Account movement')")));
    expect(editor, isNot(contains('Record this in an account')));
    expect(editor, contains('state.loanRecordTransactionsByDefault'));
    expect(editor, contains('state.defaultAccountId ?? state.accounts.firstOrNull?.id'));
    expect(editor, contains('installmentCount: old?.installmentCount'));
  });
}
