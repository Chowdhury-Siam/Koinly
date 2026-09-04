part of '../main.dart';

enum _LoanFilter { collect, pay, settled, all }

String _signedLoanAmount(AppController state, double value) {
  if (state.amountsHidden || loanNearZero(value)) return state.format(value.abs());
  return '${value > 0 ? '+' : '−'}${state.format(value.abs())}';
}

String _loanDueLabel(Loan loan, LoanComputation computation) {
  if (loan.status == LoanStatus.writtenOff) return 'Written off';
  if (loan.status == LoanStatus.closed || computation.settled) return 'Settled';
  if (computation.overdue) return '${computation.daysOverdue} day${computation.daysOverdue == 1 ? '' : 's'} overdue';
  if (loan.dueDate == null) return 'No due date';
  final rawDays = DateTime.utc(loan.dueDate!.year, loan.dueDate!.month, loan.dueDate!.day)
      .difference(DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day))
      .inDays;
  final days = rawDays < 0 ? 0 : rawDays;
  return days == 0 ? 'Due today' : 'Due in $days day${days == 1 ? '' : 's'}';
}

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  _LoanFilter filter = _LoanFilter.collect;
  final search = TextEditingController();
  bool searching = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final visible = state.loans.where((loan) {
      if (loan.status == LoanStatus.writtenOff && !state.loanShowWrittenOff) return false;
      final query = search.text.trim().toLowerCase();
      final contact = state.loanContactOf(loan.contactId);
      if (query.isNotEmpty &&
          !(contact?.name.toLowerCase().contains(query) ?? false) &&
          !loan.note.toLowerCase().contains(query)) {
        return false;
      }
      final computation = state.computationFor(loan.id);
      return switch (filter) {
        _LoanFilter.collect => loan.isLent && loan.status == LoanStatus.active && !computation.settled,
        _LoanFilter.pay => !loan.isLent && loan.status == LoanStatus.active && !computation.settled,
        _LoanFilter.settled => loan.status == LoanStatus.closed || computation.settled,
        _LoanFilter.all => true,
      };
    }).toList();
    final grouped = <LoanContact, List<Loan>>{};
    for (final loan in visible) {
      final contact = state.loanContactOf(loan.contactId);
      if (contact != null) grouped.putIfAbsent(contact, () => <Loan>[]).add(loan);
    }
    final contacts = grouped.keys.toList()
      ..sort((a, b) => state.netWithLoanContact(b.id).abs().compareTo(state.netWithLoanContact(a.id).abs()));
    final items = <Object>[];
    for (final contact in contacts) {
      final contactLoans = grouped[contact]!
        ..sort((a, b) {
        final ac = state.computationFor(a.id);
        final bc = state.computationFor(b.id);
        if (ac.overdue != bc.overdue) return ac.overdue ? -1 : 1;
        if (a.dueDate == null && b.dueDate != null) return 1;
        if (a.dueDate != null && b.dueDate == null) return -1;
        if (a.dueDate != null && b.dueDate != null) {
          final byDue = a.dueDate!.compareTo(b.dueDate!);
          if (byDue != 0) return byDue;
        }
        return b.updatedOn.compareTo(a.updatedOn);
      });
      items.add(_LoanContactGroup(contact));
      items.addAll(contactLoans);
    }

    return PageScaffold(
      title: 'Loans',
      subtitle: 'Money you lent and borrowed',
      actions: [
        IconButton(
          tooltip: searching ? 'Close search' : 'Search',
          onPressed: () => setState(() {
            searching = !searching;
            if (!searching) search.clear();
          }),
          icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Preferences',
          onPressed: () => showLoanPreferencesSheet(context),
          icon: const Icon(Icons.tune_rounded),
        ),
        IconButton(
          tooltip: 'New loan',
          onPressed: () => showLoanEditorSheet(context, defaultDirection: filter == _LoanFilter.pay ? LoanDirection.borrowed : LoanDirection.lent),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: ResponsiveListContent(
        itemCount: items.length,
        header: [
          _LoanSummaryHero(summary: state.loanSummary),
          const SizedBox(height: 14),
          if (searching) ...[
            TextField(
              controller: search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search people or notes',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SleekPillSelector<_LoanFilter>(
            options: const [
              SleekPillOption(value: _LoanFilter.collect, label: 'Collect', icon: Icons.south_west_rounded),
              SleekPillOption(value: _LoanFilter.pay, label: 'Pay', icon: Icons.north_east_rounded),
              SleekPillOption(value: _LoanFilter.settled, label: 'Settled', icon: Icons.check_rounded),
              SleekPillOption(value: _LoanFilter.all, label: 'All', icon: Icons.list_rounded),
            ],
            selected: filter,
            onChanged: (value) => setState(() => filter = value),
          ),
          SectionHeader(
            filter == _LoanFilter.settled ? 'Settled records' : 'People',
            trailing: TextButton.icon(
              onPressed: () => showLoanEditorSheet(context, defaultDirection: filter == _LoanFilter.pay ? LoanDirection.borrowed : LoanDirection.lent),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New loan'),
            ),
          ),
        ],
        empty: EmptyCard(
          icon: Icons.currency_exchange_rounded,
          title: filter == _LoanFilter.settled ? 'Nothing settled yet' : 'No matching records',
          body: 'Add the first amount you lend or borrow, then record repayments here.',
          action: () => showLoanEditorSheet(context, defaultDirection: filter == _LoanFilter.pay ? LoanDirection.borrowed : LoanDirection.lent),
          actionLabel: 'New loan',
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is _LoanContactGroup) {
            final net = state.netWithLoanContact(item.contact.id);
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Row(
                children: [
                  Expanded(child: Text(item.contact.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                  Text(_signedLoanAmount(state, net), style: const TextStyle(color: kSleekMuted, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          }
          return _LoanTile(loan: item as Loan);
        },
      ),
    );
  }
}

class _LoanContactGroup {
  const _LoanContactGroup(this.contact);
  final LoanContact contact;
}

class _LoanSummaryHero extends StatelessWidget {
  const _LoanSummaryHero({required this.summary});
  final LoanPortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    final scheme = Theme.of(context).colorScheme;
    return PixelFinanceSurface(
      radius: 28,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Money between people', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4))),
              if (summary.overdueCount > 0) PixelPill(label: '${summary.overdueCount} overdue', icon: Icons.schedule_rounded, compact: true),
            ],
          ),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: MiniMetric('To collect', state.format(summary.toCollect), Icons.south_west_rounded)),
            const SizedBox(width: 8),
            Expanded(child: MiniMetric('To pay', state.format(summary.toPay), Icons.north_east_rounded)),
          ]),
          const SizedBox(height: 8),
          MiniMetric('Net position', _signedLoanAmount(state, summary.net), Icons.balance_rounded),
        ],
      ),
    );
  }
}



