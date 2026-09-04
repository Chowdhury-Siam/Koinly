part of '../main.dart';

Future<void> showLoanEditorSheet(BuildContext context, {Loan? loan, LoanDirection defaultDirection = LoanDirection.lent}) {
  return showKoinlyPopup<void>(
    context,
    maxWidth: 600,
    maxHeight: 760,
    barrierDismissible: false,
    child: _LoanEditorSheet(loan: loan, defaultDirection: defaultDirection),
  );
}

class _LoanEditorSheet extends StatefulWidget {
  const _LoanEditorSheet({required this.loan, required this.defaultDirection});

  final Loan? loan;
  final LoanDirection defaultDirection;

  @override
  State<_LoanEditorSheet> createState() => _LoanEditorSheetState();
}

class _LoanEditorSheetState extends State<_LoanEditorSheet> {
  late LoanDirection direction;
  late LoanInterestType interestType;
  late LoanInterestPeriod interestPeriod;
  bool defaultsLoaded = false;
  late DateTime startDate;
  DateTime? dueDate;
  String? contactId;
  String? accountId;
  late bool recordInAccount;
  bool busy = false;
  late final TextEditingController amount;
  late final TextEditingController rate;
  late final TextEditingController installments;
  late final TextEditingController note;
  late final TextEditingController newPerson;

