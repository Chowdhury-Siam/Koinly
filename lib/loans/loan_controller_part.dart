part of '../main.dart';

extension LoanControllerActions on AppController {
  LoanRepository get loanRepository => _loanRepository ??= LoanRepository(() => database.db);

  LoanContact? loanContactOf(String? id) => id == null ? null : _loanContactsById[id];

  Loan? loanOf(String id) => _loansById[id];

  List<LoanPayment> paymentsForLoan(String loanId) => List.unmodifiable(_paymentsByLoan[loanId] ?? const <LoanPayment>[]);

  List<Loan> loansForContact(String contactId) => loans.where((loan) => loan.contactId == contactId).toList(growable: false);

  LoanComputation computationFor(String loanId, {DateTime? at}) {
    final loan = loanOf(loanId);
    if (loan == null) {
      throw StateError('The selected record no longer exists.');
    }
    return computeLoan(loan, _paymentsByLoan[loanId] ?? const <LoanPayment>[], at: at);
  }

  double netWithLoanContact(String contactId) {
    var net = 0.0;
    for (final loan in loansForContact(contactId)) {
      if (loan.status == LoanStatus.writtenOff) continue;
      final outstanding = loanNonNegative(computationFor(loan.id).outstanding);
      net += loan.isLent ? outstanding : -outstanding;
    }
    return roundLoanMoney(net);
  }

  LoanPortfolioSummary get loanSummary {
    var toCollect = 0.0;
    var toPay = 0.0;
    var overdueAmount = 0.0;
    var active = 0;
    var settled = 0;
    var overdue = 0;
    final activeContacts = <String>{};
    final collectors = <String>{};
    final debtors = <String>{};
    for (final loan in loans) {
      if (loan.status == LoanStatus.writtenOff) continue;
      final computation = computationFor(loan.id);
      if (loan.status == LoanStatus.closed || computation.settled) {
        settled++;
        continue;
      }
      active++;
      activeContacts.add(loan.contactId);
      final outstanding = loanNonNegative(computation.outstanding);
      if (loan.isLent) {
        toCollect += outstanding;
        collectors.add(loan.contactId);
      } else {
        toPay += outstanding;
        debtors.add(loan.contactId);
      }
      if (computation.overdue) {
        overdue++;
        overdueAmount += outstanding;
      }
    }
    return LoanPortfolioSummary(
      toCollect: roundLoanMoney(toCollect),
      toPay: roundLoanMoney(toPay),
      net: roundLoanMoney(toCollect - toPay),
      overdueAmount: roundLoanMoney(overdueAmount),
      activeCount: active,
      settledCount: settled,
      overdueCount: overdue,
      contactCount: activeContacts.length,
      collectorCount: collectors.length,
      debtorCount: debtors.length,
    );
  }

  Future<void> refreshLoanReminders() async {
    try {
      if (!loanRemindersEnabled) {
        await ReminderService.cancelLoanDueReminders();
        return;
      }
      final reminders = <LoanDueReminder>[];
      for (final loan in loans) {
        if (loan.status != LoanStatus.active || loan.dueDate == null) continue;
        final computation = computationFor(loan.id);
        if (computation.settled) continue;
        reminders.add(LoanDueReminder(
          id: loan.id,
          personName: loanContactOf(loan.contactId)?.name ?? 'a contact',
          dueDate: loan.dueDate!,
          amountText: format(loanNonNegative(computation.outstanding)),
          toCollect: loan.isLent,
        ));
      }
      reminders.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      await ReminderService.scheduleLoanDueReminders(reminders);
    } catch (_) {
      // Notification support is optional on platforms/builds that omit it.
    }
  }

  Future<void> saveLoanContact(LoanContact contact) async {
    if (contact.name.trim().isEmpty) throw StateError('Enter a person name.');
    await loanRepository.upsertContact(contact.copyWith(name: contact.name.trim(), updatedOn: DateTime.now()));
    await database.enqueueTableRow('loan_contacts', contact.id);
    await reload(queueSync: true);
  }

  Future<void> deleteLoanContact(String id) async {
    if (loans.any((loan) => loan.contactId == id)) {
      throw StateError('Delete this person’s records first.');
    }
    await database.enqueueDelete('loan_contacts', id);
    await loanRepository.deleteContact(id);
    await reload(queueSync: true);
  }

