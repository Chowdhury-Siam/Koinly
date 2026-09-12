import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Handles recurring subscription charges without depending on the widget tree.
///
/// Foreground code calls this service for near-immediate processing. Android's
/// WorkManager callback also calls it while the app is closed, so a scheduled
/// charge is persisted even if the user does not have Koinly open at that
/// moment. IDs for automatic occurrences are deterministic, which makes the
/// operation idempotent across multiple devices processing the same due date.
class SubscriptionBackgroundService {
  const SubscriptionBackgroundService._();

  static const _uuid = Uuid();
  static const int _maxOccurrencesPerSweep = 48;

  static Future<sql.Database> _openDatabase() async {
    final dir = await sql.getDatabasesPath();
    return sql.openDatabase(p.join(dir, 'koinly_flutter.db'), singleInstance: false);
  }

  static Future<int> processDueNow({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    sql.Database? database;
    try {
      database = await _openDatabase();
      final tableCheck = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='subscriptions'",
      );
      if (tableCheck.isEmpty) return 0;
      final rows = await database.query(
        'subscriptions',
        where: 'next_due_on <= ?',
        whereArgs: [dateToDb(effectiveNow)],
        orderBy: 'next_due_on ASC, created_on ASC',
      );
      var createdTransactions = 0;
      for (final row in rows) {
        createdTransactions += await _processSubscription(
          database,
          RecurringSubscription.fromMap(row),
          effectiveNow,
        );
      }
      return createdTransactions;
    } catch (_) {
      // Background scheduling is best-effort. Foreground startup/resume performs
      // another sweep, so a transient database error cannot lose a charge.
      return 0;
    } finally {
      if (database != null) await database.close();
    }
  }

  static Future<int> _processSubscription(
    sql.Database database,
    RecurringSubscription subscription,
    DateTime now,
  ) async {
    if (!subscription.autoPay || subscription.amount <= 0 || subscription.accountId.isEmpty || subscription.categoryId.isEmpty) {
      return 0;
    }
    final accountRows = await database.query(
      'accounts',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [subscription.accountId],
      limit: 1,
    );
    final categoryRows = await database.query(
      'categories',
      columns: ['id', 'type'],
      where: 'id = ?',
      whereArgs: [subscription.categoryId],
      limit: 1,
    );
    if (accountRows.isEmpty || categoryRows.isEmpty || categoryRows.first['type'] != 'expense') return 0;

    var due = subscription.nextDueOn;
    var lastProcessed = subscription.lastProcessedOn;
    var created = 0;
    var iterations = 0;

    await database.transaction((txn) async {
      final liveRows = await txn.query(
        'subscriptions',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [subscription.id],
        limit: 1,
      );
      if (liveRows.isEmpty) return;

      while (!due.isAfter(now) && iterations < _maxOccurrencesPerSweep) {
        iterations += 1;
        final occurrence = due;
        final transactionId = _automaticTransactionId(subscription.id, occurrence);
        final existing = await txn.query(
          'transactions',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [transactionId],
          limit: 1,
        );
        if (existing.isEmpty) {
          final transactionRow = <String, Object?>{
            'id': transactionId,
            'type': 'expense',
            'amount': subscription.amount,
            'title': subscription.name,
            'notes': subscription.notes,
            'category_id': subscription.categoryId,
            'from_account_id': subscription.accountId,
            'to_account_id': null,
            'image_path': '',
            'exclude_from_reports': 0,
            'linked_entity_type': 'subscription',
            'linked_entity_id': subscription.id,
            'created_on': dateToDb(occurrence),
            'end_on': null,
            'updated_on': dateToDb(now),
          };
          final inserted = await txn.insert(
            'transactions',
            transactionRow,
            conflictAlgorithm: sql.ConflictAlgorithm.ignore,
          );
          if (inserted != 0) {
            await txn.rawUpdate(
              'UPDATE accounts SET amount = amount - ?, updated_on = ? WHERE id = ?',
              [subscription.amount, dateToDb(now), subscription.accountId],
            );
            await _enqueueRow(txn, 'transactions', transactionId);
            created += 1;
          }
        }
        lastProcessed = occurrence;
        due = nextSubscriptionOccurrence(due, subscription.frequency);
      }

      // If a daily subscription was offline for a very long time, keep the next
      // due point at the first unprocessed occurrence. Subsequent WorkManager or
      // foreground sweeps continue catching up without creating an unbounded
      // transaction burst in a single isolate run.
      // [lastProcessed] is captured and mutated by this transaction closure, so
      // Dart cannot promote it from DateTime? to DateTime in a conditional
      // expression. Snapshot it into an immutable local before serialization.
      final processedOn = lastProcessed;
      await txn.update(
        'subscriptions',
        {
          'next_due_on': dateToDb(due),
          'last_processed_on': processedOn == null ? null : dateToDb(processedOn),
          'updated_on': dateToDb(now),
        },
        where: 'id = ?',
        whereArgs: [subscription.id],
      );
      if (created > 0 || lastProcessed != subscription.lastProcessedOn) {
        await _enqueueRow(txn, 'subscriptions', subscription.id);
        await _enqueueRow(txn, 'accounts', subscription.accountId);
      }
    });
    return created;
  }

