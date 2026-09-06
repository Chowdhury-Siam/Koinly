import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/loans/loan_computation.dart';
import 'package:koinly/loans/loan_models.dart';

Loan loan({
  double principal = 1000,
  LoanInterestType interestType = LoanInterestType.none,
  double interestRate = 0,
  LoanInterestPeriod interestPeriod = LoanInterestPeriod.yearly,
  DateTime? dueDate,
  LoanAccrualStop accrualStop = LoanAccrualStop.settled,
  int? installments,
}) {
  final start = DateTime.utc(2025, 1, 1);
  return Loan(
    id: 'loan-1',
    contactId: 'contact-1',
    direction: LoanDirection.lent,
    principal: principal,
    interestType: interestType,
    interestRate: interestRate,
    interestPeriod: interestPeriod,
    startDate: start,
    dueDate: dueDate,
    installmentCount: installments,
    interestAccrualStop: accrualStop,
    createdOn: start,
    updatedOn: start,
  );
}

LoanPayment payment(String id, double amount, DateTime date) => LoanPayment(
      id: id,
      loanId: 'loan-1',
      amount: amount,
      interestComponent: 0,
      principalComponent: amount,
      paidOn: date,
      createdOn: date,
      updatedOn: date,
    );

void main() {
  test('no-interest loan tracks partial and complete repayment', () {
    final value = loan();
    final partial = computeLoan(value, [payment('p1', 400, DateTime.utc(2025, 2, 1))], at: DateTime.utc(2025, 3, 1));
    expect(partial.totalDue, 1000);
    expect(partial.outstanding, 600);
    expect(partial.settled, isFalse);

    final settled = computeLoan(value, [
      payment('p1', 400, DateTime.utc(2025, 2, 1)),
      payment('p2', 600, DateTime.utc(2025, 3, 1)),
    ], at: DateTime.utc(2025, 3, 1));
    expect(settled.outstanding, 0);
    expect(settled.settled, isTrue);
  });

  test('simple interest uses annual APR and original principal', () {
    final value = loan(interestType: LoanInterestType.simple, interestRate: 10);
    final result = computeLoan(value, [payment('p1', 500, DateTime.utc(2025, 7, 2))], at: DateTime.utc(2026, 1, 1));
    expect(result.interestAccrued, 100);
    expect(result.totalDue, 1100);
    expect(result.outstanding, 600);
  });

  test('compound interest is reduced by an early principal payment', () {
    final value = loan(interestType: LoanInterestType.compound, interestRate: 10);
    final withoutPayment = computeLoan(value, const [], at: DateTime.utc(2027, 1, 1));
    final withPayment = computeLoan(
      value,
      [payment('p1', 600, DateTime.utc(2026, 1, 1))],
      at: DateTime.utc(2027, 1, 1),
    );
    expect(withoutPayment.totalDue, 1210);
    expect(withPayment.totalDue, 1150);
    expect(withPayment.outstanding, 550);
  });

  test('payments are allocated to accrued interest first', () {
    final value = loan(interestType: LoanInterestType.simple, interestRate: 10);
    final split = allocateLoanPayment(value, const [], 150, DateTime.utc(2026, 1, 1));
    expect(split.interest, 100);
    expect(split.principal, 50);
  });

  test('due-date accrual stop still accepts later repayments', () {
    final due = DateTime.utc(2025, 7, 2);
    final value = loan(
      interestType: LoanInterestType.simple,
      interestRate: 10,
      dueDate: due,
      accrualStop: LoanAccrualStop.dueDate,
    );
    final result = computeLoan(
      value,
      [payment('late', 1050, DateTime.utc(2026, 1, 1))],
      at: DateTime.utc(2026, 1, 1),
    );
    expect(result.interestAccrued, 49.86);
    expect(result.outstanding, -0.14);
    expect(result.settled, isTrue);
  });

  test('future payments are excluded from the current balance', () {
    final result = computeLoan(
      loan(),
      [payment('future', 1000, DateTime.utc(2026, 1, 1))],
      at: DateTime.utc(2025, 6, 1),
    );
    expect(result.totalPaid, 0);
    expect(result.outstanding, 1000);
    expect(result.paymentsCount, 0);
  });

  test('EMI uses APR as an annual rate', () {
    final value = loan(
      principal: 12000,
      interestType: LoanInterestType.compound,
      interestRate: 12,
      installments: 12,
    );
    expect(loanEmiAmount(value), 1066.19);
  });
}
