part of '../main.dart';

enum AnalyticsPdfVariant { summary, transactionHistory }

extension AnalyticsPdfVariantLabel on AnalyticsPdfVariant {
  String get label => switch (this) {
        AnalyticsPdfVariant.summary => 'Summary',
        AnalyticsPdfVariant.transactionHistory => 'Transaction history',
      };

  String get description => switch (this) {
        AnalyticsPdfVariant.summary => 'Detailed report for the selected date filter with comparison, activity, budgets, category breakdowns, and account balances.',
        AnalyticsPdfVariant.transactionHistory => 'Complete transaction ledger for the selected date filter.',
      };
}

extension AnalyticsDateFilterLabel on DateRangeType {
  String get analyticsLabel => switch (this) {
        DateRangeType.today => 'Today',
        DateRangeType.thisWeek => 'This Week',
        DateRangeType.thisMonth => 'This Month',
        DateRangeType.thisYear => 'This Year',
        DateRangeType.allTime => 'All Time',
        DateRangeType.custom => 'Custom Range',
      };
}

class AnalyticsRange {
  const AnalyticsRange({required this.start, required this.end, required this.label});

  final DateTime start;
  final DateTime end;
  final String label;

  int get dayCount => math.max(1, end.difference(start).inDays);
}

DateTime _analyticsDay(DateTime value) => DateTime(value.year, value.month, value.day);

String _analyticsRangeLabel(DateTime start, DateTime endExclusive) {
  final last = endExclusive.subtract(const Duration(days: 1));
  if (start.year == last.year && start.month == last.month && start.day == last.day) {
    return DateFormat('EEE, MMM d, yyyy').format(start);
  }
  if (start.year == last.year) {
    return '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(last)}';
  }
  return '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(last)}';
}

AnalyticsRange analyticsRangeForDateFilter(
  AppController state,
  DateRangeType filter, {
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final now = DateTime.now();
  final today = _analyticsDay(now);
  switch (filter) {
    case DateRangeType.today:
      return AnalyticsRange(
        start: today,
        end: today.add(const Duration(days: 1)),
        label: DateFormat('EEE, MMM d, yyyy').format(today),
      );
    case DateRangeType.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - DateTime.monday));
      final end = start.add(const Duration(days: 7));
      return AnalyticsRange(start: start, end: end, label: _analyticsRangeLabel(start, end));
    case DateRangeType.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      return AnalyticsRange(
        start: start,
        end: DateTime(start.year, start.month + 1, 1),
        label: DateFormat('MMMM yyyy').format(start),
      );
    case DateRangeType.thisYear:
      final start = DateTime(today.year, 1, 1);
      return AnalyticsRange(
        start: start,
        end: DateTime(today.year + 1, 1, 1),
        label: today.year.toString(),
      );
    case DateRangeType.allTime:
      final dates = <DateTime>[
        ...state.transactions.map((tx) => tx.listOn),
        ...state.loans.map((loan) => loan.startDate),
        ...state.loanPayments.map((payment) => payment.paidOn),
        ...state.budgets.map((budget) => budget.selectedMonth),
      ];
      if (dates.isEmpty) {
        return AnalyticsRange(
          start: today,
          end: today.add(const Duration(days: 1)),
          label: 'All time',
        );
      }
      dates.sort();
      final start = _analyticsDay(dates.first);
      final latest = dates.last.isAfter(now) ? dates.last : now;
      final end = _analyticsDay(latest).add(const Duration(days: 1));
      return AnalyticsRange(start: start, end: end, label: 'All time');
    case DateRangeType.custom:
      var start = _analyticsDay(customStart ?? today);
      var last = _analyticsDay(customEnd ?? customStart ?? today);
      if (last.isBefore(start)) {
        final swap = start;
        start = last;
        last = swap;
      }
      final end = last.add(const Duration(days: 1));
      return AnalyticsRange(start: start, end: end, label: _analyticsRangeLabel(start, end));
  }
}

AnalyticsRange _analyticsPreviousRange(AnalyticsRange range) {
  final duration = range.end.difference(range.start);
  final end = range.start;
  final start = end.subtract(duration);
  return AnalyticsRange(start: start, end: end, label: _analyticsRangeLabel(start, end));
}

class AnalyticsCategoryItem {
  const AnalyticsCategoryItem({required this.category, required this.amount, required this.share});

  final Category? category;
  final double amount;
  final double share;

  String get name => category?.name ?? 'Uncategorized';
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.dateFilter,
    required this.range,
    required this.transactions,
    required this.income,
    required this.expense,
    required this.transferVolume,
    required this.transferCount,
    required this.savingsIn,
    required this.savingsOut,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.budgetLimit,
    required this.budgetSpent,
    required this.budgetCount,
    required this.newLoanCount,
    required this.repaymentCount,
    required this.repaymentTotal,
    required this.previousIncome,
    required this.previousExpense,
    required this.previousNet,
    required this.compareWithPrevious,
  });

  final DateRangeType dateFilter;
  final AnalyticsRange range;
  final List<MoneyTransaction> transactions;
  final double income;
  final double expense;
  final double transferVolume;
  final int transferCount;
  final double savingsIn;
  final double savingsOut;
  final List<AnalyticsCategoryItem> expenseCategories;
  final List<AnalyticsCategoryItem> incomeCategories;
  final double budgetLimit;
  final double budgetSpent;
  final int budgetCount;
  final int newLoanCount;
  final int repaymentCount;
  final double repaymentTotal;
  final double previousIncome;
  final double previousExpense;
  final double previousNet;
  final bool compareWithPrevious;

  String get filterLabel => dateFilter.analyticsLabel;
  double get net => income - expense;
  double get savingsNet => savingsIn - savingsOut;
  double get averageIncomePerDay => income / range.dayCount;
  double get averageExpensePerDay => expense / range.dayCount;
  double get budgetRemaining => budgetLimit - budgetSpent;
  double get budgetUsage => budgetLimit <= 0 ? 0 : budgetSpent / budgetLimit;
  int get transactionCount => transactions.length;
  int get incomeCount => transactions.where((tx) => tx.countsAsIncome).length;
  int get expenseCount => transactions.where((tx) => tx.countsAsExpense).length;

  static AnalyticsSnapshot build(
    AppController state,
    DateRangeType dateFilter, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final range = analyticsRangeForDateFilter(
      state,
      dateFilter,
      customStart: customStart,
      customEnd: customEnd,
    );
    final current = _buildAnalyticsCore(state, range);
    final compareWithPrevious = dateFilter != DateRangeType.allTime;
    final previous = compareWithPrevious ? _buildAnalyticsCore(state, _analyticsPreviousRange(range)) : null;

    return AnalyticsSnapshot(
      dateFilter: dateFilter,
      range: range,
      transactions: current.transactions,
      income: current.income,
      expense: current.expense,
      transferVolume: current.transferVolume,
      transferCount: current.transferCount,
      savingsIn: current.savingsIn,
      savingsOut: current.savingsOut,
      expenseCategories: current.expenseCategories,
      incomeCategories: current.incomeCategories,
      budgetLimit: current.budgetLimit,
      budgetSpent: current.budgetSpent,
      budgetCount: current.budgetCount,
      newLoanCount: current.newLoanCount,
      repaymentCount: current.repaymentCount,
      repaymentTotal: current.repaymentTotal,
      previousIncome: previous?.income ?? 0,
      previousExpense: previous?.expense ?? 0,
      previousNet: previous == null ? 0 : previous.income - previous.expense,
      compareWithPrevious: compareWithPrevious,
    );
  }
}

class _AnalyticsCore {
  const _AnalyticsCore({
    required this.transactions,
    required this.income,
    required this.expense,
    required this.transferVolume,
    required this.transferCount,
    required this.savingsIn,
    required this.savingsOut,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.budgetLimit,
    required this.budgetSpent,
    required this.budgetCount,
    required this.newLoanCount,
    required this.repaymentCount,
    required this.repaymentTotal,
  });

  final List<MoneyTransaction> transactions;
  final double income;
  final double expense;
  final double transferVolume;
  final int transferCount;
  final double savingsIn;
  final double savingsOut;
  final List<AnalyticsCategoryItem> expenseCategories;
  final List<AnalyticsCategoryItem> incomeCategories;
  final double budgetLimit;
  final double budgetSpent;
  final int budgetCount;
  final int newLoanCount;
  final int repaymentCount;
  final double repaymentTotal;
}

bool _analyticsDateInside(DateTime value, AnalyticsRange range) => !value.isBefore(range.start) && value.isBefore(range.end);