  bool get editing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    direction = loan?.direction ?? widget.defaultDirection;
    interestType = loan?.interestType ?? LoanInterestType.none;
    interestPeriod = loan?.interestPeriod ?? LoanInterestPeriod.yearly;
    startDate = loan?.startDate ?? DateTime.now();
    dueDate = loan?.dueDate;
    contactId = loan?.contactId;
    amount = TextEditingController(text: loan == null ? '' : loan.principal.toStringAsFixed(2));
    rate = TextEditingController(text: loan == null || loan.interestRate == 0 ? '' : loan.interestRate.toStringAsFixed(2));
    installments = TextEditingController(text: loan?.installmentCount?.toString() ?? '');
    note = TextEditingController(text: loan?.note ?? '');
    newPerson = TextEditingController();
    recordInAccount = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (defaultsLoaded) return;
    final state = context.read<AppController>();
    contactId ??= state.loanContacts.where((contact) => !contact.archived).firstOrNull?.id ?? '__new__';
    accountId ??= state.defaultAccountId ?? state.accounts.firstOrNull?.id;
    if (!editing) recordInAccount = state.loanRecordTransactionsByDefault;
    defaultsLoaded = true;
  }

  @override
  void dispose() {
    amount.dispose();
    rate.dispose();
    installments.dispose();
    note.dispose();
    newPerson.dispose();
    super.dispose();
  }

  SelectionOption? _contactOption(AppController state) {
    if (contactId == '__new__') {
      return const SelectionOption(id: '__new__', title: 'Add new person', subtitle: 'Create while saving', iconName: 'favorite', iconColor: '#FBC879');
    }
    final contact = state.loanContactOf(contactId);
    return contact == null
        ? null
        : SelectionOption(id: contact.id, title: contact.name, subtitle: contact.phone.isEmpty ? 'Saved person' : contact.phone, iconName: contact.iconName, iconColor: contact.iconColor);
  }

  Future<void> _pickContact(AppController state) async {
    final options = [
      ...state.loanContacts.where((contact) => !contact.archived).map(
            (contact) => SelectionOption(id: contact.id, title: contact.name, subtitle: contact.phone.isEmpty ? 'Saved person' : contact.phone, iconName: contact.iconName, iconColor: contact.iconColor),
          ),
      const SelectionOption(id: '__new__', title: 'Add new person', subtitle: 'Create while saving', iconName: 'favorite', iconColor: '#FBC879'),
    ];
    final selected = await showAppleWheelSelectionSheet(context, title: 'Choose a person', options: options, selectedId: contactId);
    if (selected != null && mounted) setState(() => contactId = selected);
  }

  Future<void> _pickAccount(AppController state) async {
    final options = state.accounts.map((account) => optionFromAccount(account, state)).toList();
    final selected = await showAppleWheelSelectionSheet(context, title: 'Choose an account', options: options, selectedId: accountId);
    if (selected != null && mounted) setState(() => accountId = selected);
  }

  Future<void> _save() async {
    if (busy) return;
    final state = context.read<AppController>();
    final principal = double.tryParse(amount.text.trim()) ?? 0;
    final annualRate = interestType == LoanInterestType.none ? 0.0 : double.tryParse(rate.text.trim()) ?? 0;
    final installmentCount = int.tryParse(installments.text.trim());
    if (!principal.isFinite || principal <= 0) return showSnack(context, 'Enter a valid amount.');
    if (!annualRate.isFinite || annualRate < 0 || annualRate > 1000) return showSnack(context, 'Enter a valid annual rate.');
    if (installmentCount != null && (installmentCount < 1 || installmentCount > 600)) return showSnack(context, 'Installments must be between 1 and 600.');
    if (dueDate != null && dueDate!.isBefore(startDate)) return showSnack(context, 'Due date cannot be before the start date.');
    if (recordInAccount && (accountId == null || accountId!.isEmpty)) return showSnack(context, 'Select an account.');
    setState(() => busy = true);
    try {
      var selectedContactId = contactId;
      if (selectedContactId == '__new__') {
        final name = newPerson.text.trim();
        if (name.isEmpty) throw StateError('Enter a person name.');
        final now = DateTime.now();
        final contact = LoanContact(id: _uuid.v4(), name: name, createdOn: now, updatedOn: now);
        await state.saveLoanContact(contact);
        selectedContactId = contact.id;
      }
      if (selectedContactId == null || selectedContactId.isEmpty) throw StateError('Select a person.');
      final now = DateTime.now();
      final old = widget.loan;
      final value = Loan(
        id: old?.id ?? _uuid.v4(),
        contactId: selectedContactId,
        direction: direction,
        principal: roundLoanMoney(principal),
        interestType: interestType,
        interestRate: annualRate,
        interestPeriod: interestPeriod,
        startDate: DateTime(startDate.year, startDate.month, startDate.day),
        dueDate: dueDate == null ? null : DateTime(dueDate!.year, dueDate!.month, dueDate!.day),
        installmentCount: installmentCount,
        interestAccrualStop: old?.interestAccrualStop ?? LoanAccrualStop.settled,
        note: note.text.trim(),
        status: old?.status ?? LoanStatus.active,
        closedOn: old?.closedOn,
        disbursalTransactionId: old?.disbursalTransactionId,
        createdOn: old?.createdOn ?? now,
        updatedOn: now,
      );
      await state.saveLoan(value, recordDisbursal: !editing && recordInAccount, accountId: accountId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showSnack(context, error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final contactOption = _contactOption(state);
    final account = state.accountOf(accountId ?? '');
    final accountOption = account == null ? null : optionFromAccount(account, state);
    final previewPrincipal = double.tryParse(amount.text) ?? 0;
    final previewRate = double.tryParse(rate.text) ?? 0;
    final previewCount = int.tryParse(installments.text);
    final now = DateTime.now();
    final preview = Loan(
      id: 'preview',
      contactId: contactId ?? '',
      direction: direction,
      principal: loanNonNegative(previewPrincipal),
      interestType: interestType,
      interestRate: loanNonNegative(previewRate),
      interestPeriod: interestPeriod,
      startDate: startDate,
      dueDate: dueDate,
      installmentCount: previewCount,
      createdOn: now,
      updatedOn: now,
    );
    final emi = loanEmiAmount(preview);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(editing ? 'Edit loan' : 'New loan', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          SleekPillSelector<LoanDirection>(
            options: const [
              SleekPillOption(value: LoanDirection.lent, label: 'I gave', icon: Icons.south_west_rounded),
              SleekPillOption(value: LoanDirection.borrowed, label: 'I took', icon: Icons.north_east_rounded),
            ],
            selected: direction,
            onChanged: (value) => setState(() => direction = value),
          ),
          const SizedBox(height: 6),
          Text(direction == LoanDirection.lent ? 'They owe you this amount.' : 'You owe them this amount.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          AppleSelectionField(label: 'Person', option: contactOption, onTap: () => _pickContact(state)),
          if (contactId == '__new__') ...[
            const SizedBox(height: 10),
            TextField(controller: newPerson, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Person name', prefixIcon: Icon(Icons.person_add_rounded))),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Amount', prefixText: state.currencyPosition == CurrencyPosition.prefix ? state.currencySymbol : null, suffixText: state.currencyPosition == CurrencyPosition.suffix ? state.currencySymbol : null),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final selected = await pickDate(context, startDate);
              if (selected != null && mounted) setState(() => startDate = selected);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text('Start · ${DateFormat('MMM d, yyyy').format(startDate)}'),
          ),
          const SectionHeader('Interest'),
          SleekPillSelector<LoanInterestType>(
            options: const [
              SleekPillOption(value: LoanInterestType.none, label: 'None'),
              SleekPillOption(value: LoanInterestType.simple, label: 'Simple'),
              SleekPillOption(value: LoanInterestType.compound, label: 'Compound'),
            ],
            selected: interestType,
            onChanged: (value) => setState(() {
              interestType = value;
              if (value == LoanInterestType.simple && interestPeriod != LoanInterestPeriod.flat) {
                interestPeriod = LoanInterestPeriod.yearly;
              }
            }),
          ),
          if (interestType != LoanInterestType.none) ...[
            const SizedBox(height: 12),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: interestPeriod == LoanInterestPeriod.flat ? 'Fixed total interest' : 'Annual interest rate',
                suffixText: interestPeriod == LoanInterestPeriod.flat ? '% of principal' : '% APR',
              ),
            ),
            const SizedBox(height: 10),
            SleekCyclePillSelector<LoanInterestPeriod>(
              options: interestType == LoanInterestType.simple
                  ? const [
                      SleekPillOption(value: LoanInterestPeriod.yearly, label: 'Accrue by day'),
                      SleekPillOption(value: LoanInterestPeriod.flat, label: 'Fixed total'),
                    ]
                  : const [
                      SleekPillOption(value: LoanInterestPeriod.yearly, label: 'Yearly compounding'),
                      SleekPillOption(value: LoanInterestPeriod.monthly, label: 'Monthly compounding'),
                      SleekPillOption(value: LoanInterestPeriod.daily, label: 'Daily compounding'),
                      SleekPillOption(value: LoanInterestPeriod.flat, label: 'Fixed total interest'),
                    ],
              selected: interestPeriod,
              onChanged: (value) => setState(() => interestPeriod = value),
            ),
          ],
          const SectionHeader('Plan'),
          TextField(
            controller: installments,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Monthly installments (optional)', hintText: 'Example: 12'),
          ),
          if (emi != null) ...[
            const SizedBox(height: 8),
            Text('Estimated monthly payment: ${state.format(emi)}', style: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900)),
          ],
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: dueDate != null,
            onChanged: (enabled) => setState(() => dueDate = enabled ? startDate.add(const Duration(days: 30)) : null),
            title: const Text('Set a due date', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (dueDate != null)
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await pickDate(context, dueDate!);
                if (selected != null && mounted) setState(() => dueDate = selected);
              },
              icon: const Icon(Icons.event_available_rounded),
              label: Text('Due · ${DateFormat('MMM d, yyyy').format(dueDate!)}'),
            ),
          if (!editing) ...[
            const SectionHeader('Account movement'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: recordInAccount,
              onChanged: (value) => setState(() => recordInAccount = value),
              title: const Text('Record this in an account', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Updates the balance without changing income or expense reports.'),
            ),
            if (recordInAccount) AppleSelectionField(label: 'Account', option: accountOption, onTap: () => _pickAccount(state)),
          ],
          const SizedBox(height: 12),
          TextField(controller: note, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Note (optional)')),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving...' : 'Save loan'))),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showLoanPaymentSheet(BuildContext context, {required Loan loan, double? initialAmount}) {
  return showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 700,
    barrierDismissible: false,
    child: _LoanPaymentSheet(loan: loan, initialAmount: initialAmount),
  );
}