  Future<Category> _loanCategory(LoanDirection direction, {required bool payment}) async {
    final isIncome = payment ? direction == LoanDirection.lent : direction == LoanDirection.borrowed;
    final category = await database.ensureCategory(
      payment
          ? (isIncome ? 'Repayment received' : 'Repayment paid')
          : (isIncome ? 'Borrowed funds' : 'Lent funds'),
      isIncome ? CategoryType.income : CategoryType.expense,
      isIncome ? '#9BE7B4' : '#FF9E9E',
      payment ? 'receipt' : 'exchange',
    );
    await database.enqueueTableRow('categories', category.id);
    return category;
  }

  MoneyTransaction _loanMoneyTransaction({
    required String id,
    required LoanDirection direction,
    required bool payment,
    required double amount,
    required String title,
    required String accountId,
    required String categoryId,
    required String linkedEntityType,
    required String linkedEntityId,
    required DateTime occurredOn,
    required String notes,
  }) {
    final isIncome = payment ? direction == LoanDirection.lent : direction == LoanDirection.borrowed;
    return MoneyTransaction(
      id: id,
      type: isIncome ? MoneyTransactionType.income : MoneyTransactionType.expense,
      amount: roundLoanMoney(amount),
      title: title,
      notes: notes,
      categoryId: categoryId,
      fromAccountId: accountId,
      excludeFromReports: true,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
      createdOn: occurredOn,
      updatedOn: DateTime.now(),
    );
  }

  Future<void> saveLoan(Loan loan, {bool recordDisbursal = false, String? accountId}) async {
    if (!loan.principal.isFinite || loan.principal <= 0) throw StateError('Enter a valid amount.');
    if (loan.interestRate < 0 || loan.interestRate > 1000) throw StateError('Enter a valid annual interest rate.');
    if (!_loanContactsById.containsKey(loan.contactId)) throw StateError('Select a person.');
    final previous = loanOf(loan.id);
    var saved = loan.copyWith(principal: roundLoanMoney(loan.principal), updatedOn: DateTime.now());

    if (previous == null && recordDisbursal) {
      if (accountId == null || accountId.isEmpty) throw StateError('Select an account.');
      final category = await _loanCategory(saved.direction, payment: false);
      final transaction = _loanMoneyTransaction(
        id: _uuid.v4(),
        direction: saved.direction,
        payment: false,
        amount: saved.principal,
        title: category.name,
        accountId: accountId,
        categoryId: category.id,
        linkedEntityType: 'loans',
        linkedEntityId: saved.id,
        occurredOn: saved.startDate,
        notes: saved.note.isEmpty ? 'Recorded money movement' : saved.note,
      );
      saved = await loanRepository.createLoanWithDisbursal(saved, transaction);
      await database.enqueueTableRow('transactions', transaction.id);
      await database.enqueueRowsForTable('accounts');
    } else if (previous != null && previous.disbursalTransactionId != null) {
      final linked = transactions.where((item) => item.id == previous.disbursalTransactionId).firstOrNull;
      if (linked != null) {
        final category = await _loanCategory(saved.direction, payment: false);
        final updatedTransaction = _loanMoneyTransaction(
          id: linked.id,
          direction: saved.direction,
          payment: false,
          amount: saved.principal,
          title: category.name,
          accountId: linked.fromAccountId,
          categoryId: category.id,
          linkedEntityType: 'loans',
          linkedEntityId: saved.id,
          occurredOn: saved.startDate,
          notes: saved.note.isEmpty ? linked.notes : saved.note,
        );
        await database.updateTransaction(updatedTransaction);
        await database.enqueueTableRow('transactions', linked.id);
        await database.enqueueRowsForTable('accounts');
      }
      saved = saved.copyWith(disbursalTransactionId: previous.disbursalTransactionId);
      await loanRepository.upsertLoan(saved);
    } else {
      await loanRepository.upsertLoan(saved);
    }

    await database.enqueueTableRow('loans', saved.id);
    await reload(queueSync: true);
  }

