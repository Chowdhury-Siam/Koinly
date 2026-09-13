part of '../main.dart';

enum AnalyticsPeriod { daily, weekly, monthly, yearly }

extension AnalyticsPeriodLabel on AnalyticsPeriod {
  String get label => switch (this) {
        AnalyticsPeriod.daily => 'Daily',
        AnalyticsPeriod.weekly => 'Weekly',
        AnalyticsPeriod.monthly => 'Monthly',
        AnalyticsPeriod.yearly => 'Yearly',
      };

  IconData get icon => switch (this) {
        AnalyticsPeriod.daily => Icons.today_rounded,
        AnalyticsPeriod.weekly => Icons.view_week_rounded,
        AnalyticsPeriod.monthly => Icons.calendar_month_rounded,
        AnalyticsPeriod.yearly => Icons.calendar_view_month_rounded,
      };
}

class AnalyticsRange {
  const AnalyticsRange({required this.start, required this.end, required this.label});

  final DateTime start;
  final DateTime end;
  final String label;

  int get dayCount => math.max(1, end.difference(start).inDays);
}

AnalyticsRange analyticsRangeFor(AnalyticsPeriod period, DateTime anchor) {
  final day = DateTime(anchor.year, anchor.month, anchor.day);
  switch (period) {
    case AnalyticsPeriod.daily:
      return AnalyticsRange(
        start: day,
        end: day.add(const Duration(days: 1)),
        label: DateFormat('EEE, MMM d, yyyy').format(day),
      );
    case AnalyticsPeriod.weekly:
      final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
      final end = start.add(const Duration(days: 7));
      final last = end.subtract(const Duration(days: 1));
      final sameYear = start.year == last.year;
      final label = sameYear
          ? '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(last)}'
          : '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(last)}';
      return AnalyticsRange(start: start, end: end, label: label);
    case AnalyticsPeriod.monthly:
      final start = DateTime(day.year, day.month, 1);
      return AnalyticsRange(
        start: start,
        end: DateTime(start.year, start.month + 1, 1),
        label: DateFormat('MMMM yyyy').format(start),
      );
    case AnalyticsPeriod.yearly:
      final start = DateTime(day.year, 1, 1);
      return AnalyticsRange(
        start: start,
        end: DateTime(day.year + 1, 1, 1),
        label: day.year.toString(),
      );
  }
}

