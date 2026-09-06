import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/models.dart';

void main() {
  test('linked loan account movement does not affect income reports', () {
    final now = DateTime.utc(2025, 1, 1);
    final transaction = MoneyTransaction(
      id: 'transaction-1',
      type: MoneyTransactionType.income,
      amount: 500,
      notes: 'Loan repayment',
      categoryId: 'loan-repayment',
      fromAccountId: 'account-1',
      excludeFromReports: true,
      linkedEntityType: 'loan_payment',
      linkedEntityId: 'payment-1',
      createdOn: now,
      updatedOn: now,
    );

    expect(transaction.countsAsIncome, isFalse);
    expect(transaction.countsAsExpense, isFalse);
    expect(transaction.toMap()['exclude_from_reports'], 1);
    expect(MoneyTransaction.fromMap(transaction.toMap()).excludeFromReports, isTrue);
  });

  test('ordinary transactions retain existing reporting behavior', () {
    final now = DateTime.utc(2025, 1, 1);
    final transaction = MoneyTransaction(
      id: 'transaction-2',
      type: MoneyTransactionType.expense,
      amount: 25,
      notes: 'Groceries',
      categoryId: 'groceries',
      fromAccountId: 'account-1',
      createdOn: now,
      updatedOn: now,
    );

    expect(transaction.countsAsExpense, isTrue);
    expect(transaction.countsAsIncome, isFalse);
  });
}
