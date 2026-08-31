import '../models.dart';

enum LoanDirection { lent, borrowed }

enum LoanInterestType { none, simple, compound }

enum LoanInterestPeriod { daily, monthly, yearly, flat }

enum LoanStatus { active, closed, writtenOff }

enum LoanAccrualStop { settled, dueDate }

String loanStatusToDb(LoanStatus value) => switch (value) {
      LoanStatus.active => 'active',
      LoanStatus.closed => 'closed',
      LoanStatus.writtenOff => 'written_off',
    };

LoanStatus loanStatusFromDb(Object? raw) => switch (raw?.toString()) {
      'closed' => LoanStatus.closed,
      'written_off' || 'writtenOff' => LoanStatus.writtenOff,
      _ => LoanStatus.active,
    };

String loanAccrualStopToDb(LoanAccrualStop value) => value == LoanAccrualStop.dueDate ? 'due_date' : 'settled';

LoanAccrualStop loanAccrualStopFromDb(Object? raw) => raw?.toString() == 'due_date' || raw?.toString() == 'dueDate'
    ? LoanAccrualStop.dueDate
    : LoanAccrualStop.settled;

class LoanContact {
  const LoanContact({
    required this.id,
    required this.name,
    this.phone = '',
    this.note = '',
    this.iconName = 'exchange',
    this.iconColor = '#FBC879',
    this.archived = false,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String name;
  final String phone;
  final String note;
  final String iconName;
  final String iconColor;
  final bool archived;
  final DateTime createdOn;
  final DateTime updatedOn;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  LoanContact copyWith({
    String? id,
    String? name,
    String? phone,
    String? note,
    String? iconName,
    String? iconColor,
    bool? archived,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) =>
      LoanContact(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        note: note ?? this.note,
        iconName: iconName ?? this.iconName,
        iconColor: iconColor ?? this.iconColor,
        archived: archived ?? this.archived,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'note': note,
        'icon_name': iconName,
        'icon_color': iconColor,
        'archived': archived ? 1 : 0,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static LoanContact fromMap(Map<String, Object?> map) => LoanContact(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        phone: map['phone']?.toString() ?? '',
        note: map['note']?.toString() ?? '',
        iconName: map['icon_name']?.toString() ?? 'exchange',
        iconColor: map['icon_color']?.toString() ?? '#FBC879',
        archived: (map['archived'] as num? ?? 0).toInt() == 1,
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );
}

class Loan {
  const Loan({
    required this.id,
    required this.contactId,
    required this.direction,
    required this.principal,
    this.interestType = LoanInterestType.none,
    this.interestRate = 0,
    this.interestPeriod = LoanInterestPeriod.yearly,
    required this.startDate,
    this.dueDate,
    this.installmentCount,
    this.interestAccrualStop = LoanAccrualStop.settled,
    this.note = '',
    this.status = LoanStatus.active,
    this.closedOn,
    this.disbursalTransactionId,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String contactId;
  final LoanDirection direction;
  final double principal;
  final LoanInterestType interestType;
  final double interestRate;
  final LoanInterestPeriod interestPeriod;
  final DateTime startDate;
  final DateTime? dueDate;
  final int? installmentCount;
  final LoanAccrualStop interestAccrualStop;
  final String note;
  final LoanStatus status;
  final DateTime? closedOn;
  final String? disbursalTransactionId;
  final DateTime createdOn;
  final DateTime updatedOn;

  bool get isLent => direction == LoanDirection.lent;
  bool get isActive => status == LoanStatus.active;
  bool get hasInterest => interestType != LoanInterestType.none && interestRate > 0;

  Loan copyWith({
    String? id,
    String? contactId,
    LoanDirection? direction,
    double? principal,
    LoanInterestType? interestType,
    double? interestRate,
    LoanInterestPeriod? interestPeriod,
    DateTime? startDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    int? installmentCount,
    bool clearInstallmentCount = false,
    LoanAccrualStop? interestAccrualStop,
    String? note,
    LoanStatus? status,
    DateTime? closedOn,
    bool clearClosedOn = false,
    String? disbursalTransactionId,
    bool clearDisbursalTransactionId = false,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) =>
      Loan(
        id: id ?? this.id,
        contactId: contactId ?? this.contactId,
        direction: direction ?? this.direction,
        principal: principal ?? this.principal,
        interestType: interestType ?? this.interestType,
        interestRate: interestRate ?? this.interestRate,
        interestPeriod: interestPeriod ?? this.interestPeriod,
        startDate: startDate ?? this.startDate,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        installmentCount: clearInstallmentCount ? null : (installmentCount ?? this.installmentCount),
        interestAccrualStop: interestAccrualStop ?? this.interestAccrualStop,
        note: note ?? this.note,
        status: status ?? this.status,
        closedOn: clearClosedOn ? null : (closedOn ?? this.closedOn),
        disbursalTransactionId:
            clearDisbursalTransactionId ? null : (disbursalTransactionId ?? this.disbursalTransactionId),
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'contact_id': contactId,
        'direction': enumName(direction),
        'principal': principal,
        'interest_type': enumName(interestType),
        'interest_rate': interestRate,
        'interest_period': enumName(interestPeriod),
        'start_date': dateToDb(startDate),
        'due_date': dueDate == null ? null : dateToDb(dueDate!),
        'installment_count': installmentCount,
        'interest_accrual_stop': loanAccrualStopToDb(interestAccrualStop),
        'note': note,
        'status': loanStatusToDb(status),
        'closed_on': closedOn == null ? null : dateToDb(closedOn!),
        'disbursal_transaction_id': disbursalTransactionId,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static Loan fromMap(Map<String, Object?> map) => Loan(
        id: map['id']?.toString() ?? '',
        contactId: map['contact_id']?.toString() ?? '',
        direction: enumByName(LoanDirection.values, map['direction']?.toString(), LoanDirection.lent),
        principal: (map['principal'] as num? ?? 0).toDouble(),
        interestType: enumByName(LoanInterestType.values, map['interest_type']?.toString(), LoanInterestType.none),
        interestRate: (map['interest_rate'] as num? ?? 0).toDouble(),
        interestPeriod: enumByName(LoanInterestPeriod.values, map['interest_period']?.toString(), LoanInterestPeriod.yearly),
        startDate: dateFromDb(map['start_date']),
        dueDate: map['due_date'] == null ? null : dateFromDb(map['due_date']),
        installmentCount: (map['installment_count'] as num?)?.toInt(),
        interestAccrualStop: loanAccrualStopFromDb(map['interest_accrual_stop']),
        note: map['note']?.toString() ?? '',
        status: loanStatusFromDb(map['status']),
        closedOn: map['closed_on'] == null ? null : dateFromDb(map['closed_on']),
        disbursalTransactionId: map['disbursal_transaction_id']?.toString(),
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );
}

class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.interestComponent,
    required this.principalComponent,
    required this.paidOn,
    this.note = '',
    this.transactionId,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String loanId;
  final double amount;
  final double interestComponent;
  final double principalComponent;
  final DateTime paidOn;
  final String note;
  final String? transactionId;
  final DateTime createdOn;
  final DateTime updatedOn;

  LoanPayment copyWith({
    String? id,
    String? loanId,
    double? amount,
    double? interestComponent,
    double? principalComponent,
    DateTime? paidOn,
    String? note,
    String? transactionId,
    bool clearTransactionId = false,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) =>
      LoanPayment(
        id: id ?? this.id,
        loanId: loanId ?? this.loanId,
        amount: amount ?? this.amount,
        interestComponent: interestComponent ?? this.interestComponent,
        principalComponent: principalComponent ?? this.principalComponent,
        paidOn: paidOn ?? this.paidOn,
        note: note ?? this.note,
        transactionId: clearTransactionId ? null : (transactionId ?? this.transactionId),
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'loan_id': loanId,
        'amount': amount,
        'interest_component': interestComponent,
        'principal_component': principalComponent,
        'paid_on': dateToDb(paidOn),
        'note': note,
        'transaction_id': transactionId,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static LoanPayment fromMap(Map<String, Object?> map) => LoanPayment(
        id: map['id']?.toString() ?? '',
        loanId: map['loan_id']?.toString() ?? '',
        amount: (map['amount'] as num? ?? 0).toDouble(),
        interestComponent: (map['interest_component'] as num? ?? 0).toDouble(),
        principalComponent: (map['principal_component'] as num? ?? 0).toDouble(),
        paidOn: dateFromDb(map['paid_on']),
        note: map['note']?.toString() ?? '',
        transactionId: map['transaction_id']?.toString(),
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );
}

class LoanPaymentSplit {
  const LoanPaymentSplit({required this.interest, required this.principal});
  final double interest;
  final double principal;
}

class LoanComputation {
  const LoanComputation({
    required this.principal,
    required this.interestAccrued,
    required this.totalDue,
    required this.totalPaid,
    required this.interestPaid,
    required this.principalPaid,
    required this.outstanding,
    required this.overpaid,
    required this.progress,
    required this.settled,
    required this.daysOverdue,
    required this.overdue,
    required this.emiAmount,
    required this.paymentsCount,
    required this.installmentsPaid,
    required this.computedAt,
  });

  final double principal;
  final double interestAccrued;
  final double totalDue;
  final double totalPaid;
  final double interestPaid;
  final double principalPaid;
  final double outstanding;
  final double overpaid;
  final double progress;
  final bool settled;
  final int daysOverdue;
  final bool overdue;
  final double? emiAmount;
  final int paymentsCount;
  final int installmentsPaid;
  final DateTime computedAt;
}

class LoanPortfolioSummary {
  const LoanPortfolioSummary({
    required this.toCollect,
    required this.toPay,
    required this.net,
    required this.overdueAmount,
    required this.activeCount,
    required this.settledCount,
    required this.overdueCount,
    required this.contactCount,
    required this.collectorCount,
    required this.debtorCount,
  });

  final double toCollect;
  final double toPay;
  final double net;
  final double overdueAmount;
  final int activeCount;
  final int settledCount;
  final int overdueCount;
  final int contactCount;
  final int collectorCount;
  final int debtorCount;
}