DateTime shiftAnalyticsAnchor(AnalyticsPeriod period, DateTime anchor, int amount) {
  switch (period) {
    case AnalyticsPeriod.daily:
      return anchor.add(Duration(days: amount));
    case AnalyticsPeriod.weekly:
      return anchor.add(Duration(days: amount * 7));
    case AnalyticsPeriod.monthly:
      return DateTime(anchor.year, anchor.month + amount, 1);
    case AnalyticsPeriod.yearly:
      return DateTime(anchor.year + amount, 1, 1);
  }
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
    required this.period,
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
  });

  final AnalyticsPeriod period;
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

  double get net => income - expense;
  double get savingsNet => savingsIn - savingsOut;
  double get averageIncomePerDay => income / range.dayCount;
  double get averageExpensePerDay => expense / range.dayCount;
  double get budgetRemaining => budgetLimit - budgetSpent;
  double get budgetUsage => budgetLimit <= 0 ? 0 : budgetSpent / budgetLimit;
  int get transactionCount => transactions.length;
  int get incomeCount => transactions.where((tx) => tx.countsAsIncome).length;
  int get expenseCount => transactions.where((tx) => tx.countsAsExpense).length;

  static AnalyticsSnapshot build(AppController state, AnalyticsPeriod period, DateTime anchor) {
    final range = analyticsRangeFor(period, anchor);
    final previousAnchor = shiftAnalyticsAnchor(period, range.start, -1);
    final previousRange = analyticsRangeFor(period, previousAnchor);
    final current = _buildAnalyticsCore(state, range);
    final previous = _buildAnalyticsCore(state, previousRange);

    return AnalyticsSnapshot(
      period: period,
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
      previousIncome: previous.income,
      previousExpense: previous.expense,
      previousNet: previous.income - previous.expense,
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

String analyticsPdfFileName(AnalyticsSnapshot snapshot) {
  final stamp = switch (snapshot.period) {
    AnalyticsPeriod.daily => DateFormat('yyyy-MM-dd').format(snapshot.range.start),
    AnalyticsPeriod.weekly => '${DateFormat('yyyy-MM-dd').format(snapshot.range.start)}_week',
    AnalyticsPeriod.monthly => DateFormat('yyyy-MM').format(snapshot.range.start),
    AnalyticsPeriod.yearly => snapshot.range.start.year.toString(),
  };
  return 'Koinly-Analytics-${snapshot.period.name}-$stamp.pdf';
}

class AnalyticsPdfService {
  const AnalyticsPdfService._();

  static Future<Uint8List> build(AppController state, AnalyticsSnapshot snapshot) async {
    final document = pw.Document();

    pw.Widget metric(String label, String value) => pw.Container(
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

    pw.Widget categorySection(String title, List<AnalyticsCategoryItem> items) {
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
          pw.Text('${snapshot.period.label} summary - ${_analyticsPdfSafe(snapshot.range.label)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Generated $generated | App version $appVersion', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 18),
          pw.Wrap(children: [
            metric('Income', _analyticsPdfMoney(state, snapshot.income)),
            metric('Expense', _analyticsPdfMoney(state, snapshot.expense)),
            metric('Net cash flow', _analyticsPdfMoney(state, snapshot.net)),
            metric('Transactions', snapshot.transactionCount.toString()),
            metric('Avg income / day', _analyticsPdfMoney(state, snapshot.averageIncomePerDay)),
            metric('Avg expense / day', _analyticsPdfMoney(state, snapshot.averageExpensePerDay)),
          ]),
          pw.SizedBox(height: 10),
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
          categorySection('Top expense categories', snapshot.expenseCategories),
          pw.SizedBox(height: 16),
          categorySection('Top income categories', snapshot.incomeCategories),
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
}

Future<String?> downloadAnalyticsPdf(BuildContext context, AppController state, AnalyticsSnapshot snapshot) async {
  try {
    final bytes = await AnalyticsPdfService.build(state, snapshot);
    final fileName = analyticsPdfFileName(snapshot);
    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Koinly analytics PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (savedPath == null) return null;
      if (context.mounted) showSnack(context, 'Analytics PDF saved.');
      return savedPath;
    } catch (_) {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(documents.path, 'Koinly', 'Analytics'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      if (context.mounted) showSnack(context, 'Analytics PDF saved to ${file.path}.');
      return file.path;
    }
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not create the analytics PDF.');
    return null;
  }
}

Future<void> shareAnalyticsPdf(BuildContext context, AppController state, AnalyticsSnapshot snapshot) async {
  try {
    final bytes = await AnalyticsPdfService.build(state, snapshot);
    final temp = await getTemporaryDirectory();
    final file = File(p.join(temp.path, analyticsPdfFileName(snapshot)));
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: p.basename(file.path))],
      subject: 'Koinly Analytics - ${snapshot.range.label}',
      text: 'Koinly ${snapshot.period.label.toLowerCase()} analytics summary for ${snapshot.range.label}.',
    );
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not open the share sheet for this PDF.');
  }
}

String _analyticsUploadError(Object error) {
  if (error is CloudSyncException) return error.message;
  final text = error.toString().replaceFirst('Bad state: ', '').trim();
  return text.isEmpty ? 'The upload failed.' : text;
}

String _analyticsTelegramCaption(AnalyticsSnapshot snapshot) {
  return 'Koinly ${snapshot.period.label} Analytics\n${snapshot.range.label}';
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsPeriod period = AnalyticsPeriod.monthly;
  DateTime anchor = DateTime.now();
  bool exporting = false;

  void _changePeriod(AnalyticsPeriod value) {
    setState(() {
      period = value;
      anchor = DateTime.now();
    });
  }

  void _movePeriod(int amount) {
    final candidate = shiftAnalyticsAnchor(period, anchor, amount);
    final currentStart = analyticsRangeFor(period, DateTime.now()).start;
    if (analyticsRangeFor(period, candidate).start.isAfter(currentStart)) return;
    setState(() => anchor = candidate);
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: anchor.isAfter(now) ? now : anchor,
      firstDate: DateTime(2000, 1, 1),
      lastDate: now,
      helpText: 'Choose ${period.label.toLowerCase()} analytics period',
    );
    if (selected != null && mounted) setState(() => anchor = selected);
  }

  Future<void> _download(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await downloadAnalyticsPdf(context, state, snapshot);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _share(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await shareAnalyticsPdf(context, state, snapshot);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _uploadTelegram(AppController state, AnalyticsSnapshot snapshot) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final bytes = await AnalyticsPdfService.build(state, snapshot);
      await state.uploadAnalyticsPdfToTelegram(
        fileName: analyticsPdfFileName(snapshot),
        bytes: bytes,
        caption: _analyticsTelegramCaption(snapshot),
      );
      if (mounted) showSnack(context, 'Analytics PDF uploaded to Telegram.');
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
      final bytes = await AnalyticsPdfService.build(state, snapshot);
      final result = await state.uploadAnalyticsPdfToGoogleDrive(
        fileName: analyticsPdfFileName(snapshot),
        bytes: bytes,
      );
      if (!mounted) return;
      final folder = result['folderName']?.toString() ?? 'Koinly Analytics';
      showSnack(context, 'Analytics PDF uploaded to Google Drive • $folder');
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
    final snapshot = AnalyticsSnapshot.build(state, period, anchor);
    final currentStart = analyticsRangeFor(period, DateTime.now()).start;
    final canMoveForward = analyticsRangeFor(period, shiftAnalyticsAnchor(period, anchor, 1)).start.compareTo(currentStart) <= 0;

    return PageScaffold(
      title: 'Analytics',
      subtitle: snapshot.range.label,
      actions: [
        IconButton.filledTonal(
          tooltip: 'Analytics upload settings',
          onPressed: exporting ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsUploadSettingsScreen())),
          icon: const Icon(Icons.cloud_upload_rounded),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SleekPillSelector<AnalyticsPeriod>(
              options: const [
                SleekPillOption(value: AnalyticsPeriod.daily, label: 'Daily'),
                SleekPillOption(value: AnalyticsPeriod.weekly, label: 'Weekly'),
                SleekPillOption(value: AnalyticsPeriod.monthly, label: 'Monthly'),
                SleekPillOption(value: AnalyticsPeriod.yearly, label: 'Yearly'),
              ],
              selected: period,
              onChanged: _changePeriod,
            ),
            const SizedBox(height: 12),
            _AnalyticsPeriodNavigator(
              label: snapshot.range.label,
              icon: period.icon,
              onPrevious: () => _movePeriod(-1),
              onNext: canMoveForward ? () => _movePeriod(1) : null,
              onPick: _pickPeriod,
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
            const SectionHeader('Compared with previous period'),
            _AnalyticsComparisonCard(snapshot: snapshot),
            const SectionHeader('Activity'),
            _AnalyticsActivityCard(snapshot: snapshot),
            if (snapshot.budgetCount > 0) ...[
              const SectionHeader('Budgets'),
              _AnalyticsBudgetCard(snapshot: snapshot),
            ],
            const SectionHeader('Top expense categories'),
            _AnalyticsCategoryCard(items: snapshot.expenseCategories, emptyLabel: 'No expense activity in this period.'),
            const SectionHeader('Top income categories'),
            _AnalyticsCategoryCard(items: snapshot.incomeCategories, emptyLabel: 'No income activity in this period.'),
            const SectionHeader('Current account snapshot'),
            _AnalyticsAccountsCard(accounts: state.accounts),
            const SectionHeader('PDF report'),
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
                        Text('Export this summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          'Create a PDF with totals, activity, category breakdowns, budgets, and account balances.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: exporting ? null : () => _download(state, snapshot),
                        icon: exporting ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
                        label: const Text('Download PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exporting ? null : () => _share(state, snapshot),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share PDF'),
                      ),
                    ),
                  ]),
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
                    'Telegram and Google Drive uploads go directly through your Self-Hosted Sync Worker. Configure them with the cloud button above.',
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

class AnalyticsUploadSettingsScreen extends StatefulWidget {
  const AnalyticsUploadSettingsScreen({super.key});

  @override
  State<AnalyticsUploadSettingsScreen> createState() => _AnalyticsUploadSettingsScreenState();
}

class _AnalyticsUploadSettingsScreenState extends State<AnalyticsUploadSettingsScreen> {
  final clientIdController = TextEditingController();
  final clientSecretController = TextEditingController();
  GoogleDriveAnalyticsSettings drive = const GoogleDriveAnalyticsSettings.defaults();
  TelegramBackupSettings telegram = const TelegramBackupSettings.defaults();
  bool loading = true;
  bool busy = false;
  bool secretVisible = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    clientIdController.dispose();
    clientSecretController.dispose();
    super.dispose();
  }

  bool _signedIn(AppController state) {
    return state.cloudSyncEnabled && state.syncAccountUsername.isNotEmpty && state.selfHostedSyncApiBaseUrl.isNotEmpty;
  }

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
        loading = false;
        loadError = null;
      });
      return;
    }
    if (!quiet) setState(() => loading = true);
    try {
      final nextTelegram = await state.loadSelfHostedTelegramBackupSettings();
      if (!mounted) return;
      setState(() => telegram = nextTelegram);
      final nextDrive = await state.loadGoogleDriveAnalyticsSettings();
      if (!mounted) return;
      setState(() {
        drive = nextDrive;
        clientIdController.text = nextDrive.clientId;
        loadError = null;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _analyticsUploadError(error);
      setState(() {
        loadError = message == 'Not found.' ? 'Redeploy the latest Self-Hosted Sync Worker to enable Analytics uploads.' : message;
        loading = false;
      });
    }
  }

  Future<void> _openTelegramSettings() async {
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      showSnack(context, 'Sign in to your Self-Hosted Sync Worker first.');
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfHostedTelegramBackupScreen()));
    if (mounted) await _load(quiet: true);
  }

  Future<void> _connectGoogleDrive() async {
    if (busy) return;
    final state = context.read<AppController>();
    if (!_signedIn(state)) {
      showSnack(context, 'Sign in to your Self-Hosted Sync Worker first.');
      return;
    }
    setState(() => busy = true);
    try {
      final saved = await state.saveGoogleDriveAnalyticsSettings(
        clientId: clientIdController.text,
        clientSecret: clientSecretController.text,
      );
      if (!mounted) return;
      setState(() => drive = saved);
      clientSecretController.clear();
      final result = await state.googleDriveAnalyticsConnectUrl();
      final rawUrl = result['authorizationUrl']?.toString() ?? '';
      final url = Uri.tryParse(rawUrl);
      if (url == null || url.scheme.toLowerCase() != 'https') throw StateError('The Worker did not return a valid Google authorization URL.');
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open Google authorization in your browser.');
      if (mounted) showSnack(context, 'Finish Google authorization in the browser. Koinly will detect it automatically.');

      for (var attempt = 0; attempt < 60 && mounted; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        try {
          final next = await state.loadGoogleDriveAnalyticsSettings();
          if (!mounted) return;
          setState(() => drive = next);
          if (next.connected) {
            showSnack(context, next.accountEmail.isEmpty ? 'Google Drive connected.' : 'Google Drive connected • ${next.accountEmail}');
            return;
          }
        } catch (_) {
          // The browser may still be completing the OAuth callback. Keep polling.
        }
      }
      if (mounted) showSnack(context, 'Google Drive is not connected yet. Finish authorization, then tap Refresh.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    if (busy) return;
    final state = context.read<AppController>();
    setState(() => busy = true);
    try {
      final next = await state.disconnectGoogleDriveAnalytics();
      if (!mounted) return;
      setState(() => drive = next);
      showSnack(context, 'Google Drive disconnected.');
    } catch (error) {
      if (mounted) showSnack(context, _analyticsUploadError(error));
    } finally {
      if (mounted) setState(() => busy = false);
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final signedIn = _signedIn(state);
    final redirectUri = _redirectUri(state);
    final telegramReady = telegram.tokenConfigured && telegram.chatId.isNotEmpty;

    return PageScaffold(
      title: 'Analytics uploads',
      subtitle: 'Telegram and Google Drive',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: loading || busy ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: loading
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
                        Text('Direct Analytics uploads use your own Worker so credentials stay with your self-hosted account.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiDeviceSyncScreen())),
                          icon: const Icon(Icons.cloud_sync_rounded),
                          label: const Text('Open Account & sync'),
                        ),
                      ]),
                    )
                  else ...[
                    if (loadError != null) ...[
                      ExpressiveCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(loadError!, style: const TextStyle(fontWeight: FontWeight.w800))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SectionHeader('Telegram'),
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
                                telegramReady ? 'Ready • ${telegram.chatId}' : 'Configure your Telegram bot and destination',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                              ),
                            ]),
                          ),
                          Icon(telegramReady ? Icons.check_circle_rounded : Icons.settings_rounded, color: telegramReady ? kSleekAccent : kSleekMuted),
                        ]),
                        const SizedBox(height: 12),
                        Text('Analytics PDFs reuse the same bot token and group/channel destination as Telegram backup. Automatic backup can stay off.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: busy ? null : _openTelegramSettings,
                          icon: const Icon(Icons.settings_rounded),
                          label: Text(telegramReady ? 'Telegram backup settings' : 'Configure Telegram'),
                        ),
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
                                drive.connected
                                    ? (drive.accountEmail.isEmpty ? 'Connected' : 'Connected • ${drive.accountEmail}')
                                    : 'Connect once, then upload PDFs directly',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                              ),
                            ]),
                          ),
                          Icon(drive.connected ? Icons.check_circle_rounded : Icons.cloud_upload_rounded, color: drive.connected ? kSleekAccent : kSleekMuted),
                        ]),
                        const SizedBox(height: 14),
                        Text('1. Enable Google Drive API.  2. Create an OAuth 2.0 Web application.  3. Add the redirect URI below.  4. Paste the Client ID and Client Secret, then connect.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700, height: 1.45)),
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
                            IconButton(onPressed: busy ? null : () => _copyRedirect(state), icon: const Icon(Icons.copy_rounded), tooltip: 'Copy redirect URI'),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clientIdController,
                          enabled: !busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(labelText: 'Google OAuth Client ID', prefixIcon: Icon(Icons.badge_outlined)),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: clientSecretController,
                          enabled: !busy,
                          obscureText: !secretVisible,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Google OAuth Client Secret',
                            hintText: drive.clientSecretConfigured ? 'Saved securely in your Worker' : null,
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => secretVisible = !secretVisible),
                              icon: Icon(secretVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (drive.connected) ...[
                          FilledButton.icon(
                            onPressed: busy ? null : _connectGoogleDrive,
                            icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
                            label: const Text('Reconnect Google Drive'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: busy ? null : _disconnectGoogleDrive,
                            icon: const Icon(Icons.link_off_rounded),
                            label: const Text('Disconnect Google Drive'),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: busy ? null : _connectGoogleDrive,
                            icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded),
                            label: const Text('Save and connect Google Drive'),
                          ),
                        const SizedBox(height: 10),
                        Text('PDFs are uploaded to a “${drive.folderName}” folder created by Koinly. The Worker stores the OAuth Client Secret and refresh token encrypted with your Worker JWT secret.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                        if (drive.lastUploadAt != null) ...[
                          const SizedBox(height: 6),
                          Text('Last upload ${DateFormat('MMM d, yyyy HH:mm').format(drive.lastUploadAt!.toLocal())}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                        ],
                        if (drive.lastError?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text('Last error: ${drive.lastError}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent, fontWeight: FontWeight.w800)),
                        ],
                      ]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _AnalyticsPeriodNavigator extends StatelessWidget {
  const _AnalyticsPeriodNavigator({required this.label, required this.icon, required this.onPrevious, required this.onNext, required this.onPick});

  final String label;
  final IconData icon;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous period'),
        Expanded(
          child: MotionInkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20, color: kSleekAccent),
                const SizedBox(width: 8),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
              ]),
            ),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next period'),
      ]),
    );
  }
}

