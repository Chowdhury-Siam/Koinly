import 'package:sqflite/sqflite.dart' as sql;

import '../models.dart';
import 'loan_models.dart';

class LoanDeleteResult {
  const LoanDeleteResult({required this.transactionIds, required this.paymentIds});
  final List<String> transactionIds;
  final List<String> paymentIds;
}

class LoanRepository {
  LoanRepository(this._db);

  final Future<sql.Database> Function() _db;

  Future<List<LoanContact>> contacts({bool includeArchived = false}) async {
    final rows = await (await _db()).query(
      'loan_contacts',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(LoanContact.fromMap).toList();
  }

  Future<List<Loan>> loans({String? contactId, LoanStatus? status}) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (contactId != null) {
      clauses.add('contact_id = ?');
      args.add(contactId);
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(loanStatusToDb(status));
    }
    final rows = await (await _db()).query(
      'loans',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_on DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  Future<List<LoanPayment>> payments({String? loanId}) async {
    final rows = await (await _db()).query(
      'loan_payments',
      where: loanId == null ? null : 'loan_id = ?',
      whereArgs: loanId == null ? null : [loanId],
      orderBy: 'paid_on ASC, created_on ASC',
    );
    return rows.map(LoanPayment.fromMap).toList();
  }

  Future<void> upsertContact(LoanContact contact) async {
    await (await _db()).insert('loan_contacts', contact.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> deleteContact(String id) async {
    await (await _db()).delete('loan_contacts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertLoan(Loan loan) async {
    await (await _db()).insert('loans', loan.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> setLoanStatus(String id, LoanStatus status, DateTime? closedOn) async {
    await (await _db()).update(
      'loans',
      {
        'status': loanStatusToDb(status),
        'closed_on': closedOn == null ? null : dateToDb(closedOn),
        'updated_on': dateToDb(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertPayment(LoanPayment payment) async {
    await (await _db()).insert('loan_payments', payment.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<String?> deletePayment(String id) async {
    final database = await _db();
    final rows = await database.query('loan_payments', columns: ['transaction_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    final transactionId = rows.isEmpty ? null : rows.first['transaction_id']?.toString();
    await database.delete('loan_payments', where: 'id = ?', whereArgs: [id]);
    return transactionId;
  }

  Future<Loan> createLoanWithDisbursal(Loan loan, MoneyTransaction transaction) async {
    final database = await _db();
    final linked = loan.copyWith(disbursalTransactionId: transaction.id, updatedOn: DateTime.now());
    await database.transaction((txn) async {
      await txn.insert('loans', linked.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await txn.insert('transactions', transaction.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await _applyTransaction(txn, transaction, 1);
    });
    return linked;
  }

  Future<LoanPayment> addPaymentWithTransaction(LoanPayment payment, MoneyTransaction transaction) async {
    final database = await _db();
    final linked = payment.copyWith(transactionId: transaction.id, updatedOn: DateTime.now());
    await database.transaction((txn) async {
      await txn.insert('loan_payments', linked.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await txn.insert('transactions', transaction.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await _applyTransaction(txn, transaction, 1);
    });
    return linked;
  }

  Future<LoanDeleteResult> deleteLoanCascade(String id) async {
    final database = await _db();
    final loanRows = await database.query('loans', columns: ['disbursal_transaction_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    final paymentRows = await database.query('loan_payments', columns: ['id', 'transaction_id'], where: 'loan_id = ?', whereArgs: [id]);
    final transactionIds = <String>[
      if (loanRows.isNotEmpty && (loanRows.first['disbursal_transaction_id']?.toString() ?? '').isNotEmpty)
        loanRows.first['disbursal_transaction_id']!.toString(),
      ...paymentRows.map((row) => row['transaction_id']?.toString() ?? '').where((value) => value.isNotEmpty),
    ];
    final paymentIds = paymentRows.map((row) => row['id']?.toString() ?? '').where((value) => value.isNotEmpty).toList();
    await database.transaction((txn) async {
      await txn.delete('loan_payments', where: 'loan_id = ?', whereArgs: [id]);
      await txn.delete('loans', where: 'id = ?', whereArgs: [id]);
    });
    return LoanDeleteResult(transactionIds: transactionIds, paymentIds: paymentIds);
  }

  Future<void> _applyTransaction(sql.Transaction txn, MoneyTransaction transaction, int direction) async {
    Future<void> updateAmount(String accountId, double delta) async {
      if (accountId.isEmpty) return;
      await txn.rawUpdate(
        'UPDATE accounts SET amount = amount + ?, updated_on = ? WHERE id = ?',
        [delta * direction, dateToDb(DateTime.now()), accountId],
      );
    }

    if (transaction.type == MoneyTransactionType.income) {
      await updateAmount(transaction.fromAccountId, transaction.amount);
    } else if (transaction.type == MoneyTransactionType.expense) {
      await updateAmount(transaction.fromAccountId, -transaction.amount);
    } else {
      await updateAmount(transaction.fromAccountId, -transaction.amount);
      await updateAmount(transaction.toAccountId ?? '', transaction.amount);
    }
  }
}