_AnalyticsCore _buildAnalyticsCore(AppController state, AnalyticsRange range) {
  final transactions = state.transactions.where((tx) => _analyticsDateInside(tx.listOn, range)).toList(growable: false);
  var income = 0.0;
  var expense = 0.0;
  var transferVolume = 0.0;
  var transferCount = 0;
  var savingsIn = 0.0;
  var savingsOut = 0.0;
  final expenseByCategory = <String, double>{};
  final incomeByCategory = <String, double>{};

  for (final tx in transactions) {
    if (tx.countsAsIncome) {
      income += tx.amount;
      incomeByCategory[tx.categoryId] = (incomeByCategory[tx.categoryId] ?? 0) + tx.amount;
    }
    if (tx.countsAsExpense) {
      expense += tx.amount;
      expenseByCategory[tx.categoryId] = (expenseByCategory[tx.categoryId] ?? 0) + tx.amount;
    }
    if (tx.type == MoneyTransactionType.transfer) {
      transferVolume += tx.amount;
      transferCount++;
    }
    if (isSavingsTransferIn(state, tx)) savingsIn += tx.amount;
    if (isSavingsTransferOut(state, tx)) savingsOut += tx.amount;
  }

  List<AnalyticsCategoryItem> categoryItems(Map<String, double> totals, double overall) {
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .map((entry) => AnalyticsCategoryItem(
              category: state.categoryOf(entry.key),
              amount: entry.value,
              share: overall <= 0 ? 0 : entry.value / overall,
            ))
        .toList(growable: false);
  }

  var budgetLimit = 0.0;
  var budgetSpent = 0.0;
  var budgetCount = 0;
  for (final budget in state.budgets) {
    final monthStart = DateTime(budget.selectedMonth.year, budget.selectedMonth.month, 1);
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    final overlaps = range.start.isBefore(monthEnd) && range.end.isAfter(monthStart);
    if (!overlaps) continue;
    budgetCount++;
    budgetLimit += budget.amount;
    final monthRange = AnalyticsRange(start: monthStart, end: monthEnd, label: '');
    for (final tx in transactions) {
      if (!tx.countsAsExpense) continue;
      if (!_analyticsDateInside(tx.listOn, monthRange)) continue;
      if (!budget.allAccountsSelected && !budget.accountIds.contains(tx.fromAccountId)) continue;
      if (!budget.allCategoriesSelected && !budget.categoryIds.contains(tx.categoryId)) continue;
      budgetSpent += tx.amount;
    }
  }

  final newLoanCount = state.loans.where((loan) => _analyticsDateInside(loan.startDate, range)).length;
  final repayments = state.loanPayments.where((payment) => _analyticsDateInside(payment.paidOn, range)).toList(growable: false);

  return _AnalyticsCore(
    transactions: transactions,
    income: income,
    expense: expense,
    transferVolume: transferVolume,
    transferCount: transferCount,
    savingsIn: savingsIn,
    savingsOut: savingsOut,
    expenseCategories: categoryItems(expenseByCategory, expense),
    incomeCategories: categoryItems(incomeByCategory, income),
    budgetLimit: budgetLimit,
    budgetSpent: budgetSpent,
    budgetCount: budgetCount,
    newLoanCount: newLoanCount,
    repaymentCount: repayments.length,
    repaymentTotal: repayments.fold<double>(0, (sum, payment) => sum + payment.amount),
  );
}

String _analyticsPdfSafe(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 32 && rune <= 126) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

String _analyticsPdfMoney(AppController state, double value) {
  final formatter = NumberFormat('#,##0.##');
  final sign = value < 0 ? '-' : '';
  return '$sign${_analyticsPdfSafe(state.currencyCode)} ${formatter.format(value.abs())}';
}

String _analyticsComparisonLabel(double current, double previous) {
  if (previous.abs() < .0001) return current.abs() < .0001 ? 'No change' : 'New activity';
  final percent = ((current - previous) / previous.abs()) * 100;
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}%';
}

String _analyticsPdfDateStamp(AnalyticsSnapshot snapshot) {
  final start = snapshot.range.start;
  final last = snapshot.range.end.subtract(const Duration(days: 1));
  return switch (snapshot.dateFilter) {
    DateRangeType.today => DateFormat('yyyy-MM-dd').format(start),
    DateRangeType.thisWeek => '${DateFormat('yyyy-MM-dd').format(start)}_week',
    DateRangeType.thisMonth => DateFormat('yyyy-MM').format(start),
    DateRangeType.thisYear => start.year.toString(),
    DateRangeType.allTime => 'all-time',
    DateRangeType.custom => '${DateFormat('yyyy-MM-dd').format(start)}_to_${DateFormat('yyyy-MM-dd').format(last)}',
  };
}

String analyticsPdfFileName(AnalyticsSnapshot snapshot, {AnalyticsPdfVariant variant = AnalyticsPdfVariant.summary}) {
  final stamp = _analyticsPdfDateStamp(snapshot);
  if (variant == AnalyticsPdfVariant.transactionHistory) {
    return 'Koinly-Transaction-History-$stamp.pdf';
  }
  return 'Koinly-Analytics-${snapshot.dateFilter.name}-$stamp.pdf';
}

class AnalyticsPdfService {
  const AnalyticsPdfService._();

  static Future<Uint8List> build(
    AppController state,
    AnalyticsSnapshot snapshot, {
    AnalyticsPdfVariant variant = AnalyticsPdfVariant.summary,
  }) async {
    return switch (variant) {
      AnalyticsPdfVariant.summary => _buildSummary(state, snapshot),
      AnalyticsPdfVariant.transactionHistory => _buildTransactionHistory(state, snapshot),
    };
  }

  static pw.Widget _metric(String label, String value) => pw.Container(
        width: 155,
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(right: 8, bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_analyticsPdfSafe(label), style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(_analyticsPdfSafe(value), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _categorySection(AppController state, String title, List<AnalyticsCategoryItem> items) {
    final visible = items.take(8).toList();
    if (visible.isEmpty) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('No activity in this period.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ]);
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      ...visible.map((item) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text(_analyticsPdfSafe(item.name), style: const pw.TextStyle(fontSize: 10))),
              pw.Text('${(item.share * 100).toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 95,
                child: pw.Text(
                  _analyticsPdfSafe(_analyticsPdfMoney(state, item.amount)),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ]),
          )),
    ]);
  }