class _LoanPaymentSheet extends StatefulWidget {
  const _LoanPaymentSheet({required this.loan, this.initialAmount});
  final Loan loan;
  final double? initialAmount;

  @override
  State<_LoanPaymentSheet> createState() => _LoanPaymentSheetState();
}

class _LoanPaymentSheetState extends State<_LoanPaymentSheet> {
  final amount = TextEditingController();
  final note = TextEditingController();
  DateTime paidOn = DateTime.now();
  String? accountId;
  bool recordInAccount = false;
  bool defaultsLoaded = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final initialAmount = widget.initialAmount;
    if (initialAmount != null && initialAmount > 0) {
      amount.text = roundLoanMoney(initialAmount).toStringAsFixed(2);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (defaultsLoaded) return;
    final state = context.read<AppController>();
    accountId ??= state.defaultAccountId ?? state.accounts.firstOrNull?.id;
    recordInAccount = state.loanRecordTransactionsByDefault;
    defaultsLoaded = true;
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void _fill(double value) {
    amount.text = roundLoanMoney(loanNonNegative(value)).toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _save() async {
    if (busy) return;
    final state = context.read<AppController>();
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (!value.isFinite || value <= 0) return showSnack(context, 'Enter a valid payment amount.');
    if (recordInAccount && (accountId == null || accountId!.isEmpty)) return showSnack(context, 'Select an account.');
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final payment = LoanPayment(
        id: _uuid.v4(),
        loanId: widget.loan.id,
        amount: roundLoanMoney(value),
        interestComponent: 0,
        principalComponent: roundLoanMoney(value),
        paidOn: paidOn,
        note: note.text.trim(),
        createdOn: now,
        updatedOn: now,
      );
      await state.addLoanPayment(payment, recordInAccount: recordInAccount, accountId: accountId);
      if (mounted) {
        final remaining = loanNonNegative(state.computationFor(widget.loan.id).outstanding);
        showSnack(context, remaining <= 0.005 ? 'Payment recorded · settled.' : 'Payment recorded · ${state.format(remaining)} left.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showSnack(context, error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final computation = state.computationFor(widget.loan.id, at: paidOn);
    final remaining = loanNonNegative(computation.outstanding);
    final value = double.tryParse(amount.text) ?? 0;
    final split = allocateLoanPayment(widget.loan, state.paymentsForLoan(widget.loan.id), value, paidOn);
    final account = state.accountOf(accountId ?? '');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Record payment', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Remaining ${state.format(remaining)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: kSleekAccent, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Payment amount', suffixText: state.currencyPosition == CurrencyPosition.suffix ? state.currencySymbol : null),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(label: const Text('Full'), onPressed: () => _fill(remaining)),
              ActionChip(label: const Text('Half'), onPressed: () => _fill(remaining / 2)),
              if (computation.emiAmount != null) ActionChip(label: const Text('Monthly'), onPressed: () => _fill(computation.emiAmount!)),
              ActionChip(label: const Text('Round up'), onPressed: () => _fill((remaining / 100).ceil() * 100)),
            ],
          ),
          if (value > 0) ...[
            const SizedBox(height: 12),
            ExpressiveCard(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${state.format(split.interest)} interest · ${state.format(split.principal)} principal\nRemaining after this: ${state.format(loanNonNegative(remaining - value))}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (value > remaining + 0.005) ...[
            const SizedBox(height: 8),
            Text(
              'This overpays by ${state.format(value - remaining)}.',
              style: const TextStyle(color: kSleekWarning, fontWeight: FontWeight.w800),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final selected = await pickDate(context, paidOn);
              if (selected != null && mounted) setState(() => paidOn = selected);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text(DateFormat('MMM d, yyyy').format(paidOn)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: recordInAccount,
            onChanged: (value) => setState(() => recordInAccount = value),
            title: const Text('Record this in an account', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Updates the balance but stays outside reports.'),
          ),
          if (recordInAccount)
            AppleSelectionField(
              label: 'Account',
              option: account == null ? null : optionFromAccount(account, state),
              onTap: () async {
                final selected = await showAppleWheelSelectionSheet(
                  context,
                  title: 'Choose an account',
                  options: state.accounts.map((item) => optionFromAccount(item, state)).toList(),
                  selectedId: accountId,
                );
                if (selected != null && mounted) setState(() => accountId = selected);
              },
            ),
          const SizedBox(height: 12),
          TextField(controller: note, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Note (optional)')),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving...' : 'Save payment'))),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showLoanPreferencesSheet(BuildContext context) {
  return showKoinlyPopup<void>(context, maxWidth: 540, maxHeight: 520, child: const _LoanPreferencesSheet());
}

class _LoanPreferencesSheet extends StatelessWidget {
  const _LoanPreferencesSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Loan preferences', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.loanRecordTransactionsByDefault,
            onChanged: (value) => state.setLoanPreferences(recordTransactions: value),
            title: const Text('Record account movements by default', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('These movements never count as income or expenses.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.loanRemindersEnabled,
            onChanged: (value) => state.setLoanPreferences(reminders: value),
            title: const Text('Due-date reminders', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.loanShowWrittenOff,
            onChanged: (value) => state.setLoanPreferences(showWrittenOff: value),
            title: const Text('Show written-off records', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}