class _LoanTile extends StatelessWidget {
  const _LoanTile({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    final contact = state.loanContactOf(loan.contactId);
    final computation = state.computationFor(loan.id);
    final dueLabel = _loanDueLabel(loan, computation);
    final accent = computation.overdue ? kSleekWarning : loan.isLent ? kSleekIncome : kSleekExpense;
    return Semantics(
      button: true,
      label: '${contact?.name ?? 'Unknown person'}, ${loan.isLent ? 'lent' : 'borrowed'} ${state.format(loan.principal)}, ${state.format(loanNonNegative(computation.outstanding))} outstanding, $dueLabel',
      child: PixelFinanceSurface(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.id))),
        radius: 20,
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            iconBubble(context, loan.isLent ? 'gift' : 'cash', loan.isLent ? '#83D6A9' : '#FF8D9B', size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(contact?.name ?? 'Unknown person', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                    const SizedBox(width: 8),
                    Text(state.format(loanNonNegative(computation.outstanding)), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: accent, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${loan.isLent ? 'Collect' : 'Pay'} · $dueLabel', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: computation.overdue ? kSleekWarning : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: computation.progress, minHeight: 5, color: accent, backgroundColor: accent.withOpacity(.12)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}



class LoanDetailScreen extends StatelessWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final loan = state.loanOf(loanId);
    if (loan == null) {
      return const PageScaffold(
        title: 'Record unavailable',
        child: ResponsiveContent(child: EmptyCard(icon: Icons.info_rounded, title: 'This record was removed', body: 'Go back to view the current portfolio.')),
      );
    }
    final contact = state.loanContactOf(loan.contactId);
    final computation = state.computationFor(loan.id);
    final payments = state.paymentsForLoan(loan.id).reversed.toList(growable: false);
    final remaining = loanNonNegative(computation.outstanding);
    return PageScaffold(
      title: contact?.name ?? 'Loan details',
      subtitle: '${loan.isLent ? 'Lent' : 'Borrowed'} on ${DateFormat('MMM d, yyyy').format(loan.startDate)}',
      actions: [
        IconButton(
          tooltip: 'Share statement',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => Share.share(
            loan.isLent
                ? '${contact?.name ?? 'This person'} will pay you ${state.format(remaining)} as of ${DateFormat('MMM d, yyyy').format(DateTime.now())}.'
                : 'You will pay ${contact?.name ?? 'this person'} ${state.format(remaining)} as of ${DateFormat('MMM d, yyyy').format(DateTime.now())}.',
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') await showLoanEditorSheet(context, loan: loan);
            if (value == 'close') {
              if (remaining <= 0.005) {
                await state.setLoanStatus(loan.id, LoanStatus.closed);
              } else {
                await showLoanPaymentSheet(context, loan: loan, initialAmount: remaining);
              }
            }
            if (value == 'reopen') await state.setLoanStatus(loan.id, LoanStatus.active);
            if (value == 'writeoff') await state.setLoanStatus(loan.id, LoanStatus.writtenOff);
            if (value == 'delete' && context.mounted) await _confirmDeleteLoan(context, state, loan);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (loan.status == LoanStatus.active)
              PopupMenuItem(value: 'close', child: Text(remaining <= 0.005 ? 'Mark as settled' : 'Settle with final payment')),
            if (loan.status != LoanStatus.active) const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
            if (loan.status != LoanStatus.writtenOff) const PopupMenuItem(value: 'writeoff', child: Text('Write off')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
      child: ResponsiveListContent(
        itemCount: payments.length,
        header: [
          _LoanDetailHero(loan: loan, computation: computation),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MiniMetric('Principal', state.format(computation.principal), Icons.account_balance_wallet_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Interest', state.format(computation.interestAccrued), Icons.percent_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MiniMetric('Paid', state.format(computation.totalPaid), Icons.payments_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Remaining', state.format(remaining), Icons.pending_actions_rounded)),
            ],
          ),
          if (loan.installmentCount != null || loan.dueDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: MiniMetric('Monthly estimate', computation.emiAmount == null ? '—' : state.format(computation.emiAmount!), Icons.calculate_rounded)),
                const SizedBox(width: 10),
                Expanded(child: MiniMetric('Due date', loan.dueDate == null ? 'Not set' : DateFormat('MMM d, yyyy').format(loan.dueDate!), Icons.event_rounded)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: loan.status == LoanStatus.active ? () => showLoanPaymentSheet(context, loan: loan) : null,
            icon: const Icon(Icons.add_card_rounded),
            label: const Text('Record payment'),
          ),
          const SectionHeader('Payments'),
        ],
        empty: const EmptyCard(icon: Icons.receipt_long_rounded, title: 'No payments yet', body: 'Payments recorded for this person will appear here.'),
        itemBuilder: (context, index) {
          final payment = payments[index];
          return ExpressiveCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: iconBubble(context, 'receipt', '#A6E3A1', size: 44),
              title: Text(state.format(payment.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(
                '${DateFormat('MMM d, yyyy').format(payment.paidOn)} · ${state.format(payment.interestComponent)} interest + ${state.format(payment.principalComponent)} principal',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Delete payment',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDeleteLoanPayment(context, state, payment),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoanDetailHero extends StatelessWidget {
  const _LoanDetailHero({required this.loan, required this.computation});
  final Loan loan;
  final LoanComputation computation;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final color = computation.overdue ? kSleekWarning : loan.isLent ? kSleekIncome : kSleekExpense;
    return PixelFinanceSurface(
      radius: 28,
      color: color.withOpacity(Theme.of(context).brightness == Brightness.dark ? .12 : .15),
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loan.isLent ? 'Still to collect' : 'Still to pay', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(state.format(loanNonNegative(computation.outstanding)), style: Theme.of(context).textTheme.displaySmall?.copyWith(color: color, fontWeight: FontWeight.w900, letterSpacing: -1)),
          const SizedBox(height: 6),
          Text(_loanDueLabel(loan, computation), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: computation.overdue ? kSleekWarning : scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: computation.progress, minHeight: 7, color: color, backgroundColor: color.withOpacity(.12))),
          const SizedBox(height: 6),
          Text('${(computation.progress * 100).round()}% repaid', textAlign: TextAlign.right, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}



Future<void> _confirmDeleteLoan(BuildContext context, AppController state, Loan loan) async {
  var deleteTransactions = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setModalState) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The repayment history will also be removed.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteTransactions,
              onChanged: (value) => setModalState(() => deleteTransactions = value ?? false),
              title: const Text('Also delete linked account transactions'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    ),
  );
  if (confirmed != true) return;
  await state.deleteLoan(loan.id, deleteLinkedTransactions: deleteTransactions);
  if (context.mounted) Navigator.pop(context);
}

Future<void> _confirmDeleteLoanPayment(BuildContext context, AppController state, LoanPayment payment) async {
  var deleteTransaction = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setModalState) => AlertDialog(
        title: const Text('Delete payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The remaining amount will be recalculated.'),
            if (payment.transactionId != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteTransaction,
                onChanged: (value) => setModalState(() => deleteTransaction = value ?? false),
                title: const Text('Also delete the linked account transaction'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    ),
  );
  if (confirmed == true) await state.deleteLoanPayment(payment.id, deleteLinkedTransaction: deleteTransaction);
}