  static Future<Uint8List> _buildSummary(AppController state, AnalyticsSnapshot snapshot) async {
    final document = pw.Document();
    final generated = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 36, 34, 36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Koinly Analytics | Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Text('Koinly Analytics', style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
          pw.SizedBox(height: 4),
          pw.Text('${snapshot.filterLabel} summary - ${_analyticsPdfSafe(snapshot.range.label)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Generated $generated | App version $appVersion', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 18),
          pw.Wrap(children: [
            _metric('Income', _analyticsPdfMoney(state, snapshot.income)),
            _metric('Expense', _analyticsPdfMoney(state, snapshot.expense)),
            _metric('Net cash flow', _analyticsPdfMoney(state, snapshot.net)),
            _metric('Transactions', snapshot.transactionCount.toString()),
            _metric('Avg income / day', _analyticsPdfMoney(state, snapshot.averageIncomePerDay)),
            _metric('Avg expense / day', _analyticsPdfMoney(state, snapshot.averageExpensePerDay)),
          ]),
          if (snapshot.compareWithPrevious) ...[
            pw.SizedBox(height: 10),
            pw.Text('Compared with previous period', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text('Income: ${_analyticsComparisonLabel(snapshot.income, snapshot.previousIncome)}'),
            pw.Text('Expense: ${_analyticsComparisonLabel(snapshot.expense, snapshot.previousExpense)}'),
            pw.Text('Net cash flow: ${_analyticsComparisonLabel(snapshot.net, snapshot.previousNet)}'),
            pw.SizedBox(height: 16),
          ] else
            pw.SizedBox(height: 16),
          pw.Text('Activity', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Income transactions: ${snapshot.incomeCount}'),
          pw.Text('Expense transactions: ${snapshot.expenseCount}'),
          pw.Text('Transfers: ${snapshot.transferCount} (${_analyticsPdfMoney(state, snapshot.transferVolume)})'),
          pw.Text('Savings in: ${_analyticsPdfMoney(state, snapshot.savingsIn)}'),
          pw.Text('Savings out: ${_analyticsPdfMoney(state, snapshot.savingsOut)}'),
          pw.Text('Loan records started: ${snapshot.newLoanCount}'),
          pw.Text('Repayments: ${snapshot.repaymentCount} (${_analyticsPdfMoney(state, snapshot.repaymentTotal)})'),
          if (snapshot.budgetCount > 0) ...[
            pw.Text('Relevant budgets: ${snapshot.budgetCount}'),
            pw.Text('Budget spend: ${_analyticsPdfMoney(state, snapshot.budgetSpent)} of ${_analyticsPdfMoney(state, snapshot.budgetLimit)}'),
          ],
          pw.SizedBox(height: 16),
          _categorySection(state, 'Top expense categories', snapshot.expenseCategories),
          pw.SizedBox(height: 16),
          _categorySection(state, 'Top income categories', snapshot.incomeCategories),
          pw.SizedBox(height: 16),
          pw.Text('Current account balances', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Account balances are a current snapshot, not historical balances for the selected period.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          ...state.accounts.map((account) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(children: [
                  pw.Expanded(child: pw.Text(_analyticsPdfSafe(account.name))),
                  pw.Text(_analyticsPdfSafe(_analyticsPdfMoney(state, account.amount)), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ]),
              )),
          pw.Divider(height: 22, color: PdfColors.grey300),
          pw.Text(
            'This report is generated locally from the finance data currently available in Koinly. Transfers are not counted as income or expense.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<Uint8List> _buildTransactionHistory(AppController state, AnalyticsSnapshot snapshot) async {
    final document = pw.Document();
    final transactions = List<MoneyTransaction>.of(snapshot.transactions)
      ..sort((a, b) => b.listOn.compareTo(a.listOn));
    final generated = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final income = transactions.where((tx) => tx.countsAsIncome).fold<double>(0, (sum, tx) => sum + tx.amount);
    final expense = transactions.where((tx) => tx.countsAsExpense).fold<double>(0, (sum, tx) => sum + tx.amount);
    final transfers = transactions.where((tx) => tx.type == MoneyTransactionType.transfer).toList(growable: false);
    final transferVolume = transfers.fold<double>(0, (sum, tx) => sum + tx.amount);

    String accountName(String id) => state.accountOf(id)?.name ?? 'Unknown account';
    String categoryName(MoneyTransaction tx) => state.categoryOf(tx.categoryId)?.name ?? 'Uncategorized';
    String transactionDateLabel(MoneyTransaction tx) {
      final start = DateFormat('yyyy-MM-dd HH:mm').format(tx.createdOn);
      final end = tx.effectiveEndOn;
      if (end.year == tx.createdOn.year &&
          end.month == tx.createdOn.month &&
          end.day == tx.createdOn.day &&
          end.hour == tx.createdOn.hour &&
          end.minute == tx.createdOn.minute) {
        return start;
      }
      return '$start -> ${DateFormat('yyyy-MM-dd HH:mm').format(end)}';
    }
    String amountLabel(MoneyTransaction tx) {
      final money = _analyticsPdfMoney(state, tx.amount);
      return switch (tx.type) {
        MoneyTransactionType.income => '+$money',
        MoneyTransactionType.expense => '-$money',
        MoneyTransactionType.transfer => money,
      };
    }

    pw.Widget transactionEntry(MoneyTransaction tx) {
      final savedTitle = tx.title.trim();
      final category = categoryName(tx);
      final from = accountName(tx.fromAccountId);
      final to = tx.toAccountId == null ? null : accountName(tx.toAccountId!);
      final title = tx.type == MoneyTransactionType.transfer
          ? '$from -> ${to ?? 'Unknown account'}'
          : savedTitle.isNotEmpty
              ? savedTitle
              : category;
      final details = <String>[
        tx.displayType,
        if (tx.type != MoneyTransactionType.transfer) category,
        if (tx.type != MoneyTransactionType.transfer) from,
        if (tx.excludeFromReports) 'Excluded from reports',
      ];
      var notes = tx.notes.trim();
      if (notes.length > 1000) notes = '${notes.substring(0, 1000)}...';
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_analyticsPdfSafe(title), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(transactionDateLabel(tx), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Text(_analyticsPdfSafe(amountLabel(tx)), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 3),
          pw.Text(_analyticsPdfSafe(details.join(' | ')), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text('Note: ${_analyticsPdfSafe(notes)}', style: const pw.TextStyle(fontSize: 8.5)),
          ],
          pw.SizedBox(height: 7),
          pw.Divider(height: 1, color: PdfColors.grey300),
        ]),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 36, 34, 36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Koinly Transaction History | Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Text('Koinly Transaction History', style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
          pw.SizedBox(height: 4),
          pw.Text(_analyticsPdfSafe(snapshot.range.label), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Generated $generated | App version $appVersion', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          if (transactions.isNotEmpty)
            pw.Text(
              '${DateFormat('yyyy-MM-dd').format(transactions.last.listOn)} to ${DateFormat('yyyy-MM-dd').format(transactions.first.listOn)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 18),
          pw.Wrap(children: [
            _metric('Transactions', transactions.length.toString()),
            _metric('Income', _analyticsPdfMoney(state, income)),
            _metric('Expense', _analyticsPdfMoney(state, expense)),
            _metric('Net cash flow', _analyticsPdfMoney(state, income - expense)),
            _metric('Transfers', transfers.length.toString()),
            _metric('Transfer volume', _analyticsPdfMoney(state, transferVolume)),
          ]),
          pw.SizedBox(height: 12),
          if (transactions.isEmpty)
            pw.Text('No transactions match the selected date filter.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))
          else ...[
            pw.Text('Transaction ledger', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ...transactions.map(transactionEntry),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            'This report contains transactions matching the selected Koinly date filter. Transactions excluded from analytics are still included and are marked accordingly.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }
}


extension AnalyticsReportFormatPresentation on AnalyticsReportFormat {
  String get label => switch (this) {
        AnalyticsReportFormat.pdf => 'PDF',
        AnalyticsReportFormat.xlsx => 'XLSX',
        AnalyticsReportFormat.txt => 'TXT',
      };

  String get extension => name;

  String get mimeType => switch (this) {
        AnalyticsReportFormat.pdf => 'application/pdf',
        AnalyticsReportFormat.xlsx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        AnalyticsReportFormat.txt => 'text/plain',
      };
}

String analyticsReportFileName(
  AnalyticsSnapshot snapshot, {
  AnalyticsPdfVariant variant = AnalyticsPdfVariant.summary,
  AnalyticsReportFormat format = AnalyticsReportFormat.pdf,
}) {
  final stamp = _analyticsPdfDateStamp(snapshot);
  final base = variant == AnalyticsPdfVariant.transactionHistory
      ? 'Koinly-Transaction-History-$stamp'
      : 'Koinly-Analytics-${snapshot.dateFilter.name}-$stamp';
  return '$base.${format.extension}';
}

String _analyticsReportMoney(AppController state, double value) {
  final formatter = NumberFormat('#,##0.##');
  final sign = value < 0 ? '-' : '';
  return '$sign${state.currencyCode} ${formatter.format(value.abs())}';
}

String _analyticsTransactionTitle(AppController state, MoneyTransaction tx) {
  final savedTitle = tx.title.trim();
  if (tx.type == MoneyTransactionType.transfer) {
    final from = state.accountOf(tx.fromAccountId)?.name ?? 'Unknown account';
    final to = tx.toAccountId == null ? 'Unknown account' : (state.accountOf(tx.toAccountId!)?.name ?? 'Unknown account');
    return '$from -> $to';
  }
  if (savedTitle.isNotEmpty) return savedTitle;
  return state.categoryOf(tx.categoryId)?.name ?? 'Uncategorized';
}

List<MoneyTransaction> _analyticsReportTransactions(AnalyticsSnapshot snapshot) =>
    List<MoneyTransaction>.of(snapshot.transactions)..sort((a, b) => b.listOn.compareTo(a.listOn));

Uint8List _analyticsTextReport(AppController state, AnalyticsSnapshot snapshot, AnalyticsPdfVariant variant) {
  final lines = <String>[];
  final generated = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  if (variant == AnalyticsPdfVariant.transactionHistory) {
    final transactions = _analyticsReportTransactions(snapshot);
    final income = transactions.where((tx) => tx.countsAsIncome).fold<double>(0, (sum, tx) => sum + tx.amount);
    final expense = transactions.where((tx) => tx.countsAsExpense).fold<double>(0, (sum, tx) => sum + tx.amount);
    final transfers = transactions.where((tx) => tx.type == MoneyTransactionType.transfer).toList(growable: false);
    final transferVolume = transfers.fold<double>(0, (sum, tx) => sum + tx.amount);
    lines
      ..add('Koinly Transaction History')
      ..add('${snapshot.filterLabel} | ${snapshot.range.label}')
      ..add('Generated $generated | App version $appVersion')
      ..add('')
      ..add('Transactions: ${transactions.length}')
      ..add('Income: ${_analyticsReportMoney(state, income)}')
      ..add('Expense: ${_analyticsReportMoney(state, expense)}')
      ..add('Net cash flow: ${_analyticsReportMoney(state, income - expense)}')
      ..add('Transfers: ${transfers.length} (${_analyticsReportMoney(state, transferVolume)})')
      ..add('');
    if (transactions.isEmpty) {
      lines.add('No transactions match the selected date filter.');
    } else {
      for (final tx in transactions) {
        final start = DateFormat('yyyy-MM-dd HH:mm').format(tx.createdOn);
        final end = DateFormat('yyyy-MM-dd HH:mm').format(tx.effectiveEndOn);
        final category = state.categoryOf(tx.categoryId)?.name ?? 'Uncategorized';
        final from = state.accountOf(tx.fromAccountId)?.name ?? 'Unknown account';
        final to = tx.toAccountId == null ? '' : (state.accountOf(tx.toAccountId!)?.name ?? 'Unknown account');
        final signedAmount = switch (tx.type) {
          MoneyTransactionType.income => tx.amount,
          MoneyTransactionType.expense => -tx.amount,
          MoneyTransactionType.transfer => tx.amount,
        };
        lines
          ..add('Start: $start${tx.effectiveEndOn == tx.createdOn ? '' : ' | End: $end'}')
          ..add('Type: ${tx.displayType} | Amount: ${_analyticsReportMoney(state, signedAmount)}')
          ..add('Title: ${_analyticsTransactionTitle(state, tx)}')
          ..add('Category: $category | From: $from${to.isEmpty ? '' : ' | To: $to'}${tx.excludeFromReports ? ' | Excluded from reports' : ''}');
        if (tx.notes.trim().isNotEmpty) lines.add('Notes: ${tx.notes.trim()}');
        lines.add('');
      }
    }
  } else {
    lines
      ..add('Koinly Analytics')
      ..add('${snapshot.filterLabel} summary | ${snapshot.range.label}')
      ..add('Generated $generated | App version $appVersion')
      ..add('')
      ..add('Income: ${_analyticsReportMoney(state, snapshot.income)}')
      ..add('Expense: ${_analyticsReportMoney(state, snapshot.expense)}')
      ..add('Net cash flow: ${_analyticsReportMoney(state, snapshot.net)}')
      ..add('Transactions: ${snapshot.transactionCount}')
      ..add('Average income / day: ${_analyticsReportMoney(state, snapshot.averageIncomePerDay)}')
      ..add('Average expense / day: ${_analyticsReportMoney(state, snapshot.averageExpensePerDay)}');
    if (snapshot.compareWithPrevious) {
      lines
        ..add('')
        ..add('Compared with previous period')
        ..add('Income: ${_analyticsComparisonLabel(snapshot.income, snapshot.previousIncome)}')
        ..add('Expense: ${_analyticsComparisonLabel(snapshot.expense, snapshot.previousExpense)}')
        ..add('Net cash flow: ${_analyticsComparisonLabel(snapshot.net, snapshot.previousNet)}');
    }
    lines
      ..add('')
      ..add('Activity')
      ..add('Income transactions: ${snapshot.incomeCount}')
      ..add('Expense transactions: ${snapshot.expenseCount}')
      ..add('Transfers: ${snapshot.transferCount} (${_analyticsReportMoney(state, snapshot.transferVolume)})')
      ..add('Savings in: ${_analyticsReportMoney(state, snapshot.savingsIn)}')
      ..add('Savings out: ${_analyticsReportMoney(state, snapshot.savingsOut)}')
      ..add('Loan records started: ${snapshot.newLoanCount}')
      ..add('Repayments: ${snapshot.repaymentCount} (${_analyticsReportMoney(state, snapshot.repaymentTotal)})');
    if (snapshot.budgetCount > 0) {
      lines
        ..add('Relevant budgets: ${snapshot.budgetCount}')
        ..add('Budget spend: ${_analyticsReportMoney(state, snapshot.budgetSpent)} of ${_analyticsReportMoney(state, snapshot.budgetLimit)}');
    }
    void appendCategories(String title, List<AnalyticsCategoryItem> items) {
      lines
        ..add('')
        ..add(title);
      if (items.isEmpty) {
        lines.add('No activity in this period.');
      } else {
        for (final item in items.take(8)) {
          lines.add('${item.name} | ${(item.share * 100).toStringAsFixed(1)}% | ${_analyticsReportMoney(state, item.amount)}');
        }
      }
    }
    appendCategories('Top expense categories', snapshot.expenseCategories);
    appendCategories('Top income categories', snapshot.incomeCategories);
    lines
      ..add('')
      ..add('Current account balances')
      ..add('Account balances are a current snapshot, not historical balances for the selected period.');
    for (final account in state.accounts) {
      lines.add('${account.name}: ${_analyticsReportMoney(state, account.amount)}');
    }
  }
  return Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));
}

class _AnalyticsXlsxSheet {
  const _AnalyticsXlsxSheet(this.name, this.rows, {this.headerRows = const <int>{}});
  final String name;
  final List<List<Object?>> rows;
  final Set<int> headerRows;
}

String _xlsxXmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _xlsxColumnName(int index) {
  var value = index + 1;
  final chars = <int>[];
  while (value > 0) {
    value -= 1;
    chars.add(65 + value % 26);
    value ~/= 26;
  }
  return String.fromCharCodes(chars.reversed);
}

String _xlsxCellXml(Object? value, int row, int column, {bool bold = false}) {
  final ref = '${_xlsxColumnName(column)}$row';
  final style = bold ? ' s="1"' : '';
  if (value is num && value.isFinite) return '<c r="$ref"$style><v>$value</v></c>';
  if (value is bool) return '<c r="$ref"$style t="b"><v>${value ? 1 : 0}</v></c>';
  final text = _xlsxXmlEscape(value?.toString() ?? '');
  return '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">$text</t></is></c>';
}

int _zipCrc32(Uint8List data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void _writeUint16(BytesBuilder target, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  target.add(data.buffer.asUint8List());
}

void _writeUint32(BytesBuilder target, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  target.add(data.buffer.asUint8List());
}

Uint8List _zipStored(Map<String, Uint8List> entries) {
  final output = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  for (final entry in entries.entries) {
    final name = Uint8List.fromList(utf8.encode(entry.key));
    final data = entry.value;
    final crc = _zipCrc32(data);
    final local = BytesBuilder(copy: false);
    _writeUint32(local, 0x04034b50);
    _writeUint16(local, 20);
    _writeUint16(local, 0x0800);
    _writeUint16(local, 0);
    _writeUint16(local, 0);
    _writeUint16(local, 0);
    _writeUint32(local, crc);
    _writeUint32(local, data.length);
    _writeUint32(local, data.length);
    _writeUint16(local, name.length);
    _writeUint16(local, 0);
    local.add(name);
    final localBytes = local.takeBytes();
    output
      ..add(localBytes)
      ..add(data);

    _writeUint32(central, 0x02014b50);
    _writeUint16(central, 20);
    _writeUint16(central, 20);
    _writeUint16(central, 0x0800);
    _writeUint16(central, 0);
    _writeUint16(central, 0);
    _writeUint16(central, 0);
    _writeUint32(central, crc);
    _writeUint32(central, data.length);
    _writeUint32(central, data.length);
    _writeUint16(central, name.length);
    _writeUint16(central, 0);
    _writeUint16(central, 0);
    _writeUint16(central, 0);
    _writeUint16(central, 0);
    _writeUint32(central, 0);
    _writeUint32(central, offset);
    central.add(name);
    offset += localBytes.length + data.length;
  }
  final centralBytes = central.takeBytes();
  output.add(centralBytes);
  _writeUint32(output, 0x06054b50);
  _writeUint16(output, 0);
  _writeUint16(output, 0);
  _writeUint16(output, entries.length);
  _writeUint16(output, entries.length);
  _writeUint32(output, centralBytes.length);
  _writeUint32(output, offset);
  _writeUint16(output, 0);
  return output.takeBytes();
}

Uint8List _buildAnalyticsXlsx(List<_AnalyticsXlsxSheet> sheets) {
  String safeSheetName(String value) {
    final clean = value.replaceAll(RegExp(r'[\\/:*?\[\]]'), ' ').trim();
    final fallback = clean.isEmpty ? 'Sheet' : clean;
    return fallback.substring(0, math.min(31, fallback.length));
  }

  final normalized = <_AnalyticsXlsxSheet>[];
  final used = <String>{};
  for (var i = 0; i < sheets.length; i++) {
    final name = safeSheetName(sheets[i].name);
    var candidate = name;
    var suffix = 2;
    while (used.contains(candidate.toLowerCase())) {
      final tail = ' $suffix';
      candidate = '${name.substring(0, math.min(name.length, 31 - tail.length))}$tail';
      suffix += 1;
    }
    used.add(candidate.toLowerCase());
    normalized.add(_AnalyticsXlsxSheet(candidate, sheets[i].rows, headerRows: sheets[i].headerRows));
  }

  final workbookSheets = StringBuffer();
  final workbookRels = StringBuffer();
  final contentTypes = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  final entries = <String, Uint8List>{};
  for (var i = 0; i < normalized.length; i++) {
    final sheet = normalized[i];
    final id = i + 1;
    workbookSheets.write('<sheet name="${_xlsxXmlEscape(sheet.name)}" sheetId="$id" r:id="rId$id"/>');
    workbookRels.write('<Relationship Id="rId$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$id.xml"/>');
    contentTypes.write('<Override PartName="/xl/worksheets/sheet$id.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    final body = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (var rowIndex = 0; rowIndex < sheet.rows.length; rowIndex++) {
      final rowNumber = rowIndex + 1;
      body.write('<row r="$rowNumber">');
      final row = sheet.rows[rowIndex];
      for (var column = 0; column < row.length; column++) {
        body.write(_xlsxCellXml(row[column], rowNumber, column, bold: sheet.headerRows.contains(rowIndex)));
      }
      body.write('</row>');
    }
    body.write('</sheetData></worksheet>');
    entries['xl/worksheets/sheet$id.xml'] = Uint8List.fromList(utf8.encode(body.toString()));
  }
  contentTypes.write('</Types>');
  workbookRels.write('<Relationship Id="rId${normalized.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  entries['[Content_Types].xml'] = Uint8List.fromList(utf8.encode(contentTypes.toString()));
  entries['_rels/.rels'] = Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'));
  entries['xl/workbook.xml'] = Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>$workbookSheets</sheets></workbook>'));
  entries['xl/_rels/workbook.xml.rels'] = Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$workbookRels</Relationships>'));
  entries['xl/styles.xml'] = Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'));
  return _zipStored(entries);
}

Uint8List _analyticsXlsxReport(AppController state, AnalyticsSnapshot snapshot, AnalyticsPdfVariant variant) {
  final generated = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  if (variant == AnalyticsPdfVariant.transactionHistory) {
    final transactions = _analyticsReportTransactions(snapshot);
    final rows = <List<Object?>>[
      ['Koinly Transaction History'],
      ['Date filter', snapshot.filterLabel],
      ['Range', snapshot.range.label],
      ['Generated', generated],
      ['App version', appVersion],
      [],
      ['Start', 'End', 'Type', 'Amount', 'Currency', 'Title', 'Category', 'From account', 'To account', 'Notes', 'Excluded from reports'],
    ];
    for (final tx in transactions) {
      final amount = switch (tx.type) {
        MoneyTransactionType.income => tx.amount,
        MoneyTransactionType.expense => -tx.amount,
        MoneyTransactionType.transfer => tx.amount,
      };
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm').format(tx.createdOn),
        DateFormat('yyyy-MM-dd HH:mm').format(tx.effectiveEndOn),
        tx.displayType,
        amount,
        state.currencyCode,
        _analyticsTransactionTitle(state, tx),
        state.categoryOf(tx.categoryId)?.name ?? 'Uncategorized',
        state.accountOf(tx.fromAccountId)?.name ?? 'Unknown account',
        tx.toAccountId == null ? '' : (state.accountOf(tx.toAccountId!)?.name ?? 'Unknown account'),
        tx.notes.trim(),
        tx.excludeFromReports,
      ]);
    }
    return _buildAnalyticsXlsx([_AnalyticsXlsxSheet('Transactions', rows, headerRows: const {0, 6})]);
  }

  final summaryRows = <List<Object?>>[
    ['Koinly Analytics'],
    ['Date filter', snapshot.filterLabel],
    ['Range', snapshot.range.label],
    ['Generated', generated],
    ['App version', appVersion],
    ['Currency', state.currencyCode],
    [],
    ['Metric', 'Value'],
    ['Income', snapshot.income],
    ['Expense', snapshot.expense],
    ['Net cash flow', snapshot.net],
    ['Transactions', snapshot.transactionCount],
    ['Average income / day', snapshot.averageIncomePerDay],
    ['Average expense / day', snapshot.averageExpensePerDay],
    [],
    ['Activity', 'Value'],
    ['Income transactions', snapshot.incomeCount],
    ['Expense transactions', snapshot.expenseCount],
    ['Transfers', snapshot.transferCount],
    ['Transfer volume', snapshot.transferVolume],
    ['Savings in', snapshot.savingsIn],
    ['Savings out', snapshot.savingsOut],
    ['Loan records started', snapshot.newLoanCount],
    ['Repayments', snapshot.repaymentCount],
    ['Repayment total', snapshot.repaymentTotal],
    ['Relevant budgets', snapshot.budgetCount],
    ['Budget limit', snapshot.budgetLimit],
    ['Budget spent', snapshot.budgetSpent],
  ];
  final headerRows = <int>{0, 7, 15};
  if (snapshot.compareWithPrevious) {
    final comparisonHeader = summaryRows.length + 1;
    summaryRows.addAll([
      [],
      ['Compared with previous period', 'Change'],
      ['Income', _analyticsComparisonLabel(snapshot.income, snapshot.previousIncome)],
      ['Expense', _analyticsComparisonLabel(snapshot.expense, snapshot.previousExpense)],
      ['Net cash flow', _analyticsComparisonLabel(snapshot.net, snapshot.previousNet)],
    ]);
    headerRows.add(comparisonHeader);
  }
  final expenseRows = <List<Object?>>[['Category', 'Amount', 'Share %']];
  expenseRows.addAll(snapshot.expenseCategories.map((item) => [item.name, item.amount, item.share * 100]));
  final incomeRows = <List<Object?>>[['Category', 'Amount', 'Share %']];
  incomeRows.addAll(snapshot.incomeCategories.map((item) => [item.name, item.amount, item.share * 100]));
  final accountRows = <List<Object?>>[['Account', 'Balance', 'Currency']];
  accountRows.addAll(state.accounts.map((account) => [account.name, account.amount, state.currencyCode]));
  return _buildAnalyticsXlsx([
    _AnalyticsXlsxSheet('Summary', summaryRows, headerRows: headerRows),
    _AnalyticsXlsxSheet('Expense categories', expenseRows, headerRows: const {0}),
    _AnalyticsXlsxSheet('Income categories', incomeRows, headerRows: const {0}),
    _AnalyticsXlsxSheet('Accounts', accountRows, headerRows: const {0}),
  ]);
}

Future<Uint8List> buildAnalyticsReport(
  AppController state,
  AnalyticsSnapshot snapshot, {
  required AnalyticsPdfVariant variant,
  required AnalyticsReportFormat format,
}) async {
  return switch (format) {
    AnalyticsReportFormat.pdf => AnalyticsPdfService.build(state, snapshot, variant: variant),
    AnalyticsReportFormat.xlsx => _analyticsXlsxReport(state, snapshot, variant),
    AnalyticsReportFormat.txt => _analyticsTextReport(state, snapshot, variant),
  };
}

Future<String?> downloadAnalyticsReport(
  BuildContext context,
  AppController state,
  AnalyticsSnapshot snapshot, {
  AnalyticsPdfVariant variant = AnalyticsPdfVariant.summary,
  AnalyticsReportFormat format = AnalyticsReportFormat.pdf,
}) async {
  try {
    final bytes = await buildAnalyticsReport(state, snapshot, variant: variant, format: format);
    final fileName = analyticsReportFileName(snapshot, variant: variant, format: format);
    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: variant == AnalyticsPdfVariant.summary
            ? 'Save Koinly analytics ${format.label}'
            : 'Save Koinly transaction history ${format.label}',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [format.extension],
        bytes: bytes,
      );
      if (savedPath == null) return null;
      if (context.mounted) showSnack(context, '${variant == AnalyticsPdfVariant.summary ? 'Analytics' : 'Transaction history'} ${format.label} saved.');
      return savedPath;
    } catch (_) {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(documents.path, 'Koinly', 'Analytics'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      if (context.mounted) showSnack(context, '${format.label} saved to ${file.path}.');
      return file.path;
    }
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not create the ${format.label} report.');
    return null;
  }
}

String _analyticsUploadError(Object error) {
  if (error is CloudSyncException) return error.message;
  final text = error.toString().replaceFirst('Bad state: ', '').trim();
  return text.isEmpty ? 'The upload failed.' : text;
}

String _analyticsTelegramCaption(AnalyticsSnapshot snapshot, AnalyticsPdfVariant variant, AnalyticsReportFormat format) {
  final title = switch (variant) {
    AnalyticsPdfVariant.summary => 'Koinly ${snapshot.filterLabel} Analytics',
    AnalyticsPdfVariant.transactionHistory => 'Koinly Transaction History',
  };
  return '$title • ${format.label}\n${snapshot.range.label}';
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  DateRangeType dateFilter = DateRangeType.thisMonth;
  DateTime? customStart;
  DateTime? customEnd;
  bool exporting = false;
  AnalyticsPdfVariant pdfVariant = AnalyticsPdfVariant.summary;
  AnalyticsReportFormat reportFormat = AnalyticsReportFormat.pdf;

  Future<void> _chooseDateFilter() async {
    final selectedId = await showAppleWheelSelectionSheet(
      context,
      title: 'Choose Date Filter',
      selectedId: enumName(dateFilter),
      options: DateRangeType.values.map(optionFromDateRangeType).toList(),
    );
    if (selectedId == null || !mounted) return;

    final selected = DateRangeType.values.firstWhere(
      (type) => enumName(type) == selectedId,
      orElse: () => dateFilter,
    );

    if (selected == DateRangeType.custom) {
      final range = await pickCustomDateRange(
        context,
        start: customStart,
        end: customEnd,
      );
      if (!mounted || range == null) return;
      setState(() {
        dateFilter = DateRangeType.custom;
        customStart = range.start;
        customEnd = range.end;
      });
      return;
    }

    setState(() => dateFilter = selected);
  }

  Future<void> _download(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await downloadAnalyticsReport(context, state, snapshot, variant: pdfVariant, format: reportFormat);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _uploadTelegram(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final bytes = await buildAnalyticsReport(state, snapshot, variant: pdfVariant, format: reportFormat);
      await state.uploadAnalyticsPdfToTelegram(
        fileName: analyticsReportFileName(snapshot, variant: pdfVariant, format: reportFormat),
        bytes: bytes,
        caption: _analyticsTelegramCaption(snapshot, pdfVariant, reportFormat),
      );
      if (mounted) showSnack(context, '${pdfVariant == AnalyticsPdfVariant.summary ? 'Analytics' : 'Transaction history'} ${reportFormat.label} uploaded to Telegram.');
    } catch (error) {
      if (!mounted) return;
      final message = _analyticsUploadError(error);
      if (message == 'Not found.' || message.contains('HTTP_404')) {
        showSnack(context, 'Redeploy the latest Self-Hosted Sync Worker to enable Analytics uploads.');
      } else {
        showSnack(context, message);
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _uploadGoogleDrive(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final bytes = await buildAnalyticsReport(state, snapshot, variant: pdfVariant, format: reportFormat);
      final result = await state.uploadAnalyticsPdfToGoogleDrive(
        fileName: analyticsReportFileName(snapshot, variant: pdfVariant, format: reportFormat),
        bytes: bytes,
      );
      if (!mounted) return;
      final folder = result['folderPath']?.toString() ?? result['folderName']?.toString() ?? 'Koinly Analytics';
      showSnack(context, '${pdfVariant == AnalyticsPdfVariant.summary ? 'Analytics' : 'Transaction history'} ${reportFormat.label} uploaded to Google Drive • $folder');
    } catch (error) {
      if (!mounted) return;
      final message = _analyticsUploadError(error);
      if (message == 'Not found.' || message.contains('HTTP_404')) {
        showSnack(context, 'Redeploy the latest Self-Hosted Sync Worker to enable Analytics uploads.');
      } else {
        showSnack(context, message);
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final snapshot = AnalyticsSnapshot.build(
      state,
      dateFilter,
      customStart: customStart,
      customEnd: customEnd,
    );

    return PageScaffold(
      title: 'Analytics',
      subtitle: snapshot.range.label,
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              padding: EdgeInsets.zero,
              child: MotionInkWell(
                onTap: exporting ? null : _chooseDateFilter,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    iconBubble(context, 'custom_range', '#B4A5FF', size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Choose Date Filter', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          '${dateFilter.analyticsLabel} • ${snapshot.range.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ),
            const SectionHeader('Overview'),
            Row(children: [
              Expanded(child: MiniMetric('Income', state.format(snapshot.income), Icons.south_west_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Expense', state.format(snapshot.expense), Icons.north_east_rounded)),
            ]),
            const SizedBox(height: 10),
            MiniMetric('Net cash flow', state.format(snapshot.net), Icons.compare_arrows_rounded),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: MiniMetric('Transactions', snapshot.transactionCount.toString(), Icons.receipt_long_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Transfers', snapshot.transferCount.toString(), Icons.swap_horiz_rounded)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: MiniMetric('Income / day', state.format(snapshot.averageIncomePerDay), Icons.trending_up_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Expense / day', state.format(snapshot.averageExpensePerDay), Icons.trending_down_rounded)),
            ]),
            const SectionHeader('Report'),
            ExpressiveCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    iconBubble(context, 'document', '#9AD0F5', size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Report type', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          pdfVariant.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  SleekPillSelector<AnalyticsPdfVariant>(
                    options: const [
                      SleekPillOption(value: AnalyticsPdfVariant.summary, label: 'Summary'),
                      SleekPillOption(value: AnalyticsPdfVariant.transactionHistory, label: 'Transaction history'),
                    ],
                    selected: pdfVariant,
                    onChanged: (value) {
                      if (!exporting) setState(() => pdfVariant = value);
                    },
                  ),
                  if (pdfVariant == AnalyticsPdfVariant.transactionHistory) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Transaction history uses the selected date filter. Choose All Time to include every transaction stored in Koinly.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('File format', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  SegmentedButton<AnalyticsReportFormat>(
                    segments: const [
                      ButtonSegment(value: AnalyticsReportFormat.pdf, label: Text('PDF')),
                      ButtonSegment(value: AnalyticsReportFormat.xlsx, label: Text('XLSX')),
                      ButtonSegment(value: AnalyticsReportFormat.txt, label: Text('TXT')),
                    ],
                    selected: {reportFormat},
                    onSelectionChanged: exporting ? null : (value) => setState(() => reportFormat = value.first),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: exporting ? null : () => _download(state, snapshot),
                      icon: exporting ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
                      label: Text('Download ${reportFormat.label}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exporting ? null : () => _uploadTelegram(state, snapshot),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Upload Telegram'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exporting ? null : () => _uploadGoogleDrive(state, snapshot),
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text('Upload Drive'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Telegram and Google Drive uploads go directly through your Self-Hosted Sync Worker. Configure both integrations in Settings > Credential.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _driveFolderController = TextEditingController();

  TelegramBackupSettings _telegram = const TelegramBackupSettings.defaults();
  GoogleDriveAnalyticsSettings _drive = const GoogleDriveAnalyticsSettings.defaults();
  bool _loading = true;
  bool _busy = false;
  bool _botTokenVisible = false;
  bool _clientSecretVisible = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _chatIdController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _driveFolderController.dispose();
    super.dispose();
  }

  bool _signedIn(AppController state) =>
      state.cloudSyncEnabled && state.syncAccountUsername.isNotEmpty && state.selfHostedSyncApiBaseUrl.isNotEmpty;

  String _redirectUri(AppController state) {
    final base = CloudSyncService.normalizeApiBaseUrl(
      state.cloudSyncApiBaseUrl.isNotEmpty ? state.cloudSyncApiBaseUrl : state.selfHostedSyncApiBaseUrl,
    );
    return base.isEmpty ? '' : '$base/v1/analytics-upload/google-drive/callback';
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      setState(() {
        _loading = false;
        _loadError = null;
      });
      return;
    }
    if (!quiet) setState(() => _loading = true);
    try {
      final telegram = await state.loadSelfHostedTelegramBackupSettings();
      final drive = await state.loadGoogleDriveAnalyticsSettings();
      if (!mounted) return;
      setState(() {
        _telegram = telegram;
        _drive = drive;
        _chatIdController.text = telegram.chatId;
        _clientIdController.text = drive.clientId;
        _driveFolderController.text = drive.folderPath;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _analyticsUploadError(error);
      setState(() {
        _loadError = message == 'Not found.'
            ? 'Redeploy the latest Self-Hosted Sync Worker to use cloud credentials.'
            : message;
        _loading = false;
      });
    }
  }

  Future<void> _saveTelegramCredentials() async {
    if (_busy) return;
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) {
      showSnack(context, 'Enter the Telegram group or channel Chat ID.');
      return;
    }
    if (!_telegram.tokenConfigured && _botTokenController.text.trim().isEmpty) {
      showSnack(context, 'Enter a Telegram bot token.');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await context.read<AppController>().saveSelfHostedTelegramBackupSettings(
            enabled: _telegram.enabled,
            botToken: _botTokenController.text,
            chatId: chatId,
            frequency: _telegram.frequency,
            hour: _telegram.hour,
            minute: _telegram.minute,
            weekday: _telegram.weekday,
            monthDay: _telegram.monthDay,
          );
      if (!mounted) return;
      _botTokenController.clear();
      setState(() {
        _telegram = saved;
        _chatIdController.text = saved.chatId;
        _botTokenVisible = false;
      });
      showSnack(context, 'Telegram credentials saved.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testTelegramCredentials() async {
    if (_busy) return;
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) {
      showSnack(context, 'Enter the Telegram group or channel Chat ID.');
      return;
    }
    if (!_telegram.tokenConfigured && _botTokenController.text.trim().isEmpty) {
      showSnack(context, 'Enter a Telegram bot token.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppController>().testSelfHostedTelegramBackup(
            botToken: _botTokenController.text,
            chatId: chatId,
          );
      if (mounted) showSnack(context, 'Telegram credentials are working. Check the target chat.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyRedirect(AppController state) async {
    final value = _redirectUri(state);
    if (value.isEmpty) {
      showSnack(context, 'Validate your Self-Hosted Sync Worker first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showSnack(context, 'Google OAuth redirect URI copied.');
  }

  Future<void> _saveGoogleDriveSettings() async {
    if (_busy) return;
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      showSnack(context, 'Sign in to your Self-Hosted Sync Worker first.');
      return;
    }
    if (_clientIdController.text.trim().isEmpty) {
      showSnack(context, 'Enter the Google OAuth Client ID.');
      return;
    }
    if (!_drive.clientSecretConfigured && _clientSecretController.text.trim().isEmpty) {
      showSnack(context, 'Enter the Google OAuth Client Secret.');
      return;
    }
    if (_driveFolderController.text.trim().isEmpty) {
      showSnack(context, 'Enter a Google Drive upload folder.');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await state.saveGoogleDriveAnalyticsSettings(
        clientId: _clientIdController.text,
        clientSecret: _clientSecretController.text,
        folderPath: _driveFolderController.text,
      );
      if (!mounted) return;
      _clientSecretController.clear();
      setState(() {
        _drive = saved;
        _driveFolderController.text = saved.folderPath;
        _clientSecretVisible = false;
      });
      showSnack(
        context,
        saved.connected ? 'Google Drive settings saved.' : 'Google Drive settings saved. Connect Drive to authorize uploads.',
      );
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectGoogleDrive() async {
    if (_busy) return;
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      showSnack(context, 'Sign in to your Self-Hosted Sync Worker first.');
      return;
    }
    if (_clientIdController.text.trim().isEmpty) {
      showSnack(context, 'Enter the Google OAuth Client ID.');
      return;
    }
    if (!_drive.clientSecretConfigured && _clientSecretController.text.trim().isEmpty) {
      showSnack(context, 'Enter the Google OAuth Client Secret.');
      return;
    }
    if (_driveFolderController.text.trim().isEmpty) {
      showSnack(context, 'Enter a Google Drive upload folder.');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await state.saveGoogleDriveAnalyticsSettings(
        clientId: _clientIdController.text,
        clientSecret: _clientSecretController.text,
        folderPath: _driveFolderController.text,
      );
      if (!mounted) return;
      setState(() {
        _drive = saved;
        _driveFolderController.text = saved.folderPath;
      });
      _clientSecretController.clear();
      final result = await state.googleDriveAnalyticsConnectUrl();
      final rawUrl = result['authorizationUrl']?.toString() ?? '';
      final url = Uri.tryParse(rawUrl);
      if (url == null || url.scheme.toLowerCase() != 'https') {
        throw StateError('The Worker did not return a valid Google authorization URL.');
      }
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open Google authorization in your browser.');
      if (mounted) showSnack(context, 'Finish Google authorization in the browser. Koinly will detect it automatically.');

      for (var attempt = 0; attempt < 60 && mounted; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        try {
          final next = await state.loadGoogleDriveAnalyticsSettings();
          if (!mounted) return;
          setState(() => _drive = next);
          if (next.connected) {
            showSnack(context, next.accountEmail.isEmpty ? 'Google Drive connected.' : 'Google Drive connected • ${next.accountEmail}');
            return;
          }
        } catch (_) {
          // Browser authorization may still be completing. Keep polling.
        }
      }
      if (mounted) showSnack(context, 'Google Drive is not connected yet. Finish authorization, then tap Refresh.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await context.read<AppController>().disconnectGoogleDriveAnalytics();
      if (!mounted) return;
      setState(() => _drive = next);
      showSnack(context, 'Google Drive disconnected. Automatic Drive report upload was turned off.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final signedIn = _signedIn(state);
    final redirectUri = _redirectUri(state);

    return PageScaffold(
      title: 'Credential',
      subtitle: 'Telegram and Google Drive',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: _loading || _busy ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!signedIn)
                    ExpressiveCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          iconBubble(context, 'cloud', kSleekAccentHex, size: 48),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Self-Hosted Sync Worker required', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          'Telegram and Google Drive credentials are stored by your Self-Hosted Sync Worker. Sign in first to configure them.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiDeviceSyncScreen())),
                          icon: const Icon(Icons.cloud_sync_rounded),
                          label: const Text('Open Account & sync'),
                        ),
                      ]),
                    )
                  else ...[
                    if (_loadError != null) ...[
                      ExpressiveCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_loadError!, style: const TextStyle(fontWeight: FontWeight.w800))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SectionHeader('Telegram bot'),
                    ExpressiveCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          iconBubble(context, 'send', '#86E3CE', size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Telegram', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(
                                _telegram.tokenConfigured && _telegram.chatId.isNotEmpty
                                    ? 'Configured • ${_telegram.chatId}'
                                    : 'Used for automatic backups and report delivery',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                              ),
                            ]),
                          ),
                          Icon(
                            _telegram.tokenConfigured && _telegram.chatId.isNotEmpty ? Icons.check_circle_rounded : Icons.key_rounded,
                            color: _telegram.tokenConfigured && _telegram.chatId.isNotEmpty ? kSleekAccent : kSleekMuted,
                          ),
                        ]),
                        const SizedBox(height: 14),
                        TextField(
                          contextMenuBuilder: koinlyTextFieldContextMenu,
                          enableInteractiveSelection: true,
                          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                          controller: _botTokenController,
                          readOnly: _busy,
                          obscureText: !_botTokenVisible,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: _telegram.tokenConfigured ? 'Bot token (saved)' : 'Bot token',
                            hintText: _telegram.tokenConfigured ? 'Leave blank to keep the current token' : '123456789:AA...',
                            prefixIcon: const Icon(Icons.smart_toy_rounded),
                            suffixIcon: IconButton(
                              tooltip: _botTokenVisible ? 'Hide token' : 'Show token',
                              onPressed: _busy ? null : () => setState(() => _botTokenVisible = !_botTokenVisible),
                              icon: Icon(_botTokenVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          contextMenuBuilder: koinlyTextFieldContextMenu,
                          enableInteractiveSelection: true,
                          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                          controller: _chatIdController,
                          readOnly: _busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Group or channel Chat ID',
                            hintText: '-1001234567890 or @channelname',
                            prefixIcon: Icon(Icons.forum_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _testTelegramCredentials,
                              icon: const Icon(Icons.verified_rounded),
                              label: const Text('Test'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _saveTelegramCredentials,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save'),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const SectionHeader('Google Drive'),
                    ExpressiveCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          iconBubble(context, 'cloud', '#9AD0F5', size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Google Drive', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(
                                _drive.connected
                                    ? (_drive.accountEmail.isEmpty ? 'Connected' : 'Connected • ${_drive.accountEmail}')
                                    : 'Configure OAuth credentials and connect your Drive',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                              ),
                            ]),
                          ),
                          Icon(_drive.connected ? Icons.check_circle_rounded : Icons.key_rounded, color: _drive.connected ? kSleekAccent : kSleekMuted),
                        ]),
                        const SizedBox(height: 14),
                        Text(
                          'Enable Google Drive API, create an OAuth 2.0 Web application, add the redirect URI below, then enter its Client ID and Client Secret.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700, height: 1.45),
                        ),
                        const SizedBox(height: 14),
                        Text('Authorized redirect URI', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: .45),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .55)),
                          ),
                          child: Row(children: [
                            Expanded(child: SelectableText(redirectUri, style: const TextStyle(fontWeight: FontWeight.w700))),
                            IconButton(onPressed: _busy ? null : () => _copyRedirect(state), icon: const Icon(Icons.copy_rounded), tooltip: 'Copy redirect URI'),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _clientIdController,
                          enabled: !_busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(labelText: 'Google OAuth Client ID', prefixIcon: Icon(Icons.badge_outlined)),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clientSecretController,
                          enabled: !_busy,
                          obscureText: !_clientSecretVisible,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Google OAuth Client Secret',
                            hintText: _drive.clientSecretConfigured ? 'Leave blank to keep the saved secret' : null,
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: IconButton(
                              tooltip: _clientSecretVisible ? 'Hide secret' : 'Show secret',
                              onPressed: _busy ? null : () => setState(() => _clientSecretVisible = !_clientSecretVisible),
                              icon: Icon(_clientSecretVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _driveFolderController,
                          enabled: !_busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Google Drive upload folder',
                            hintText: 'Koinly Analytics or Finance/Koinly',
                            prefixIcon: Icon(Icons.folder_rounded),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose a folder path inside My Drive. Koinly creates missing folders and uses the same destination for manual and automatic report uploads.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        if (_drive.connected) ...[
                          FilledButton.icon(
                            onPressed: _busy ? null : _saveGoogleDriveSettings,
                            icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                            label: const Text('Save Google Drive settings'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _connectGoogleDrive,
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('Reconnect Google Drive'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _disconnectGoogleDrive,
                            icon: const Icon(Icons.link_off_rounded),
                            label: const Text('Disconnect Google Drive'),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: _busy ? null : _connectGoogleDrive,
                            icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded),
                            label: const Text('Save and connect Google Drive'),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'Koinly keeps the Google OAuth Client Secret and refresh token encrypted in your Worker. These credentials are configured only on this page.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  GoogleDriveAnalyticsSettings _drive = const GoogleDriveAnalyticsSettings.defaults();
  TelegramBackupSettings _telegram = const TelegramBackupSettings.defaults();
  AnalyticsPdfScheduleSettings _telegramPdfSchedule =
      const AnalyticsPdfScheduleSettings.defaults(AnalyticsPdfScheduleDestination.telegram);
  AnalyticsPdfScheduleSettings _drivePdfSchedule =
      const AnalyticsPdfScheduleSettings.defaults(AnalyticsPdfScheduleDestination.googleDrive);
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool _signedIn(AppController state) =>
      state.cloudSyncEnabled && state.syncAccountUsername.isNotEmpty && state.selfHostedSyncApiBaseUrl.isNotEmpty;

  Future<void> _load() async {
    if (!mounted) return;
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      setState(() {
        _loading = false;
        _loadError = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final telegram = await state.loadSelfHostedTelegramBackupSettings();
      final drive = await state.loadGoogleDriveAnalyticsSettings();
      final schedules = await state.loadAnalyticsPdfSchedules();
      if (!mounted) return;
      setState(() {
        _telegram = telegram;
        _drive = drive;
        _telegramPdfSchedule = schedules[AnalyticsPdfScheduleDestination.telegram] ??
            const AnalyticsPdfScheduleSettings.defaults(AnalyticsPdfScheduleDestination.telegram);
        _drivePdfSchedule = schedules[AnalyticsPdfScheduleDestination.googleDrive] ??
            const AnalyticsPdfScheduleSettings.defaults(AnalyticsPdfScheduleDestination.googleDrive);
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _analyticsUploadError(error);
      setState(() {
        _loadError = message == 'Not found.'
            ? 'Redeploy the latest Self-Hosted Sync Worker to use automatic cloud report uploads.'
            : message;
        _loading = false;
      });
    }
  }

  AnalyticsPdfScheduleSettings _schedule(AnalyticsPdfScheduleDestination destination) =>
      destination == AnalyticsPdfScheduleDestination.telegram ? _telegramPdfSchedule : _drivePdfSchedule;

  void _setSchedule(AnalyticsPdfScheduleDestination destination, AnalyticsPdfScheduleSettings next) {
    setState(() {
      if (destination == AnalyticsPdfScheduleDestination.telegram) {
        _telegramPdfSchedule = next;
      } else {
        _drivePdfSchedule = next;
      }
    });
  }

  Future<void> _pickScheduleTime(AnalyticsPdfScheduleDestination destination) async {
    final current = _schedule(destination);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    _setSchedule(
      destination,
      current.copyWith(
        hour: picked.hour,
        minute: picked.minute,
        timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      ),
    );
  }

  Future<void> _savePdfSchedule(AnalyticsPdfScheduleDestination destination) async {
    if (_busy) return;
    final current = _schedule(destination);
    final telegramReady = _telegram.tokenConfigured && _telegram.chatId.isNotEmpty;
    if (current.enabled && destination == AnalyticsPdfScheduleDestination.telegram && !telegramReady) {
      showSnack(context, 'Configure Telegram in Settings > Credential before enabling automatic report uploads.');
      return;
    }
    if (current.enabled && destination == AnalyticsPdfScheduleDestination.googleDrive && !_drive.connected) {
      showSnack(context, 'Connect Google Drive in Settings > Credential before enabling automatic report uploads.');
      return;
    }
    if (current.dateFilter == AnalyticsPdfScheduleDateFilter.custom && (current.customStart == null || current.customEnd == null)) {
      showSnack(context, 'Choose a custom start and end date before saving the report schedule.');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await context.read<AppController>().saveAnalyticsPdfSchedule(current);
      if (!mounted) return;
      _setSchedule(destination, saved);
      showSnack(
        context,
        saved.enabled
            ? '${destination == AnalyticsPdfScheduleDestination.telegram ? 'Telegram' : 'Google Drive'} automatic report schedule saved.'
            : '${destination == AnalyticsPdfScheduleDestination.telegram ? 'Telegram' : 'Google Drive'} automatic report upload is off.',
      );
      await _load();
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadReportNow(AnalyticsPdfScheduleDestination destination) async {
    if (_busy) return;
    final current = _schedule(destination);
    final telegramReady = _telegram.tokenConfigured && _telegram.chatId.isNotEmpty;
    if (destination == AnalyticsPdfScheduleDestination.telegram && !telegramReady) {
      showSnack(context, 'Configure Telegram in Settings > Credential first.');
      return;
    }
    if (destination == AnalyticsPdfScheduleDestination.googleDrive && !_drive.connected) {
      showSnack(context, 'Connect Google Drive in Settings > Credential first.');
      return;
    }
    if (current.dateFilter == AnalyticsPdfScheduleDateFilter.custom && (current.customStart == null || current.customEnd == null)) {
      showSnack(context, 'Choose a custom start and end date before uploading the report.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await context.read<AppController>().sendAnalyticsReportNow(current);
      if (!mounted) return;
      final destinationName = destination == AnalyticsPdfScheduleDestination.telegram ? 'Telegram' : 'Google Drive';
      final fileName = result['fileName']?.toString();
      final folderPath = result['folderPath']?.toString();
      final suffix = destination == AnalyticsPdfScheduleDestination.googleDrive && folderPath != null && folderPath.isNotEmpty
          ? ' • $folderPath'
          : '';
      showSnack(context, '${fileName?.isNotEmpty == true ? fileName! : 'Report'} uploaded to $destinationName$suffix');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _weekdayLabel(int weekday) => const {
        DateTime.monday: 'Monday',
        DateTime.tuesday: 'Tuesday',
        DateTime.wednesday: 'Wednesday',
        DateTime.thursday: 'Thursday',
        DateTime.friday: 'Friday',
        DateTime.saturday: 'Saturday',
        DateTime.sunday: 'Sunday',
      }[weekday] ?? 'Sunday';

  String _scheduleDateFilterLabel(AnalyticsPdfScheduleDateFilter filter) => switch (filter) {
        AnalyticsPdfScheduleDateFilter.today => 'Today',
        AnalyticsPdfScheduleDateFilter.thisWeek => 'This Week',
        AnalyticsPdfScheduleDateFilter.thisMonth => 'This Month',
        AnalyticsPdfScheduleDateFilter.thisYear => 'This Year',
        AnalyticsPdfScheduleDateFilter.allTime => 'All Time',
        AnalyticsPdfScheduleDateFilter.custom => 'Custom Range',
      };

  SelectionOption _scheduleDateFilterOption(AnalyticsPdfScheduleDateFilter filter) => switch (filter) {
        AnalyticsPdfScheduleDateFilter.today => const SelectionOption(id: 'today', title: 'Today', subtitle: 'Only today', iconName: 'today', iconColor: kSleekAccentHex),
        AnalyticsPdfScheduleDateFilter.thisWeek => const SelectionOption(id: 'thisWeek', title: 'This Week', subtitle: 'Current week', iconName: 'week', iconColor: '#A6E3A1'),
        AnalyticsPdfScheduleDateFilter.thisMonth => const SelectionOption(id: 'thisMonth', title: 'This Month', subtitle: 'Current month', iconName: 'month', iconColor: kSleekAccentHex),
        AnalyticsPdfScheduleDateFilter.thisYear => const SelectionOption(id: 'thisYear', title: 'This Year', subtitle: 'Current year', iconName: 'year', iconColor: '#FBC879'),
        AnalyticsPdfScheduleDateFilter.allTime => const SelectionOption(id: 'allTime', title: 'All Time', subtitle: 'Everything synchronized', iconName: 'all_time', iconColor: '#B4A5FF'),
        AnalyticsPdfScheduleDateFilter.custom => const SelectionOption(id: 'custom', title: 'Custom range', subtitle: 'Choose start and end date', iconName: 'custom_range', iconColor: '#FFB5D0'),
      };

  String _scheduleCustomRangeLabel(AnalyticsPdfScheduleSettings settings) {
    final start = settings.customStart;
    final end = settings.customEnd;
    if (start == null || end == null) return 'Choose start and end date';
    if (DateUtils.isSameDay(start, end)) return DateFormat('MMM d, yyyy').format(start);
    if (start.year == end.year) {
      return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
    }
    return '${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }

  Future<void> _pickScheduleDateFilter(AnalyticsPdfScheduleDestination destination) async {
    final current = _schedule(destination);
    final selectedId = await showAppleWheelSelectionSheet(
      context,
      title: 'Choose Date Filter',
      selectedId: current.dateFilter.name,
      options: AnalyticsPdfScheduleDateFilter.values.map(_scheduleDateFilterOption).toList(growable: false),
    );
    if (!mounted || selectedId == null) return;
    final selected = AnalyticsPdfScheduleDateFilter.values.firstWhere(
      (value) => value.name == selectedId,
      orElse: () => current.dateFilter,
    );
    if (selected == AnalyticsPdfScheduleDateFilter.custom) {
      final range = await pickCustomDateRange(
        context,
        start: current.customStart,
        end: current.customEnd,
      );
      if (!mounted || range == null) return;
      _setSchedule(
        destination,
        current.copyWith(
          dateFilter: selected,
          customStart: range.start,
          customEnd: range.end,
        ),
      );
      return;
    }
    _setSchedule(destination, current.copyWith(dateFilter: selected));
  }

  String _scheduleStatusTime(DateTime? value) =>
      value == null ? 'Not yet' : DateFormat('MMM d, yyyy • h:mm a').format(value.toLocal());

  Widget _automaticPdfScheduleCard(
    AnalyticsPdfScheduleDestination destination, {
    required bool destinationReady,
  }) {
    final settings = _schedule(destination);
    final destinationName = destination == AnalyticsPdfScheduleDestination.telegram ? 'Telegram' : 'Google Drive';
    final time = TimeOfDay(hour: settings.hour, minute: settings.minute).format(context);
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          iconBubble(context, destination == AnalyticsPdfScheduleDestination.telegram ? 'send' : 'cloud', destination == AnalyticsPdfScheduleDestination.telegram ? '#86E3CE' : '#9AD0F5', size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(destinationName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                destinationReady ? 'Credentials ready' : 'Configure in Settings > Credential first',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
          Icon(destinationReady ? Icons.check_circle_rounded : Icons.key_rounded, color: destinationReady ? kSleekAccent : kSleekMuted),
        ]),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.enabled,
          onChanged: _busy
              ? null
              : (value) {
                  if (value && !destinationReady) {
                    showSnack(
                      context,
                      destination == AnalyticsPdfScheduleDestination.telegram
                          ? 'Configure Telegram in Settings > Credential first.'
                          : 'Connect Google Drive in Settings > Credential first.',
                    );
                    return;
                  }
                  _setSchedule(destination, settings.copyWith(enabled: value));
                },
          title: const Text('Automatic report upload', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('Generated from the latest data synchronized to your Self-Hosted Worker.'),
        ),
        const SizedBox(height: 8),
        SegmentedButton<AnalyticsPdfScheduleReportVariant>(
          segments: const [
            ButtonSegment(value: AnalyticsPdfScheduleReportVariant.summary, label: Text('Summary')),
            ButtonSegment(value: AnalyticsPdfScheduleReportVariant.transactionHistory, label: Text('Transaction history')),
          ],
          selected: {settings.reportVariant},
          onSelectionChanged: _busy ? null : (value) => _setSchedule(destination, settings.copyWith(reportVariant: value.first)),
        ),
        const SizedBox(height: 12),
        Text('File format', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        SegmentedButton<AnalyticsReportFormat>(
          segments: const [
            ButtonSegment(value: AnalyticsReportFormat.pdf, label: Text('PDF')),
            ButtonSegment(value: AnalyticsReportFormat.xlsx, label: Text('XLSX')),
            ButtonSegment(value: AnalyticsReportFormat.txt, label: Text('TXT')),
          ],
          selected: {settings.fileFormat},
          onSelectionChanged: _busy ? null : (value) => _setSchedule(destination, settings.copyWith(fileFormat: value.first)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _pickScheduleDateFilter(destination),
          icon: const Icon(Icons.date_range_rounded),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date filter · ${_scheduleDateFilterLabel(settings.dateFilter)}'),
                if (settings.dateFilter == AnalyticsPdfScheduleDateFilter.custom)
                  Text(
                    _scheduleCustomRangeLabel(settings),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<TelegramBackupFrequency>(
          segments: const [
            ButtonSegment(value: TelegramBackupFrequency.daily, label: Text('Daily')),
            ButtonSegment(value: TelegramBackupFrequency.weekly, label: Text('Weekly')),
            ButtonSegment(value: TelegramBackupFrequency.monthly, label: Text('Monthly')),
          ],
          selected: {settings.frequency},
          onSelectionChanged: _busy ? null : (value) => _setSchedule(destination, settings.copyWith(frequency: value.first)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _pickScheduleTime(destination),
          icon: const Icon(Icons.schedule_rounded),
          label: Text('Time · $time'),
        ),
        if (settings.frequency == TelegramBackupFrequency.weekly) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: settings.weekday,
            decoration: const InputDecoration(labelText: 'Day of week', prefixIcon: Icon(Icons.calendar_view_week_rounded)),
            items: List.generate(7, (index) {
              final weekday = index + 1;
              return DropdownMenuItem(value: weekday, child: Text(_weekdayLabel(weekday)));
            }),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _setSchedule(destination, settings.copyWith(weekday: value));
                  },
          ),
        ],
        if (settings.frequency == TelegramBackupFrequency.monthly) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: settings.monthDay,
            decoration: const InputDecoration(labelText: 'Day of month', prefixIcon: Icon(Icons.calendar_month_rounded)),
            items: List.generate(31, (index) => DropdownMenuItem(value: index + 1, child: Text('Day ${index + 1}'))),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _setSchedule(destination, settings.copyWith(monthDay: value));
                  },
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Telegram report, Google Drive report, and Telegram Backup times must all be at least 5 minutes apart.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text('Last automatic upload: ${_scheduleStatusTime(settings.lastSentAt)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Next scheduled: ${settings.enabled ? _scheduleStatusTime(settings.nextDueAt) : 'Automatic upload is off'}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        if (settings.lastError?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(settings.lastError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || !destinationReady ? null : () => _uploadReportNow(destination),
          icon: const Icon(Icons.cloud_upload_rounded),
          label: const Text('Upload now'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _savePdfSchedule(destination),
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save automatic report schedule'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final signedIn = _signedIn(state);
    final telegramReady = _telegram.tokenConfigured && _telegram.chatId.isNotEmpty;

    return PageScaffold(
      title: 'Cloud Backup',
      subtitle: 'Manual and automatic report uploads',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: _loading || _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!signedIn)
                    ExpressiveCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          iconBubble(context, 'cloud', kSleekAccentHex, size: 48),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Self-Hosted Sync Worker required', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          'Telegram and Google Drive report uploads run through your Self-Hosted Sync Worker.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiDeviceSyncScreen())),
                          icon: const Icon(Icons.cloud_sync_rounded),
                          label: const Text('Open Account & sync'),
                        ),
                      ]),
                    )
                  else ...[
                    if (_loadError != null) ...[
                      ExpressiveCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_loadError!, style: const TextStyle(fontWeight: FontWeight.w800))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _automaticPdfScheduleCard(
                      AnalyticsPdfScheduleDestination.telegram,
                      destinationReady: telegramReady,
                    ),
                    const SizedBox(height: 12),
                    _automaticPdfScheduleCard(
                      AnalyticsPdfScheduleDestination.googleDrive,
                      destinationReady: _drive.connected,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CredentialsScreen()));
                        if (mounted) await _load();
                      },
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Open Credential'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