class _AnalyticsComparisonCard extends StatelessWidget {
  const _AnalyticsComparisonCard({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  String _delta(double current, double previous) {
    if (previous.abs() < .0001) return current.abs() < .0001 ? 'No change' : 'New activity';
    final percent = ((current - previous) / previous.abs()) * 100;
    final sign = percent > 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    Widget line(String label, double current, double previous, IconData icon) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, size: 20, color: kSleekAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(_delta(current, previous), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        ]),
      );
    }

    return ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(children: [
        line('Income', snapshot.income, snapshot.previousIncome, Icons.south_west_rounded),
        line('Expense', snapshot.expense, snapshot.previousExpense, Icons.north_east_rounded),
        line('Net cash flow', snapshot.net, snapshot.previousNet, Icons.compare_arrows_rounded),
      ]),
    );
  }
}

class _AnalyticsActivityCard extends StatelessWidget {
  const _AnalyticsActivityCard({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final items = <(String, String, IconData)>[
      ('Income transactions', snapshot.incomeCount.toString(), Icons.south_west_rounded),
      ('Expense transactions', snapshot.expenseCount.toString(), Icons.north_east_rounded),
      ('Transfer volume', state.format(snapshot.transferVolume), Icons.swap_horiz_rounded),
      ('Savings change', state.format(snapshot.savingsNet), Icons.savings_rounded),
      ('New loans', snapshot.newLoanCount.toString(), Icons.account_balance_rounded),
      ('Repayments', '${snapshot.repaymentCount} • ${state.format(snapshot.repaymentTotal)}', Icons.payments_rounded),
    ];
    return ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(item.$3, size: 20, color: kSleekAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(item.$2, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                ))
            .toList(),
      ),
    );
  }
}

