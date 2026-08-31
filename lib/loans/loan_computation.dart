import 'dart:math' as math;

import 'loan_models.dart';

double roundLoanMoney(double value) => (value * 100).roundToDouble() / 100;

bool loanNearZero(double value) => value.abs() < 0.005;

double loanNonNegative(double value) => value < 0 ? 0.0 : value;

DateTime _civilDate(DateTime value) => DateTime.utc(value.year, value.month, value.day);

int _calendarDays(DateTime from, DateTime to) {
  final days = _civilDate(to).difference(_civilDate(from)).inDays;
  return days < 0 ? 0 : days;
}

double _compoundGrowth(LoanInterestPeriod period, double annualRate, int days) {
  if (days <= 0 || annualRate <= 0) return 1;
  return switch (period) {
    LoanInterestPeriod.daily => math.pow(1 + annualRate / 365, days).toDouble(),
    LoanInterestPeriod.monthly => math.pow(1 + annualRate / 12, days / 30.4375).toDouble(),
    LoanInterestPeriod.yearly => math.pow(1 + annualRate, days / 365).toDouble(),
    LoanInterestPeriod.flat => 1 + annualRate,
  };
}

double? loanEmiAmount(Loan loan) {
  final count = loan.installmentCount ?? 0;
  if (count <= 0 || loan.principal <= 0) return null;
  final annualRate = loanNonNegative(loan.interestRate) / 100;
  if (loan.interestType == LoanInterestType.none || annualRate == 0) {
    return roundLoanMoney(loan.principal / count);
  }
  if (loan.interestPeriod == LoanInterestPeriod.flat) {
    return roundLoanMoney((loan.principal + loan.principal * annualRate) / count);
  }
  final monthlyRate = annualRate / 12;
  final factor = math.pow(1 + monthlyRate, count).toDouble();
  return roundLoanMoney(loan.principal * monthlyRate * factor / (factor - 1));
}

LoanComputation computeLoan(Loan loan, Iterable<LoanPayment> payments, {DateTime? at}) {
  final requestedAt = at ?? DateTime.now();
  var effectiveAt = requestedAt.isBefore(loan.startDate) ? loan.startDate : requestedAt;
  if (loan.interestAccrualStop == LoanAccrualStop.dueDate && loan.dueDate != null && effectiveAt.isAfter(loan.dueDate!)) {
    effectiveAt = loan.dueDate!;
  }

  final eligible = payments
      .where((payment) => !payment.paidOn.isAfter(requestedAt))
      .toList()
    ..sort((a, b) {
      final byDate = a.paidOn.compareTo(b.paidOn);
      return byDate != 0 ? byDate : a.createdOn.compareTo(b.createdOn);
    });

  final annualRate = loanNonNegative(loan.interestRate) / 100;
  var cursor = loan.startDate;
  var principalBalance = loanNonNegative(loan.principal);
  var interestAccrued = loan.interestType != LoanInterestType.none && loan.interestPeriod == LoanInterestPeriod.flat
      ? loan.principal * annualRate
      : 0.0;
  var interestPaid = 0.0;
  var principalPaid = 0.0;
  var totalPaid = 0.0;

  void accrueUntil(DateTime eventDate) {
    final clamped = eventDate.isAfter(effectiveAt) ? effectiveAt : eventDate;
    final days = _calendarDays(cursor, clamped);
    if (days <= 0 || loan.interestType == LoanInterestType.none || loan.interestPeriod == LoanInterestPeriod.flat) {
      if (clamped.isAfter(cursor)) cursor = clamped;
      return;
    }
    if (loan.interestType == LoanInterestType.simple) {
      interestAccrued += loan.principal * annualRate * days / 365;
    } else {
      final growth = _compoundGrowth(loan.interestPeriod, annualRate, days);
      interestAccrued += principalBalance * (growth - 1);
    }
    cursor = clamped;
  }

  for (final payment in eligible) {
    final paymentDate = payment.paidOn.isBefore(loan.startDate) ? loan.startDate : payment.paidOn;
    accrueUntil(paymentDate);
    final amount = loanNonNegative(payment.amount);
    final interestOutstanding = loanNonNegative(interestAccrued - interestPaid);
    final interestPart = math.min(amount, interestOutstanding).toDouble();
    final principalPart = loanNonNegative(amount - interestPart);
    interestPaid += interestPart;
    principalPaid += principalPart;
    totalPaid += amount;
    principalBalance = loanNonNegative(principalBalance - principalPart);
  }
  accrueUntil(effectiveAt);

  final totalDue = loan.principal + interestAccrued;
  final outstanding = totalDue - totalPaid;
  final overpaid = loanNonNegative(-outstanding);
  final settled = outstanding <= 0.005;
  final progress = totalDue <= 0 ? 0.0 : (totalPaid / totalDue).clamp(0.0, 1.0).toDouble();
  final overdueDays = loan.dueDate == null || !requestedAt.isAfter(loan.dueDate!) ? 0 : _calendarDays(loan.dueDate!, requestedAt);
  final overdue = loan.status == LoanStatus.active && overdueDays > 0 && !settled;
  final emi = loanEmiAmount(loan);

  return LoanComputation(
    principal: roundLoanMoney(loan.principal),
    interestAccrued: roundLoanMoney(interestAccrued),
    totalDue: roundLoanMoney(totalDue),
    totalPaid: roundLoanMoney(totalPaid),
    interestPaid: roundLoanMoney(interestPaid),
    principalPaid: roundLoanMoney(principalPaid),
    outstanding: roundLoanMoney(outstanding),
    overpaid: roundLoanMoney(overpaid),
    progress: progress,
    settled: settled,
    daysOverdue: overdue ? overdueDays : 0,
    overdue: overdue,
    emiAmount: emi,
    paymentsCount: eligible.length,
    installmentsPaid: emi == null || emi <= 0 ? 0 : (totalPaid / emi).floor(),
    computedAt: requestedAt,
  );
}

LoanPaymentSplit allocateLoanPayment(Loan loan, Iterable<LoanPayment> existingPayments, double amount, DateTime paidOn) {
  final computation = computeLoan(loan, existingPayments, at: paidOn);
  final interestOutstanding = loanNonNegative(computation.interestAccrued - computation.interestPaid);
  final roundedAmount = roundLoanMoney(loanNonNegative(amount));
  final interest = roundLoanMoney(math.min(roundedAmount, interestOutstanding).toDouble());
  return LoanPaymentSplit(interest: interest, principal: roundLoanMoney(roundedAmount - interest));
}
