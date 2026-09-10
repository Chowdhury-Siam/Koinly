import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loan-linked transactions use the dedicated Loan editor classification only', () {
    final models = File('lib/models.dart').readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();

    expect(models, contains("linkedEntityType == 'loans' || linkedEntityType == 'loan_payments'"));
    expect(models, contains("isLoanTransaction ? 'Loan' : enumName(type)"));
    expect(app, contains("final isLoanTransaction = widget.transaction?.isLoanTransaction ?? false;"));
    expect(app, contains("SleekPillOption(value: type, label: 'Loan'"));
    expect(app, contains("Text('Loan', style:"));
    expect(app, contains("widget.transaction?.linkedEntityType == 'loan_payments' ? 'Loan repayment' : 'Loan disbursal'"));
    expect(app, contains('else if (isLoanTransaction) {\n                  await state.updateLinkedLoanTransaction(tx);'));
  });

  test('loan transaction edits and deletes keep linked loan data synchronized', () {
    final controller = File('lib/loans/loan_controller_part.dart').readAsStringSync();
    final repository = File('lib/loans/loan_repository.dart').readAsStringSync();

    expect(controller, contains('Future<void> updateLinkedLoanTransaction(MoneyTransaction candidate)'));
    expect(controller, contains('Future<void> deleteLinkedLoanTransaction(MoneyTransaction transaction)'));
    expect(controller, contains('allocateLoanPayment(loan, otherPayments, candidate.amount, candidate.createdOn)'));
    expect(controller, contains('clearDisbursalTransactionId: true'));
    expect(repository, contains('Future<void> updatePaymentWithTransaction('));
    expect(repository, contains('Future<void> updateLoanWithDisbursalTransaction('));
  });
}