class _AnalyticsBudgetCard extends StatelessWidget {
  const _AnalyticsBudgetCard({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final usage = snapshot.budgetUsage.clamp(0.0, 2.0).toDouble();
    final progress = usage.clamp(0.0, 1.0).toDouble();
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${snapshot.budgetCount} relevant budget${snapshot.budgetCount == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w900))),
          Text('${(usage * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: progress, minHeight: 8)),
        const SizedBox(height: 10),
        Text('${state.format(snapshot.budgetSpent)} spent of ${state.format(snapshot.budgetLimit)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800)),
        Text('Remaining: ${state.format(snapshot.budgetRemaining)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _AnalyticsCategoryCard extends StatelessWidget {
  const _AnalyticsCategoryCard({required this.items, required this.emptyLabel});

  final List<AnalyticsCategoryItem> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final visible = items.take(6).toList();
    return ExpressiveCard(
      padding: const EdgeInsets.all(14),
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(emptyLabel, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
            )
          : Column(
              children: visible
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          iconBubble(context, item.category?.iconName ?? 'category', item.category?.iconColor ?? kSleekAccentHex, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(value: item.share.clamp(0.0, 1.0).toDouble(), minHeight: 5),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(state.format(item.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text('${(item.share * 100).toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800)),
                          ]),
                        ]),
                      ))
                  .toList(),
            ),
    );
  }
}

class _AnalyticsAccountsCard extends StatelessWidget {
  const _AnalyticsAccountsCard({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return ExpressiveCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Balances shown here are the current account balances, not reconstructed historical balances.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('No accounts yet.', textAlign: TextAlign.center))
        else
          ...accounts.map((account) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  iconBubble(context, account.iconName, account.iconColor, size: 38),
                  const SizedBox(width: 10),
                  Expanded(child: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(state.format(account.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              )),
      ]),
    );
  }
}