  Future<void> addLoanPayment(LoanPayment payment, {bool recordInAccount = false, String? accountId}) async {
    final loan = loanOf(payment.loanId);
    if (loan == null) throw StateError('The selected record no longer exists.');
    if (!payment.amount.isFinite || payment.amount <= 0) throw StateError('Enter a valid payment amount.');
    if (payment.paidOn.isBefore(loan.startDate)) throw StateError('Payment date cannot be before the start date.');
    if (payment.paidOn.isAfter(DateTime.now().add(const Duration(minutes: 1)))) throw StateError('Payment date cannot be in the future.');
    final split = allocateLoanPayment(loan, paymentsForLoan(loan.id), payment.amount, payment.paidOn);
    var saved = payment.copyWith(
      amount: roundLoanMoney(payment.amount),
      interestComponent: split.interest,
      principalComponent: split.principal,
      updatedOn: DateTime.now(),
    );

    if (recordInAccount) {
      if (accountId == null || accountId.isEmpty) throw StateError('Select an account.');
      final category = await _loanCategory(loan.direction, payment: true);
      final transaction = _loanMoneyTransaction(
        id: _uuid.v4(),
        direction: loan.direction,
        payment: true,
        amount: saved.amount,
        title: category.name,
        accountId: accountId,
        categoryId: category.id,
        linkedEntityType: 'loan_payments',
        linkedEntityId: saved.id,
        occurredOn: saved.paidOn,
        notes: saved.note.isEmpty ? 'Recorded repayment' : saved.note,
      );
      saved = await loanRepository.addPaymentWithTransaction(saved, transaction);
      await database.enqueueTableRow('transactions', transaction.id);
      await database.enqueueRowsForTable('accounts');
    } else {
      await loanRepository.insertPayment(saved);
    }

    await database.enqueueTableRow('loan_payments', saved.id);
    final updatedComputation = computeLoan(loan, [...paymentsForLoan(loan.id), saved]);
    if (updatedComputation.settled && loan.status == LoanStatus.active) {
      await loanRepository.setLoanStatus(loan.id, LoanStatus.closed, DateTime.now());
      await database.enqueueTableRow('loans', loan.id);
    }
    await reload(queueSync: true);
  }

  Future<void> deleteLoanPayment(String id, {bool deleteLinkedTransaction = false}) async {
    final payment = loanPayments.where((item) => item.id == id).firstOrNull;
    if (payment == null) return;
    await database.enqueueDelete('loan_payments', id);
    final linkedTransactionId = await loanRepository.deletePayment(id);
    if (deleteLinkedTransaction && linkedTransactionId != null && linkedTransactionId.isNotEmpty) {
      await database.enqueueDelete('transactions', linkedTransactionId);
      await database.deleteTransaction(linkedTransactionId);
      await database.enqueueRowsForTable('accounts');
    }
    final loan = loanOf(payment.loanId);
    if (loan != null) {
      final remaining = paymentsForLoan(loan.id).where((item) => item.id != id);
      if (!computeLoan(loan, remaining).settled && loan.status == LoanStatus.closed) {
        await loanRepository.setLoanStatus(loan.id, LoanStatus.active, null);
        await database.enqueueTableRow('loans', loan.id);
      }
    }
    await reload(queueSync: true);
  }

  Future<void> setLoanStatus(String id, LoanStatus status) async {
    await loanRepository.setLoanStatus(id, status, status == LoanStatus.closed ? DateTime.now() : null);
    await database.enqueueTableRow('loans', id);
    await reload(queueSync: true);
  }

  Future<void> deleteLoan(String id, {bool deleteLinkedTransactions = false}) async {
    final result = await loanRepository.deleteLoanCascade(id);
    for (final paymentId in result.paymentIds) {
      await database.enqueueDelete('loan_payments', paymentId);
    }
    await database.enqueueDelete('loans', id);
    if (deleteLinkedTransactions) {
      for (final transactionId in result.transactionIds) {
        await database.enqueueDelete('transactions', transactionId);
        await database.deleteTransaction(transactionId);
      }
      await database.enqueueRowsForTable('accounts');
    }
    await reload(queueSync: true);
  }

  Future<void> setLoanPreferences({bool? recordTransactions, bool? reminders, bool? showWrittenOff}) async {
    if (recordTransactions != null) {
      loanRecordTransactionsByDefault = recordTransactions;
      await prefs.setBool('loanRecordTransactionsByDefault', recordTransactions);
    }
    if (reminders != null) {
      loanRemindersEnabled = reminders;
      await prefs.setBool('loanRemindersEnabled', reminders);
      unawaited(refreshLoanReminders());
    }
    if (showWrittenOff != null) {
      loanShowWrittenOff = showWrittenOff;
      await prefs.setBool('loanShowWrittenOff', showWrittenOff);
    }
    notifyListeners();
    await queuePreferenceSync();
  }
}