  static Future<String> recordNow(
    String subscriptionId, {
    DateTime? occurredOn,
    String? accountId,
  }) async {
    final effectiveOn = occurredOn ?? DateTime.now();
    final database = await _openDatabase();
    try {
      final rows = await database.query(
        'subscriptions',
        where: 'id = ?',
        whereArgs: [subscriptionId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('This subscription no longer exists.');
      final subscription = RecurringSubscription.fromMap(rows.first);
      if (subscription.amount <= 0) throw StateError('This subscription has an invalid price.');
      final selectedAccountId = (accountId ?? subscription.accountId).trim();
      final accountRows = await database.query('accounts', columns: ['id'], where: 'id = ?', whereArgs: [selectedAccountId], limit: 1);
      if (accountRows.isEmpty) throw StateError('Choose a valid account for this subscription.');
      final categoryRows = await database.query('categories', columns: ['id', 'type'], where: 'id = ?', whereArgs: [subscription.categoryId], limit: 1);
      if (categoryRows.isEmpty || categoryRows.first['type'] != 'expense') {
        throw StateError('Choose a valid expense category for this subscription.');
      }

      final transactionId = _uuid.v4();
      var nextDue = subscription.nextDueOn;
      var lastProcessedOn = subscription.lastProcessedOn;
      if (!effectiveOn.isBefore(subscription.nextDueOn)) {
        do {
          nextDue = nextSubscriptionOccurrence(nextDue, subscription.frequency);
        } while (!nextDue.isAfter(effectiveOn));
        lastProcessedOn = effectiveOn;
      }
      await database.transaction((txn) async {
        await txn.insert('transactions', <String, Object?>{
          'id': transactionId,
          'type': 'expense',
          'amount': subscription.amount,
          'title': subscription.name,
          'notes': subscription.notes,
          'category_id': subscription.categoryId,
          'from_account_id': selectedAccountId,
          'to_account_id': null,
          'image_path': '',
          'exclude_from_reports': 0,
          'linked_entity_type': 'subscription',
          'linked_entity_id': subscription.id,
          'created_on': dateToDb(effectiveOn),
          'end_on': null,
          'updated_on': dateToDb(DateTime.now()),
        });
        await txn.rawUpdate(
          'UPDATE accounts SET amount = amount - ?, updated_on = ? WHERE id = ?',
          [subscription.amount, dateToDb(DateTime.now()), selectedAccountId],
        );
        if (nextDue != subscription.nextDueOn || lastProcessedOn != subscription.lastProcessedOn) {
          await txn.update(
            'subscriptions',
            {
              'next_due_on': dateToDb(nextDue),
              'last_processed_on': lastProcessedOn == null ? null : dateToDb(lastProcessedOn),
              'updated_on': dateToDb(DateTime.now()),
            },
            where: 'id = ?',
            whereArgs: [subscription.id],
          );
          await _enqueueRow(txn, 'subscriptions', subscription.id);
        }
        await _enqueueRow(txn, 'transactions', transactionId);
        await _enqueueRow(txn, 'accounts', selectedAccountId);
      });
      return transactionId;
    } finally {
      await database.close();
    }
  }

  static String _automaticTransactionId(String subscriptionId, DateTime occurrence) =>
      'subscription:$subscriptionId:${occurrence.millisecondsSinceEpoch}';

  static Future<void> _enqueueRow(sql.Transaction txn, String table, String entityId) async {
    final rows = await txn.query(table, where: 'id = ?', whereArgs: [entityId], limit: 1);
    if (rows.isEmpty) return;
    final versionRows = await txn.query(
      'sync_entity_versions',
      columns: ['version'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [table, entityId],
      limit: 1,
    );
    final baseVersion = versionRows.isEmpty ? 0 : (versionRows.first['version'] as num? ?? 0).toInt();
    final now = DateTime.now().millisecondsSinceEpoch;
    await txn.insert('sync_outbox', <String, Object?>{
      'id': _uuid.v4(),
      'entity_type': table,
      'entity_id': entityId,
      'operation': 'upsert',
      'payload_json': jsonEncode(rows.first),
      'base_version': baseVersion,
      'created_at': now,
      'attempt_count': 0,
      'last_attempt_at': null,
      'last_error': null,
    });
  }
}
